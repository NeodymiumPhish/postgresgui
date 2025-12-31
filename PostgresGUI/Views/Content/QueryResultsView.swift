//
//  QueryResultsView.swift
//  PostgresGUI
//
//  Displays query results in a table. Delegates business logic to QueryResultsViewModel.
//

import SwiftUI

// MARK: - Timestamp Detection Utilities

private enum TimestampUtils {
    static let patterns = [
        "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
        "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}",
        "^\\d{4}-\\d{2}-\\d{2}$"
    ]

    static func isTimestamp(_ value: String) -> Bool {
        patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    static func parseDate(_ value: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: value) { return date }

        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

// MARK: - Table Row Comparator

struct TableRowComparator: SortComparator, Hashable {
    let columnName: String
    var order: SortOrder = .forward

    func compare(_ lhs: TableRow, _ rhs: TableRow) -> ComparisonResult {
        let result = compareValues(lhs.values[columnName] ?? nil, rhs.values[columnName] ?? nil)
        return order == .reverse ? result.reversed : result
    }

    private func compareValues(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (v1?, v2?):
            if let num1 = Double(v1), let num2 = Double(v2) {
                return num1 < num2 ? .orderedAscending : (num1 > num2 ? .orderedDescending : .orderedSame)
            }
            if TimestampUtils.isTimestamp(v1) && TimestampUtils.isTimestamp(v2),
               let date1 = TimestampUtils.parseDate(v1),
               let date2 = TimestampUtils.parseDate(v2) {
                return date1 < date2 ? .orderedAscending : (date1 > date2 ? .orderedDescending : .orderedSame)
            }
            return v1.localizedStandardCompare(v2)
        }
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

struct QueryResultsView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @State private var viewModel: QueryResultsViewModel?
    @State private var sortOrder: [TableRowComparator] = []
    var searchText: String = ""
    var onDeleteKeyPressed: (() -> Void)?
    var onSpaceKeyPressed: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Results or error display
            resultsContent

            // Pagination row (only show if there's more than one page)
            if appState.query.currentPage > 0 || appState.query.hasNextPage {
                paginationBar
            }
        }
        .padding(.leading, 4)
        .onAppear {
            viewModel = QueryResultsViewModel(appState: appState, tabManager: tabManager)
        }
        .onChange(of: appState.connection.selectedTable?.id) { oldValue, newValue in
            // Reset sort order when table changes
            if oldValue != newValue {
                sortOrder = []
            }
            viewModel?.handleTableSelectionChange(oldValue: oldValue, newValue: newValue)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let errorMessage = appState.query.queryErrorMessage {
            ContentUnavailableView {
                Label {
                    Text("Query Failed")
                        .font(.title3)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            } description: {
                Text(errorMessage)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.query.isExecutingQuery {
            // Show loading state while query executes
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.query.queryResults.isEmpty {
            // Show empty table with headers if column names are available
            if let columnNames = getColumnNames(), !columnNames.isEmpty {
                // Empty table with overlay empty state message
                emptyTableWithHeaders(columnNames: columnNames)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .center) {
                        Text("No rows returned")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Text("No rows returned")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Display results using SwiftUI Table
            resultsTable
        }
    }

    @ViewBuilder
    private var paginationBar: some View {
        HStack {
            Text("\(appState.query.queryResults.count) rows")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    viewModel?.goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(!canGoToPreviousPage(currentPage: appState.query.currentPage) || appState.query.isExecutingQuery)

                Text("Page \(appState.query.currentPage + 1)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button {
                    viewModel?.goToNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!appState.query.hasNextPage || appState.query.isExecutingQuery)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var resultsTable: some View {
        if let columnNames = getColumnNames() {
            Table(sortedResults, selection: Binding(
                get: { appState.query.selectedRowIDs },
                set: { appState.query.selectedRowIDs = $0 }
            ), sortOrder: $sortOrder) {
                TableColumnForEach(columnNames, id: \.self) { columnName in
                    TableColumn(columnName, sortUsing: TableRowComparator(columnName: columnName)) { row in
                        Text(formatValue(row.values[columnName] ?? nil))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: Constants.ColumnWidth.tableColumnMin)
                }
            }
            .id(appState.connection.selectedTable?.id)
            .onDeleteCommand {
                if !appState.query.selectedRowIDs.isEmpty {
                    onDeleteKeyPressed?()
                }
            }
            .onKeyPress(.space) {
                if !appState.query.selectedRowIDs.isEmpty {
                    onSpaceKeyPressed?()
                    return .handled
                }
                return .ignored
            }
        }
    }

    @ViewBuilder
    private func emptyTableWithHeaders(columnNames: [String]) -> some View {
        // Create a Table with just headers, no rows
        Table([] as [TableRow], selection: .constant(Set<TableRow.ID>())) {
            TableColumnForEach(columnNames, id: \.self) { columnName in
                TableColumn(columnName) { row in
                    Text(formatValue(row.values[columnName] ?? nil))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: Constants.ColumnWidth.tableColumnMin)
            }
        }
        .id(appState.connection.selectedTable?.id)
    }

    private var filteredResults: [TableRow] {
        guard !searchText.isEmpty else { return appState.query.queryResults }
        let lowercasedSearch = searchText.lowercased()
        return appState.query.queryResults.filter { row in
            row.values.values.contains { value in
                guard let value = value else { return false }
                return value.lowercased().contains(lowercasedSearch)
            }
        }
    }

    private var sortedResults: [TableRow] {
        filteredResults.sorted(using: sortOrder)
    }

    private func getColumnNames() -> [String]? {
        // First try to get column names from stored queryColumnNames (works even for empty results)
        if let columnNames = appState.query.queryColumnNames, !columnNames.isEmpty {
            return columnNames
        }

        // Fallback: Extract column names from the first row
        guard let firstRow = appState.query.queryResults.first else {
            return nil
        }
        // Sort column names alphabetically for consistent ordering
        return Array(firstRow.values.keys.sorted())
    }

    private func formatValue(_ value: String?) -> String {
        guard let value = value else { return "NULL" }
        return TimestampUtils.isTimestamp(value) ? Formatters.formatTimestamp(value) : value
    }
}

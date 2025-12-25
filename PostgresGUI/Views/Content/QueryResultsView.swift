//
//  QueryResultsView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
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
    @State private var sortOrder: [TableRowComparator] = []
    @State private var lastExecutedTableID: String? = nil
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
        .onChange(of: appState.connection.selectedTable?.id) { oldValue, newValue in
            // Clear results immediately when table changes (prevents column mismatch crashes)
            if oldValue != newValue {
                appState.query.queryResults = []
                appState.query.queryColumnNames = nil
                appState.query.queryError = nil
                appState.query.currentPage = 0
                sortOrder = []
            }

            // Execute query when a table is selected
            if let table = appState.connection.selectedTable, table.id != lastExecutedTableID {
                lastExecutedTableID = table.id
                Task { @MainActor in
                    await appState.executeTableQuery(for: table)
                }
            } else if newValue == nil {
                // Clear query results when table selection is cleared (but preserve queryText)
                lastExecutedTableID = nil
                DebugLog.print("📋 [QueryResultsView] Table selection cleared - preserving queryText, clearing results")
                appState.query.showQueryResults = false
            }
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
                        ContentUnavailableView(
                            "Empty Table",
                            systemImage: "tablecells",
                            description: Text("Query returned no rows")
                        )
                    }
            } else {
                ContentUnavailableView(
                    "Empty Table",
                    systemImage: "tablecells",
                    description: Text("Query returned no rows")
                )
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
                    goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(appState.query.currentPage == 0 || appState.query.isExecutingQuery)

                Text("Page \(appState.query.currentPage + 1)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button {
                    goToNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!appState.query.hasNextPage || appState.query.isExecutingQuery)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func goToPreviousPage() {
        guard appState.query.currentPage > 0,
              let table = appState.connection.selectedTable else { return }
        appState.query.currentPage -= 1
        appState.query.hasNextPage = true  // We know there's a next page since we came from it
        Task {
            await appState.executeTableQuery(for: table)
        }
    }

    private func goToNextPage() {
        guard let table = appState.connection.selectedTable else { return }
        appState.query.currentPage += 1
        Task {
            await appState.executeTableQuery(for: table)
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
            DebugLog.print("📋 [QueryResultsView] Using stored column names: \(columnNames.joined(separator: ", "))")
            return columnNames
        }

        // Fallback: Extract column names from the first row
        guard let firstRow = appState.query.queryResults.first else {
            DebugLog.print("⚠️  [QueryResultsView] No column names available")
            return nil
        }
        // Sort column names alphabetically for consistent ordering
        let columnNames = Array(firstRow.values.keys.sorted())
        DebugLog.print("📋 [QueryResultsView] Using column names from first row: \(columnNames.joined(separator: ", "))")
        return columnNames
    }

    private func formatValue(_ value: String?) -> String {
        guard let value = value else { return "NULL" }
        return TimestampUtils.isTimestamp(value) ? Formatters.formatTimestamp(value) : value
    }
}

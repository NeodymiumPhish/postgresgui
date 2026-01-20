//
//  TablesListView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

// Legacy wrapper - kept for compatibility
struct TablesListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TablesListIsolated(
            tables: appState.connection.filteredTables,
            groupedTables: appState.connection.groupedTables,
            selectedTable: Binding(
                get: { appState.connection.selectedTable },
                set: { appState.connection.selectedTable = $0 }
            ),
            expandedSchemas: Binding(
                get: { appState.connection.expandedSchemas },
                set: { appState.connection.expandedSchemas = $0 }
            ),
            isLoadingTables: appState.connection.isLoadingTables,
            isExecutingQuery: appState.query.isExecutingQuery,
            selectedDatabase: appState.connection.selectedDatabase,
            refreshQueryAction: { table in
                await appState.executeTableQuery(for: table)
            }
        )
    }
}

// Isolated view that only depends on explicit parameters, not AppState environment
struct TablesListIsolated: View {
    let tables: [TableInfo]
    let groupedTables: [SchemaGroup]
    @Binding var selectedTable: TableInfo?
    @Binding var expandedSchemas: Set<String>
    let isLoadingTables: Bool
    let isExecutingQuery: Bool
    let selectedDatabase: DatabaseInfo?

    let refreshQueryAction: (TableInfo) async -> Void

    /// Whether to show grouped view (multiple schemas present)
    private var shouldShowGrouped: Bool {
        groupedTables.count > 1
    }

    var body: some View {
        let _ = {
            DebugLog.print("🔍 [TablesListView] Body computed - isLoadingTables: \(isLoadingTables), tablesCount: \(tables.count), selectedTable: \(selectedTable?.name ?? "nil"), grouped: \(shouldShowGrouped)")
        }()

        Group {
            if isLoadingTables {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tables.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No tables found")
                            .font(.title3)
                            .fontWeight(.regular)
                    } icon: { }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shouldShowGrouped {
                groupedTablesList
            } else {
                flatTablesList
            }
        }
    }

    // MARK: - Flat List (single schema or filtered)

    private var flatTablesList: some View {
        List(tables, selection: $selectedTable) { table in
            TableListRowView(
                table: table,
                isExecutingQuery: isExecutingQuery,
                refreshQueryAction: refreshQueryAction
            )
            .tag(table)
            .listRowSeparator(.visible)
        }
        .padding(.top, 8)
    }

    // MARK: - Grouped List (multiple schemas)

    private var groupedTablesList: some View {
        List(selection: $selectedTable) {
            ForEach(groupedTables) { group in
                SchemaGroupView(
                    group: group,
                    isExpanded: Binding(
                        get: { expandedSchemas.contains(group.name) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedSchemas.insert(group.name)
                            } else {
                                expandedSchemas.remove(group.name)
                            }
                        }
                    ),
                    selectedTable: $selectedTable,
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction
                )
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Table Row View

struct TableListRowView: View {
    @Environment(AppState.self) private var appState

    let table: TableInfo
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void
    var showSchemaPrefix: Bool = true

    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var viewModel: TableContextMenuViewModel?

    /// Display name based on whether schema prefix should be shown
    private var displayText: String {
        showSchemaPrefix ? table.displayName : table.name
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: table.tableType == .foreign ? "tablecells.fill" : "tablecells")
                .foregroundColor(.secondary)
            Text(displayText)
                .lineLimit(1)
            Spacer()

            Menu {
                tableMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(isButtonHovered ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .opacity((isHovered || isButtonHovered) ? 1.0 : 0.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isButtonHovered = hovering
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            tableMenuContent
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TableContextMenuViewModel(table: table, appState: appState)
            }
        }
        .onChange(of: table.id) { _, newValue in
            // Update viewModel when table changes (e.g., in a reused row)
            viewModel = TableContextMenuViewModel(table: table, appState: appState)
        }
        .modifier(TableContextMenuModalsWrapper(viewModel: $viewModel))
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var tableMenuContent: some View {
        // Refresh
        Button {
            Task {
                await refreshQueryAction(table)
            }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(isExecutingQuery)

        Divider()

        // Generate DDL
        Button {
            Task {
                await viewModel?.generateDDL()
            }
        } label: {
            Label("Generate DDL", systemImage: "doc.text")
        }
        .disabled(isExecutingQuery)

        // Export
        Button {
            viewModel?.showExportSheet = true
        } label: {
            Label("Export...", systemImage: "square.and.arrow.up")
        }
        .disabled(isExecutingQuery)

        Divider()

        // Truncate (destructive)
        Button(role: .destructive) {
            viewModel?.showTruncateConfirmation = true
        } label: {
            Label("Truncate...", systemImage: "trash.slash")
        }
        .disabled(isExecutingQuery)

        // Drop (destructive)
        Button(role: .destructive) {
            viewModel?.showDropConfirmation = true
        } label: {
            Label("Drop...", systemImage: "trash")
        }
        .disabled(isExecutingQuery)
    }
}

// MARK: - Modals Wrapper

/// Wrapper to safely handle optional viewModel binding
private struct TableContextMenuModalsWrapper: ViewModifier {
    @Binding var viewModel: TableContextMenuViewModel?

    func body(content: Content) -> some View {
        if let vm = viewModel {
            content.tableContextMenuModals(viewModel: vm) {
                // No additional action needed after drop - the ViewModel handles refresh
            }
        } else {
            content
        }
    }
}


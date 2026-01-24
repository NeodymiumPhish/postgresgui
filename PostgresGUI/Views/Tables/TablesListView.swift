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
            selectedSchema: appState.connection.selectedSchema,
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
    let selectedSchema: String?  // nil means "All Schemas"
    @Binding var selectedTable: TableInfo?
    @Binding var expandedSchemas: Set<String>
    let isLoadingTables: Bool
    let isExecutingQuery: Bool
    let selectedDatabase: DatabaseInfo?

    let refreshQueryAction: (TableInfo) async -> Void

    /// Number of tables to load per batch for incremental rendering
    private static let batchSize = 100

    /// Current number of tables to display (for incremental loading)
    @State private var displayedCount: Int = TablesListIsolated.batchSize

    /// Whether to show grouped view (multiple schemas present)
    private var shouldShowGrouped: Bool {
        groupedTables.count > 1
    }

    /// Tables to display (limited for performance)
    private var displayedTables: ArraySlice<TableInfo> {
        tables.prefix(displayedCount)
    }

    /// Whether there are more tables to load
    private var hasMoreTables: Bool {
        displayedCount < tables.count
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
        .onChange(of: tables.count) { _, _ in
            // Reset displayed count when tables change (e.g., schema filter changed)
            displayedCount = Self.batchSize
        }
        .onChange(of: selectedSchema) { _, _ in
            // Reset displayed count when schema filter changes
            displayedCount = Self.batchSize
        }
    }

    // MARK: - Flat List (single schema or filtered)

    private var flatTablesList: some View {
        List(selection: $selectedTable) {
            ForEach(displayedTables, id: \.id) { table in
                TableListRowView(
                    table: table,
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction,
                    showSchemaPrefix: selectedSchema == nil
                )
                .tag(table)
                .listRowSeparator(.visible)
            }

            // "Load more" button when there are more tables to show
            if hasMoreTables {
                loadMoreButton
            }
        }
        .padding(.top, 8)
    }

    private var loadMoreButton: some View {
        Button {
            displayedCount = min(displayedCount + Self.batchSize, tables.count)
        } label: {
            HStack {
                Spacer()
                Text("Load more (\(tables.count - displayedCount) remaining)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
        .modifier(TableContextMenuModalsWrapper(viewModel: $viewModel))
    }

    // MARK: - Menu Content

    /// Ensures the viewModel exists, creating it lazily if needed.
    /// Called when menu actions require the ViewModel.
    private func ensureViewModel() -> TableContextMenuViewModel {
        if let existing = viewModel {
            return existing
        }
        let vm = TableContextMenuViewModel(table: table, appState: appState)
        viewModel = vm
        return vm
    }

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
                await ensureViewModel().generateDDL()
            }
        } label: {
            Label("Generate DDL", systemImage: "doc.text")
        }
        .disabled(isExecutingQuery)

        // Export
        Button {
            ensureViewModel().showExportSheet = true
        } label: {
            Label("Export...", systemImage: "square.and.arrow.up")
        }
        .disabled(isExecutingQuery)

        Divider()

        // Truncate (destructive)
        Button(role: .destructive) {
            ensureViewModel().showTruncateConfirmation = true
        } label: {
            Label("Truncate...", systemImage: "trash.slash")
        }
        .disabled(isExecutingQuery)

        // Drop (destructive)
        Button(role: .destructive) {
            ensureViewModel().showDropConfirmation = true
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


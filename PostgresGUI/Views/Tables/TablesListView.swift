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
    let table: TableInfo
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void
    var showSchemaPrefix: Bool = true

    @State private var isHovered = false
    @State private var isButtonHovered = false

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
                Button {
                    Task {
                        await refreshQueryAction(table)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isExecutingQuery)
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
            Button {
                Task {
                    await refreshQueryAction(table)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isExecutingQuery)
        }
    }
}


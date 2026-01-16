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
            tables: appState.connection.tables,
            selectedTable: Binding(
                get: { appState.connection.selectedTable },
                set: { appState.connection.selectedTable = $0 }
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
    @Binding var selectedTable: TableInfo?
    let isLoadingTables: Bool
    let isExecutingQuery: Bool
    let selectedDatabase: DatabaseInfo?

    let refreshQueryAction: (TableInfo) async -> Void

    var body: some View {
        // Debug: Log when isLoadingTables changes
        let _ = {
            DebugLog.print("🔍 [TablesListView] Body computed - isLoadingTables: \(isLoadingTables), tablesCount: \(tables.count), selectedTable: \(selectedTable?.name ?? "nil")")
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
            } else {
                List(tables, selection: $selectedTable) { table in
                    TableListRowView(
                        table: table,
                        isExecutingQuery: isExecutingQuery,
                        refreshQueryAction: refreshQueryAction
                    )
                    .tag(table)
                    .listRowSeparator(.visible)
                }
                .padding(.top, 12)
                .onChange(of: selectedTable?.id) { oldValue, newValue in
                    DebugLog.print("🔍 [TablesListView] selectedTable changed - old: \(oldValue ?? "nil"), new: \(newValue ?? "nil")")
                }
                .onChange(of: isLoadingTables) { oldValue, newValue in
                    DebugLog.print("🔍 [TablesListView] isLoadingTables changed - old: \(oldValue), new: \(newValue)")
                }
                .onChange(of: tables.count) { oldValue, newValue in
                    DebugLog.print("🔍 [TablesListView] tables.count changed - old: \(oldValue), new: \(newValue)")
                }
            }
        }
    }
}

struct TableListRowView: View {
    let table: TableInfo
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: table.tableType == .foreign ? "tablecells.fill" : "tablecells")
                .foregroundColor(.secondary)
            Text(table.displayName)
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


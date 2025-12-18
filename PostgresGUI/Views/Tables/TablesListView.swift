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
            tables: appState.tables,
            selectedTable: $appState.selectedTable,
            isLoadingTables: appState.isLoadingTables,
            selectedDatabase: appState.selectedDatabase,
            refreshTablesAction: {
                await refreshTables(appState: appState)
            }
        )
    }
}

// Isolated view that only depends on explicit parameters, not AppState environment
struct TablesListIsolated: View {
    let tables: [TableInfo]
    @Binding var selectedTable: TableInfo?
    let isLoadingTables: Bool
    let selectedDatabase: DatabaseInfo?
    
    // Use a closure to access appState only when needed, avoiding observation of AppState
    // This prevents the view from recomputing when query-related state changes
    let refreshTablesAction: () async -> Void

    var body: some View {
        // Debug: Log when isLoadingTables changes
        let _ = {
            DebugLog.print("🔍 [TablesListView] Body computed - isLoadingTables: \(isLoadingTables), tablesCount: \(tables.count), selectedTable: \(selectedTable?.name ?? "nil")")
        }()
        
        Group {
            if tables.isEmpty {
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
                    HStack(spacing: 8) {
                        Image(systemName: "tablecells")
                            .foregroundColor(.secondary)
                        Text(table.name)
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .tag(table)
                }
                .onChange(of: selectedTable?.id) { oldValue, newValue in
                    DebugLog.print("🔍 [TablesListView] selectedTable changed - old: \(oldValue ?? "nil"), new: \(newValue ?? "nil")")
                }
                .onChange(of: isLoadingTables) { oldValue, newValue in
                    DebugLog.print("🔍 [TablesListView] isLoadingTables changed - old: \(oldValue), new: \(newValue)")
                }
                .onChange(of: tables.count) { oldValue, newValue in
                    DebugLog.print("🔍 [TablesListView] tables.count changed - old: \(oldValue), new: \(newValue)")
                }
                .contextMenu {
                    Button {
                        Task {
                            await refreshTablesAction()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingTables || selectedDatabase == nil)
                }
            }
        }
        // .toolbar {
        //     // ToolbarItem(placement: .automatic) {
        //     //     Button(action: {
        //     //         Task {
        //     //             await refreshTables()
        //     //         }
        //     //     }) {
        //     //         Image(systemName: "arrow.clockwise")
        //     //     }
        //     //     .disabled(appState.isLoadingTables || appState.selectedDatabase == nil)
        //     //     .keyboardShortcut(.init("r"), modifiers: [.command])
        //     // }
        // }
    }
}

// Helper function to refresh tables - extracted to avoid observing AppState in the view
@MainActor
func refreshTables(appState: AppState) async {
        DebugLog.print("🔄 [TablesListView] Refresh tables START")
        
        guard let database = appState.selectedDatabase else {
            DebugLog.print("❌ [TablesListView] No database selected for refresh")
            return
        }
        
        defer {
            DebugLog.print("🔄 [TablesListView] Refresh tables END - setting isLoadingTables=false")
            appState.isLoadingTables = false
        }
        
        appState.isLoadingTables = true
        
        // Check if we're connected
        guard appState.databaseService.isConnected else {
            DebugLog.print("❌ [TablesListView] Not connected, cannot refresh")
            return
        }
        
        // Refresh databases list
        do {
            DebugLog.print("📊 [TablesListView] Fetching databases...")
            appState.databases = try await appState.databaseService.fetchDatabases()
            DebugLog.print("✅ [TablesListView] Refreshed \(appState.databases.count) databases")
        } catch {
            DebugLog.print("❌ [TablesListView] Error refreshing databases: \(error)")
            DebugLog.print("❌ [TablesListView] Error details: \(String(describing: error))")
            // Continue with table refresh even if database refresh fails
        }
        
        // Refresh tables list
        do {
            DebugLog.print("📊 [TablesListView] Fetching tables from database: \(database.name)")
            appState.tables = try await appState.databaseService.fetchTables(database: database.name)
            DebugLog.print("✅ [TablesListView] Refreshed \(appState.tables.count) tables")
            
            // Update selectedTable reference if it still exists in the refreshed list
            // Only update if the table object has actually changed (e.g., primaryKeyColumns or columnInfo updated)
            // This prevents unnecessary refreshes when the table is the same
            if let selectedTable = appState.selectedTable,
               let refreshedTable = appState.tables.first(where: { $0.id == selectedTable.id }) {
                // Only update if the table has actually changed (e.g., metadata was added)
                if refreshedTable != selectedTable {
                    DebugLog.print("🔄 [TablesListView] Updating selectedTable with refreshed metadata")
                    appState.selectedTable = refreshedTable
                } else {
                    DebugLog.print("🔄 [TablesListView] selectedTable unchanged, skipping update")
                }
            } else if appState.selectedTable != nil {
                // Clear selection if the table no longer exists
                DebugLog.print("🔄 [TablesListView] Selected table no longer exists, clearing selection")
                appState.selectedTable = nil
            }
        } catch {
            DebugLog.print("❌ [TablesListView] Error refreshing tables: \(error)")
            DebugLog.print("❌ [TablesListView] Error details: \(String(describing: error))")
            // Keep existing tables on error
        }
}

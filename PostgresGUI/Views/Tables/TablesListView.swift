//
//  TablesListView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TablesListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableID: TableInfo.ID?

    var body: some View {
        Group {
            if appState.isLoadingTables {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.tables.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No tables found")
                            .font(.title3)
                            .fontWeight(.regular)
                    } icon: { }
                }
            } else {
                List(selection: Binding<TableInfo.ID?>(
                    get: { selectedTableID },
                    set: { newID in
                        guard let unwrappedID = newID else {
                            selectedTableID = nil
                            appState.selectedTable = nil
                            appState.showQueryResults = false
                            appState.queryText = ""
                            appState.queryResults = []
                            DebugLog.print("🔴 [TablesListView] Table selection cleared")
                            return
                        }
                        selectedTableID = unwrappedID
                        DebugLog.print("🟢 [TablesListView] selectedTableID changed to \(unwrappedID)")

                        // Find the table object from the ID
                        let table = appState.tables.first { $0.id == unwrappedID }

                        DebugLog.print("🔵 [TablesListView] Updating selectedTable to: \(table?.name ?? "nil")")
                        appState.selectedTable = table

                        if let table = table {
                            DebugLog.print("🟠 [TablesListView] Generating and executing query for: \(table.schema).\(table.name)")
                            Task {
                                await populateAndExecuteQuery(for: table)
                            }
                        }
                    }
                )) {
                    ForEach(appState.tables) { table in
                        TableRowView(table: table)
                    }
                }
                .contextMenu {
                    Button {
                        Task {
                            await refreshTables()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isLoadingTables || appState.selectedDatabase == nil)
                }
            }
        }
        .navigationTitle("Tables")
        .onChange(of: appState.selectedTable) { oldValue, newValue in
            // Clear local selection when selectedTable is cleared (e.g., when database changes)
            if newValue == nil {
                selectedTableID = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        await refreshTables()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(appState.isLoadingTables || appState.selectedDatabase == nil)
                .keyboardShortcut(.init("r"), modifiers: [.command])
            }
        }
    }

    private func generateTableQuery(for table: TableInfo) -> String {
        return "SELECT * FROM \(table.schema).\(table.name) LIMIT \(appState.rowsPerPage);"
    }

    @MainActor
    private func populateAndExecuteQuery(for table: TableInfo) async {
        DebugLog.print("🔍 [TablesListView] Auto-generating query for table: \(table.schema).\(table.name)")

        // Set loading state FIRST to prevent empty state flicker
        appState.isExecutingQuery = true
        appState.queryError = nil
        appState.queryExecutionTime = nil
        appState.showQueryResults = false // Hide results view during loading
        
        // Clear existing state to prevent rendering issues
        appState.queryResults = []
        appState.queryColumnNames = nil

        // Generate SELECT query with pagination
        let query = generateTableQuery(for: table)
        DebugLog.print("📝 [TablesListView] Generated query: \(query)")

        // Update query text in editor
        appState.queryText = query

        // Ensure loading state is still set (in case it was cleared during column fetch)
        appState.isExecutingQuery = true
        appState.queryColumnNames = nil // Clear previous column names

        let startTime = Date()

        do {
            DebugLog.print("📊 [TablesListView] Executing query...")
            let (results, columnNames) = try await appState.databaseService.executeQuery(query)
            appState.queryResults = results
            appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
            appState.showQueryResults = true

            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)

            DebugLog.print("✅ [TablesListView] Query executed successfully - \(appState.queryResults.count) rows")
        } catch {
            appState.queryError = error.localizedDescription
            appState.queryColumnNames = nil
            appState.showQueryResults = true

            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)

            DebugLog.print("❌ [TablesListView] Query execution failed: \(error)")
        }

        appState.isExecutingQuery = false
    }
    
    @MainActor
    private func refreshTables() async {
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
            if let selectedTable = appState.selectedTable,
               let refreshedTable = appState.tables.first(where: { $0.id == selectedTable.id }) {
                appState.selectedTable = refreshedTable
            }
        } catch {
            DebugLog.print("❌ [TablesListView] Error refreshing tables: \(error)")
            DebugLog.print("❌ [TablesListView] Error details: \(String(describing: error))")
            // Keep existing tables on error
        }
        
        // Refresh query results if a table is selected
        if let selectedTable = appState.selectedTable {
            DebugLog.print("🔄 [TablesListView] Refreshing query results for table: \(selectedTable.schema).\(selectedTable.name)")
            await populateAndExecuteQuery(for: selectedTable)
        }
    }
}

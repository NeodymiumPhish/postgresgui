//
//  AppState.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

@Observable
@MainActor
class AppState {
    // Navigation
    var navigationPath: NavigationPath = NavigationPath()
    
    // Connection state
    var currentConnection: ConnectionProfile?
    // Computed property - single source of truth is databaseService
    var isConnected: Bool {
        databaseService.isConnected
    }
    var databaseService = DatabaseService()
    
    // Current selections
    var selectedDatabase: DatabaseInfo?
    var selectedTable: TableInfo?
    
    // Data caches (populated by DatabaseService)
    var databases: [DatabaseInfo] = []
    var tables: [TableInfo] = []

    // UI state
    var isShowingConnectionForm: Bool = false
    var isShowingConnectionsList: Bool = false
    var connectionToEdit: ConnectionProfile? = nil
    var isShowingWelcomeScreen: Bool = true
    var currentPage: Int = 0
    var rowsPerPage: Int = Constants.Pagination.defaultRowsPerPage
    var isLoadingTables: Bool = false

    // Query editor state
    var queryText: String = ""
    var queryResults: [TableRow] = []
    var queryColumnNames: [String]? = nil
    var isExecutingQuery: Bool = false
    var queryError: String? = nil
    var showQueryResults: Bool = false
    var queryExecutionTime: TimeInterval? = nil
    var selectedRowIDs: Set<UUID> = []
    
    // Sheet management helpers - ensure only one sheet is shown at a time
    func showConnectionForm() {
        isShowingConnectionsList = false
        isShowingConnectionForm = true
    }
    
    func showConnectionsList() {
        isShowingConnectionForm = false
        isShowingConnectionsList = true
    }
    
    // Centralized query execution to prevent race conditions when rapidly switching tables
    private var currentQueryTask: Task<Void, Never>? = nil
    private var queryCounter: Int = 0

    @MainActor
    func executeTableQuery(for table: TableInfo) async {
        // Cancel any existing query task
        currentQueryTask?.cancel()
        currentQueryTask = nil

        // Increment counter to track which query is active
        queryCounter += 1
        let thisQueryID = queryCounter

        DebugLog.print("🔍 [AppState] Auto-generating query for table: \(table.schema).\(table.name) (ID: \(thisQueryID))")

        isExecutingQuery = true
        queryError = nil
        queryExecutionTime = nil

        let query = "SELECT * FROM \(table.schema).\(table.name) LIMIT \(rowsPerPage);"
        DebugLog.print("📝 [AppState] Generated query: \(query) (ID: \(thisQueryID))")

        let startTime = Date()

        // Create and store the task
        currentQueryTask = Task { @MainActor in
            do {
                DebugLog.print("📊 [AppState] Executing query... (ID: \(thisQueryID))")
                let (results, columnNames) = try await databaseService.executeQuery(query)

                // Check if task was cancelled or a newer query has started
                guard !Task.isCancelled, thisQueryID == queryCounter else {
                    DebugLog.print("⚠️ [AppState] Query was cancelled or superseded (ID: \(thisQueryID), current: \(queryCounter))")
                    return
                }

                // Update results atomically
                queryResults = results
                queryColumnNames = columnNames.isEmpty ? nil : columnNames
                showQueryResults = true

                let endTime = Date()
                queryExecutionTime = endTime.timeIntervalSince(startTime)

                DebugLog.print("✅ [AppState] Query executed successfully - \(results.count) rows (ID: \(thisQueryID))")
            } catch {
                // Check if task was cancelled or a newer query has started
                guard !Task.isCancelled, thisQueryID == queryCounter else {
                    DebugLog.print("⚠️ [AppState] Query was cancelled or superseded during error handling (ID: \(thisQueryID), current: \(queryCounter))")
                    return
                }

                queryError = error.localizedDescription
                queryColumnNames = nil
                showQueryResults = true

                let endTime = Date()
                queryExecutionTime = endTime.timeIntervalSince(startTime)

                DebugLog.print("❌ [AppState] Query execution failed: \(error) (ID: \(thisQueryID))")
            }

            // Only clear isExecutingQuery if this is still the current query
            if thisQueryID == queryCounter {
                isExecutingQuery = false
            }

            if currentQueryTask?.isCancelled == false {
                currentQueryTask = nil
            }
        }

        // Don't await - let it run in the background and get cancelled if needed
    }

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up connection...")

        // Cancel any pending queries
        currentQueryTask?.cancel()
        currentQueryTask = nil

        // Disconnect database (awaits proper shutdown)
        await databaseService.disconnect()

        // Reset state
        currentConnection = nil
        selectedDatabase = nil
        selectedTable = nil
        databases = []
        tables = []

        DebugLog.print("✅ Cleanup completed")
    }
}

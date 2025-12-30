//
//  QueryEditorViewModel.swift
//  PostgresGUI
//
//  Handles query execution, auto-save, and schema detection.
//  Extracted from QueryEditorView to separate business logic from presentation.
//

import Foundation
import SwiftData

@Observable
@MainActor
class QueryEditorViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager
    private let modelContext: ModelContext

    // MARK: - State

    var showNoDatabaseAlert = false
    var showSaveErrorAlert = false
    var saveErrorMessage = ""

    private var saveTask: Task<Void, Never>?

    // MARK: - Initialization

    init(appState: AppState, tabManager: TabManager, modelContext: ModelContext) {
        self.appState = appState
        self.tabManager = tabManager
        self.modelContext = modelContext
    }

    // MARK: - Query Text Change Handling

    /// Handle query text changes: debounced auto-save and tab update
    func handleQueryTextChange(_ newText: String) {
        // Capture restoration flag now (before debounce)
        let isRestoring = appState.query.isRestoringFromTab

        // Cancel previous save task
        saveTask?.cancel()

        // Debounced auto-save (500ms) - skip if restoring from tab
        if !isRestoring {
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else {
                    DebugLog.print("💾 [QueryEditorViewModel] Auto-save cancelled (new keystroke)")
                    return
                }
                DebugLog.print("💾 [QueryEditorViewModel] Auto-save triggered after debounce")
                await saveQueryWithRetry()
            }
        }

        // Update tab state immediately
        tabManager.updateActiveTab(connectionId: nil, databaseName: nil, queryText: newText)
    }

    // MARK: - Query Execution

    /// Execute the current query
    func executeQuery() async {
        DebugLog.print("🎬 [QueryEditorViewModel] Execute button clicked")

        // Check if database is selected
        guard let database = appState.connection.selectedDatabase else {
            showNoDatabaseAlert = true
            DebugLog.print("⚠️ [QueryEditorViewModel] No database selected")
            return
        }

        let queryText = appState.query.queryText
        let queryType = QueryTypeDetector.detect(queryText)
        let tableName = QueryTypeDetector.extractTableName(queryText)

        // Set loading state - but keep previous results visible to prevent flicker
        appState.query.isExecutingQuery = true
        appState.query.queryError = nil
        appState.query.queryExecutionTime = nil

        let startTime = Date()

        do {
            DebugLog.print("📊 [QueryEditorViewModel] Executing query (type: \(queryType))...")
            let (results, columnNames) = try await appState.connection.databaseService.executeQuery(queryText)

            let endTime = Date()
            let executionTime = endTime.timeIntervalSince(startTime)
            appState.query.queryExecutionTime = executionTime

            if queryType.isMutation && results.isEmpty {
                // Mutation query with no returned rows: keep previous results, show toast
                appState.query.showMutationToast(
                    type: queryType,
                    tableName: tableName
                )
                appState.query.setTemporaryStatus("Executed in \(QueryState.formatExecutionTime(executionTime))")
                DebugLog.print("✅ [QueryEditorViewModel] Mutation query executed, showing toast")

                // Refresh table results if mutation was on the currently selected table
                if let selectedTable = appState.connection.selectedTable,
                   let mutatedTable = tableName,
                   selectedTable.name.lowercased() == mutatedTable.lowercased() {
                    DebugLog.print("🔄 [QueryEditorViewModel] Refreshing selected table after mutation")
                    await appState.executeTableQuery(for: selectedTable)
                }
            } else {
                // Query returned rows (SELECT, or mutation with RETURNING): show results
                appState.query.queryResults = results
                appState.query.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.query.showQueryResults = true
                appState.query.setTemporaryStatus("Executed in \(QueryState.formatExecutionTime(executionTime))")
                DebugLog.print("✅ [QueryEditorViewModel] Query executed, showing \(results.count) results")

                // Cache results to tab for restoration on tab switch
                tabManager.updateActiveTabResults(
                    results: results,
                    columnNames: columnNames.isEmpty ? nil : columnNames
                )
            }

            // Refresh tables list if query modified schema
            if Self.isSchemaModifyingQuery(queryText) {
                await refreshTables(database: database)

                // Clear results if dropped table was the selected table
                if Self.isDropTableQuery(queryText),
                   let selectedTable = appState.connection.selectedTable,
                   let droppedTable = tableName,
                   selectedTable.name.lowercased() == droppedTable.lowercased() {
                    DebugLog.print("🗑️ [QueryEditorViewModel] Dropped selected table, clearing results")
                    appState.connection.selectedTable = nil
                    appState.query.queryResults = []
                    appState.query.queryColumnNames = nil
                    appState.query.showQueryResults = false
                }
            }
        } catch {
            appState.query.queryError = error
            appState.query.queryColumnNames = nil
            appState.query.showQueryResults = true

            let endTime = Date()
            appState.query.queryExecutionTime = endTime.timeIntervalSince(startTime)

            // Show truncated error message
            let errorMessage = PostgresError.extractDetailedMessage(error)
            let truncatedError = errorMessage.count > 50
                ? String(errorMessage.prefix(47)) + "..."
                : errorMessage
            appState.query.setTemporaryStatus("Error: \(truncatedError)")

            DebugLog.print("❌ [QueryEditorViewModel] Query execution failed: \(error)")
        }

        appState.query.isExecutingQuery = false
    }

    // MARK: - Query Persistence

    private func saveQueryWithRetry() async {
        let maxRetries = 2
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                try saveQuery()
                DebugLog.print("💾 [QueryEditorViewModel] Auto-save successful")
                return
            } catch {
                lastError = error
                DebugLog.print("❌ [QueryEditorViewModel] Save attempt \(attempt)/\(maxRetries) failed: \(error)")
                if attempt < maxRetries {
                    DebugLog.print("💾 [QueryEditorViewModel] Retrying save in 100ms...")
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        // All retries failed, show alert
        if let error = lastError {
            DebugLog.print("❌ [QueryEditorViewModel] All save attempts failed, showing alert")
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }

    private func saveQuery() throws {
        let queryText = appState.query.queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't save empty queries
        guard !queryText.isEmpty else {
            DebugLog.print("💾 [QueryEditorViewModel] Save skipped - empty query")
            return
        }

        let now = Date()
        var savedQueryName: String?

        // Check if we're updating an existing saved query
        if let existingId = appState.query.currentSavedQueryId {
            // Update existing query
            let descriptor = FetchDescriptor<SavedQuery>(
                predicate: #Predicate { $0.id == existingId }
            )
            if let existingQuery = try? modelContext.fetch(descriptor).first {
                existingQuery.queryText = queryText
                existingQuery.updatedAt = now
                savedQueryName = existingQuery.name
                DebugLog.print("💾 [QueryEditorViewModel] Updated existing query: \(existingQuery.name)")
            }
        } else {
            // Create new saved query
            let queryName = SavedQuery.generateName(from: queryText)
            let savedQuery = SavedQuery(
                name: queryName,
                queryText: queryText,
                connectionId: appState.connection.currentConnection?.id,
                databaseName: appState.connection.selectedDatabase?.name
            )
            modelContext.insert(savedQuery)

            // Update state to track this query
            appState.query.currentSavedQueryId = savedQuery.id
            savedQueryName = queryName

            // Update tab with new saved query ID
            tabManager.updateActiveTab(savedQueryId: savedQuery.id)

            DebugLog.print("💾 [QueryEditorViewModel] Saved new query: \(queryName)")
        }

        // Update saved timestamp
        appState.query.lastSavedAt = now

        // Update query name for idle display
        appState.query.currentQueryName = savedQueryName

        // Save context - throws on failure
        try modelContext.save()
        DebugLog.print("💾 [QueryEditorViewModel] Context saved to SwiftData")
    }

    // MARK: - Schema Detection

    /// Check if SQL contains schema-modifying statements that affect the tables list
    static func isSchemaModifyingQuery(_ sql: String) -> Bool {
        let upperSQL = sql.uppercased()
        let patterns = [
            "CREATE\\s+TABLE",
            "DROP\\s+TABLE",
            "ALTER\\s+TABLE",
            "CREATE\\s+TEMP(ORARY)?\\s+TABLE"
        ]
        return patterns.contains { pattern in
            upperSQL.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Check if SQL is a DROP TABLE statement
    static func isDropTableQuery(_ sql: String) -> Bool {
        sql.uppercased().range(of: "DROP\\s+TABLE", options: .regularExpression) != nil
    }

    // MARK: - Private Helpers

    private func refreshTables(database: DatabaseInfo) async {
        do {
            appState.connection.tables = try await appState.connection.databaseService.fetchTables(
                database: database.name
            )
            DebugLog.print("🔄 [QueryEditorViewModel] Tables list refreshed after schema change")
        } catch {
            DebugLog.print("⚠️ [QueryEditorViewModel] Failed to refresh tables: \(error)")
        }
    }
}

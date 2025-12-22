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
    // MARK: - Composed State Managers

    let navigation: NavigationState
    let connection: ConnectionState
    let query: QueryState

    // MARK: - Initialization

    init(
        navigation: NavigationState? = nil,
        connection: ConnectionState? = nil,
        query: QueryState? = nil
    ) {
        self.navigation = navigation ?? NavigationState()
        self.connection = connection ?? ConnectionState()
        self.query = query ?? QueryState()
    }

    // MARK: - Convenience Methods

    func showConnectionForm() {
        navigation.showConnectionForm()
    }

    func showConnectionsList() {
        navigation.showConnectionsList()
    }

    // MARK: - Query Execution

    /// Centralized query execution to prevent race conditions when rapidly switching tables
    @MainActor
    func executeTableQuery(for table: TableInfo) async {
        let queryService = QueryService(
            databaseService: connection.databaseService,
            queryState: query
        )

        // Set loading state
        query.isExecutingQuery = true
        query.queryError = nil
        query.queryExecutionTime = nil

        // Execute query
        let result = await queryService.executeTableQuery(
            for: table,
            limit: query.rowsPerPage,
            offset: 0
        )

        // Update state based on result
        if result.isSuccess {
            query.queryResults = result.rows
            query.queryColumnNames = result.columnNames.isEmpty ? nil : result.columnNames
            query.showQueryResults = true
            query.queryExecutionTime = result.executionTime

            // Fetch table metadata (primary keys, column info) for edit/delete operations
            await fetchTableMetadata(for: table)
        } else if let error = result.error {
            query.queryError = error
            query.queryColumnNames = nil
            query.showQueryResults = true
            query.queryExecutionTime = result.executionTime
        }

        query.isExecutingQuery = false
    }

    /// Fetch and cache table metadata (primary keys, column info)
    @MainActor
    private func fetchTableMetadata(for table: TableInfo) async {
        var updatedTable = table

        // Fetch primary key columns if not cached
        if updatedTable.primaryKeyColumns == nil {
            do {
                let pkColumns = try await connection.databaseService.fetchPrimaryKeyColumns(
                    schema: table.schema,
                    table: table.name
                )
                updatedTable.primaryKeyColumns = pkColumns
            } catch {
                DebugLog.print("⚠️ [AppState] Failed to fetch primary keys: \(error)")
            }
        }

        // Fetch column info if not cached
        if updatedTable.columnInfo == nil {
            do {
                let columnInfo = try await connection.databaseService.fetchColumnInfo(
                    schema: table.schema,
                    table: table.name
                )
                updatedTable.columnInfo = columnInfo
            } catch {
                DebugLog.print("⚠️ [AppState] Failed to fetch column info: \(error)")
            }
        }

        // Update selectedTable with metadata
        connection.selectedTable = updatedTable
    }

    // MARK: - Cleanup

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard connection.isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up...")

        // Cancel any pending queries
        query.cleanup()

        // Disconnect and reset connection state
        await connection.cleanupOnWindowClose()

        DebugLog.print("✅ Cleanup completed")
    }
}

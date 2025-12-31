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

    // MARK: - Services

    private let tableMetadataService: TableMetadataServiceProtocol

    // MARK: - Initialization

    init(
        navigation: NavigationState? = nil,
        connection: ConnectionState? = nil,
        query: QueryState? = nil,
        tableMetadataService: TableMetadataServiceProtocol? = nil
    ) {
        self.navigation = navigation ?? NavigationState()
        self.connection = connection ?? ConnectionState()
        self.query = query ?? QueryState()
        self.tableMetadataService = tableMetadataService ?? TableMetadataService()
    }

    // MARK: - Convenience Methods

    func showConnectionForm() {
        navigation.showConnectionForm()
    }

    // MARK: - Query Execution

    /// Centralized query execution to prevent race conditions when rapidly switching tables
    @MainActor
    func executeTableQuery(for table: TableInfo) async {
        // Capture context to verify nothing changed after async operations
        // This prevents stale query results when user switches table, database, or connection
        let tableId = table.id
        let databaseId = connection.selectedDatabase?.id
        let connectionId = connection.currentConnection?.id

        let queryService = QueryService(
            databaseService: connection.databaseService,
            queryState: query
        )

        // Set loading state
        query.startQueryExecution()

        // Execute query (fetch +1 to detect if more pages exists)
        let result = await queryService.executeTableQuery(
            for: table,
            limit: query.rowsPerPage + 1,
            offset: calculateOffset(page: query.currentPage, pageSize: query.rowsPerPage)
        )

        // Only update state if context hasn't changed (table, database, AND connection)
        // Prevents stale results when same table name exists in different databases
        guard connection.isQueryContextValid(
            tableId: tableId,
            databaseId: databaseId,
            connectionId: connectionId
        ) else {
            DebugLog.print("⚠️ [AppState] Query for \(table.name) superseded (context changed), skipping state update")
            query.isExecutingQuery = false
            return
        }

        // Update state based on result
        if result.isSuccess {
            // Check if we got more rows than requested (indicates next page exists)
            query.hasNextPage = hasMorePages(fetchedRowCount: result.rows.count, pageSize: query.rowsPerPage)
            // Trim to actual page size
            let trimmedRows = query.hasNextPage ? Array(result.rows.prefix(query.rowsPerPage)) : result.rows
            let trimmedResult = QueryResult.success(
                rows: trimmedRows,
                columnNames: result.columnNames,
                executionTime: result.executionTime
            )
            query.finishQueryExecution(with: trimmedResult)

            // Fetch table metadata (primary keys, column info) for edit/delete operations
            await fetchTableMetadata(for: table)
        } else {
            query.finishQueryExecution(with: result)
        }
    }

    /// Fetch and cache table metadata (primary keys, column info)
    @MainActor
    private func fetchTableMetadata(for table: TableInfo) async {
        _ = await tableMetadataService.fetchAndCacheMetadata(
            for: table,
            connectionState: connection,
            databaseService: connection.databaseService
        )
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

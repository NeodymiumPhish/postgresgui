//
//  TableRefreshService.swift
//  PostgresGUI
//
//  Centralized service for table loading and refresh operations.
//  Eliminates duplicate loadTables logic across views.
//

import Foundation

/// Service for loading and refreshing table lists
@MainActor
final class TableRefreshService: TableRefreshServiceProtocol {
    private let keychainService: KeychainServiceProtocol

    init(keychainService: KeychainServiceProtocol? = nil) {
        self.keychainService = keychainService ?? KeychainServiceImpl()
    }

    /// Loads tables for a database, reconnecting if necessary.
    /// - Parameters:
    ///   - database: The database to load tables from
    ///   - connection: The connection profile to use
    ///   - appState: The app state to update
    func loadTables(
        for database: DatabaseInfo,
        connection: ConnectionProfile,
        appState: AppState
    ) async {
        // Only clear loading state if we're still the active request for this database
        defer {
            if appState.connection.selectedDatabase?.id == database.id {
                appState.connection.isLoadingTables = false
            }
        }

        guard !Task.isCancelled else { return }

        // Verify this is still the selected database before any work
        guard appState.connection.selectedDatabase?.id == database.id else { return }

        // Extract connection values before async boundaries (Swift 6 Sendable compliance)
        let connectionId = connection.id
        let host = connection.host
        let port = connection.port
        let username = connection.username
        let sslMode = connection.sslModeEnum

        do {
            // Reconnect if not connected to target database
            if appState.connection.databaseService.connectedDatabase != database.name {
                let password = try keychainService.getPassword(for: connectionId) ?? ""
                try await withDatabaseTimeout {
                    try await appState.connection.databaseService.connect(
                        host: host,
                        port: port,
                        username: username,
                        password: password,
                        database: database.name,
                        sslMode: sslMode
                    )
                }
            }

            guard !Task.isCancelled else { return }

            // Verify still selected after reconnect
            guard appState.connection.selectedDatabase?.id == database.id else { return }

            let tables = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchTables(database: database.name)
            }

            let schemas = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchSchemas(database: database.name)
            }

            // Final check before writing - prevent stale data from overwriting newer results
            guard !Task.isCancelled,
                  appState.connection.selectedDatabase?.id == database.id else { return }

            appState.connection.tables = tables
            appState.connection.schemas = schemas
            appState.connection.selectedSchema = nil  // Reset schema filter on database change
            await appState.setSchemaSearchPath(nil)  // Reset search_path to default
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch ConnectionError.connectionCancelled {
            // Silently ignore - superseded by newer request
        } catch {
            // Only write error state if still the active request
            guard appState.connection.selectedDatabase?.id == database.id else { return }
            DebugLog.print("❌ [TableRefreshService] Error loading tables: \(error)")
            appState.connection.tables = []
            appState.connection.tableLoadingError = error
            // Show alert for timeout errors
            if DatabaseError.isTimeout(error) {
                appState.connection.showTableLoadingTimeoutAlert = true
            }
        }
    }

    /// Refreshes both databases and tables lists.
    /// - Parameter appState: The app state to update
    func refresh(appState: AppState) async {
        guard let database = appState.connection.selectedDatabase,
              appState.connection.currentConnection != nil else { return }

        let databaseId = database.id

        defer {
            if appState.connection.selectedDatabase?.id == databaseId {
                appState.connection.isLoadingTables = false
            }
        }
        appState.connection.isLoadingTables = true
        appState.connection.tableLoadingError = nil

        guard appState.connection.databaseService.isConnected else { return }

        // Refresh databases
        do {
            appState.connection.databases = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchDatabases()
            }
            appState.connection.databasesVersion += 1
        } catch {
            DebugLog.print("❌ [TableRefreshService] Error refreshing databases: \(error)")
        }

        // Verify still selected before fetching tables
        guard appState.connection.selectedDatabase?.id == databaseId else { return }

        // Refresh tables and schemas
        do {
            let tables = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchTables(database: database.name)
            }

            let schemas = try await withDatabaseTimeout {
                try await appState.connection.databaseService.fetchSchemas(database: database.name)
            }

            // Final check before writing
            guard appState.connection.selectedDatabase?.id == databaseId else { return }

            appState.connection.tables = tables
            appState.connection.schemas = schemas
            updateSelectedTable(appState: appState)
        } catch {
            guard appState.connection.selectedDatabase?.id == databaseId else { return }
            DebugLog.print("❌ [TableRefreshService] Error refreshing tables: \(error)")
            appState.connection.tables = []
            appState.connection.selectedTable = nil
            appState.connection.tableLoadingError = error
            // Show alert for timeout errors
            if DatabaseError.isTimeout(error) {
                appState.connection.showTableLoadingTimeoutAlert = true
            }
        }
    }

    /// Updates selectedTable reference if it still exists in refreshed list.
    private func updateSelectedTable(appState: AppState) {
        guard let selectedTable = appState.connection.selectedTable,
              let refreshedTable = appState.connection.tables.first(where: { $0.id == selectedTable.id }) else {
            if appState.connection.selectedTable != nil {
                appState.connection.selectedTable = nil
            }
            return
        }

        // Only update if metadata changed
        if refreshedTable != selectedTable {
            appState.connection.selectedTable = refreshedTable
        }
    }
}

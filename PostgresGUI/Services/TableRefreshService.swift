//
//  TableRefreshService.swift
//  PostgresGUI
//
//  Centralized service for table loading and refresh operations.
//  Eliminates duplicate loadTables logic across views.
//

import Foundation

@MainActor
struct TableRefreshService {

    /// Loads tables for a database, reconnecting if necessary.
    /// - Parameters:
    ///   - database: The database to load tables from
    ///   - connection: The connection profile to use
    ///   - appState: The app state to update
    static func loadTables(
        for database: DatabaseInfo,
        connection: ConnectionProfile,
        appState: AppState
    ) async {
        defer { appState.connection.isLoadingTables = false }

        do {
            // Reconnect if not connected to target database
            if appState.connection.databaseService.connectedDatabase != database.name {
                let password = try KeychainService.getPassword(for: connection.id) ?? ""
                try await appState.connection.databaseService.connect(
                    host: connection.host,
                    port: connection.port,
                    username: connection.username,
                    password: password,
                    database: database.name,
                    sslMode: connection.sslModeEnum
                )
            }

            appState.connection.tables = try await appState.connection.databaseService.fetchTables(database: database.name)
        } catch {
            DebugLog.print("❌ [TableRefreshService] Error loading tables: \(error)")
            appState.connection.tables = []
        }
    }

    /// Refreshes both databases and tables lists.
    /// - Parameter appState: The app state to update
    static func refresh(appState: AppState) async {
        guard let database = appState.connection.selectedDatabase,
              appState.connection.currentConnection != nil else { return }

        defer { appState.connection.isLoadingTables = false }
        appState.connection.isLoadingTables = true

        guard appState.connection.databaseService.isConnected else { return }

        // Refresh databases
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("❌ [TableRefreshService] Error refreshing databases: \(error)")
        }

        // Refresh tables
        do {
            appState.connection.tables = try await appState.connection.databaseService.fetchTables(database: database.name)
            updateSelectedTable(appState: appState)
        } catch {
            DebugLog.print("❌ [TableRefreshService] Error refreshing tables: \(error)")
            appState.connection.tables = []
            appState.connection.selectedTable = nil
        }
    }

    /// Updates selectedTable reference if it still exists in refreshed list.
    private static func updateSelectedTable(appState: AppState) {
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

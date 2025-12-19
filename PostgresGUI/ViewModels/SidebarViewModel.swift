//
//  SidebarViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftData

/// ViewModel for ConnectionsDatabasesSidebar
@Observable
@MainActor
class SidebarViewModel {
    private let appState: AppState
    private let connectionService: ConnectionServiceProtocol
    private let userDefaults: UserDefaultsProtocol

    // UI State
    var selectedDatabaseID: DatabaseInfo.ID?
    var showCreateDatabaseForm = false
    var newDatabaseName = ""
    var connectionError: String?
    var showConnectionError = false

    init(appState: AppState, connectionService: ConnectionServiceProtocol, userDefaults: UserDefaultsProtocol? = nil) {
        self.appState = appState
        self.connectionService = connectionService
        self.userDefaults = userDefaults ?? UserDefaultsWrapper()
    }

    /// Connect to a database
    func connect(to connection: ConnectionProfile, persistenceContext: PersistenceContextProtocol) async {
        let result = await connectionService.connect(to: connection, password: nil, saveAsLast: true)

        switch result {
        case .success:
            try? persistenceContext.save()
            // After loading databases, restore last selected database if available
            await restoreLastDatabase()

        case .failure(let error):
            DebugLog.print("Failed to connect: \(error)")
            connectionError = error.localizedDescription
            showConnectionError = true
            // Connection state already reset by ConnectionService
        }
    }

    /// Load tables for a database
    func loadTables(for database: DatabaseInfo) async {
        DebugLog.print("🔄 [SidebarViewModel] Loading tables for database: \(database.name)")

        // Clear tables immediately and show loading state
        appState.tables = []
        appState.isLoadingTables = true

        // Clear table selection and all query-related state
        appState.selectedTable = nil
        appState.queryText = ""
        appState.queryResults = []
        appState.queryColumnNames = nil
        appState.showQueryResults = false
        appState.queryError = nil
        appState.selectedRowIDs = []

        do {
            let tables = try await appState.databaseService.fetchTables(database: database.name)
            appState.tables = tables
            DebugLog.print("✅ [SidebarViewModel] Loaded \(tables.count) tables")
        } catch {
            DebugLog.print("❌ [SidebarViewModel] Failed to load tables: \(error)")
            appState.tables = []
        }

        appState.isLoadingTables = false
    }

    /// Create a new database
    func createDatabase() async {
        guard !newDatabaseName.isEmpty else { return }

        do {
            try await appState.databaseService.createDatabase(name: newDatabaseName)

            // Refresh databases list
            await refreshDatabases()

            // Clear form
            newDatabaseName = ""
            showCreateDatabaseForm = false

            DebugLog.print("✅ [SidebarViewModel] Database created successfully")
        } catch {
            DebugLog.print("❌ [SidebarViewModel] Failed to create database: \(error)")
            // TODO: Show error to user
        }
    }

    /// Delete a database
    func deleteDatabase(_ database: DatabaseInfo) async {
        do {
            try await appState.databaseService.deleteDatabase(name: database.name)

            // If we deleted the selected database, clear selection
            if appState.selectedDatabase?.id == database.id {
                appState.selectedDatabase = nil
                selectedDatabaseID = nil
                appState.tables = []
            }

            // Refresh databases list
            await refreshDatabases()

            DebugLog.print("✅ [SidebarViewModel] Database deleted successfully")
        } catch {
            DebugLog.print("❌ [SidebarViewModel] Failed to delete database: \(error)")
            // TODO: Show error to user
        }
    }

    /// Refresh databases list
    func refreshDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()

            // After refreshing databases, restore last selected database if available
            await restoreLastDatabase()
        } catch {
            DebugLog.print("Failed to refresh databases: \(error)")
        }
    }

    /// Restore the last connected connection on app start
    func restoreLastConnection(connections: [ConnectionProfile], persistenceContext: PersistenceContextProtocol) async {
        // Only restore if not already connected and we have connections
        guard !appState.isConnected, !connections.isEmpty else { return }

        // Get last connection ID from UserDefaults
        guard let lastConnectionIdString = userDefaults.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
              let lastConnectionId = UUID(uuidString: lastConnectionIdString) else {
            return
        }

        // Find the connection in the list
        guard let lastConnection = connections.first(where: { $0.id == lastConnectionId }) else {
            // Connection not found, clear the stored ID
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            return
        }

        DebugLog.print("🔄 [SidebarViewModel] Restoring last connection: \(lastConnection.displayName)")

        // Connect to the last connection
        await connect(to: lastConnection, persistenceContext: persistenceContext)
    }

    // MARK: - Private Helpers

    private func restoreLastDatabase() async {
        // Only restore if no database is currently selected and we have databases
        guard appState.selectedDatabase == nil, !appState.databases.isEmpty else { return }

        // Get last database name from UserDefaults
        guard let lastDatabaseName = userDefaults.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName),
              !lastDatabaseName.isEmpty else {
            return
        }

        // Find the database in the list
        guard let lastDatabase = appState.databases.first(where: { $0.name == lastDatabaseName }) else {
            // Database not found, clear the stored name
            userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            return
        }

        // Set the database selection
        selectedDatabaseID = lastDatabase.id
        appState.selectedDatabase = lastDatabase

        // Load tables for this database
        await loadTables(for: lastDatabase)
    }
}

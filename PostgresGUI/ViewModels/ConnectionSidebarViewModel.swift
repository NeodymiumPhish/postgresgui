//
//  ConnectionSidebarViewModel.swift
//  PostgresGUI
//
//  Handles connection management, database selection, and CRUD operations.
//  Extracted from ConnectionsDatabasesSidebar to separate business logic from presentation.
//
//  Created by ghazi on 12/30/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class ConnectionSidebarViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager
    private let loadingState: LoadingState
    private let modelContext: ModelContext
    private let keychainService: KeychainServiceProtocol

    // MARK: - State

    var connectionError: String?
    var showConnectionError = false
    var hasRestoredConnection = false

    // Database state
    var showCreateDatabaseForm = false
    var newDatabaseName = ""
    var createDatabaseError: String?
    var databaseToDelete: DatabaseInfo?
    var deleteError: String?

    // Connection state
    var connectionToDelete: ConnectionProfile?

    /// Static flag to ensure auto-restore only happens once per app session
    private static var hasRestoredConnectionGlobally = false

    // MARK: - Initialization

    init(
        appState: AppState,
        tabManager: TabManager,
        loadingState: LoadingState,
        modelContext: ModelContext,
        keychainService: KeychainServiceProtocol? = nil
    ) {
        self.appState = appState
        self.tabManager = tabManager
        self.loadingState = loadingState
        self.modelContext = modelContext
        self.keychainService = keychainService ?? KeychainServiceImpl()
    }

    // MARK: - Initialization & Restoration

    /// Wait for initial load to complete before restoring connection
    func waitForInitialLoad() async {
        while !loadingState.hasCompletedInitialLoad {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if appState.connection.currentConnection != nil {
            hasRestoredConnection = true
            Self.hasRestoredConnectionGlobally = true
        }
    }

    /// Restore the last used connection from UserDefaults
    func restoreLastConnection(connections: [ConnectionProfile]) async {
        guard !hasRestoredConnection,
            !Self.hasRestoredConnectionGlobally,
            appState.connection.currentConnection == nil
        else { return }

        hasRestoredConnection = true
        Self.hasRestoredConnectionGlobally = true

        try? await Task.sleep(nanoseconds: 100_000_000)

        guard !connections.isEmpty else { return }

        guard
            let lastConnectionIdString = UserDefaults.standard.string(
                forKey: Constants.UserDefaultsKeys.lastConnectionId),
            let lastConnectionId = UUID(uuidString: lastConnectionIdString)
        else {
            if connections.count == 1, let onlyConnection = connections.first {
                await connect(to: onlyConnection)
            }
            return
        }

        guard let lastConnection = connections.first(where: { $0.id == lastConnectionId }) else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            return
        }

        await connect(to: lastConnection)
    }

    // MARK: - Connection Management

    /// Connect to a connection profile
    func connect(to connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        switch result {
        case .success:
            try? modelContext.save()
            if appState.connection.databases.isEmpty {
                await refreshDatabasesAsync()
            } else {
                await restoreLastDatabase()
            }

        case .failure(let error):
            DebugLog.print("Failed to connect: \(error)")
            connectionError = error.localizedDescription
            showConnectionError = true
        }
    }

    /// Select and connect to a connection from the dropdown
    func selectConnection(_ connection: ConnectionProfile) async {
        // Skip if already connected to this connection
        guard appState.connection.currentConnection?.id != connection.id else { return }

        // Clear current state before switching
        appState.connection.selectedDatabase = nil
        appState.connection.tables = []
        appState.connection.selectedTable = nil
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)

        await connect(to: connection)
    }

    /// Delete a connection
    func deleteConnection(_ connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )
        await connectionService.delete(connection: connection, from: modelContext)
        connectionToDelete = nil
    }

    // MARK: - Database Management

    /// Select a database
    func selectDatabase(_ database: DatabaseInfo, persistSelection: Bool = true) {
        appState.connection.selectedDatabase = database
        appState.connection.tables = []
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil

        if persistSelection {
            UserDefaults.standard.set(
                database.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            tabManager.updateActiveTab(connectionId: nil, databaseName: database.name, queryText: nil)
        }

        Task {
            await loadTables(for: database)
        }
    }

    /// Create a new database
    func createDatabase() async {
        guard !newDatabaseName.isEmpty else { return }

        do {
            try await appState.connection.databaseService.createDatabase(name: newDatabaseName)
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            newDatabaseName = ""
        } catch {
            createDatabaseError = PostgresError.extractDetailedMessage(error)
        }
    }

    /// Delete a database
    func deleteDatabase(_ database: DatabaseInfo) async {
        do {
            try await appState.connection.databaseService.deleteDatabase(name: database.name)
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            databaseToDelete = nil
        } catch {
            deleteError = PostgresError.extractDetailedMessage(error)
        }
    }

    // MARK: - Connection State Change Handling

    /// Handle connection change: clear database selection when connection changes
    func handleConnectionChange(oldValue: ConnectionProfile?, newValue: ConnectionProfile?) {
        if oldValue != nil && newValue != oldValue {
            UserDefaults.standard.removeObject(
                forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            appState.connection.selectedDatabase = nil
        }
    }

    /// Update tab when connection changes
    func updateTabForConnectionChange(_ newConnection: ConnectionProfile?) {
        tabManager.updateActiveTab(
            connectionId: newConnection?.id, databaseName: nil, queryText: nil)
    }

    /// Update tab when database changes
    func updateTabForDatabaseChange(_ newDatabase: DatabaseInfo?) {
        tabManager.updateActiveTab(
            connectionId: nil, databaseName: newDatabase?.name, queryText: nil)
    }

    // MARK: - Private Helpers

    private func refreshDatabasesAsync() async {
        do {
            appState.connection.databases = try await appState.connection.databaseService
                .fetchDatabases()
            await restoreLastDatabase()
        } catch {
            DebugLog.print("Failed to refresh databases: \(error)")
        }
    }

    private func restoreLastDatabase() async {
        guard appState.connection.selectedDatabase == nil, !appState.connection.databases.isEmpty
        else { return }

        guard
            let lastDatabaseName = UserDefaults.standard.string(
                forKey: Constants.UserDefaultsKeys.lastDatabaseName),
            !lastDatabaseName.isEmpty
        else { return }

        guard
            let lastDatabase = appState.connection.databases.first(where: {
                $0.name == lastDatabaseName
            })
        else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            return
        }

        selectDatabase(lastDatabase, persistSelection: false)
    }

    private func loadTables(for database: DatabaseInfo) async {
        guard let connection = appState.connection.currentConnection else { return }
        await TableRefreshService.loadTables(
            for: database,
            connection: connection,
            appState: appState,
            keychainService: keychainService
        )
    }
}

//
//  ConnectionsDatabasesSidebar.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftData
import SwiftUI

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(LoadingState.self) private var loadingState
    @Environment(\.modelContext) private var modelContext

    @Query private var connections: [ConnectionProfile]

    @State private var connectionError: String?
    @State private var showConnectionError = false
    @State private var hasRestoredConnection = false

    // Database dropdown state
    @State private var showDatabaseDropdown = false
    @State private var showCreateDatabaseForm = false
    @State private var newDatabaseName = ""
    @State private var createDatabaseError: String?
    @State private var databaseToDelete: DatabaseInfo?
    @State private var deleteError: String?

    /// Static flag to ensure auto-restore only happens once per app session
    private static var hasRestoredConnectionGlobally = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionDatabasePicker(
                showDatabaseDropdown: $showDatabaseDropdown,
                onShowConnectionsList: {
                    appState.navigation.showConnectionsList()
                },
                onSelectDatabase: { database in
                    selectDatabase(database, persistSelection: true)
                },
                onDeleteDatabase: { database in
                    databaseToDelete = database
                },
                onCreateDatabase: {
                    showCreateDatabaseForm = true
                },
                onDeleteError: { error in
                    deleteError = error
                }
            )

            TablesListIsolated(
                tables: appState.connection.tables,
                selectedTable: Binding(
                    get: { appState.connection.selectedTable },
                    set: { appState.connection.selectedTable = $0 }
                ),
                isLoadingTables: appState.connection.isLoadingTables,
                selectedDatabase: appState.connection.selectedDatabase,
                refreshTablesAction: {
                    await TableRefreshService.refresh(appState: appState)
                }
            )
        }
        .onChange(of: appState.connection.currentConnection) { oldValue, newValue in
            if oldValue != nil && newValue != oldValue {
                UserDefaults.standard.removeObject(
                    forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                appState.connection.selectedDatabase = nil
            }
        }
        .task {
            await waitForInitialLoad()
            await restoreLastConnection()
        }
        .onChange(of: appState.connection.currentConnection) { _, newConnection in
            tabManager.updateActiveTab(
                connectionId: newConnection?.id, databaseName: nil, queryText: nil)
        }
        .onChange(of: appState.connection.selectedDatabase) { _, newDatabase in
            tabManager.updateActiveTab(
                connectionId: nil, databaseName: newDatabase?.name, queryText: nil)
        }
        .alert("Connection Failed", isPresented: $showConnectionError) {
            Button("OK", role: .cancel) {
                connectionError = nil
            }
        } message: {
            if let error = connectionError {
                Text(error)
            }
        }
        .alert("Create Database", isPresented: $showCreateDatabaseForm) {
            TextField("Database Name", text: $newDatabaseName)
            Button("Create") {
                Task {
                    await createDatabase()
                }
            }
            Button("Cancel", role: .cancel) {
                newDatabaseName = ""
            }
        }
        .alert("Error Creating Database", isPresented: Binding(
            get: { createDatabaseError != nil },
            set: { if !$0 { createDatabaseError = nil } }
        )) {
            Button("OK", role: .cancel) {
                createDatabaseError = nil
            }
        } message: {
            if let error = createDatabaseError {
                Text(error)
            }
        }
        .confirmationDialog(
            "Delete Database?",
            isPresented: Binding(
                get: { databaseToDelete != nil },
                set: { if !$0 { databaseToDelete = nil } }
            ),
            presenting: databaseToDelete
        ) { database in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteDatabase(database)
                }
            }
            Button("Cancel", role: .cancel) {
                databaseToDelete = nil
            }
        } message: { database in
            Text("Are you sure you want to delete '\(database.name)'? This action cannot be undone.")
        }
        .alert("Error Deleting Database", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {
                deleteError = nil
            }
        } message: {
            if let error = deleteError {
                Text(error)
            }
        }
    }

    // MARK: - Database Selection

    /// Unified database selection logic used by both user selection and restore
    private func selectDatabase(_ database: DatabaseInfo, persistSelection: Bool) {
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

    // MARK: - Initialization

    private func waitForInitialLoad() async {
        while !loadingState.hasCompletedInitialLoad {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if appState.connection.currentConnection != nil {
            hasRestoredConnection = true
            Self.hasRestoredConnectionGlobally = true
        }
    }

    private func restoreLastConnection() async {
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

    // MARK: - Connection

    @MainActor
    private func connect(to connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: KeychainServiceImpl()
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

    // MARK: - Database Operations

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
            for: database, connection: connection, appState: appState)
    }

    private func createDatabase() async {
        guard !newDatabaseName.isEmpty else { return }

        do {
            try await appState.connection.databaseService.createDatabase(name: newDatabaseName)
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            newDatabaseName = ""
        } catch {
            createDatabaseError = PostgresError.extractDetailedMessage(error)
        }
    }

    private func deleteDatabase(_ database: DatabaseInfo) async {
        do {
            try await appState.connection.databaseService.deleteDatabase(name: database.name)
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            databaseToDelete = nil
        } catch {
            deleteError = PostgresError.extractDetailedMessage(error)
        }
    }
}

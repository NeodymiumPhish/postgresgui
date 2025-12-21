//
//  ConnectionsDatabasesSidebar.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

enum SidebarViewMode: String, CaseIterable {
    case connections
    case queries
}

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(LoadingState.self) private var loadingState
    @Environment(\.modelContext) private var modelContext

    @Query private var connections: [ConnectionProfile]
    @Query(sort: \SavedQuery.updatedAt, order: .reverse) private var savedQueries: [SavedQuery]
    @Query(sort: \QueryFolder.name) private var queryFolders: [QueryFolder]

    @State private var selectedDatabaseID: DatabaseInfo.ID?
    @State private var selectedQueryIDs: Set<SavedQuery.ID> = []
    @State private var connectionError: String?
    @State private var showConnectionError = false
    @State private var showCreateDatabaseForm = false
    @State private var newDatabaseName = ""
    @State private var createDatabaseError: String?
    @State private var hasRestoredConnection = false

    /// Static flag to ensure auto-restore only happens once per app session
    private static var hasRestoredConnectionGlobally = false

    var body: some View {
        Group {
            switch appState.sidebarViewMode {
            case .connections:
                ConnectionsSidebarSection(
                    selectedDatabaseID: $selectedDatabaseID,
                    showCreateDatabaseForm: $showCreateDatabaseForm,
                    connections: connections,
                    onConnect: connect,
                    onLoadTables: loadTables
                )
            case .queries:
                SavedQueriesSidebarSection(
                    savedQueries: savedQueries,
                    folders: queryFolders,
                    selectedQueryIDs: $selectedQueryIDs
                )
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Divider()
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
        .onChange(of: appState.currentConnection) { oldValue, newValue in
            if oldValue != nil && newValue != oldValue {
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                selectedDatabaseID = nil
                appState.selectedDatabase = nil
            }
        }
        .task {
            await waitForInitialLoad()
            await restoreLastConnection()
        }
        .onChange(of: appState.currentConnection) { _, newConnection in
            tabManager.updateActiveTab(connectionId: newConnection?.id, databaseName: nil, queryText: nil)
        }
        .onChange(of: appState.selectedDatabase) { _, newDatabase in
            tabManager.updateActiveTab(connectionId: nil, databaseName: newDatabase?.name, queryText: nil)
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
    }

    // MARK: - Initialization

    private func waitForInitialLoad() async {
        while !loadingState.hasCompletedInitialLoad {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if appState.currentConnection != nil {
            hasRestoredConnection = true
            Self.hasRestoredConnectionGlobally = true
            if let database = appState.selectedDatabase {
                selectedDatabaseID = database.id
            }
        }
    }

    private func restoreLastConnection() async {
        guard !hasRestoredConnection,
              !Self.hasRestoredConnectionGlobally,
              appState.currentConnection == nil else { return }

        hasRestoredConnection = true
        Self.hasRestoredConnectionGlobally = true

        try? await Task.sleep(nanoseconds: 100_000_000)

        guard !connections.isEmpty else { return }

        guard let lastConnectionIdString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
              let lastConnectionId = UUID(uuidString: lastConnectionIdString) else {
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

    private func connect(to connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: KeychainServiceImpl()
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        switch result {
        case .success:
            try? modelContext.save()
            if appState.databases.isEmpty {
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
            appState.databases = try await appState.databaseService.fetchDatabases()
            await restoreLastDatabase()
        } catch {
            DebugLog.print("Failed to refresh databases: \(error)")
        }
    }

    private func restoreLastDatabase() async {
        guard appState.selectedDatabase == nil, !appState.databases.isEmpty else { return }

        guard let lastDatabaseName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName),
              !lastDatabaseName.isEmpty else { return }

        guard let lastDatabase = appState.databases.first(where: { $0.name == lastDatabaseName }) else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            return
        }

        selectedDatabaseID = lastDatabase.id
        appState.selectedDatabase = lastDatabase
        appState.tables = []
        appState.isLoadingTables = true
        appState.selectedTable = nil

        await loadTables(for: lastDatabase)
    }

    private func loadTables(for database: DatabaseInfo) async {
        guard let connection = appState.currentConnection else { return }
        await TableRefreshService.loadTables(for: database, connection: connection, appState: appState)
    }

    private func createDatabase() async {
        guard !newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            createDatabaseError = "Database name cannot be empty"
            return
        }

        let databaseName = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await appState.databaseService.createDatabase(name: databaseName)
            newDatabaseName = ""
            await refreshDatabasesAsync()
        } catch {
            createDatabaseError = error.localizedDescription
        }
    }
}

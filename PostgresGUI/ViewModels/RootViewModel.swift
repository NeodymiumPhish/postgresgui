//
//  RootViewModel.swift
//  PostgresGUI
//
//  Handles app initialization, tab switching, and connection restoration.
//  Extracted from RootView to separate business logic from presentation.
//
//  Created by ghazi on 12/30/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class RootViewModel {
    // MARK: - Dependencies

    private let appState: AppState
    private let tabManager: TabManager
    private let loadingState: LoadingState
    private let modelContext: ModelContext
    private let keychainService: KeychainServiceProtocol

    // MARK: - State

    var initializationError: String?

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

    // MARK: - App Initialization

    /// Initialize the app: restore tabs, connect to last connection, load databases/tables
    func initializeApp(connections: [ConnectionProfile]) async {
        DebugLog.print("🚀 [RootViewModel] initializeApp started")

        // Initialize tab manager with model context
        loadingState.setPhase(.restoringTabs)
        tabManager.initialize(with: modelContext)

        // Wait for SwiftData to load connections
        try? await Task.sleep(nanoseconds: 100_000_000)

        DebugLog.print("🚀 [RootViewModel] connections count: \(connections.count)")

        // If no connections exist, skip to ready state (show welcome)
        guard !connections.isEmpty else {
            DebugLog.print("🚀 [RootViewModel] No connections, showing welcome")
            loadingState.setReady()
            return
        }

        // Get active tab's connection
        guard let activeTab = tabManager.activeTab,
              let connectionId = activeTab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            DebugLog.print("🚀 [RootViewModel] No connection to restore, finishing")
            loadingState.setReady()
            return
        }

        DebugLog.print("🚀 [RootViewModel] Restoring connection: \(connection.displayName)")

        // Restore query text and saved query selection from active tab
        restoreQueryStateFromTab(activeTab)

        // Connect to database
        loadingState.setPhase(.connectingToDatabase)
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: keychainService
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        if case .failure(let error) = result {
            initializationError = PostgresError.extractDetailedMessage(error)
            loadingState.setReady()
            return
        }

        // Load databases
        loadingState.setPhase(.loadingDatabases)
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("Failed to load databases: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            loadingState.setReady()
            return
        }

        // Restore database selection from active tab
        if let databaseName = activeTab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database

            // Load tables
            loadingState.setPhase(.loadingTables)
            await loadTables(for: database, connection: connection)
        }

        loadingState.setReady()
        appState.navigation.isShowingWelcomeScreen = false
    }

    // MARK: - Tab Change Handling

    /// Handle tab switch: restore query state, connect if needed, load tables
    func handleTabChange(_ tab: TabState?, connections: [ConnectionProfile]) async {
        guard let tab = tab else { return }
        guard !Task.isCancelled else {
            DebugLog.print("📑 [RootViewModel] Tab change cancelled before start")
            return
        }

        DebugLog.print("📑 [RootViewModel] Tab changed to: \(tab.id)")

        // Restore query text and saved query selection
        let previousQueryText = appState.query.queryText
        restoreQueryStateFromTab(tab)
        if previousQueryText != tab.queryText {
            DebugLog.print("📝 [RootViewModel] queryText changed from: \"\(previousQueryText.prefix(30))...\" to: \"\(tab.queryText.prefix(30))...\" (tab restore)")
        }

        // Restore cached results from tab (or clear if none)
        restoreCachedResultsFromTab(tab)

        // If tab has no connection, just clear and return
        guard let connectionId = tab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            clearConnectionState()
            return
        }

        // Check if we're switching to the same connection AND database
        let sameConnection = appState.connection.currentConnection?.id == connectionId
        let sameDatabase = appState.connection.selectedDatabase?.name == tab.databaseName
        let isConnected = appState.connection.databaseService.isConnected

        if sameConnection && sameDatabase && isConnected && !appState.connection.tables.isEmpty {
            // Fast path: same connection and database, just restore table selection
            DebugLog.print("📑 [RootViewModel] Tab switch - same connection/database, restoring table selection only")
            restoreTableSelectionFromTab(tab)
            return
        }

        // Set loading state and clear tables for full reload
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil
        appState.connection.tables = []

        // Connect if different connection or not connected
        if !sameConnection || !isConnected {
            DebugLog.print("🔌 [RootViewModel] Tab switch requires connection to: \(connection.displayName)")
            let connectionService = ConnectionService(
                appState: appState,
                keychainService: keychainService
            )

            let result = await connectionService.connect(to: connection, saveAsLast: false)

            // Check if cancelled after async operation
            guard !Task.isCancelled else {
                DebugLog.print("📑 [RootViewModel] Tab change cancelled after connection")
                appState.connection.isLoadingTables = false
                return
            }

            if case .failure(let error) = result {
                DebugLog.print("❌ [RootViewModel] Tab switch connection failed: \(error)")
                initializationError = PostgresError.extractDetailedMessage(error)
                appState.connection.isLoadingTables = false
                return
            }
            DebugLog.print("✅ [RootViewModel] Tab switch connection successful")
        } else {
            DebugLog.print("🔌 [RootViewModel] Tab switch reusing existing connection to: \(connection.displayName)")
        }

        // Load databases
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("Failed to load databases: \(error)")
            initializationError = PostgresError.extractDetailedMessage(error)
            appState.connection.isLoadingTables = false
            return
        }

        // Check if cancelled after database fetch
        guard !Task.isCancelled else {
            DebugLog.print("📑 [RootViewModel] Tab change cancelled after fetching databases")
            appState.connection.isLoadingTables = false
            return
        }

        // Restore database selection
        if let databaseName = tab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database
            await loadTables(for: database, connection: connection)

            // Restore table selection from tab (after tables are loaded)
            restoreTableSelectionFromTab(tab)
        } else {
            // No database selected in tab, stop loading
            appState.connection.isLoadingTables = false
        }
    }

    // MARK: - Tab State Management

    /// Save current state to active tab before switching or closing
    func saveCurrentStateToTab() {
        guard let activeTab = tabManager.activeTab else { return }
        tabManager.updateActiveTab(
            connectionId: activeTab.connectionId,
            databaseName: activeTab.databaseName,
            queryText: appState.query.queryText,
            savedQueryId: appState.query.currentSavedQueryId
        )
    }

    /// Create a new tab inheriting from current
    func createNewTab() {
        saveCurrentStateToTab()
        tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
    }

    /// Close the current tab
    func closeCurrentTab() {
        guard let activeTab = tabManager.activeTab else { return }
        tabManager.closeTab(activeTab)
    }

    // MARK: - Private Helpers

    private func restoreQueryStateFromTab(_ tab: TabState) {
        appState.query.isRestoringFromTab = true
        appState.query.queryText = tab.queryText
        appState.query.currentSavedQueryId = tab.savedQueryId
        restoreSavedQueryMetadata(for: tab.savedQueryId)
        appState.query.isRestoringFromTab = false
    }

    private func restoreCachedResultsFromTab(_ tab: TabState) {
        if let cachedResults = tab.cachedResults {
            appState.query.queryResults = cachedResults
            appState.query.queryColumnNames = tab.cachedColumnNames
            appState.query.showQueryResults = true
            if let schema = tab.selectedTableSchema, let name = tab.selectedTableName {
                appState.query.cachedResultsTableId = "\(schema).\(name)"
            } else {
                appState.query.cachedResultsTableId = nil
            }
            DebugLog.print("📊 [RootViewModel] Restored \(cachedResults.count) cached query results")
        } else {
            appState.query.queryResults = []
            appState.query.queryColumnNames = nil
            appState.query.cachedResultsTableId = nil
        }
    }

    private func restoreTableSelectionFromTab(_ tab: TabState) {
        if let tableSchema = tab.selectedTableSchema,
           let tableName = tab.selectedTableName,
           let table = appState.connection.tables.first(where: {
               $0.schema == tableSchema && $0.name == tableName
           }) {
            appState.connection.selectedTable = table
        } else {
            appState.connection.selectedTable = nil
        }
    }

    private func clearConnectionState() {
        appState.connection.currentConnection = nil
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
        appState.connection.databases = []
        appState.connection.tables = []
        appState.connection.isLoadingTables = false
    }

    private func restoreSavedQueryMetadata(for savedQueryId: UUID?) {
        guard let savedQueryId = savedQueryId else {
            appState.query.currentQueryName = nil
            appState.query.lastSavedAt = nil
            return
        }

        let descriptor = FetchDescriptor<SavedQuery>(
            predicate: #Predicate { $0.id == savedQueryId }
        )
        if let savedQuery = try? modelContext.fetch(descriptor).first {
            appState.query.currentQueryName = savedQuery.name
            appState.query.lastSavedAt = savedQuery.updatedAt
        }
    }

    private func loadTables(for database: DatabaseInfo, connection: ConnectionProfile) async {
        await TableRefreshService.loadTables(
            for: database,
            connection: connection,
            appState: appState,
            keychainService: keychainService
        )
    }
}

//
//  RootView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appState = AppState()
    @State private var loadingState = LoadingState()
    @State private var tabManager = TabManager()
    @State private var initializationError: String?
    @State private var tabChangeTask: Task<Void, Never>?
    @Query private var connections: [ConnectionProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if appState.navigation.isShowingWelcomeScreen && connections.isEmpty {
                    WelcomeView()
                        .environment(appState)
                } else {
                    MainSplitView()
                        .environment(appState)
                }
            }

            if loadingState.isLoading {
                LoadingOverlayView(phase: loadingState.phase)
            }
        }
        .environment(tabManager)
        .environment(loadingState)
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingConnectionForm },
            set: { newValue in
                appState.navigation.isShowingConnectionForm = newValue
                if !newValue {
                    // Clear state when sheet is dismissed
                    appState.navigation.connectionToEdit = nil
                }
            }
        )) {
            ConnectionFormView(connectionToEdit: appState.navigation.connectionToEdit)
                .environment(appState)
        }
        .task {
            await initializeApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { notification in
            // Cancel any in-progress tab change to prevent race conditions
            tabChangeTask?.cancel()
            tabChangeTask = Task {
                await handleTabChange(notification.object as? TabState)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTab)) { _ in
            // Save only query state before creating new tab - use tab's stored connection/database
            // to avoid overwriting with stale UI state during rapid switching
            if let activeTab = tabManager.activeTab {
                tabManager.updateActiveTab(
                    connectionId: activeTab.connectionId,
                    databaseName: activeTab.databaseName,
                    queryText: appState.query.queryText,
                    savedQueryId: appState.query.currentSavedQueryId
                )
            }
            // Create new tab inheriting from current
            tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
            // Switch to the new tab
            if let newTab = tabManager.activeTab {
                tabChangeTask?.cancel()
                tabChangeTask = Task {
                    await handleTabChange(newTab)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            guard let activeTab = tabManager.activeTab else { return }
            tabManager.closeTab(activeTab)
            // Switch to the new active tab
            if let newActiveTab = tabManager.activeTab {
                tabChangeTask?.cancel()
                tabChangeTask = Task {
                    await handleTabChange(newActiveTab)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                // Window is closing - save tab state and cleanup connection
                Task { @MainActor in
                    // Use tab's stored connection/database to avoid stale UI state
                    if let activeTab = tabManager.activeTab {
                        tabManager.updateActiveTab(
                            connectionId: activeTab.connectionId,
                            databaseName: activeTab.databaseName,
                            queryText: appState.query.queryText,
                            savedQueryId: appState.query.currentSavedQueryId
                        )
                    }
                    await appState.cleanupOnWindowClose()
                }
            }
        }
        .alert("Connection Error", isPresented: .init(
            get: { initializationError != nil },
            set: { if !$0 { initializationError = nil } }
        )) {
            Button("OK", role: .cancel) { initializationError = nil }
        } message: {
            if let error = initializationError { Text(error) }
        }
    }

    private func initializeApp() async {
        DebugLog.print("🚀 [RootView] initializeApp started")

        // Initialize tab manager with model context
        loadingState.setPhase(.restoringTabs)
        tabManager.initialize(with: modelContext)

        // Wait for SwiftData to load connections
        try? await Task.sleep(nanoseconds: 100_000_000)

        DebugLog.print("🚀 [RootView] connections count: \(connections.count)")

        // If no connections exist, skip to ready state (show welcome)
        guard !connections.isEmpty else {
            DebugLog.print("🚀 [RootView] No connections, showing welcome")
            loadingState.setReady()
            return
        }

        // Get active tab's connection
        guard let activeTab = tabManager.activeTab,
              let connectionId = activeTab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            DebugLog.print("🚀 [RootView] No connection to restore, finishing")
            loadingState.setReady()
            return
        }

        DebugLog.print("🚀 [RootView] Restoring connection: \(connection.displayName)")

        // Restore query text and saved query selection from active tab
        // Set flag to prevent auto-save from creating duplicate queries
        appState.query.isRestoringFromTab = true
        appState.query.queryText = activeTab.queryText
        appState.query.currentSavedQueryId = activeTab.savedQueryId
        restoreSavedQueryMetadata(for: activeTab.savedQueryId)
        appState.query.isRestoringFromTab = false

        // Restore cached query results from tab
        if let cachedResults = activeTab.cachedResults {
            appState.query.queryResults = cachedResults
            appState.query.queryColumnNames = activeTab.cachedColumnNames
            appState.query.showQueryResults = true
            // Set the table ID so QueryResultsView knows these results belong to this table
            if let schema = activeTab.selectedTableSchema, let name = activeTab.selectedTableName {
                appState.query.cachedResultsTableId = "\(schema).\(name)"
            }
            DebugLog.print("📊 [RootView] Restored \(cachedResults.count) cached query results on app launch")
        }

        // Connect to database
        loadingState.setPhase(.connectingToDatabase)
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: KeychainServiceImpl()
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

    private func loadTables(for database: DatabaseInfo, connection: ConnectionProfile) async {
        await TableRefreshService.loadTables(for: database, connection: connection, appState: appState)
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

    private func handleTabChange(_ tab: TabState?) async {
        guard let tab = tab else { return }
        guard !Task.isCancelled else {
            DebugLog.print("📑 [RootView] Tab change cancelled before start")
            return
        }

        DebugLog.print("📑 [RootView] Tab changed to: \(tab.id)")

        // Restore query text and saved query selection
        // Set flag to prevent auto-save from creating duplicate queries
        let previousQueryText = appState.query.queryText
        appState.query.isRestoringFromTab = true
        appState.query.queryText = tab.queryText
        appState.query.currentSavedQueryId = tab.savedQueryId
        restoreSavedQueryMetadata(for: tab.savedQueryId)
        appState.query.isRestoringFromTab = false
        if previousQueryText != tab.queryText {
            DebugLog.print("📝 [RootView] queryText changed from: \"\(previousQueryText.prefix(30))...\" to: \"\(tab.queryText.prefix(30))...\" (tab restore)")
        }

        // Restore cached results from tab (or clear if none)
        if let cachedResults = tab.cachedResults {
            appState.query.queryResults = cachedResults
            appState.query.queryColumnNames = tab.cachedColumnNames
            appState.query.showQueryResults = true
            // Set the table ID so QueryResultsView knows these results belong to this table
            if let schema = tab.selectedTableSchema, let name = tab.selectedTableName {
                appState.query.cachedResultsTableId = "\(schema).\(name)"
            } else {
                appState.query.cachedResultsTableId = nil
            }
        } else {
            appState.query.queryResults = []
            appState.query.queryColumnNames = nil
            appState.query.cachedResultsTableId = nil
        }

        // If tab has no connection, just clear and return
        guard let connectionId = tab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            appState.connection.currentConnection = nil
            appState.connection.selectedDatabase = nil
            appState.connection.selectedTable = nil
            appState.connection.databases = []
            appState.connection.tables = []
            appState.connection.isLoadingTables = false
            return
        }

        // Check if we're switching to the same connection AND database
        let sameConnection = appState.connection.currentConnection?.id == connectionId
        let sameDatabase = appState.connection.selectedDatabase?.name == tab.databaseName
        let isConnected = appState.connection.databaseService.isConnected

        if sameConnection && sameDatabase && isConnected && !appState.connection.tables.isEmpty {
            // Fast path: same connection and database, just restore table selection
            DebugLog.print("📑 [RootView] Tab switch - same connection/database, restoring table selection only")

            if let tableSchema = tab.selectedTableSchema,
               let tableName = tab.selectedTableName,
               let table = appState.connection.tables.first(where: {
                   $0.schema == tableSchema && $0.name == tableName
               }) {
                appState.connection.selectedTable = table
            } else {
                appState.connection.selectedTable = nil
            }
            return
        }

        // Set loading state and clear tables for full reload
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil
        appState.connection.tables = []

        // Connect if different connection or not connected
        if !sameConnection || !isConnected {
            DebugLog.print("🔌 [RootView] Tab switch requires connection to: \(connection.displayName)")
            let connectionService = ConnectionService(
                appState: appState,
                keychainService: KeychainServiceImpl()
            )

            let result = await connectionService.connect(to: connection, saveAsLast: false)

            // Check if cancelled after async operation
            guard !Task.isCancelled else {
                DebugLog.print("📑 [RootView] Tab change cancelled after connection")
                appState.connection.isLoadingTables = false
                return
            }

            if case .failure(let error) = result {
                DebugLog.print("❌ [RootView] Tab switch connection failed: \(error)")
                initializationError = PostgresError.extractDetailedMessage(error)
                appState.connection.isLoadingTables = false
                return
            }
            DebugLog.print("✅ [RootView] Tab switch connection successful")
        } else {
            DebugLog.print("🔌 [RootView] Tab switch reusing existing connection to: \(connection.displayName)")
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
            DebugLog.print("📑 [RootView] Tab change cancelled after fetching databases")
            appState.connection.isLoadingTables = false
            return
        }

        // Restore database selection
        if let databaseName = tab.databaseName,
           let database = appState.connection.databases.first(where: { $0.name == databaseName }) {
            appState.connection.selectedDatabase = database
            await loadTables(for: database, connection: connection)

            // Restore table selection from tab (after tables are loaded)
            if let tableSchema = tab.selectedTableSchema,
               let tableName = tab.selectedTableName,
               let table = appState.connection.tables.first(where: {
                   $0.schema == tableSchema && $0.name == tableName
               }) {
                appState.connection.selectedTable = table
            }
        } else {
            // No database selected in tab, stop loading
            appState.connection.isLoadingTables = false
        }
    }
}

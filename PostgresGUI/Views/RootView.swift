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
                if newValue {
                    // Close other sheet before opening this one
                    appState.navigation.isShowingConnectionsList = false
                }
                appState.navigation.isShowingConnectionForm = newValue
                if !newValue {
                    // If form was opened from connections list, return to it
                    // (unless this was the first connection from welcome screen)
                    if appState.navigation.connectionFormOpenedFromList {
                        appState.navigation.isShowingConnectionsList = true
                    }
                    // Clear state when sheet is dismissed
                    appState.navigation.connectionToEdit = nil
                    appState.navigation.connectionFormOpenedFromList = false
                }
            }
        )) {
            ConnectionFormView(connectionToEdit: appState.navigation.connectionToEdit)
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.navigation.isShowingConnectionsList },
            set: { newValue in
                if newValue {
                    // Close other sheet before opening this one
                    appState.navigation.isShowingConnectionForm = false
                }
                appState.navigation.isShowingConnectionsList = newValue
            }
        )) {
            ConnectionsListView()
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
        .alert(
            "Connection Created: \"\(appState.navigation.savedConnection?.displayName ?? "")\"",
            isPresented: Binding(
                get: { appState.navigation.showConnectionSavedAlert },
                set: { appState.navigation.showConnectionSavedAlert = $0 }
            )
        ) {
            Button("Not Now", role: .cancel) {
                appState.navigation.savedConnection = nil
            }
            Button("Connect") {
                if let connection = appState.navigation.savedConnection {
                    appState.connection.currentConnection = connection
                }
                appState.navigation.savedConnection = nil
            }
        } message: {
            Text("Connect now?")
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

        // Set loading state BEFORE clearing tables to prevent "No tables found" flash
        appState.connection.isLoadingTables = true

        // Clear current state
        appState.connection.selectedTable = nil
        appState.connection.tables = []
        appState.query.queryResults = []
        appState.query.queryColumnNames = nil

        // If tab has no connection, just clear and return
        guard let connectionId = tab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            appState.connection.currentConnection = nil
            appState.connection.selectedDatabase = nil
            appState.connection.databases = []
            appState.connection.isLoadingTables = false
            return
        }

        // Connect if different connection or not connected
        if appState.connection.currentConnection?.id != connectionId || !appState.connection.databaseService.isConnected {
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
        } else {
            // No database selected in tab, stop loading
            appState.connection.isLoadingTables = false
        }
    }
}

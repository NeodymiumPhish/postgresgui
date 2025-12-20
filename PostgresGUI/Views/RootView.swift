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
    @Query private var connections: [ConnectionProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if appState.isShowingWelcomeScreen && connections.isEmpty {
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
            get: { appState.isShowingConnectionForm },
            set: { newValue in
                if newValue {
                    // Close other sheet before opening this one
                    appState.isShowingConnectionsList = false
                }
                appState.isShowingConnectionForm = newValue
                if !newValue {
                    // Clear edit state when sheet is dismissed
                    appState.connectionToEdit = nil
                }
            }
        )) {
            ConnectionFormView(connectionToEdit: appState.connectionToEdit)
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingConnectionsList },
            set: { newValue in
                if newValue {
                    // Close other sheet before opening this one
                    appState.isShowingConnectionForm = false
                }
                appState.isShowingConnectionsList = newValue
            }
        )) {
            ConnectionsListView()
                .environment(appState)
        }
        .task {
            await initializeApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { notification in
            Task {
                await handleTabChange(notification.object as? TabState)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTab)) { _ in
            // Save current state before creating new tab
            tabManager.updateActiveTab(
                connectionId: appState.currentConnection?.id,
                databaseName: appState.selectedDatabase?.name,
                queryText: appState.queryText
            )
            // Create new tab inheriting from current
            tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
            // Switch to the new tab
            if let newTab = tabManager.activeTab {
                Task {
                    await handleTabChange(newTab)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeCurrentTab)) { _ in
            guard let activeTab = tabManager.activeTab else { return }
            tabManager.closeTab(activeTab)
            // Switch to the new active tab
            if let newActiveTab = tabManager.activeTab {
                Task {
                    await handleTabChange(newActiveTab)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                // Window is closing - save tab state and cleanup connection
                Task { @MainActor in
                    tabManager.updateActiveTab(
                        connectionId: appState.currentConnection?.id,
                        databaseName: appState.selectedDatabase?.name,
                        queryText: appState.queryText
                    )
                    await appState.cleanupOnWindowClose()
                }
            }
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

        // Restore query text from active tab
        appState.queryText = activeTab.queryText

        // Connect to database
        loadingState.setPhase(.connectingToDatabase)
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: KeychainServiceImpl()
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        guard case .success = result else {
            loadingState.setReady()
            return
        }

        // Load databases
        loadingState.setPhase(.loadingDatabases)
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("Failed to load databases: \(error)")
            loadingState.setReady()
            return
        }

        // Restore database selection from active tab
        if let databaseName = activeTab.databaseName,
           let database = appState.databases.first(where: { $0.name == databaseName }) {
            appState.selectedDatabase = database

            // Load tables
            loadingState.setPhase(.loadingTables)
            await loadTables(for: database, connection: connection)
        }

        loadingState.setReady()
        appState.isShowingWelcomeScreen = false
    }

    private func loadTables(for database: DatabaseInfo, connection: ConnectionProfile) async {
        await TableRefreshService.loadTables(for: database, connection: connection, appState: appState)
    }

    private func handleTabChange(_ tab: TabState?) async {
        guard let tab = tab else { return }

        DebugLog.print("📑 [RootView] Tab changed to: \(tab.id)")

        // Restore query text
        appState.queryText = tab.queryText

        // Clear current state
        appState.selectedTable = nil
        appState.tables = []
        appState.queryResults = []
        appState.queryColumnNames = nil

        // If tab has no connection, just clear and return
        guard let connectionId = tab.connectionId,
              let connection = connections.first(where: { $0.id == connectionId }) else {
            appState.currentConnection = nil
            appState.selectedDatabase = nil
            appState.databases = []
            return
        }

        // Connect if different connection or not connected
        if appState.currentConnection?.id != connectionId || !appState.databaseService.isConnected {
            let connectionService = ConnectionService(
                appState: appState,
                keychainService: KeychainServiceImpl()
            )

            let result = await connectionService.connect(to: connection, saveAsLast: false)
            guard case .success = result else { return }
        }

        // Load databases
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("Failed to load databases: \(error)")
            return
        }

        // Restore database selection
        if let databaseName = tab.databaseName,
           let database = appState.databases.first(where: { $0.name == databaseName }) {
            appState.selectedDatabase = database
            await loadTables(for: database, connection: connection)
        }
    }
}

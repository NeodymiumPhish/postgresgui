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
    @State private var selectedDatabaseID: DatabaseInfo.ID?
    @State private var connectionError: String?
    @State private var showConnectionError = false
    @State private var showCreateDatabaseForm = false
    @State private var newDatabaseName = ""
    @State private var createDatabaseError: String?
    @State private var hasRestoredConnection = false
    @State private var queryToEdit: SavedQuery?
    @State private var queryToDelete: SavedQuery?
    @State private var selectedQueryID: SavedQuery.ID?

    /// Static flag to ensure auto-restore only happens once per app session (not for new tabs)
    private static var hasRestoredConnectionGlobally = false

    private var sortedConnections: [ConnectionProfile] {
        connections.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        Group {
            switch appState.sidebarViewMode {
            case .connections:
                connectionsView
            case .queries:
                savedQueriesView
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
            // Clear saved database when connection changes (databases are connection-specific)
            if oldValue != nil && newValue != oldValue {
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                selectedDatabaseID = nil
                appState.selectedDatabase = nil
            }
        }
        .task {
            // Wait for RootView's initial loading to complete before doing anything
            // This prevents race conditions with duplicate connection attempts
            while !loadingState.hasCompletedInitialLoad {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            // Skip restoration if RootView already restored from tab state
            if appState.currentConnection != nil {
                hasRestoredConnection = true
                Self.hasRestoredConnectionGlobally = true
                // Sync selectedDatabaseID with appState
                if let database = appState.selectedDatabase {
                    selectedDatabaseID = database.id
                }
                return
            }

            // Restore last connection on app launch (fallback if no tab state)
            await restoreLastConnection()
        }
        .onChange(of: appState.currentConnection) { _, newConnection in
            // Save connection change to active tab
            tabManager.updateActiveTab(connectionId: newConnection?.id, databaseName: nil, queryText: nil)
        }
        .onChange(of: appState.selectedDatabase) { _, newDatabase in
            // Save database change to active tab
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

    // MARK: - Connections View

    private var connectionsView: some View {
        List(selection: Binding<DatabaseInfo.ID?>(
            get: { selectedDatabaseID },
            set: { newID in
                guard let unwrappedID = newID else {
                    selectedDatabaseID = nil
                    appState.selectedDatabase = nil
                    appState.tables = []
                    appState.isLoadingTables = false
                    DebugLog.print("🔴 [ConnectionsDatabasesSidebar] Selection cleared")
                    return
                }
                selectedDatabaseID = unwrappedID
                DebugLog.print("🟢 [ConnectionsDatabasesSidebar] selectedDatabaseID changed to \(unwrappedID)")

                // Find the database object from the ID
                let database = appState.databases.first { $0.id == unwrappedID }

                DebugLog.print("🔵 [ConnectionsDatabasesSidebar] Updating selectedDatabase to: \(database?.name ?? "nil")")
                appState.selectedDatabase = database

                // Clear tables immediately and show loading state
                appState.tables = []
                appState.isLoadingTables = true
                appState.selectedTable = nil
                DebugLog.print("🟡 [ConnectionsDatabasesSidebar] Cleared tables, isLoadingTables=true")

                if let database = database {
                    // Save last selected database name
                    UserDefaults.standard.set(database.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)

                    DebugLog.print("🟠 [ConnectionsDatabasesSidebar] Starting loadTables for: \(database.name)")
                    Task {
                        await loadTables(for: database)
                    }
                } else {
                    // Clear saved database when selection is cleared
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
                    DebugLog.print("🔴 [ConnectionsDatabasesSidebar] No database selected, stopping loading")
                    appState.isLoadingTables = false
                }
            }
        )) {
            Section("Connection") {
                HStack {
                    Picker("Connection", selection: Binding(
                        get: { appState.currentConnection },
                        set: { newConnection in
                            if let connection = newConnection {
                                Task {
                                    await connect(to: connection)
                                }
                            }
                        }
                    )) {
                        if appState.currentConnection == nil {
                            Text("Select Connection").tag(nil as ConnectionProfile?)
                        }
                        ForEach(sortedConnections) { connection in
                            Text(connection.displayName).tag(connection as ConnectionProfile?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button {
                        appState.showConnectionsList()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.connectionToEdit = nil
                        appState.showConnectionForm()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Databases") {
                if appState.databases.isEmpty {
                    Text("No databases")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(appState.databases) { database in
                        DatabaseRowView(database: database)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if appState.isConnected {
                Button {
                    showCreateDatabaseForm = true
                } label: {
                    Label("Create Database", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
                .padding()
            }
        }
    }

    // MARK: - Saved Queries View

    private var savedQueriesView: some View {
        List(selection: $selectedQueryID) {
            Section("Saved Queries") {
                if savedQueries.isEmpty {
                    Text("No saved queries")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedQueries) { query in
                        SavedQueryRowView(
                            query: query,
                            onEdit: { queryToEdit = query },
                            onDelete: { queryToDelete = query },
                            onDuplicate: { duplicateQuery(query) }
                        )
                    }
                }
            }
        }
        .onChange(of: selectedQueryID) { _, newID in
            if let newID = newID,
               let query = savedQueries.first(where: { $0.id == newID }) {
                loadQuery(query)
            }
        }
        .onChange(of: appState.currentSavedQueryId) { _, newID in
            selectedQueryID = newID
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                createNewQuery()
            } label: {
                Label("New Query", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
            .padding()
        }
        .sheet(item: $queryToEdit) { query in
            EditQuerySheet(query: query)
        }
        .confirmationDialog(
            "Delete Query?",
            isPresented: Binding(
                get: { queryToDelete != nil },
                set: { if !$0 { queryToDelete = nil } }
            ),
            presenting: queryToDelete
        ) { query in
            Button("Delete", role: .destructive) {
                deleteQuery(query)
            }
            Button("Cancel", role: .cancel) {
                queryToDelete = nil
            }
        } message: { query in
            Text("Are you sure you want to delete \"\(query.name)\"? This action cannot be undone.")
        }
    }

    private func createNewQuery() {
        // Clear selection
        selectedQueryID = nil

        // Clear current query state
        appState.queryText = ""
        appState.currentSavedQueryId = nil
        appState.lastSavedAt = nil
        appState.showQueryResults = false
        appState.queryResults = []
        appState.queryColumnNames = nil
        appState.queryError = nil
        appState.queryExecutionTime = nil

        DebugLog.print("📝 [ConnectionsDatabasesSidebar] Created new query")
    }

    private func loadQuery(_ query: SavedQuery) {
        appState.queryText = query.queryText
        appState.currentSavedQueryId = query.id
        appState.lastSavedAt = query.updatedAt

        // Clear previous results
        appState.showQueryResults = false
        appState.queryResults = []
        appState.queryColumnNames = nil
        appState.queryError = nil
        appState.queryExecutionTime = nil

        DebugLog.print("📂 [ConnectionsDatabasesSidebar] Loaded query: \(query.name)")
    }

    private func duplicateQuery(_ query: SavedQuery) {
        let newQuery = SavedQuery(
            name: "\(query.name) (Copy)",
            queryText: query.queryText,
            connectionId: query.connectionId,
            databaseName: query.databaseName
        )
        modelContext.insert(newQuery)

        do {
            try modelContext.save()
            DebugLog.print("📋 [ConnectionsDatabasesSidebar] Duplicated query: \(query.name)")
        } catch {
            DebugLog.print("❌ [ConnectionsDatabasesSidebar] Failed to duplicate query: \(error)")
        }
    }

    private func deleteQuery(_ query: SavedQuery) {
        // Clear current query reference if this is the loaded query
        if appState.currentSavedQueryId == query.id {
            appState.currentSavedQueryId = nil
            appState.lastSavedAt = nil
        }

        modelContext.delete(query)

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [ConnectionsDatabasesSidebar] Deleted query: \(query.name)")
        } catch {
            DebugLog.print("❌ [ConnectionsDatabasesSidebar] Failed to delete query: \(error)")
        }

        queryToDelete = nil
    }
    
    private func restoreLastConnection() async {
        // Only restore once per app session (not for new tabs) and if no connection is currently selected
        guard !hasRestoredConnection,
              !Self.hasRestoredConnectionGlobally,
              appState.currentConnection == nil else { return }

        // Set flags immediately to prevent race condition with rapid tab creation
        hasRestoredConnection = true
        Self.hasRestoredConnectionGlobally = true

        // Wait a bit for connections to load from SwiftData
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Check again after waiting
        guard !connections.isEmpty else { return }
        
        // Get last connection ID from UserDefaults
        guard let lastConnectionIdString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
              let lastConnectionId = UUID(uuidString: lastConnectionIdString) else {
            // No last connection saved - auto-select if only one connection exists
            if connections.count == 1, let onlyConnection = connections.first {
                await connect(to: onlyConnection)
            }
            return
        }

        // Find the connection in the list
        guard let lastConnection = connections.first(where: { $0.id == lastConnectionId }) else {
            // Connection not found, clear the stored ID
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            return
        }

        // Connect to the last connection
        // Note: connect() will set appState.currentConnection itself
        // Don't set it here as it would trigger the Picker's binding and cause a duplicate connection
        await connect(to: lastConnection)
    }
    
    private func refreshDatabases() {
        Task {
            await refreshDatabasesAsync()
        }
    }
    
    private func refreshDatabasesAsync() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
            
            // After refreshing databases, restore last selected database if available
            await restoreLastDatabase()
        } catch {
            DebugLog.print("Failed to refresh databases: \(error)")
        }
    }
    
    private func connect(to connection: ConnectionProfile) async {
        // Create connection service (will be injected via DI container in Phase 6)
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: KeychainServiceImpl()
        )

        let result = await connectionService.connect(to: connection, saveAsLast: true)

        switch result {
        case .success:
            try? modelContext.save()
            // Retry loading databases if cancelled during connection (race with view updates)
            if appState.databases.isEmpty {
                await refreshDatabasesAsync()
            } else {
                await restoreLastDatabase()
            }

        case .failure(let error):
            DebugLog.print("Failed to connect: \(error)")
            connectionError = error.localizedDescription
            showConnectionError = true
            // Connection state already reset by ConnectionService
        }
    }
    
    private func restoreLastDatabase() async {
        // Only restore if no database is currently selected and we have databases
        guard appState.selectedDatabase == nil, !appState.databases.isEmpty else { return }
        
        // Get last database name from UserDefaults
        guard let lastDatabaseName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName),
              !lastDatabaseName.isEmpty else {
            return
        }
        
        // Find the database in the list
        guard let lastDatabase = appState.databases.first(where: { $0.name == lastDatabaseName }) else {
            // Database not found, clear the stored name
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            return
        }
        
        // Set the database selection
        // Note: We set both the local state and appState to ensure consistency
        selectedDatabaseID = lastDatabase.id
        appState.selectedDatabase = lastDatabase

        // Clear tables immediately and show loading state
        appState.tables = []
        appState.isLoadingTables = true
        appState.selectedTable = nil

        // Load tables for the restored database
        await loadTables(for: lastDatabase)
    }
    
    private func loadTables(for database: DatabaseInfo) async {
        DebugLog.print("📍 [loadTables] START for database: \(database.name)")

        defer {
            DebugLog.print("📍 [loadTables] END - setting isLoadingTables=false")
            appState.isLoadingTables = false
        }

        do {
            // Check if we need to reconnect to a different database
            guard let connection = appState.currentConnection else {
                DebugLog.print("❌ [loadTables] ERROR: No current connection")
                return
            }
            DebugLog.print("✅ [loadTables] Current connection: \(connection.displayName)")

            // Only reconnect if we're not already connected to the target database
            if appState.databaseService.connectedDatabase != database.name {
                // Get password from keychain
                DebugLog.print("🔑 [loadTables] Getting password from Keychain for connection: \(connection.id)")
                let password = try KeychainService.getPassword(for: connection.id) ?? ""
                DebugLog.print("✅ [loadTables] Password retrieved (length: \(password.count))")

                // Reconnect to the selected database
                DebugLog.print("🔌 [loadTables] Switching database: \(appState.databaseService.connectedDatabase ?? "none") -> \(database.name)")
                try await appState.databaseService.connect(
                    host: connection.host,
                    port: connection.port,
                    username: connection.username,
                    password: password,
                    database: database.name,
                    sslMode: connection.sslModeEnum
                )
                DebugLog.print("✅ [loadTables] Connected successfully to \(database.name)")
            } else {
                DebugLog.print("ℹ️  [loadTables] Already connected to \(database.name), skipping reconnect")
            }

            // Now fetch tables from the newly connected database
            DebugLog.print("📊 [loadTables] Fetching tables from database: \(database.name)")
            appState.tables = try await appState.databaseService.fetchTables(database: database.name)
            DebugLog.print("✅ [loadTables] Fetched \(appState.tables.count) tables")
            for (index, table) in appState.tables.enumerated() {
                DebugLog.print("   Table \(index + 1): \(table.schema).\(table.name)")
            }
        } catch {
            DebugLog.print("❌ [loadTables] ERROR: \(error)")
            DebugLog.print("❌ [loadTables] Error details: \(String(describing: error))")
            appState.tables = []
            appState.selectedTable = nil
        }
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

private struct DatabaseRowView: View {
    let database: DatabaseInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        NavigationLink(value: database.id) {
            HStack {
                Label(database.name, systemImage: "externaldrive")
                Spacer()
                if isHovered {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Database...", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(isButtonHovered ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isButtonHovered = hovering
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Database...", systemImage: "trash")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .confirmationDialog(
            "Delete Database?",
            isPresented: $showDeleteConfirmation,
            presenting: database
        ) { database in
            Button(role: .destructive) {
                Task {
                    await deleteDatabase(database)
                }
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
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
    
    private func deleteDatabase(_ database: DatabaseInfo) async {
        DebugLog.print("🗑️  [DatabaseRowView] Deleting database: \(database.name)")

        do {
            // Get connection details
            guard let connection = appState.currentConnection else {
                DebugLog.print("❌ [DatabaseRowView] No current connection")
                return
            }

            // If we're connected to the database we want to delete, switch to postgres first
            if appState.databaseService.connectedDatabase == database.name {
                DebugLog.print("🔄 [DatabaseRowView] Switching to postgres before deleting \(database.name)")
                let password = try KeychainService.getPassword(for: connection.id) ?? ""
                try await appState.databaseService.connect(
                    host: connection.host,
                    port: connection.port,
                    username: connection.username,
                    password: password,
                    database: "postgres",
                    sslMode: connection.sslModeEnum
                )
            }

            // Delete the database
            try await appState.databaseService.deleteDatabase(name: database.name)
            
            // Remove from databases list
            appState.databases.removeAll { $0.id == database.id }
            
            // Clear selection if this was the selected database
            if appState.selectedDatabase?.id == database.id {
                appState.selectedDatabase = nil
                appState.tables = []
                appState.isLoadingTables = false
            }
            
            // Refresh databases list
            await refreshDatabases()
            
            DebugLog.print("✅ [DatabaseRowView] Database deleted successfully")
        } catch {
            DebugLog.print("❌ [DatabaseRowView] Error deleting database: \(error)")
            // Display error message to user
            if let connectionError = error as? ConnectionError {
                deleteError = connectionError.errorDescription ?? "Failed to delete database."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
    
    private func refreshDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("Failed to refresh databases: \(error)")
        }
    }
    
    @MainActor
    private func refreshTables(for database: DatabaseInfo) async {
        DebugLog.print("🔄 [DatabaseRowView] Refresh tables for database: \(database.name)")
        
        guard appState.databaseService.isConnected else {
            DebugLog.print("❌ [DatabaseRowView] Not connected, cannot refresh tables")
            return
        }
        
        defer {
            appState.isLoadingTables = false
        }
        
        appState.isLoadingTables = true
        
        // Set this database as selected if it's not already
        if appState.selectedDatabase?.id != database.id {
            appState.selectedDatabase = database
        }
        
        // Refresh tables list
        do {
            DebugLog.print("📊 [DatabaseRowView] Fetching tables from database: \(database.name)")
            appState.tables = try await appState.databaseService.fetchTables(database: database.name)
            DebugLog.print("✅ [DatabaseRowView] Refreshed \(appState.tables.count) tables")
            
            // Update selectedTable reference if it still exists in the refreshed list
            // Only update if the table object has actually changed (e.g., primaryKeyColumns or columnInfo updated)
            // This prevents unnecessary refreshes when the table is the same
            if let selectedTable = appState.selectedTable,
               let refreshedTable = appState.tables.first(where: { $0.id == selectedTable.id }) {
                // Only update if the table has actually changed (e.g., metadata was added)
                if refreshedTable != selectedTable {
                    DebugLog.print("🔄 [DatabaseRowView] Updating selectedTable with refreshed metadata")
                    appState.selectedTable = refreshedTable
                } else {
                    DebugLog.print("🔄 [DatabaseRowView] selectedTable unchanged, skipping update")
                }
            } else if appState.selectedTable != nil {
                // Clear selection if the table no longer exists
                DebugLog.print("🔄 [DatabaseRowView] Selected table no longer exists, clearing selection")
                appState.selectedTable = nil
            }
        } catch {
            DebugLog.print("❌ [DatabaseRowView] Error refreshing tables: \(error)")
        }
    }
}

// MARK: - Saved Query Row View

private struct SavedQueryRowView: View {
    let query: SavedQuery
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        NavigationLink(value: query.id) {
            VStack(alignment: .leading, spacing: 2) {
                Text(query.name)
                    .lineLimit(1)

                Text(query.queryText.prefix(50) + (query.queryText.count > 50 ? "..." : ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Rename...", systemImage: "pencil")
            }

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete...", systemImage: "trash")
            }
        }
    }
}

// MARK: - Edit Query Sheet

private struct EditQuerySheet: View {
    @Bindable var query: SavedQuery
    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Query")
                .font(.headline)

            TextField("Query Name", text: $editedName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    query.name = editedName
                    query.updatedAt = Date()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            editedName = query.name
        }
    }
}

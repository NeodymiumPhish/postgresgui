//
//  ConnectionsSidebarSection.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

/// Sidebar section for database connections and tables
struct ConnectionsSidebarSection: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    @Binding var selectedDatabaseID: DatabaseInfo.ID?
    @Binding var showCreateDatabaseForm: Bool

    let connections: [ConnectionProfile]
    let onConnect: @MainActor (ConnectionProfile) async -> Void
    let onLoadTables: @MainActor (DatabaseInfo) async -> Void

    /// Tracks the current database switching task to enable cancellation
    @State private var loadTablesTask: Task<Void, Never>?

    private var sortedConnections: [ConnectionProfile] {
        connections.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List(selection: Binding<DatabaseInfo.ID?>(
            get: { selectedDatabaseID },
            set: { newID in
                handleDatabaseSelection(newID)
            }
        )) {
            Section("Connection") {
                connectionPickerRow
            }

            Section("Databases") {
                if appState.connection.databases.isEmpty {
                    Text("No databases")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(appState.connection.databases) { database in
                        DatabaseRowView(database: database)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if appState.connection.isConnected {
                Button {
                    showCreateDatabaseForm = true
                } label: {
                    Label("Create Database", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
                .padding()
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Connection Picker Row

    private var connectionPickerRow: some View {
        HStack {
            Picker("Connection", selection: Binding(
                get: { appState.connection.currentConnection },
                set: { newConnection in
                    if let connection = newConnection {
                        Task {
                            await onConnect(connection)
                        }
                    }
                }
            )) {
                if appState.connection.currentConnection == nil {
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
            .accessibilityIdentifier("connectionSettingsButton")

            Button {
                appState.navigation.connectionToEdit = nil
                appState.showConnectionForm()
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addConnectionButton")
        }
    }

    // MARK: - Helpers

    private func handleDatabaseSelection(_ newID: DatabaseInfo.ID?) {
        guard let unwrappedID = newID else {
            selectedDatabaseID = nil
            appState.connection.selectedDatabase = nil
            appState.connection.tables = []
            appState.connection.isLoadingTables = false
            DebugLog.print("🔴 [ConnectionsSidebarSection] Selection cleared")
            return
        }

        selectedDatabaseID = unwrappedID
        DebugLog.print("🟢 [ConnectionsSidebarSection] selectedDatabaseID changed to \(unwrappedID)")

        let database = appState.connection.databases.first { $0.id == unwrappedID }

        DebugLog.print("🔵 [ConnectionsSidebarSection] Updating selectedDatabase to: \(database?.name ?? "nil")")
        appState.connection.selectedDatabase = database

        // Clear tables immediately and show loading state
        appState.connection.tables = []
        appState.connection.isLoadingTables = true
        appState.connection.selectedTable = nil
        DebugLog.print("🟡 [ConnectionsSidebarSection] Cleared tables, isLoadingTables=true")

        if let database = database {
            // Save last selected database name
            UserDefaults.standard.set(database.name, forKey: Constants.UserDefaultsKeys.lastDatabaseName)

            // Cancel any in-flight database switching task to prevent race conditions
            loadTablesTask?.cancel()
            DebugLog.print("🟠 [ConnectionsSidebarSection] Starting loadTables for: \(database.name)")
            loadTablesTask = Task {
                await onLoadTables(database)
            }
        } else {
            // Clear saved database when selection is cleared
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
            DebugLog.print("🔴 [ConnectionsSidebarSection] No database selected, stopping loading")
            appState.connection.isLoadingTables = false
        }
    }
}

//
//  ConnectionsListView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var connections: [ConnectionProfile]

    @State private var connectionToDelete: ConnectionProfile?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var connectionError: String?
    @State private var showConnectionError = false

    private var sortedConnections: [ConnectionProfile] {
        connections.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Connections")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()

                    Button {
                        appState.navigation.connectionToEdit = nil
                        appState.showConnectionForm()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()

                Divider()

                // List
                if connections.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("No Connections", systemImage: "server.rack")
                    } description: {
                        Text("Create your first connection to get started")
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(sortedConnections) { connection in
                            ConnectionRowView(
                                connection: connection,
                                isActive: appState.connection.currentConnection?.id == connection.id,
                                onConnect: {
                                    Task {
                                        await connect(to: connection)
                                    }
                                },
                                onEdit: {
                                    appState.navigation.connectionToEdit = connection
                                    appState.showConnectionForm()
                                },
                                onDelete: {
                                    connectionToDelete = connection
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
            }
            .confirmationDialog(
                "Delete Connection?",
                isPresented: $showDeleteConfirmation,
                presenting: connectionToDelete
            ) { connection in
                Button(role: .destructive) {
                    Task {
                        await deleteConnection(connection)
                    }
                } label: {
                    Text("Delete")
                }
                Button("Cancel", role: .cancel) {
                    connectionToDelete = nil
                }
            } message: { connection in
                Text("Are you sure you want to delete '\(connection.displayName)'? This action cannot be undone.")
            }
            .alert("Error Deleting Connection", isPresented: Binding(
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
        .frame(width: 600, height: 500)
    }

    private func connect(to connection: ConnectionProfile) async {
        let connectionService = ConnectionService(
            appState: appState,
            keychainService: KeychainServiceImpl()
        )

        let result = await connectionService.connect(to: connection)

        switch result {
        case .success:
            try? modelContext.save()
        case .failure(let error):
            DebugLog.print("Failed to connect: \(error)")
            connectionError = PostgresError.extractDetailedMessage(error)
            showConnectionError = true
        }
    }

    private func deleteConnection(_ connection: ConnectionProfile) async {
        DebugLog.print("🗑️  [ConnectionsListView] Deleting connection: \(connection.displayName)")

        do {
            let isActiveConnection = appState.connection.currentConnection?.id == connection.id
            let wasLastConnection = connections.count == 1

            try KeychainService.deletePassword(for: connection.id)

            if isActiveConnection {
                await appState.connection.databaseService.disconnect()
                appState.connection.currentConnection = nil
                appState.connection.selectedDatabase = nil
                appState.connection.tables = []
                appState.connection.databases = []

                if let lastConnectionIdString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId),
                   lastConnectionIdString == connection.id.uuidString {
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
                }
            }

            modelContext.delete(connection)
            try modelContext.save()

            DebugLog.print("✅ [ConnectionsListView] Connection deleted successfully")
            connectionToDelete = nil

            if wasLastConnection {
                appState.navigation.isShowingWelcomeScreen = true
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastConnectionId)
            }

        } catch {
            DebugLog.print("❌ [ConnectionsListView] Error deleting connection: \(error)")
            if let keychainError = error as? KeychainError {
                deleteError = keychainError.errorDescription ?? "Failed to delete connection."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
}

// MARK: - Connection Row

private struct ConnectionRowView: View {
    let connection: ConnectionProfile
    let isActive: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isButtonHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.displayName)
                        .font(.headline)
                    if connection.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }

                HStack(spacing: 12) {
                    Label(connection.rootDomain, systemImage: "server.rack")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(formatPort(connection.port), systemImage: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                onConnect()
            } label: {
                if isActive {
                    Label("Connected", systemImage: "checkmark")
                } else {
                    Label("Connect", systemImage: "powerplug")
                }
            }
            .buttonStyle(.glass)
            .tint(isActive ? .green : nil)

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit...", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete...", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(isButtonHovered ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 100))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isButtonHovered = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            Button {
                onConnect()
            } label: {
                Label("Connect", systemImage: "powerplug")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit...", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete...", systemImage: "trash")
            }
        }
    }

    private func formatPort(_ port: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: port)) ?? String(port)
    }
}

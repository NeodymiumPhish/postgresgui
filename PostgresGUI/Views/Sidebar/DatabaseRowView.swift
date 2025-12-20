//
//  DatabaseRowView.swift
//  PostgresGUI
//

import SwiftUI

struct DatabaseRowView: View {
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
                    menuButton
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
        .onHover { isHovered = $0 }
        .confirmationDialog(
            "Delete Database?",
            isPresented: $showDeleteConfirmation,
            presenting: database
        ) { db in
            Button(role: .destructive) {
                Task { await deleteDatabase(db) }
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {}
        } message: { db in
            Text("Are you sure you want to delete '\(db.name)'? This action cannot be undone.")
        }
        .alert("Error Deleting Database", isPresented: .init(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            if let error = deleteError { Text(error) }
        }
    }

    private var menuButton: some View {
        Menu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Database...", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(isButtonHovered ? .primary : .secondary)
                .padding(6)
                .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isButtonHovered = $0 }
    }

    private func deleteDatabase(_ database: DatabaseInfo) async {
        do {
            guard let connection = appState.currentConnection else { return }

            // Switch to postgres if connected to the database we're deleting
            if appState.databaseService.connectedDatabase == database.name {
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

            try await appState.databaseService.deleteDatabase(name: database.name)
            appState.databases.removeAll { $0.id == database.id }

            if appState.selectedDatabase?.id == database.id {
                appState.selectedDatabase = nil
                appState.tables = []
                appState.isLoadingTables = false
            }

            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            if let connectionError = error as? ConnectionError {
                deleteError = connectionError.errorDescription ?? "Failed to delete database."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }
}

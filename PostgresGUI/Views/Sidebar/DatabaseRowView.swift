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
    @State private var isDeleting = false

    var body: some View {
        NavigationLink(value: database.id) {
            HStack {
                Label(database.name, systemImage: "cylinder.split.1x2.fill")
                Spacer()
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                } else if isHovered {
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
            .disabled(isDeleting)
        }
        .onHover { isHovered = isDeleting ? false : $0 }
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
        DebugLog.print("[DatabaseRowView] Starting delete for database: \(database.name)")
        isDeleting = true
        defer {
            isDeleting = false
            DebugLog.print("[DatabaseRowView] Delete flow completed for: \(database.name)")
        }

        do {
            guard appState.connection.currentConnection != nil else {
                DebugLog.print("[DatabaseRowView] No current connection, aborting delete")
                return
            }

            // Prevent deleting the currently connected database
            if appState.connection.databaseService.connectedDatabase == database.name {
                DebugLog.print("[DatabaseRowView] Cannot delete currently connected database")
                deleteError = "Cannot delete '\(database.name)' while connected to it. Please switch to a different database first."
                return
            }

            DebugLog.print("[DatabaseRowView] Executing deleteDatabase for: \(database.name)")
            try await appState.connection.databaseService.deleteDatabase(name: database.name)
            DebugLog.print("[DatabaseRowView] Database deleted successfully: \(database.name)")

            appState.connection.databases.removeAll { $0.id == database.id }

            DebugLog.print("[DatabaseRowView] Refreshing database list")
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
            DebugLog.print("[DatabaseRowView] Database list refreshed, count: \(appState.connection.databases.count)")
        } catch {
            DebugLog.print("[DatabaseRowView] Delete failed with error: \(error)")
            deleteError = PostgresError.extractDetailedMessage(error)
        }
    }
}

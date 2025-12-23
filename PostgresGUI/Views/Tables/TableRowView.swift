//
//  TableRowView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import AppKit

struct TableRowView: View {
    let table: TableInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isButtonHovered = false
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        NavigationLink(value: table.id) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .foregroundColor(.secondary)

                Text(table.name)
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Table...", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(isButtonHovered ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .opacity((isHovered || isButtonHovered) ? 1.0 : 0.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isButtonHovered = hovering
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Table...", systemImage: "trash")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .confirmationDialog(
            "Delete Table?",
            isPresented: $showDeleteConfirmation,
            presenting: table
        ) { table in
            Button(role: .destructive) {
                Task {
                    await deleteTable(table)
                }
            } label: {
                Text("Delete")
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: { table in
            Text("Are you sure you want to delete '\(table.schema).\(table.name)'? This action cannot be undone.")
        }
        .alert("Error Deleting Table", isPresented: Binding(
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
    
    private func deleteTable(_ table: TableInfo) async {
        DebugLog.print("🗑️  [TableRowView] Deleting table: \(table.schema).\(table.name)")

        do {
            guard appState.connection.databaseService.isConnected else {
                deleteError = "Not connected to database"
                return
            }

            try await appState.connection.databaseService.deleteTable(schema: table.schema, table: table.name)

            // Remove from tables list
            appState.connection.tables.removeAll { $0.id == table.id }

            // Clear selection if this was the selected table
            if appState.connection.selectedTable?.id == table.id {
                appState.connection.selectedTable = nil
                appState.query.showQueryResults = false
                if !appState.query.queryText.isEmpty {
                    DebugLog.print("🗑️ [TableRowView] Cleared queryText due to table deletion: \(table.schema).\(table.name)")
                }
                appState.query.queryText = ""
                appState.query.queryResults = []
            }

            DebugLog.print("✅ [TableRowView] Table deleted successfully")
        } catch {
            DebugLog.print("❌ [TableRowView] Error deleting table: \(error)")
            if let connectionError = error as? ConnectionError {
                deleteError = connectionError.errorDescription ?? "Failed to delete table."
            } else {
                deleteError = error.localizedDescription
            }
        }
    }

    private func copyTableName() {
        let tableName = "\(table.schema).\(table.name)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tableName, forType: .string)
        DebugLog.print("📋 [TableRowView] Copied table name to clipboard: \(tableName)")
    }

    private func refreshQuery() {
        DebugLog.print("🔄 [TableRowView] Refresh query from context menu")
        Task {
            // Set loading state FIRST to prevent empty state flicker
            appState.query.isExecutingQuery = true
            appState.query.queryError = nil
            appState.query.queryExecutionTime = nil
            appState.query.showQueryResults = false // Hide results view during loading
            appState.query.queryResults = [] // Clear previous results
            appState.query.queryColumnNames = nil // Clear previous column names

            let startTime = Date()

            do {
                DebugLog.print("📊 [TableRowView] Executing query...")
                let (results, columnNames) = try await appState.connection.databaseService.executeQuery(appState.query.queryText)
                appState.query.queryResults = results
                appState.query.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.query.showQueryResults = true

                let endTime = Date()
                appState.query.queryExecutionTime = endTime.timeIntervalSince(startTime)

                DebugLog.print("✅ [TableRowView] Query executed successfully, showing results")
            } catch {
                appState.query.queryError = error
                appState.query.queryColumnNames = nil
                appState.query.showQueryResults = true

                let endTime = Date()
                appState.query.queryExecutionTime = endTime.timeIntervalSince(startTime)

                DebugLog.print("❌ [TableRowView] Query execution failed: \(error)")
            }

            appState.query.isExecutingQuery = false
        }
    }
}

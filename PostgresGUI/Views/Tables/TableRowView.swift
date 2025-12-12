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
                
                if isHovered {
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
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isButtonHovered = hovering
                    }
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
        print("🗑️  [TableRowView] Deleting table: \(table.schema).\(table.name)")
        
        do {
            guard appState.databaseService.isConnected else {
                deleteError = "Not connected to database"
                return
            }
            
            try await appState.databaseService.deleteTable(schema: table.schema, table: table.name)
            
            // Remove from tables list
            appState.tables.removeAll { $0.id == table.id }
            
            // Clear selection if this was the selected table
            if appState.selectedTable?.id == table.id {
                appState.selectedTable = nil
                appState.showQueryResults = false
                appState.queryText = ""
                appState.queryResults = []
            }
            
            print("✅ [TableRowView] Table deleted successfully")
        } catch {
            print("❌ [TableRowView] Error deleting table: \(error)")
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
        print("📋 [TableRowView] Copied table name to clipboard: \(tableName)")
    }
    
    private func refreshQuery() {
        print("🔄 [TableRowView] Refresh query from context menu")
        Task {
            // Set loading state FIRST to prevent empty state flicker
            appState.isExecutingQuery = true
            appState.queryError = nil
            appState.queryExecutionTime = nil
            appState.showQueryResults = false // Hide results view during loading
            appState.queryResults = [] // Clear previous results
            appState.queryColumnNames = nil // Clear previous column names

            let startTime = Date()

            do {
                print("📊 [TableRowView] Executing query...")
                let (results, columnNames) = try await appState.databaseService.executeQuery(appState.queryText)
                appState.queryResults = results
                appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("✅ [TableRowView] Query executed successfully, showing results")
            } catch {
                appState.queryError = error.localizedDescription
                appState.queryColumnNames = nil
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("❌ [TableRowView] Query execution failed: \(error)")
            }

            appState.isExecutingQuery = false
        }
    }
}

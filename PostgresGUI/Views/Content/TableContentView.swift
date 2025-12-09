//
//  TableContentView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TableContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showJSONView = false
    
    var body: some View {
        SplitContentView()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        refreshQuery()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isExecutingQuery || appState.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.init("r"), modifiers: [.command])
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        deleteSelectedRows()
                    }) {
                        Image(systemName: "trash")
                    }
                    .disabled(appState.selectedRowIDs.isEmpty)
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        editSelectedRows()
                    }) {
                        Image(systemName: "pencil")
                    }
                    .disabled(appState.selectedRowIDs.isEmpty)
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        showJSONView = true
                    }) {
                        Image(systemName: "doc.text")
                    }
                    .disabled(appState.selectedRowIDs.isEmpty)
                }
            }
            .sheet(isPresented: $showJSONView) {
                JSONViewerView(selectedRowIDs: appState.selectedRowIDs)
            }
    }
    
    private func refreshQuery() {
        print("🔄 [TableContentView] Refresh button clicked")
        Task {
            // Set loading state FIRST to prevent empty state flicker
            appState.isExecutingQuery = true
            appState.queryError = nil
            appState.queryExecutionTime = nil
            appState.showQueryResults = false // Hide results view during loading
            appState.queryResults = [] // Clear previous results
            appState.queryColumnNames = nil // Clear previous column names
            appState.selectedRowIDs = [] // Clear selected rows

            let startTime = Date()

            do {
                print("📊 [TableContentView] Executing query...")
                let (results, columnNames) = try await appState.databaseService.executeQuery(appState.queryText)
                appState.queryResults = results
                appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("✅ [TableContentView] Query executed successfully, showing results")
            } catch {
                appState.queryError = error.localizedDescription
                appState.queryColumnNames = nil
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("❌ [TableContentView] Query execution failed: \(error)")
            }

            appState.isExecutingQuery = false
        }
    }
    
    private func deleteSelectedRows() {
        print("🗑️ [TableContentView] Delete button clicked for \(appState.selectedRowIDs.count) row(s)")
        // TODO: Implement delete functionality
    }
    
    private func editSelectedRows() {
        print("✏️ [TableContentView] Edit button clicked for \(appState.selectedRowIDs.count) row(s)")
        // TODO: Implement edit functionality
    }
}

//
//  SavedQueriesSidebarSection.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

/// Sidebar section for saved queries
struct SavedQueriesSidebarSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let savedQueries: [SavedQuery]

    @Binding var selectedQueryID: SavedQuery.ID?
    @State private var queryToEdit: SavedQuery?
    @State private var queryToDelete: SavedQuery?

    var body: some View {
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
                        .listRowSeparator(.visible)
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
            .buttonStyle(.glass)
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

    // MARK: - Query Actions

    private func createNewQuery() {
        selectedQueryID = nil

        appState.queryText = ""
        appState.currentSavedQueryId = nil
        appState.lastSavedAt = nil
        appState.showQueryResults = false
        appState.queryResults = []
        appState.queryColumnNames = nil
        appState.queryError = nil
        appState.queryExecutionTime = nil

        DebugLog.print("📝 [SavedQueriesSidebarSection] Created new query")
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

        DebugLog.print("📂 [SavedQueriesSidebarSection] Loaded query: \(query.name)")
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
            DebugLog.print("📋 [SavedQueriesSidebarSection] Duplicated query: \(query.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesSidebarSection] Failed to duplicate query: \(error)")
        }
    }

    private func deleteQuery(_ query: SavedQuery) {
        if appState.currentSavedQueryId == query.id {
            appState.currentSavedQueryId = nil
            appState.lastSavedAt = nil
        }

        modelContext.delete(query)

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [SavedQueriesSidebarSection] Deleted query: \(query.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesSidebarSection] Failed to delete query: \(error)")
        }

        queryToDelete = nil
    }
}

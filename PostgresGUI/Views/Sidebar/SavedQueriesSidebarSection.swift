//
//  SavedQueriesSidebarSection.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

/// Sort options for saved queries
private enum SortOption: String, CaseIterable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case updatedDesc = "Updated (Newest)"
    case updatedAsc = "Updated (Oldest)"
    case createdDesc = "Created (Newest)"
    case createdAsc = "Created (Oldest)"

    var icon: String {
        switch self {
        case .nameAsc, .nameDesc: return "textformat"
        case .updatedDesc, .updatedAsc: return "clock"
        case .createdDesc, .createdAsc: return "calendar"
        }
    }
}

/// Sidebar section for saved queries
struct SavedQueriesSidebarSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let savedQueries: [SavedQuery]

    @Binding var selectedQueryIDs: Set<SavedQuery.ID>
    @State private var queryToEdit: SavedQuery?
    @State private var queriesToDelete: [SavedQuery] = []
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .updatedDesc

    private var filteredAndSortedQueries: [SavedQuery] {
        let filtered = savedQueries.filter { query in
            guard !searchText.isEmpty else { return true }
            let search = searchText.lowercased()
            return query.name.lowercased().contains(search) ||
                   query.queryText.lowercased().contains(search)
        }

        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .nameAsc:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDesc:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .updatedDesc:
                return lhs.updatedAt > rhs.updatedAt
            case .updatedAsc:
                return lhs.updatedAt < rhs.updatedAt
            case .createdDesc:
                return lhs.createdAt > rhs.createdAt
            case .createdAsc:
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Saved Queries")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Search and sort header
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Filter", text: $searchText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                .clipShape(Capsule())

                sortMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            List(selection: $selectedQueryIDs) {
                if filteredAndSortedQueries.isEmpty {
                    if savedQueries.isEmpty {
                        Text("No saved queries")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No matching queries")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(filteredAndSortedQueries) { query in
                        SavedQueryRowView(
                            query: query,
                            isSelected: selectedQueryIDs.contains(query.id),
                            selectedCount: selectedQueryIDs.count,
                            onEdit: { queryToEdit = query },
                            onDelete: { queriesToDelete = [query] },
                            onDeleteSelected: {
                                let queries = savedQueries.filter { selectedQueryIDs.contains($0.id) }
                                queriesToDelete = queries
                            },
                            onDuplicate: { duplicateQuery(query) }
                        )
                        .listRowSeparator(.visible)
                    }
                }
            }
        .onDeleteCommand {
            guard !selectedQueryIDs.isEmpty else { return }
            let queries = savedQueries.filter { selectedQueryIDs.contains($0.id) }
            queriesToDelete = queries
        }
        .onChange(of: selectedQueryIDs) { oldIDs, newIDs in
            // Load query when a single item is clicked (not added to existing selection)
            if newIDs.count == 1, let newID = newIDs.first,
               !oldIDs.contains(newID),
               let query = savedQueries.first(where: { $0.id == newID }) {
                loadQuery(query)
            }
        }
        .onChange(of: appState.currentSavedQueryId) { _, newID in
            if let newID = newID {
                selectedQueryIDs = [newID]
            } else {
                selectedQueryIDs = []
            }
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
            queriesToDelete.count == 1 ? "Delete Query?" : "Delete \(queriesToDelete.count) Queries?",
            isPresented: Binding(
                get: { !queriesToDelete.isEmpty },
                set: { if !$0 { queriesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteQueries(queriesToDelete)
            }
            Button("Cancel", role: .cancel) {
                queriesToDelete = []
            }
        } message: {
            if queriesToDelete.count == 1, let query = queriesToDelete.first {
                Text("Are you sure you want to delete \"\(query.name)\"? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(queriesToDelete.count) queries? This action cannot be undone.")
            }
        }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Label(option.rawValue, systemImage: option.icon)
                        if sortOption == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(6)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Query Actions

    private func createNewQuery() {
        // Create new saved query entry
        let newQuery = SavedQuery(
            name: "Untitled Query",
            queryText: "",
            connectionId: appState.currentConnection?.id,
            databaseName: appState.selectedDatabase?.name
        )
        modelContext.insert(newQuery)

        do {
            try modelContext.save()

            // Set this query as active
            appState.queryText = ""
            appState.currentSavedQueryId = newQuery.id
            appState.lastSavedAt = newQuery.updatedAt
            appState.showQueryResults = false
            appState.queryResults = []
            appState.queryColumnNames = nil
            appState.queryError = nil
            appState.queryExecutionTime = nil

            // Select the new query in the list
            selectedQueryIDs = [newQuery.id]

            DebugLog.print("📝 [SavedQueriesSidebarSection] Created new query: \(newQuery.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesSidebarSection] Failed to create new query: \(error)")
        }
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

    private func deleteQueries(_ queries: [SavedQuery]) {
        for query in queries {
            if appState.currentSavedQueryId == query.id {
                appState.currentSavedQueryId = nil
                appState.lastSavedAt = nil
            }
            modelContext.delete(query)
        }

        do {
            try modelContext.save()
            // Clear selection after deletion
            selectedQueryIDs = []
            DebugLog.print("🗑️ [SavedQueriesSidebarSection] Deleted \(queries.count) queries")
        } catch {
            DebugLog.print("❌ [SavedQueriesSidebarSection] Failed to delete queries: \(error)")
        }

        queriesToDelete = []
    }
}

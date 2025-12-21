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

/// Sidebar section for saved queries with folder support
struct SavedQueriesSidebarSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let savedQueries: [SavedQuery]
    let folders: [QueryFolder]

    @Binding var selectedQueryIDs: Set<SavedQuery.ID>
    @State private var queryToEdit: SavedQuery?
    @State private var folderToEdit: QueryFolder?
    @State private var queriesToDelete: [SavedQuery] = []
    @State private var folderToDelete: QueryFolder?
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .createdAsc
    @State private var expandedFolders: Set<UUID> = []
    @State private var queriesToMove: [SavedQuery] = []

    // Queries not in any folder
    private var unfolderedQueries: [SavedQuery] {
        savedQueries.filter { $0.folder == nil }
    }

    // Apply filtering and sorting to queries
    private func filteredAndSorted(_ queries: [SavedQuery]) -> [SavedQuery] {
        let filtered = queries.filter { query in
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

    // Filter and sort folders
    private var filteredFolders: [QueryFolder] {
        if searchText.isEmpty {
            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // When searching, only show folders that have matching queries
        return folders.filter { folder in
            guard let queries = folder.queries else { return false }
            return queries.contains { query in
                let search = searchText.lowercased()
                return query.name.lowercased().contains(search) ||
                       query.queryText.lowercased().contains(search)
            }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasAnyContent: Bool {
        !savedQueries.isEmpty || !folders.isEmpty
    }

    private var hasMatchingContent: Bool {
        !filteredAndSorted(unfolderedQueries).isEmpty || !filteredFolders.isEmpty
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
                if !hasAnyContent {
                    Text("No saved queries")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !hasMatchingContent {
                    Text("No matching queries")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    // Folders with their queries
                    ForEach(filteredFolders) { folder in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedFolders.contains(folder.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedFolders.insert(folder.id)
                                        DebugLog.print("📂 [SavedQueriesSidebarSection] Expanded folder: \(folder.name)")
                                    } else {
                                        expandedFolders.remove(folder.id)
                                        DebugLog.print("📁 [SavedQueriesSidebarSection] Collapsed folder: \(folder.name)")
                                    }
                                }
                            )
                        ) {
                            let folderQueries = filteredAndSorted(folder.queries ?? [])
                            ForEach(folderQueries) { query in
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
                                    onDuplicate: { duplicateQuery(query) },
                                    onMoveToFolder: {
                                        if selectedQueryIDs.count > 1 && selectedQueryIDs.contains(query.id) {
                                            queriesToMove = savedQueries.filter { selectedQueryIDs.contains($0.id) }
                                        } else {
                                            queriesToMove = [query]
                                        }
                                    }
                                )
                                .listRowSeparator(.visible)
                            }
                        } label: {
                            QueryFolderRowView(
                                folder: folder,
                                onRename: { folderToEdit = folder },
                                onDelete: { folderToDelete = folder }
                            )
                        }
                    }

                    // Queries not in any folder
                    ForEach(filteredAndSorted(unfolderedQueries)) { query in
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
                            onDuplicate: { duplicateQuery(query) },
                            onMoveToFolder: {
                                if selectedQueryIDs.count > 1 && selectedQueryIDs.contains(query.id) {
                                    queriesToMove = savedQueries.filter { selectedQueryIDs.contains($0.id) }
                                } else {
                                    queriesToMove = [query]
                                }
                            }
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
                    // Auto-expand folder containing this query
                    if let query = savedQueries.first(where: { $0.id == newID }),
                       let folder = query.folder {
                        expandedFolders.insert(folder.id)
                    }
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
            .sheet(item: $folderToEdit) { folder in
                EditFolderSheet(folder: folder)
            }
            .sheet(isPresented: Binding(
                get: { !queriesToMove.isEmpty },
                set: { if !$0 { queriesToMove = [] } }
            )) {
                MoveToFolderSheet(queries: queriesToMove, folders: folders)
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
            .confirmationDialog(
                "Delete Folder?",
                isPresented: Binding(
                    get: { folderToDelete != nil },
                    set: { if !$0 { folderToDelete = nil } }
                )
            ) {
                Button("Delete Folder Only", role: .destructive) {
                    if let folder = folderToDelete {
                        deleteFolder(folder, deleteQueries: false)
                    }
                }
                Button("Delete Folder and Queries", role: .destructive) {
                    if let folder = folderToDelete {
                        deleteFolder(folder, deleteQueries: true)
                    }
                }
                Button("Cancel", role: .cancel) {
                    folderToDelete = nil
                }
            } message: {
                if let folder = folderToDelete {
                    let queryCount = folder.queries?.count ?? 0
                    if queryCount > 0 {
                        Text("The folder \"\(folder.name)\" contains \(queryCount) queries. What would you like to do?")
                    } else {
                        Text("Are you sure you want to delete the folder \"\(folder.name)\"?")
                    }
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
        // Find the next available number for "Untitled Query X"
        let existingNumbers = savedQueries
            .compactMap { query -> Int? in
                if query.name == "Untitled Query" {
                    return 1
                }
                guard query.name.hasPrefix("Untitled Query ") else { return nil }
                let suffix = query.name.dropFirst("Untitled Query ".count)
                return Int(suffix)
            }
        let nextNumber = (existingNumbers.max() ?? 0) + 1
        let queryName = nextNumber == 1 ? "Untitled Query" : "Untitled Query \(nextNumber)"

        // Create new saved query entry
        let newQuery = SavedQuery(
            name: queryName,
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
            databaseName: query.databaseName,
            folder: query.folder
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

    private func deleteFolder(_ folder: QueryFolder, deleteQueries: Bool) {
        if deleteQueries {
            // Delete all queries in the folder
            for query in folder.queries ?? [] {
                if appState.currentSavedQueryId == query.id {
                    appState.currentSavedQueryId = nil
                    appState.lastSavedAt = nil
                }
                modelContext.delete(query)
            }
        } else {
            // Move queries out of the folder
            for query in folder.queries ?? [] {
                query.folder = nil
            }
        }

        modelContext.delete(folder)

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [SavedQueriesSidebarSection] Deleted folder: \(folder.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesSidebarSection] Failed to delete folder: \(error)")
        }

        folderToDelete = nil
    }
}

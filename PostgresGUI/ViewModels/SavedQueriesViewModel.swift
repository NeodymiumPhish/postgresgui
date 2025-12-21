//
//  SavedQueriesViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/21/25.
//

import Foundation
import SwiftData

/// Sort options for saved queries
enum QuerySortOption: String, CaseIterable {
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

/// ViewModel for SavedQueriesSidebarSection
@Observable
@MainActor
class SavedQueriesViewModel {
    private let appState: AppState

    // UI State
    var queryToEdit: SavedQuery?
    var folderToEdit: QueryFolder?
    var queriesToDelete: [SavedQuery] = []
    var folderToDelete: QueryFolder?
    var searchText: String = ""
    var sortOption: QuerySortOption = .createdAsc
    var expandedFolders: Set<UUID> = []
    var queriesToMove: [SavedQuery] = []

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Computed Properties

    /// Queries not in any folder
    func unfolderedQueries(from savedQueries: [SavedQuery]) -> [SavedQuery] {
        savedQueries.filter { $0.folder == nil }
    }

    /// Check if there's any content
    func hasAnyContent(savedQueries: [SavedQuery], folders: [QueryFolder]) -> Bool {
        !savedQueries.isEmpty || !folders.isEmpty
    }

    /// Check if there's matching content after filtering
    func hasMatchingContent(savedQueries: [SavedQuery], folders: [QueryFolder]) -> Bool {
        !filteredAndSorted(unfolderedQueries(from: savedQueries)).isEmpty ||
        !filteredFolders(from: folders, savedQueries: savedQueries).isEmpty
    }

    // MARK: - Filtering and Sorting

    /// Apply filtering and sorting to queries
    func filteredAndSorted(_ queries: [SavedQuery]) -> [SavedQuery] {
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

    /// Filter and sort folders
    func filteredFolders(from folders: [QueryFolder], savedQueries: [SavedQuery]) -> [QueryFolder] {
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

    // MARK: - Query Actions

    func createNewQuery(savedQueries: [SavedQuery], modelContext: ModelContext) {
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
            connectionId: appState.connection.currentConnection?.id,
            databaseName: appState.connection.selectedDatabase?.name
        )
        modelContext.insert(newQuery)

        do {
            try modelContext.save()

            // Set this query as active
            appState.query.queryText = ""
            appState.query.currentSavedQueryId = newQuery.id
            appState.query.lastSavedAt = newQuery.updatedAt
            appState.query.showQueryResults = false
            appState.query.queryResults = []
            appState.query.queryColumnNames = nil
            appState.query.queryError = nil
            appState.query.queryExecutionTime = nil

            DebugLog.print("📝 [SavedQueriesViewModel] Created new query: \(newQuery.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to create new query: \(error)")
        }
    }

    func loadQuery(_ query: SavedQuery) {
        appState.query.queryText = query.queryText
        appState.query.currentSavedQueryId = query.id
        appState.query.lastSavedAt = query.updatedAt

        // Clear previous results
        appState.query.showQueryResults = false
        appState.query.queryResults = []
        appState.query.queryColumnNames = nil
        appState.query.queryError = nil
        appState.query.queryExecutionTime = nil

        DebugLog.print("📂 [SavedQueriesViewModel] Loaded query: \(query.name)")
    }

    func duplicateQuery(_ query: SavedQuery, modelContext: ModelContext) {
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
            DebugLog.print("📋 [SavedQueriesViewModel] Duplicated query: \(query.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to duplicate query: \(error)")
        }
    }

    func deleteQueries(_ queries: [SavedQuery], modelContext: ModelContext) {
        for query in queries {
            if appState.query.currentSavedQueryId == query.id {
                appState.query.currentSavedQueryId = nil
                appState.query.lastSavedAt = nil
            }
            modelContext.delete(query)
        }

        do {
            try modelContext.save()
            DebugLog.print("🗑️ [SavedQueriesViewModel] Deleted \(queries.count) queries")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to delete queries: \(error)")
        }

        queriesToDelete = []
    }

    func deleteFolder(_ folder: QueryFolder, deleteQueries: Bool, modelContext: ModelContext) {
        if deleteQueries {
            // Delete all queries in the folder
            for query in folder.queries ?? [] {
                if appState.query.currentSavedQueryId == query.id {
                    appState.query.currentSavedQueryId = nil
                    appState.query.lastSavedAt = nil
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
            DebugLog.print("🗑️ [SavedQueriesViewModel] Deleted folder: \(folder.name)")
        } catch {
            DebugLog.print("❌ [SavedQueriesViewModel] Failed to delete folder: \(error)")
        }

        folderToDelete = nil
    }

    // MARK: - Folder Expansion

    func toggleFolderExpansion(_ folder: QueryFolder) {
        if expandedFolders.contains(folder.id) {
            expandedFolders.remove(folder.id)
            DebugLog.print("📁 [SavedQueriesViewModel] Collapsed folder: \(folder.name)")
        } else {
            expandedFolders.insert(folder.id)
            DebugLog.print("📂 [SavedQueriesViewModel] Expanded folder: \(folder.name)")
        }
    }

    func expandFolderContaining(_ query: SavedQuery) {
        if let folder = query.folder {
            expandedFolders.insert(folder.id)
        }
    }

    // MARK: - Selection Handling

    func handleSelectionChange(
        oldIDs: Set<SavedQuery.ID>,
        newIDs: Set<SavedQuery.ID>,
        savedQueries: [SavedQuery]
    ) {
        // Load query when a single item is clicked (not added to existing selection)
        if newIDs.count == 1, let newID = newIDs.first,
           !oldIDs.contains(newID),
           let query = savedQueries.first(where: { $0.id == newID }) {
            loadQuery(query)
        }
    }

    func handleCurrentQueryIdChange(
        newID: UUID?,
        savedQueries: [SavedQuery]
    ) -> Set<SavedQuery.ID> {
        if let newID = newID {
            // Auto-expand folder containing this query
            if let query = savedQueries.first(where: { $0.id == newID }) {
                expandFolderContaining(query)
            }
            return [newID]
        } else {
            return []
        }
    }

    // MARK: - Move to Folder

    func prepareToMoveQueries(
        query: SavedQuery,
        selectedQueryIDs: Set<SavedQuery.ID>,
        savedQueries: [SavedQuery]
    ) {
        if selectedQueryIDs.count > 1 && selectedQueryIDs.contains(query.id) {
            queriesToMove = savedQueries.filter { selectedQueryIDs.contains($0.id) }
        } else {
            queriesToMove = [query]
        }
    }

    func prepareToDeleteSelected(
        selectedQueryIDs: Set<SavedQuery.ID>,
        savedQueries: [SavedQuery]
    ) {
        let queries = savedQueries.filter { selectedQueryIDs.contains($0.id) }
        queriesToDelete = queries
    }
}

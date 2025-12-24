//
//  SavedQueriesSidebarSection.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

/// Sidebar section for saved queries with folder support
struct SavedQueriesSidebarSection: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    let savedQueries: [SavedQuery]
    let folders: [QueryFolder]

    @Binding var selectedQueryIDs: Set<SavedQuery.ID>
    @State private var viewModel: SavedQueriesViewModel?

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel = viewModel {
                // Title
                Text("Saved Queries")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Search and sort header
                searchAndSortHeader(viewModel: viewModel)

                queryList(viewModel: viewModel)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SavedQueriesViewModel(appState: appState)
            }
            // Sync initial selection from restored saved query
            if let savedQueryId = appState.query.currentSavedQueryId {
                selectedQueryIDs = [savedQueryId]
                // Auto-expand folder containing this query
                if let query = savedQueries.first(where: { $0.id == savedQueryId }) {
                    viewModel?.expandFolderContaining(query)
                }
            }
        }
    }

    // MARK: - Search and Sort Header

    @ViewBuilder
    private func searchAndSortHeader(viewModel: SavedQueriesViewModel) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Filter", text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ))
                .font(.system(size: 12))
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            .clipShape(Capsule())

            sortMenu(viewModel: viewModel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Sort Menu

    @ViewBuilder
    private func sortMenu(viewModel: SavedQueriesViewModel) -> some View {
        Menu {
            ForEach(QuerySortOption.allCases, id: \.self) { option in
                Button {
                    viewModel.sortOption = option
                } label: {
                    HStack {
                        Label(option.rawValue, systemImage: option.icon)
                        if viewModel.sortOption == option {
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

    // MARK: - Query List

    @ViewBuilder
    private func queryList(viewModel: SavedQueriesViewModel) -> some View {
        let hasContent = viewModel.hasAnyContent(savedQueries: savedQueries, folders: folders)
        let hasMatching = viewModel.hasMatchingContent(savedQueries: savedQueries, folders: folders)
        let filteredFolders = viewModel.filteredFolders(from: folders, savedQueries: savedQueries)
        let unfolderedQueries = viewModel.unfolderedQueries(from: savedQueries)

        List(selection: $selectedQueryIDs) {
            if !hasContent {
                Text("No saved queries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !hasMatching {
                Text("No matching queries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Folders with their queries
                ForEach(filteredFolders) { folder in
                    folderDisclosureGroup(folder: folder, viewModel: viewModel)
                }

                // Queries not in any folder
                ForEach(viewModel.filteredAndSorted(unfolderedQueries)) { query in
                    queryRow(query: query, viewModel: viewModel)
                        .listRowSeparator(.visible)
                }
            }
        }
        .onDeleteCommand {
            guard !selectedQueryIDs.isEmpty else { return }
            viewModel.prepareToDeleteSelected(
                selectedQueryIDs: selectedQueryIDs,
                savedQueries: savedQueries
            )
        }
        .onChange(of: selectedQueryIDs) { oldIDs, newIDs in
            viewModel.handleSelectionChange(
                oldIDs: oldIDs,
                newIDs: newIDs,
                savedQueries: savedQueries
            )
            // Clear tab's savedQueryId when deselecting
            if newIDs.isEmpty && !oldIDs.isEmpty {
                tabManager.clearActiveTabSavedQueryId()
            }
        }
        .onChange(of: appState.query.currentSavedQueryId) { _, newID in
            selectedQueryIDs = viewModel.handleCurrentQueryIdChange(
                newID: newID,
                savedQueries: savedQueries
            )
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.createNewQuery(savedQueries: savedQueries, modelContext: modelContext)
                // Select the newly created query
                if let newQueryId = appState.query.currentSavedQueryId {
                    selectedQueryIDs = [newQueryId]
                }
            } label: {
                Label("New Query", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 100, style: .continuous))
            .padding()
            .buttonStyle(.glass)
        }
        .sheet(item: Binding(
            get: { viewModel.queryToEdit },
            set: { viewModel.queryToEdit = $0 }
        )) { query in
            EditQuerySheet(query: query)
        }
        .sheet(item: Binding(
            get: { viewModel.folderToEdit },
            set: { viewModel.folderToEdit = $0 }
        )) { folder in
            EditFolderSheet(folder: folder)
        }
        .sheet(isPresented: Binding(
            get: { !viewModel.queriesToMove.isEmpty },
            set: { if !$0 { viewModel.queriesToMove = [] } }
        )) {
            MoveToFolderSheet(queries: viewModel.queriesToMove, folders: folders)
        }
        .confirmationDialog(
            viewModel.queriesToDelete.count == 1 ? "Delete Query?" : "Delete \(viewModel.queriesToDelete.count) Queries?",
            isPresented: Binding(
                get: { !viewModel.queriesToDelete.isEmpty },
                set: { if !$0 { viewModel.queriesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteQueries(viewModel.queriesToDelete, modelContext: modelContext)
                selectedQueryIDs = []
            }
            Button("Cancel", role: .cancel) {
                viewModel.queriesToDelete = []
            }
        } message: {
            if viewModel.queriesToDelete.count == 1, let query = viewModel.queriesToDelete.first {
                Text("Are you sure you want to delete \"\(query.name)\"? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(viewModel.queriesToDelete.count) queries? This action cannot be undone.")
            }
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(
                get: { viewModel.folderToDelete != nil },
                set: { if !$0 { viewModel.folderToDelete = nil } }
            )
        ) {
            Button("Delete Folder Only", role: .destructive) {
                if let folder = viewModel.folderToDelete {
                    viewModel.deleteFolder(folder, deleteQueries: false, modelContext: modelContext)
                }
            }
            Button("Delete Folder and Queries", role: .destructive) {
                if let folder = viewModel.folderToDelete {
                    viewModel.deleteFolder(folder, deleteQueries: true, modelContext: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.folderToDelete = nil
            }
        } message: {
            if let folder = viewModel.folderToDelete {
                let queryCount = folder.queries?.count ?? 0
                if queryCount > 0 {
                    Text("The folder \"\(folder.name)\" contains \(queryCount) queries. What would you like to do?")
                } else {
                    Text("Are you sure you want to delete the folder \"\(folder.name)\"?")
                }
            }
        }
    }

    // MARK: - Folder Disclosure Group

    @ViewBuilder
    private func folderDisclosureGroup(folder: QueryFolder, viewModel: SavedQueriesViewModel) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { viewModel.expandedFolders.contains(folder.id) },
                set: { _ in viewModel.toggleFolderExpansion(folder) }
            )
        ) {
            let folderQueries = viewModel.filteredAndSorted(folder.queries ?? [])
            ForEach(folderQueries) { query in
                queryRow(query: query, viewModel: viewModel)
                    .listRowSeparator(.visible)
            }
        } label: {
            QueryFolderRowView(
                folder: folder,
                onRename: { viewModel.folderToEdit = folder },
                onDelete: { viewModel.folderToDelete = folder }
            )
        }
    }

    // MARK: - Query Row

    @ViewBuilder
    private func queryRow(query: SavedQuery, viewModel: SavedQueriesViewModel) -> some View {
        SavedQueryRowView(
            query: query,
            isSelected: selectedQueryIDs.contains(query.id),
            selectedCount: selectedQueryIDs.count,
            onEdit: { viewModel.queryToEdit = query },
            onDelete: { viewModel.queriesToDelete = [query] },
            onDeleteSelected: {
                viewModel.prepareToDeleteSelected(
                    selectedQueryIDs: selectedQueryIDs,
                    savedQueries: savedQueries
                )
            },
            onDuplicate: {
                viewModel.duplicateQuery(query, modelContext: modelContext)
            },
            onMoveToFolder: {
                viewModel.prepareToMoveQueries(
                    query: query,
                    selectedQueryIDs: selectedQueryIDs,
                    savedQueries: savedQueries
                )
            }
        )
    }
}

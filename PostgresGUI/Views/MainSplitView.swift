//
//  MainSplitView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct MainSplitView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText: String = ""
    @State private var viewModel: DetailContentViewModel?

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            ConnectionsDatabasesSidebar()
                .navigationSplitViewColumnWidth(
                    min: Constants.ColumnWidth.sidebarMin,
                    ideal: Constants.ColumnWidth.sidebarIdeal,
                    max: Constants.ColumnWidth.sidebarMax
                )
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            HStack(spacing: 2) {
                                Button {
                                    appState.sidebarViewMode = .connections
                                } label: {
                                    Image(systemName: "cylinder.split.1x2.fill")
                                }
                                Button {
                                    appState.sidebarViewMode = .queries
                                } label: {
                                    Image(systemName: "text.document")
                                }
                            }
                        }
                        Spacer()
                    }
                }
        } detail: {
            VSplitView {
                // Row 1: 2 resizable columns
                HSplitView {
                    // Column 1: Table list - isolated from query state
                    TablesListIsolated(
                        tables: appState.tables,
                        selectedTable: $appState.selectedTable,
                        isLoadingTables: appState.isLoadingTables,
                        selectedDatabase: appState.selectedDatabase,
                        refreshTablesAction: {
                            await refreshTablesInMainSplitView(appState: appState)
                        }
                    )
                    .frame(minWidth: 250)

                    // Column 2: Query results with toolbar
                    VStack(spacing: 0) {
                        if let viewModel = viewModel {
                            QueryResultsView(
                                onDeleteKeyPressed: {
                                    viewModel.deleteSelectedRows()
                                },
                                onSpaceKeyPressed: {
                                    viewModel.openJSONView()
                                }
                            )
                        } else {
                            QueryResultsView()
                        }
                    }
                    .frame(minWidth: 300)
                }.frame(minHeight: 400)

                QueryEditorView()
                    .frame(minHeight: 250)
            }
            .toolbar {
                if let viewModel = viewModel {
                    DetailContentToolbar(viewModel: viewModel)
                }
            }
            .onAppear {
                if viewModel == nil {
                    let rowOperations = RowOperationsService()
                    let queryService = QueryService(
                        databaseService: appState.databaseService,
                        queryState: appState.query
                    )
                    viewModel = DetailContentViewModel(
                        appState: appState,
                        rowOperations: rowOperations,
                        queryService: queryService
                    )
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search")
        .modifier(DetailContentModalsWrapper(viewModel: viewModel))
    }
}

// Wrapper to handle optional viewModel for modals
struct DetailContentModalsWrapper: ViewModifier {
    var viewModel: DetailContentViewModel?
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        if let vm = viewModel {
            content.modifier(DetailContentModals(viewModel: vm))
        } else {
            content
        }
    }
}

// Helper function to refresh tables - same logic as in TablesListView
@MainActor
private func refreshTablesInMainSplitView(appState: AppState) async {
    DebugLog.print("🔄 [MainSplitView] Refresh tables START")
    
    guard let database = appState.selectedDatabase else {
        DebugLog.print("❌ [MainSplitView] No database selected for refresh")
        return
    }
    
    defer {
        DebugLog.print("🔄 [MainSplitView] Refresh tables END - setting isLoadingTables=false")
        appState.isLoadingTables = false
    }
    
    appState.isLoadingTables = true
    
    // Check if we're connected
    guard appState.databaseService.isConnected else {
        DebugLog.print("❌ [MainSplitView] Not connected, cannot refresh")
        return
    }
    
    // Refresh databases list
    do {
        DebugLog.print("📊 [MainSplitView] Fetching databases...")
        appState.databases = try await appState.databaseService.fetchDatabases()
        DebugLog.print("✅ [MainSplitView] Refreshed \(appState.databases.count) databases")
    } catch {
        DebugLog.print("❌ [MainSplitView] Error refreshing databases: \(error)")
        DebugLog.print("❌ [MainSplitView] Error details: \(String(describing: error))")
        // Continue with table refresh even if database refresh fails
    }
    
    // Refresh tables list
    do {
        DebugLog.print("📊 [MainSplitView] Fetching tables from database: \(database.name)")
        appState.tables = try await appState.databaseService.fetchTables(database: database.name)
        DebugLog.print("✅ [MainSplitView] Refreshed \(appState.tables.count) tables")
        
        // Update selectedTable reference if it still exists in the refreshed list
        // Only update if the table object has actually changed (e.g., primaryKeyColumns or columnInfo updated)
        // This prevents unnecessary refreshes when the table is the same
        if let selectedTable = appState.selectedTable,
           let refreshedTable = appState.tables.first(where: { $0.id == selectedTable.id }) {
            // Only update if the table has actually changed (e.g., metadata was added)
            if refreshedTable != selectedTable {
                DebugLog.print("🔄 [MainSplitView] Updating selectedTable with refreshed metadata")
                appState.selectedTable = refreshedTable
            } else {
                DebugLog.print("🔄 [MainSplitView] selectedTable unchanged, skipping update")
            }
        } else if appState.selectedTable != nil {
            // Clear selection if the table no longer exists
            DebugLog.print("🔄 [MainSplitView] Selected table no longer exists, clearing selection")
            appState.selectedTable = nil
        }
    } catch {
        DebugLog.print("❌ [MainSplitView] Error refreshing tables: \(error)")
        DebugLog.print("❌ [MainSplitView] Error details: \(String(describing: error))")
        // Clear tables and selection on error to prevent stale data
        appState.tables = []
        appState.selectedTable = nil
    }
}

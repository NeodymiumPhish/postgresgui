//
//  MainSplitView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct MainSplitView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    if horizontalSizeClass == .regular {
                        ToolbarItem(placement: .secondaryAction) {
                            HStack(spacing: 0) {
                                Button {
                                    appState.sidebarViewMode = .connections
                                } label: {
                                    Label("Connections", systemImage: "cylinder.split.1x2.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .frame(width: 32, height: 24)
                                .background(appState.sidebarViewMode == .connections ? Color.secondary.opacity(0.2) : Color.clear)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                                
                                Button {
                                    appState.sidebarViewMode = .queries
                                } label: {
                                    Label("Queries", systemImage: "text.document")
                                        .labelStyle(.iconOnly)
                                }
                                .frame(width: 32, height: 24)
                                .background(appState.sidebarViewMode == .queries ? Color.secondary.opacity(0.2) : Color.clear)
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                            }
                        }
                    }
                }
        } detail: {
            VStack(spacing: 0) {
                if tabManager.tabs.count > 1 {
                    TabBarView()
                }

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
                                await TableRefreshService.refresh(appState: appState)
                            }
                        )
                        .frame(minWidth: 250)

                        // Column 2: Query results with toolbar
                        VStack(spacing: 0) {
                            if let viewModel = viewModel {
                                QueryResultsView(
                                    searchText: searchText,
                                    onDeleteKeyPressed: {
                                        viewModel.deleteSelectedRows()
                                    },
                                    onSpaceKeyPressed: {
                                        viewModel.openJSONView()
                                    }
                                )
                            } else {
                                QueryResultsView(searchText: searchText)
                            }
                        }
                        // .frame(minWidth: 250)
                    }.frame(minHeight: 400)

                    QueryEditorView()
                        .frame(minHeight: 250)
                }
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
        .searchable(text: $searchText, prompt: "Filter results")
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


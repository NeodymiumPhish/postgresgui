//
//  DetailContentView.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// DetailContentView with improved architecture
/// Uses ViewModel pattern for better separation of concerns and testability
struct DetailContentView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: DetailContentViewModel

    init() {
        // Initialize ViewModel with dependencies
        let appState = AppState()  // Will be updated via .onAppear
        let rowOperations = RowOperationsService()
        let queryService = QueryService(
            databaseService: appState.databaseService,
            queryState: appState.query
        )
        _viewModel = State(initialValue: DetailContentViewModel(
            appState: appState,
            rowOperations: rowOperations,
            queryService: queryService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: Query results with resizable split
            ResizableSplitView(
                minLeftWidth: 180,
                minRightWidth: 400,
                idealLeftWidth: 200,
                idealRightWidth: 600,
                maxLeftWidth: 280
            ) {
                // Left pane: Tables list (commented out for now, as in original)
                // TablesListView()
            } right: {
                // Right pane: Query results
                queryResultsView
            }

            Divider()

            // Bottom row: Query editor (spans full width)
            QueryEditorView()
        }
        .toolbar {
            DetailContentToolbar(viewModel: viewModel)
        }
        .detailContentModals(viewModel: viewModel)
        .onAppear {
            // Update ViewModel with the actual AppState instance from environment
            // This is needed because we can't access @Environment in init()
            updateViewModelAppState()
        }
    }

    @ViewBuilder
    private var queryResultsView: some View {
        if appState.showQueryResults {
            QueryResultsView(
                onDeleteKeyPressed: {
                    viewModel.deleteSelectedRows()
                },
                onSpaceKeyPressed: {
                    viewModel.openJSONView()
                }
            )
        } else {
            ContentUnavailableView {
                Label {
                    Text("No results found")
                        .font(.title3)
                        .fontWeight(.regular)
                } icon: { }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateViewModelAppState() {
        // Re-initialize ViewModel with the correct AppState from environment
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

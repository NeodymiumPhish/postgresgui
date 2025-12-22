//
//  QueryEditorViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// ViewModel for QueryEditorView
@Observable
@MainActor
class QueryEditorViewModel {
    private let appState: AppState
    private let queryService: QueryServiceProtocol

    init(appState: AppState, queryService: QueryServiceProtocol) {
        self.appState = appState
        self.queryService = queryService
    }

    /// Execute the current query
    func executeQuery() async {
        DebugLog.print("🚀 [QueryEditorViewModel] Execute button clicked")

        // Set loading state
        appState.query.isExecutingQuery = true
        appState.query.queryError = nil
        appState.query.queryExecutionTime = nil
        appState.query.showQueryResults = false
        appState.query.selectedRowIDs = []

        // Execute query
        let result = await queryService.executeQuery(appState.query.queryText)

        // Update state based on result
        if result.isSuccess {
            appState.query.queryResults = result.rows
            appState.query.queryColumnNames = result.columnNames.isEmpty ? nil : result.columnNames
            appState.query.showQueryResults = true
            appState.query.queryExecutionTime = result.executionTime
            DebugLog.print("✅ [QueryEditorViewModel] Query executed successfully")
        } else if let error = result.error {
            appState.query.queryError = error
            appState.query.queryColumnNames = nil
            appState.query.showQueryResults = true
            appState.query.queryExecutionTime = result.executionTime
            DebugLog.print("❌ [QueryEditorViewModel] Query execution failed: \(error)")
        }

        appState.query.isExecutingQuery = false
    }

    /// Format execution time for display
    func formatExecutionTime(_ timeInterval: TimeInterval) -> String {
        if timeInterval < 1.0 {
            return String(format: "%.0f ms", timeInterval * 1000)
        } else {
            return String(format: "%.2f s", timeInterval)
        }
    }
}

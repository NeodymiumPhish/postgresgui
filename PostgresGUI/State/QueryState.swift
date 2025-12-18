//
//  QueryState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Manages query execution state and results
@Observable
@MainActor
class QueryState {
    // Query editor state
    var queryText: String = ""
    var queryResults: [TableRow] = []
    var queryColumnNames: [String]? = nil
    var isExecutingQuery: Bool = false
    var queryError: String? = nil
    var showQueryResults: Bool = false
    var queryExecutionTime: TimeInterval? = nil
    var selectedRowIDs: Set<UUID> = []

    // Pagination state
    var currentPage: Int = 0
    var rowsPerPage: Int = Constants.Pagination.defaultRowsPerPage

    // Query execution management (for cancellation and race condition prevention)
    var currentQueryTask: Task<Void, Never>? = nil
    var queryCounter: Int = 0

    /// Cancel the current running query
    func cancelCurrentQuery() {
        currentQueryTask?.cancel()
        currentQueryTask = nil
        queryCounter += 1
    }

    /// Reset query state
    func reset() {
        queryText = ""
        queryResults = []
        queryColumnNames = nil
        isExecutingQuery = false
        queryError = nil
        showQueryResults = false
        queryExecutionTime = nil
        selectedRowIDs = []
        currentPage = 0
    }

    /// Clean up when window closes
    func cleanup() {
        cancelCurrentQuery()
        reset()
    }
}

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
    var queryError: Error? = nil
    var showQueryResults: Bool = false
    var queryExecutionTime: TimeInterval? = nil
    var selectedRowIDs: Set<UUID> = []

    /// Formatted error message for display
    var queryErrorMessage: String? {
        guard let error = queryError else { return nil }
        return PostgresError.extractDetailedMessage(error)
    }

    /// Format execution time for display
    static func formatExecutionTime(_ timeInterval: TimeInterval) -> String {
        if timeInterval < 1.0 {
            return String(format: "%.0f ms", timeInterval * 1000)
        } else {
            return String(format: "%.2f s", timeInterval)
        }
    }

    // Saved query state
    var currentSavedQueryId: UUID? = nil
    var lastSavedAt: Date? = nil
    var currentQueryName: String? = nil

    // Status display state
    var statusMessage: String? = nil
    var statusTimer: Task<Void, Never>? = nil

    // Pagination state
    var currentPage: Int = 0
    var rowsPerPage: Int = Constants.Pagination.defaultRowsPerPage

    // Query execution management (for cancellation and race condition prevention)
    var currentQueryTask: Task<Void, Never>? = nil
    var queryCounter: Int = 0

    /// Set a temporary status message that auto-reverts after the specified duration
    func setTemporaryStatus(_ message: String, duration: TimeInterval = 3.0) {
        statusTimer?.cancel()
        statusMessage = message
        statusTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.statusMessage = nil
        }
    }

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
        currentSavedQueryId = nil
        lastSavedAt = nil
        currentQueryName = nil
        statusTimer?.cancel()
        statusTimer = nil
        statusMessage = nil
    }

    /// Clean up when window closes
    func cleanup() {
        cancelCurrentQuery()
        reset()
    }
}

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
    var isRestoringFromTab: Bool = false
    var queryResults: [TableRow] = []
    var queryColumnNames: [String]? = nil
    var cachedResultsTableId: String? = nil  // Tracks which table the cached results belong to
    var isExecutingQuery: Bool = false
    var queryError: Error? = nil
    var showQueryResults: Bool = false
    var showTimeoutAlert: Bool = false
    var lastQueryText: String? = nil  // For retry on timeout
    var queryExecutionTime: TimeInterval? = nil
    var selectedRowIDs: Set<UUID> = []

    /// Formatted error message for display
    var queryErrorMessage: String? {
        guard let error = queryError else { return nil }
        return PostgresError.extractDetailedMessage(error)
    }

    /// Check if the current error is a timeout
    var isTimeoutError: Bool {
        guard let error = queryError else { return false }
        return DatabaseError.isTimeout(error)
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

    // Mutation toast state
    var mutationToast: MutationToastData? = nil
    var toastTimer: Task<Void, Never>? = nil

    // Pagination state
    var currentPage: Int = 0
    var rowsPerPage: Int = Constants.Pagination.defaultRowsPerPage
    var hasNextPage: Bool = false

    // Query execution management (for cancellation and race condition prevention)
    var currentQueryTask: Task<Void, Never>? = nil
    var queryCounter: Int = 0

    // Results version tracking (for optimistic update rollback safety)
    var resultsVersion: Int = 0

    /// Set a temporary status message that auto-reverts after the specified duration
    func setTemporaryStatus(_ message: String, duration: TimeInterval = 3.0) {
        withAutoDismissTimer(
            timer: &statusTimer,
            duration: duration,
            setValue: { self.statusMessage = message },
            clearValue: { self.statusMessage = nil }
        )
    }

    /// Show mutation toast notification
    func showMutationToast(type: QueryType, tableName: String?, duration: TimeInterval = 5.0) {
        withAutoDismissTimer(
            timer: &toastTimer,
            duration: duration,
            setValue: {
                self.mutationToast = MutationToastData(
                    title: type.successTitle,
                    tableName: tableName,
                    queryType: type
                )
            },
            clearValue: { self.mutationToast = nil }
        )
    }
    
    // MARK: - Private Timer Helpers
    
    /// Generic helper for auto-dismissing timers
    /// Cancels previous timer, sets value, then creates new timer to clear value after duration
    private func withAutoDismissTimer(
        timer: inout Task<Void, Never>?,
        duration: TimeInterval,
        setValue: () -> Void,
        clearValue: @escaping () -> Void
    ) {
        timer?.cancel()
        setValue()
        timer = Task {
            try? await Task.sleep(nanoseconds: duration.nanoseconds)
            guard !Task.isCancelled else { return }
            clearValue()
        }
    }

    /// Dismiss mutation toast
    func dismissMutationToast() {
        toastTimer?.cancel()
        toastTimer = nil
        mutationToast = nil
    }

    /// Cancel the current running query
    func cancelCurrentQuery() {
        currentQueryTask?.cancel()
        currentQueryTask = nil
        queryCounter += 1
    }

    // MARK: - Query Execution State Helpers

    /// Start query execution - resets error and execution time, sets loading state
    func startQueryExecution() {
        isExecutingQuery = true
        queryError = nil
        queryExecutionTime = nil
    }

    /// Finish query execution with a result
    func finishQueryExecution(with result: QueryResult) {
        queryExecutionTime = result.executionTime
        if result.isSuccess {
            updateQueryResults(result.rows, columnNames: result.columnNames)
        } else {
            queryError = result.error
            queryColumnNames = nil
            showQueryResults = true
            // Show timeout alert if this was a timeout error
            if DatabaseError.isTimeout(result.error!) {
                showTimeoutAlert = true
            }
        }
        isExecutingQuery = false
    }

    /// Update query results and column names
    func updateQueryResults(_ results: [TableRow], columnNames: [String]?) {
        queryResults = results
        queryColumnNames = columnNames?.isEmpty == false ? columnNames : nil
        showQueryResults = true
    }

    /// Clear query results and reset state for a new query
    func clearQueryResults() {
        showQueryResults = false
        queryResults = []
        queryColumnNames = nil
        selectedRowIDs = []
    }

    /// Reset query state
    func reset() {
        if !queryText.isEmpty {
            DebugLog.print("🗑️ [QueryState] reset() called - clearing queryText (was: \"\(queryText.prefix(50))...\")")
        }
        queryText = ""
        queryResults = []
        queryColumnNames = nil
        cachedResultsTableId = nil
        isExecutingQuery = false
        queryError = nil
        showQueryResults = false
        showTimeoutAlert = false
        lastQueryText = nil
        queryExecutionTime = nil
        selectedRowIDs = []
        currentPage = 0
        hasNextPage = false
        currentSavedQueryId = nil
        lastSavedAt = nil
        currentQueryName = nil
        statusTimer?.cancel()
        statusTimer = nil
        statusMessage = nil
        toastTimer?.cancel()
        toastTimer = nil
        mutationToast = nil
    }

    /// Clean up when window closes
    func cleanup() {
        cancelCurrentQuery()
        reset()
    }
}

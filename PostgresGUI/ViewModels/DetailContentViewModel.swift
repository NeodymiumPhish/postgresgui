//
//  DetailContentViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// ViewModel for DetailContentView
/// Manages UI state and coordinates business logic for query result operations
@Observable
@MainActor
class DetailContentViewModel {

    // MARK: - Dependencies

    private let appState: AppState
    private let rowOperations: RowOperationsServiceProtocol
    private let queryService: QueryServiceProtocol

    // MARK: - Modal State

    var showJSONView = false
    var showDeleteConfirmation = false
    var showRowEditor = false

    // MARK: - Editing State

    var rowToEdit: TableRow?
    var editedRowValues: [String: String?] = [:]

    // MARK: - Error State

    var deleteError: String?
    var editError: String?
    var jsonViewError: String?

    // MARK: - Initialization

    init(appState: AppState, rowOperations: RowOperationsServiceProtocol, queryService: QueryServiceProtocol) {
        self.appState = appState
        self.rowOperations = rowOperations
        self.queryService = queryService
    }

    // MARK: - JSON Viewer

    func openJSONView() {
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.selectedRowIDs,
            queryResults: appState.queryResults
        )

        switch result {
        case .success:
            showJSONView = true
        case .failure(let error):
            jsonViewError = error.localizedDescription
        }
    }

    // MARK: - Delete Operations

    func deleteSelectedRows() {
        DebugLog.print("🗑️ [DetailContentViewModel] Delete button clicked for \(appState.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.selectedTable else {
            deleteError = RowOperationError.noTableSelected.localizedDescription
            return
        }

        // Check for primary key (metadata is fetched when query runs)
        guard let pkColumns = selectedTable.primaryKeyColumns, !pkColumns.isEmpty else {
            deleteError = RowOperationError.noPrimaryKey.localizedDescription
            return
        }

        // Validate row selection
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.selectedRowIDs,
            queryResults: appState.queryResults
        )

        switch result {
        case .success:
            showDeleteConfirmation = true
        case .failure(let error):
            deleteError = error.localizedDescription
        }
    }

    func performDelete() async {
        guard let selectedTable = appState.selectedTable else { return }

        // Get selected rows
        let selectedRows = appState.queryResults.filter { appState.selectedRowIDs.contains($0.id) }

        // Perform delete
        let result = await rowOperations.deleteRows(
            table: selectedTable,
            rows: selectedRows,
            databaseService: appState.databaseService
        )

        switch result {
        case .success:
            // Remove deleted rows from the UI
            let deletedIDs = Set(selectedRows.map { $0.id })
            appState.queryResults.removeAll { deletedIDs.contains($0.id) }
            appState.selectedRowIDs = []
        case .failure(let error):
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Edit Operations

    func editSelectedRows() {
        DebugLog.print("✏️ [DetailContentViewModel] Edit button clicked for \(appState.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.selectedTable else {
            editError = RowOperationError.noTableSelected.localizedDescription
            return
        }

        // Check for primary key (metadata is fetched when query runs)
        guard let pkColumns = selectedTable.primaryKeyColumns, !pkColumns.isEmpty else {
            editError = RowOperationError.noPrimaryKey.localizedDescription
            return
        }

        // Validate we have column names
        guard appState.queryColumnNames != nil else {
            editError = "No query results available"
            return
        }

        // Validate row selection and get first row
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.selectedRowIDs,
            queryResults: appState.queryResults
        )

        switch result {
        case .success(let selectedRows):
            guard let rowToEdit = selectedRows.first else {
                editError = "No row selected"
                return
            }
            self.rowToEdit = rowToEdit
            showRowEditor = true
        case .failure(let error):
            editError = error.localizedDescription
        }
    }

    func saveEditedRow(originalRow: TableRow, updatedValues: [String: String?]) async throws {
        DebugLog.print("🟡 [DetailContentViewModel.saveEditedRow] Received updatedValues: \(updatedValues)")
        DebugLog.print("  updatedValues count: \(updatedValues.count)")

        guard let selectedTable = appState.selectedTable else {
            throw RowOperationError.noTableSelected
        }

        // Perform update
        let result = await rowOperations.updateRow(
            table: selectedTable,
            originalRow: originalRow,
            updatedValues: updatedValues,
            databaseService: appState.databaseService
        )

        switch result {
        case .success(let updatedRow):
            // Update the row in the UI
            if let index = appState.queryResults.firstIndex(where: { $0.id == originalRow.id }) {
                appState.queryResults[index] = updatedRow

                // Update selection to use the new row's ID
                appState.selectedRowIDs.remove(originalRow.id)
                appState.selectedRowIDs.insert(updatedRow.id)
            }
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Query Refresh

    func refreshQuery() async {
        DebugLog.print("🔄 [DetailContentViewModel] Refresh button clicked")

        // Set loading state FIRST to prevent empty state flicker
        appState.isExecutingQuery = true
        appState.queryError = nil
        appState.queryExecutionTime = nil
        appState.showQueryResults = false // Hide results view during loading
        appState.queryResults = [] // Clear previous results
        appState.queryColumnNames = nil // Clear previous column names
        appState.selectedRowIDs = [] // Clear selected rows

        // Execute query
        let result = await queryService.executeQuery(appState.queryText)

        // Update state based on result
        if result.isSuccess {
            appState.queryResults = result.rows
            appState.queryColumnNames = result.columnNames.isEmpty ? nil : result.columnNames
            appState.showQueryResults = true
            appState.queryExecutionTime = result.executionTime
            DebugLog.print("✅ [DetailContentViewModel] Query executed successfully, showing results")
        } else if let error = result.error {
            appState.queryError = error.localizedDescription
            appState.queryColumnNames = nil
            appState.showQueryResults = true
            appState.queryExecutionTime = result.executionTime
            DebugLog.print("❌ [DetailContentViewModel] Query execution failed: \(error)")
        }

        appState.isExecutingQuery = false
    }
}

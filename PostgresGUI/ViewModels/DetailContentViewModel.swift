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

    init(appState: AppState, rowOperations: RowOperationsServiceProtocol) {
        self.appState = appState
        self.rowOperations = rowOperations
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

        // Validate row selection
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.selectedRowIDs,
            queryResults: appState.queryResults
        )

        switch result {
        case .success:
            // Check if we need to fetch metadata first
            if selectedTable.primaryKeyColumns == nil {
                Task {
                    await fetchMetadataAndShowDeleteDialog()
                }
            } else {
                showDeleteConfirmation = true
            }
        case .failure(let error):
            deleteError = error.localizedDescription
        }
    }

    private func fetchMetadataAndShowDeleteDialog() async {
        guard let selectedTable = appState.selectedTable else { return }

        let result = await rowOperations.ensureTableMetadata(
            table: selectedTable,
            databaseService: appState.databaseService
        )

        switch result {
        case .success(let updatedTable):
            appState.selectedTable = updatedTable
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

            // Check if we need to fetch metadata first
            if selectedTable.primaryKeyColumns == nil || selectedTable.columnInfo == nil {
                Task {
                    await fetchMetadataAndShowEditor(rowToEdit)
                }
            } else {
                self.rowToEdit = rowToEdit
                showRowEditor = true
            }
        case .failure(let error):
            editError = error.localizedDescription
        }
    }

    private func fetchMetadataAndShowEditor(_ row: TableRow) async {
        guard let selectedTable = appState.selectedTable else { return }

        let result = await rowOperations.ensureTableMetadata(
            table: selectedTable,
            databaseService: appState.databaseService
        )

        switch result {
        case .success(let updatedTable):
            appState.selectedTable = updatedTable
            self.rowToEdit = row
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

        let startTime = Date()

        do {
            DebugLog.print("📊 [DetailContentViewModel] Executing query...")
            let (results, columnNames) = try await appState.databaseService.executeQuery(appState.queryText)
            appState.queryResults = results
            appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
            appState.showQueryResults = true

            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)

            DebugLog.print("✅ [DetailContentViewModel] Query executed successfully, showing results")
        } catch {
            appState.queryError = error.localizedDescription
            appState.queryColumnNames = nil
            appState.showQueryResults = true

            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)

            DebugLog.print("❌ [DetailContentViewModel] Query execution failed: \(error)")
        }

        appState.isExecutingQuery = false
    }
}

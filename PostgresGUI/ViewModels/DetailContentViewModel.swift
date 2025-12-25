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

    // MARK: - Table Metadata Helpers

    /// Updates the selected table with metadata if not already set
    private func updateSelectedTableMetadata(
        primaryKeys: [String]? = nil,
        columnInfo: [ColumnInfo]? = nil
    ) {
        guard let selectedTable = appState.connection.selectedTable else { return }

        let needsPKUpdate = primaryKeys != nil && selectedTable.primaryKeyColumns == nil
        let needsColInfoUpdate = columnInfo != nil && selectedTable.columnInfo == nil

        guard needsPKUpdate || needsColInfoUpdate else { return }

        var updatedTable = selectedTable
        if needsPKUpdate { updatedTable.primaryKeyColumns = primaryKeys }
        if needsColInfoUpdate { updatedTable.columnInfo = columnInfo }
        appState.connection.selectedTable = updatedTable
    }

    // MARK: - JSON Viewer

    func openJSONView() {
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
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
        DebugLog.print("🗑️ [DetailContentViewModel] Delete button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.connection.selectedTable else {
            deleteError = RowOperationError.noTableSelected.localizedDescription
            return
        }

        // Validate row selection
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
        )

        switch result {
        case .success:
            // Check metadata cache first, then selectedTable
            let cachedMetadata = appState.connection.tableMetadataCache[selectedTable.id]
            let pkColumns = cachedMetadata?.primaryKeys ?? selectedTable.primaryKeyColumns

            if let pkColumns = pkColumns, !pkColumns.isEmpty {
                updateSelectedTableMetadata(primaryKeys: pkColumns)
                showDeleteConfirmation = true
            } else {
                // Fetch primary keys if not cached
                Task {
                    await fetchPrimaryKeysAndShowDeleteDialog(table: selectedTable)
                }
            }
        case .failure(let error):
            deleteError = error.localizedDescription
        }
    }

    private func fetchPrimaryKeysAndShowDeleteDialog(table: TableInfo) async {
        do {
            let pkColumns = try await appState.connection.databaseService.fetchPrimaryKeyColumns(
                schema: table.schema,
                table: table.name
            )

            guard !pkColumns.isEmpty else {
                deleteError = RowOperationError.noPrimaryKey.localizedDescription
                return
            }

            updateSelectedTableMetadata(primaryKeys: pkColumns)
            showDeleteConfirmation = true
        } catch {
            deleteError = "Failed to fetch table metadata: \(error.localizedDescription)"
        }
    }

    func performDelete() async {
        guard let selectedTable = appState.connection.selectedTable else { return }

        // Get selected rows with their indices for potential rollback
        let deletedIDs = appState.query.selectedRowIDs
        let rowsWithIndices: [(index: Int, row: TableRow)] = appState.query.queryResults
            .enumerated()
            .filter { deletedIDs.contains($0.element.id) }
            .map { (index: $0.offset, row: $0.element) }

        guard !rowsWithIndices.isEmpty else { return }

        // Optimistic UI update: remove rows immediately
        appState.query.queryResults.removeAll { deletedIDs.contains($0.id) }
        appState.query.selectedRowIDs = []

        // Perform backend delete
        let result = await rowOperations.deleteRows(
            table: selectedTable,
            rows: rowsWithIndices.map { $0.row },
            databaseService: appState.connection.databaseService
        )

        // Rollback on failure
        if case .failure(let error) = result {
            // Restore rows at their original indices
            for (index, row) in rowsWithIndices.sorted(by: { $0.index < $1.index }) {
                let insertIndex = min(index, appState.query.queryResults.count)
                appState.query.queryResults.insert(row, at: insertIndex)
            }
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Edit Operations

    func editSelectedRows() {
        DebugLog.print("✏️ [DetailContentViewModel] Edit button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.connection.selectedTable else {
            editError = RowOperationError.noTableSelected.localizedDescription
            return
        }

        // Validate we have column names
        guard appState.query.queryColumnNames != nil else {
            editError = "No query results available"
            return
        }

        // Validate row selection and get first row
        let result = rowOperations.validateRowSelection(
            selectedRowIDs: appState.query.selectedRowIDs,
            queryResults: appState.query.queryResults
        )

        switch result {
        case .success(let selectedRows):
            // Check if multiple rows are selected
            if selectedRows.count > 1 {
                editError = "Please select only one row to edit"
                return
            }

            guard let rowToEdit = selectedRows.first else {
                editError = "No row selected"
                return
            }

            // Check metadata cache first, then selectedTable
            let cachedMetadata = appState.connection.tableMetadataCache[selectedTable.id]
            let pkColumns = cachedMetadata?.primaryKeys ?? selectedTable.primaryKeyColumns
            let colInfo = cachedMetadata?.columns ?? selectedTable.columnInfo

            if let pkColumns = pkColumns, !pkColumns.isEmpty, colInfo != nil {
                updateSelectedTableMetadata(primaryKeys: pkColumns, columnInfo: colInfo)
                self.rowToEdit = rowToEdit
                showRowEditor = true
            } else {
                // Fetch metadata if not cached
                Task {
                    await fetchMetadataAndShowEditor(table: selectedTable, row: rowToEdit)
                }
            }
        case .failure(let error):
            editError = error.localizedDescription
        }
    }

    private func fetchMetadataAndShowEditor(table: TableInfo, row: TableRow) async {
        do {
            let pkColumns = try await appState.connection.databaseService.fetchPrimaryKeyColumns(
                schema: table.schema,
                table: table.name
            )

            let columnInfo = try await appState.connection.databaseService.fetchColumnInfo(
                schema: table.schema,
                table: table.name
            )

            guard !pkColumns.isEmpty else {
                editError = RowOperationError.noPrimaryKey.localizedDescription
                return
            }

            updateSelectedTableMetadata(primaryKeys: pkColumns, columnInfo: columnInfo)
            self.rowToEdit = row
            showRowEditor = true
        } catch {
            editError = "Failed to fetch table metadata: \(error.localizedDescription)"
        }
    }

    func saveEditedRow(originalRow: TableRow, updatedValues: [String: String?]) async throws {
        DebugLog.print("🟡 [DetailContentViewModel.saveEditedRow] Received updatedValues: \(updatedValues)")
        DebugLog.print("  updatedValues count: \(updatedValues.count)")

        guard let selectedTable = appState.connection.selectedTable else {
            throw RowOperationError.noTableSelected
        }

        // Perform update
        let result = await rowOperations.updateRow(
            table: selectedTable,
            originalRow: originalRow,
            updatedValues: updatedValues,
            databaseService: appState.connection.databaseService
        )

        switch result {
        case .success(let updatedRow):
            // Update the row in the UI
            if let index = appState.query.queryResults.firstIndex(where: { $0.id == originalRow.id }) {
                appState.query.queryResults[index] = updatedRow

                // Update selection to use the new row's ID
                appState.query.selectedRowIDs.remove(originalRow.id)
                appState.query.selectedRowIDs.insert(updatedRow.id)
            }
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Query Refresh

    func refreshQuery() async {
        DebugLog.print("🔄 [DetailContentViewModel] Refresh button clicked")

        // Set loading state FIRST to prevent empty state flicker
        appState.query.isExecutingQuery = true
        appState.query.queryError = nil
        appState.query.queryExecutionTime = nil
        appState.query.showQueryResults = false // Hide results view during loading
        appState.query.queryResults = [] // Clear previous results
        appState.query.queryColumnNames = nil // Clear previous column names
        appState.query.selectedRowIDs = [] // Clear selected rows

        // Execute query
        let result = await queryService.executeQuery(appState.query.queryText)

        // Update state based on result
        if result.isSuccess {
            appState.query.queryResults = result.rows
            appState.query.queryColumnNames = result.columnNames.isEmpty ? nil : result.columnNames
            appState.query.showQueryResults = true
            appState.query.queryExecutionTime = result.executionTime
            DebugLog.print("✅ [DetailContentViewModel] Query executed successfully, showing results")
        } else if let error = result.error {
            appState.query.queryError = error
            appState.query.queryColumnNames = nil
            appState.query.showQueryResults = true
            appState.query.queryExecutionTime = result.executionTime
            DebugLog.print("❌ [DetailContentViewModel] Query execution failed: \(error)")
        }

        appState.query.isExecutingQuery = false
    }
}

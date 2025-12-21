//
//  TableContentView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TableContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showJSONView = false
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @State private var showRowEditor = false
    @State private var rowToEdit: TableRow?
    @State private var editError: String?
    @State private var jsonViewError: String?
    @State private var editedRowValues: [String: String?] = [:]

    var body: some View {
        SplitContentView(
            onDeleteKeyPressed: {
                deleteSelectedRows()
            },
            onSpaceKeyPressed: {
                openJSONView()
            }
        )
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: {
                        let selectedRows = appState.query.queryResults.filter { appState.query.selectedRowIDs.contains($0.id) }
                        guard !selectedRows.isEmpty else {
                            jsonViewError = "No rows selected"
                            return
                        }
                        showJSONView = true
                    }) {
                        Image(systemName: "doc.text")
                    }
                    .disabled(appState.query.selectedRowIDs.isEmpty)

                    Button(action: {
                        editSelectedRows()
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(appState.query.selectedRowIDs.isEmpty)

                    Button(action: {
                        deleteSelectedRows()
                    }) {
                        Image(systemName: "trash")
                    }
                    .disabled(appState.query.selectedRowIDs.isEmpty)

                    Spacer()

                    Button(action: {
                        refreshQuery()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.query.isExecutingQuery || appState.query.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.init("r"), modifiers: [.command])
                }
            }
            .sheet(isPresented: $showJSONView) {
                JSONViewerView(selectedRowIDs: appState.query.selectedRowIDs)
            }
            .confirmationDialog(
                "Delete Rows?",
                isPresented: $showDeleteConfirmation
            ) {
                Button(role: .destructive) {
                    Task {
                        await performDelete()
                    }
                } label: {
                    Text("Delete")
                }
                Button("Cancel", role: .cancel) {
                    showDeleteConfirmation = false
                }
            } message: {
                let selectedRowsCount = appState.query.queryResults.filter { appState.query.selectedRowIDs.contains($0.id) }.count
                Text("Are you sure you want to delete \(selectedRowsCount) row(s)? This action cannot be undone.")
            }
            .alert("Error Deleting Rows", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    deleteError = nil
                }
            } message: {
                if let error = deleteError {
                    Text(error)
                }
            }
            .sheet(isPresented: Binding(
                get: {
                    showRowEditor &&
                    rowToEdit != nil &&
                    appState.query.queryColumnNames != nil &&
                    appState.connection.selectedTable?.name != nil &&
                    appState.connection.selectedTable?.columnInfo != nil
                },
                set: { newValue in
                    showRowEditor = newValue
                    if !newValue {
                        rowToEdit = nil
                    }
                }
            )) {
                if let rowToEdit = rowToEdit,
                   let columnNames = appState.query.queryColumnNames,
                   let tableName = appState.connection.selectedTable?.name,
                   let columnInfo = appState.connection.selectedTable?.columnInfo {
                    RowEditorView(
                        row: rowToEdit,
                        columnNames: columnNames,
                        tableName: tableName,
                        columnInfo: columnInfo,
                        editedValues: $editedRowValues,
                        onSave: {
                            // Capture editedRowValues from parent context instead of passing as parameter
                            DebugLog.print("🔴 [Closure] Captured editedRowValues count: \(editedRowValues.count)")
                            DebugLog.print("🔴 [Closure] Keys: \(Array(editedRowValues.keys))")
                            try await saveEditedRow(originalRow: rowToEdit, updatedValues: editedRowValues)
                        }
                    )
                }
            }
            .alert("Error Editing Row", isPresented: Binding(
                get: { editError != nil },
                set: { if !$0 { editError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    editError = nil
                }
            } message: {
                if let error = editError {
                    Text(error)
                }
            }
            .alert("Error Viewing JSON", isPresented: Binding(
                get: { jsonViewError != nil },
                set: { if !$0 { jsonViewError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    jsonViewError = nil
                }
            } message: {
                if let error = jsonViewError {
                    Text(error)
                }
            }
    }
    
    private func openJSONView() {
        let selectedRows = appState.query.queryResults.filter { appState.query.selectedRowIDs.contains($0.id) }
        guard !selectedRows.isEmpty else {
            jsonViewError = "No rows selected"
            return
        }
        showJSONView = true
    }

    private func refreshQuery() {
        DebugLog.print("🔄 [TableContentView] Refresh button clicked")
        Task {
            // Set loading state FIRST to prevent empty state flicker
            appState.query.isExecutingQuery = true
            appState.query.queryError = nil
            appState.query.queryExecutionTime = nil
            appState.query.showQueryResults = false // Hide results view during loading
            appState.query.queryResults = [] // Clear previous results
            appState.query.queryColumnNames = nil // Clear previous column names
            appState.query.selectedRowIDs = [] // Clear selected rows

            let startTime = Date()

            do {
                DebugLog.print("📊 [TableContentView] Executing query...")
                let (results, columnNames) = try await appState.connection.databaseService.executeQuery(appState.query.queryText)
                appState.query.queryResults = results
                appState.query.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.query.showQueryResults = true

                let endTime = Date()
                appState.query.queryExecutionTime = endTime.timeIntervalSince(startTime)

                DebugLog.print("✅ [TableContentView] Query executed successfully, showing results")
            } catch {
                appState.query.queryError = error.localizedDescription
                appState.query.queryColumnNames = nil
                appState.query.showQueryResults = true

                let endTime = Date()
                appState.query.queryExecutionTime = endTime.timeIntervalSince(startTime)

                DebugLog.print("❌ [TableContentView] Query execution failed: \(error)")
            }

            appState.query.isExecutingQuery = false
        }
    }
    
    private func deleteSelectedRows() {
        DebugLog.print("🗑️ [TableContentView] Delete button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.connection.selectedTable else {
            deleteError = "No table selected"
            return
        }

        // Check if there are actually selected rows in the current table's results
        let selectedRows = appState.query.queryResults.filter { appState.query.selectedRowIDs.contains($0.id) }
        guard !selectedRows.isEmpty else {
            deleteError = "No rows selected"
            return
        }

        if selectedTable.primaryKeyColumns == nil {
            Task {
                await fetchPrimaryKeysAndShowDeleteDialog()
            }
        } else {
            showDeleteConfirmation = true
        }
    }

    private func fetchPrimaryKeysAndShowDeleteDialog() async {
        guard let selectedTable = appState.connection.selectedTable else { return }

        do {
            let pkColumns = try await appState.connection.databaseService.fetchPrimaryKeyColumns(
                schema: selectedTable.schema,
                table: selectedTable.name
            )

            var updatedTable = selectedTable
            updatedTable.primaryKeyColumns = pkColumns
            appState.connection.selectedTable = updatedTable

            showDeleteConfirmation = true
        } catch {
            deleteError = "Failed to fetch table metadata: \(error.localizedDescription)"
        }
    }

    private func performDelete() async {
        guard let selectedTable = appState.connection.selectedTable else { return }

        guard let pkColumns = selectedTable.primaryKeyColumns, !pkColumns.isEmpty else {
            deleteError = "This table has no primary key. DELETE requires a primary key."
            return
        }

        let selectedRows = appState.query.queryResults.filter { appState.query.selectedRowIDs.contains($0.id) }

        do {
            try await appState.connection.databaseService.deleteRows(
                schema: selectedTable.schema,
                table: selectedTable.name,
                primaryKeyColumns: pkColumns,
                rows: selectedRows
            )

            // Remove deleted rows from the UI
            let deletedIDs = Set(selectedRows.map { $0.id })
            appState.query.queryResults.removeAll { deletedIDs.contains($0.id) }
            appState.query.selectedRowIDs = []
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func editSelectedRows() {
        DebugLog.print("✏️ [TableContentView] Edit button clicked for \(appState.query.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.connection.selectedTable else {
            editError = "No table selected"
            return
        }

        // Validate we have column names
        guard appState.query.queryColumnNames != nil else {
            editError = "No query results available"
            return
        }

        // Find selected row in current table's results
        let selectedRows = appState.query.queryResults.filter { appState.query.selectedRowIDs.contains($0.id) }
        guard let rowToEdit = selectedRows.first else {
            editError = "No row selected"
            return
        }

        if selectedTable.primaryKeyColumns == nil || selectedTable.columnInfo == nil {
            Task {
                await fetchPrimaryKeysAndShowEditor(rowToEdit)
            }
        } else {
            self.rowToEdit = rowToEdit
            showRowEditor = true
        }
    }

    private func fetchPrimaryKeysAndShowEditor(_ row: TableRow) async {
        guard let selectedTable = appState.connection.selectedTable else { return }

        do {
            let pkColumns = try await appState.connection.databaseService.fetchPrimaryKeyColumns(
                schema: selectedTable.schema,
                table: selectedTable.name
            )

            let columnInfo = try await appState.connection.databaseService.fetchColumnInfo(
                schema: selectedTable.schema,
                table: selectedTable.name
            )

            var updatedTable = selectedTable
            updatedTable.primaryKeyColumns = pkColumns
            updatedTable.columnInfo = columnInfo
            appState.connection.selectedTable = updatedTable

            self.rowToEdit = row
            showRowEditor = true
        } catch {
            editError = "Failed to fetch table metadata: \(error.localizedDescription)"
        }
    }

    private func saveEditedRow(originalRow: TableRow, updatedValues: [String: String?]) async throws {
        DebugLog.print("🟡 [TableContentView.saveEditedRow] Received updatedValues: \(updatedValues)")
        DebugLog.print("  updatedValues count: \(updatedValues.count)")

        guard let selectedTable = appState.connection.selectedTable else { return }

        guard let pkColumns = selectedTable.primaryKeyColumns, !pkColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        try await appState.connection.databaseService.updateRow(
            schema: selectedTable.schema,
            table: selectedTable.name,
            primaryKeyColumns: pkColumns,
            originalRow: originalRow,
            updatedValues: updatedValues
        )

        // Update the row in the UI
        if let index = appState.query.queryResults.firstIndex(where: { $0.id == originalRow.id }) {
            let updatedRow = TableRow(values: updatedValues)
            appState.query.queryResults[index] = updatedRow

            // Update selection to use the new row's ID
            appState.query.selectedRowIDs.remove(originalRow.id)
            appState.query.selectedRowIDs.insert(updatedRow.id)
        }
    }
}

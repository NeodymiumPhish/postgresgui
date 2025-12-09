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

    var body: some View {
        SplitContentView()
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: {
                        editSelectedRows()
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(appState.selectedRowIDs.isEmpty)
                    
                    Button(action: {
                        showJSONView = true
                    }) {
                        Image(systemName: "doc.text")
                    }
                    .disabled(appState.selectedRowIDs.isEmpty)
                    
                    Button(action: {
                        deleteSelectedRows()
                    }) {
                        Image(systemName: "trash")
                    }
                    .disabled(appState.selectedRowIDs.isEmpty)

                    Spacer()

                    Button(action: {
                        refreshQuery()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appState.isExecutingQuery || appState.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.init("r"), modifiers: [.command])
                }
            }
            .sheet(isPresented: $showJSONView) {
                JSONViewerView(selectedRowIDs: appState.selectedRowIDs)
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
                let selectedRowsCount = appState.queryResults.filter { appState.selectedRowIDs.contains($0.id) }.count
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
            .sheet(isPresented: $showRowEditor) {
                if let rowToEdit = rowToEdit,
                   let columnNames = appState.queryColumnNames,
                   let tableName = appState.selectedTable?.name {
                    RowEditorView(
                        row: rowToEdit,
                        columnNames: columnNames,
                        tableName: tableName,
                        onSave: { updatedValues in
                            try await saveEditedRow(originalRow: rowToEdit, updatedValues: updatedValues)
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
    }
    
    private func refreshQuery() {
        print("🔄 [TableContentView] Refresh button clicked")
        Task {
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
                print("📊 [TableContentView] Executing query...")
                let (results, columnNames) = try await appState.databaseService.executeQuery(appState.queryText)
                appState.queryResults = results
                appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("✅ [TableContentView] Query executed successfully, showing results")
            } catch {
                appState.queryError = error.localizedDescription
                appState.queryColumnNames = nil
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                print("❌ [TableContentView] Query execution failed: \(error)")
            }

            appState.isExecutingQuery = false
        }
    }
    
    private func deleteSelectedRows() {
        print("🗑️ [TableContentView] Delete button clicked for \(appState.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.selectedTable else {
            deleteError = "No table selected"
            return
        }

        // Check if there are actually selected rows in the current table's results
        let selectedRows = appState.queryResults.filter { appState.selectedRowIDs.contains($0.id) }
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
        guard let selectedTable = appState.selectedTable else { return }

        do {
            let pkColumns = try await appState.databaseService.fetchPrimaryKeyColumns(
                schema: selectedTable.schema,
                table: selectedTable.name
            )

            var updatedTable = selectedTable
            updatedTable.primaryKeyColumns = pkColumns
            appState.selectedTable = updatedTable

            showDeleteConfirmation = true
        } catch {
            deleteError = "Failed to fetch table metadata: \(error.localizedDescription)"
        }
    }

    private func performDelete() async {
        guard let selectedTable = appState.selectedTable else { return }

        guard let pkColumns = selectedTable.primaryKeyColumns, !pkColumns.isEmpty else {
            deleteError = "This table has no primary key. DELETE requires a primary key."
            return
        }

        let selectedRows = appState.queryResults.filter { appState.selectedRowIDs.contains($0.id) }

        do {
            try await appState.databaseService.deleteRows(
                schema: selectedTable.schema,
                table: selectedTable.name,
                primaryKeyColumns: pkColumns,
                rows: selectedRows
            )

            // Remove deleted rows from the UI
            let deletedIDs = Set(selectedRows.map { $0.id })
            appState.queryResults.removeAll { deletedIDs.contains($0.id) }
            appState.selectedRowIDs = []
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func editSelectedRows() {
        print("✏️ [TableContentView] Edit button clicked for \(appState.selectedRowIDs.count) row(s)")

        guard let selectedTable = appState.selectedTable else {
            editError = "No table selected"
            return
        }

        guard let firstSelectedID = appState.selectedRowIDs.first,
              let rowToEdit = appState.queryResults.first(where: { $0.id == firstSelectedID }) else {
            editError = "No row selected"
            return
        }

        if selectedTable.primaryKeyColumns == nil {
            Task {
                await fetchPrimaryKeysAndShowEditor(rowToEdit)
            }
        } else {
            self.rowToEdit = rowToEdit
            showRowEditor = true
        }
    }

    private func fetchPrimaryKeysAndShowEditor(_ row: TableRow) async {
        guard let selectedTable = appState.selectedTable else { return }

        do {
            let pkColumns = try await appState.databaseService.fetchPrimaryKeyColumns(
                schema: selectedTable.schema,
                table: selectedTable.name
            )

            var updatedTable = selectedTable
            updatedTable.primaryKeyColumns = pkColumns
            appState.selectedTable = updatedTable

            self.rowToEdit = row
            showRowEditor = true
        } catch {
            editError = "Failed to fetch table metadata: \(error.localizedDescription)"
        }
    }

    private func saveEditedRow(originalRow: TableRow, updatedValues: [String: String?]) async throws {
        guard let selectedTable = appState.selectedTable else { return }

        guard let pkColumns = selectedTable.primaryKeyColumns, !pkColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        try await appState.databaseService.updateRow(
            schema: selectedTable.schema,
            table: selectedTable.name,
            primaryKeyColumns: pkColumns,
            originalRow: originalRow,
            updatedValues: updatedValues
        )

        refreshQuery()
    }
}

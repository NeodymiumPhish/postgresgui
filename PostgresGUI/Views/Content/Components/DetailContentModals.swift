//
//  DetailContentModals.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// ViewModifier that adds all modals and alerts for DetailContentView
/// Centralizes modal management to reduce boilerplate
struct DetailContentModals: ViewModifier {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: DetailContentViewModel

    func body(content: Content) -> some View {
        content
            // JSON Viewer Sheet
            .sheet(isPresented: $viewModel.showJSONView) {
                JSONViewerView(selectedRowIDs: appState.selectedRowIDs)
            }
            // Row Editor Sheet
            .sheet(isPresented: Binding(
                get: {
                    viewModel.showRowEditor &&
                    viewModel.rowToEdit != nil &&
                    appState.queryColumnNames != nil &&
                    appState.selectedTable?.name != nil &&
                    appState.selectedTable?.columnInfo != nil
                },
                set: { newValue in
                    viewModel.showRowEditor = newValue
                    if !newValue {
                        viewModel.rowToEdit = nil
                    }
                }
            )) {
                if let rowToEdit = viewModel.rowToEdit,
                   let columnNames = appState.queryColumnNames,
                   let tableName = appState.selectedTable?.name,
                   let columnInfo = appState.selectedTable?.columnInfo {
                    RowEditorView(
                        row: rowToEdit,
                        columnNames: columnNames,
                        tableName: tableName,
                        columnInfo: columnInfo,
                        editedValues: $viewModel.editedRowValues,
                        onSave: {
                            DebugLog.print("🔴 [Closure] Captured editedRowValues count: \(viewModel.editedRowValues.count)")
                            DebugLog.print("🔴 [Closure] Keys: \(Array(viewModel.editedRowValues.keys))")
                            try await viewModel.saveEditedRow(
                                originalRow: rowToEdit,
                                updatedValues: viewModel.editedRowValues
                            )
                        }
                    )
                }
            }
            // Delete Confirmation Dialog
            .confirmationDialog(
                "Delete Rows?",
                isPresented: $viewModel.showDeleteConfirmation
            ) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.performDelete()
                    }
                } label: {
                    Text("Delete")
                }
                Button("Cancel", role: .cancel) {
                    viewModel.showDeleteConfirmation = false
                }
            } message: {
                let selectedRowsCount = appState.queryResults.filter { appState.selectedRowIDs.contains($0.id) }.count
                Text("Are you sure you want to delete \(selectedRowsCount) row(s)? This action cannot be undone.")
            }
            // Delete Error Alert
            .alert("Error Deleting Rows", isPresented: Binding(
                get: { viewModel.deleteError != nil },
                set: { if !$0 { viewModel.deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.deleteError = nil
                }
            } message: {
                if let error = viewModel.deleteError {
                    Text(error)
                }
            }
            // Edit Error Alert
            .alert("Error Editing Row", isPresented: Binding(
                get: { viewModel.editError != nil },
                set: { if !$0 { viewModel.editError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.editError = nil
                }
            } message: {
                if let error = viewModel.editError {
                    Text(error)
                }
            }
            // JSON View Error Alert
            .alert("Error Viewing JSON", isPresented: Binding(
                get: { viewModel.jsonViewError != nil },
                set: { if !$0 { viewModel.jsonViewError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.jsonViewError = nil
                }
            } message: {
                if let error = viewModel.jsonViewError {
                    Text(error)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Apply all DetailContentView modals to this view
    func detailContentModals(viewModel: DetailContentViewModel) -> some View {
        modifier(DetailContentModals(viewModel: viewModel))
    }
}

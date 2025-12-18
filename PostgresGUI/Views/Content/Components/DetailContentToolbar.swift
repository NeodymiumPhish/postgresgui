//
//  DetailContentToolbar.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// Reusable toolbar for DetailContentView
/// Provides JSON viewer, edit, delete, and refresh buttons
struct DetailContentToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState
    let viewModel: DetailContentViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // JSON Viewer button
            Button(action: {
                viewModel.openJSONView()
            }) {
                Image(systemName: "doc.text")
            }
            .help("View selected rows as JSON")
            .disabled(appState.selectedRowIDs.isEmpty)

            // Edit button
            Button(action: {
                viewModel.editSelectedRows()
            }) {
                Image(systemName: "square.and.pencil")
            }
            .help("Edit selected row")
            .disabled(appState.selectedRowIDs.isEmpty)

            // Delete button
            Button(action: {
                viewModel.deleteSelectedRows()
            }) {
                Image(systemName: "trash")
            }
            .help("Delete selected rows")
            .disabled(appState.selectedRowIDs.isEmpty)
        }
    }
}

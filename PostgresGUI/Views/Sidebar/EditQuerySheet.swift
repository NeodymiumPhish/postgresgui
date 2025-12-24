//
//  EditQuerySheet.swift
//  PostgresGUI
//

import SwiftUI

struct EditQuerySheet: View {
    @Bindable var query: SavedQuery
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var editedName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Query")
                .font(.headline)

            TextField("Query Name", text: $editedName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    query.name = editedName
                    query.updatedAt = Date()
                    // Update toolbar if this is the currently selected query
                    if appState.query.currentSavedQueryId == query.id {
                        appState.query.currentQueryName = editedName
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear { editedName = query.name }
    }
}

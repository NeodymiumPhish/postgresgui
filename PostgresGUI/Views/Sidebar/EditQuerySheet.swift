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

    private var canSave: Bool {
        !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Query")
                .font(.headline)

            TextField("Query Name", text: $editedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSave { save() } }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear { editedName = query.name }
    }

    private func save() {
        query.name = editedName
        query.updatedAt = Date()
        // Update toolbar if this is the currently selected query
        if appState.query.currentSavedQueryId == query.id {
            appState.query.currentQueryName = editedName
        }
        dismiss()
    }
}

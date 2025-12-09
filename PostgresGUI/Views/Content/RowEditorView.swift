//
//  RowEditorView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI

struct RowEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let row: TableRow
    let columnNames: [String]
    let tableName: String
    let onSave: ([String: String?]) async throws -> Void

    @State private var editedValues: [String: String?]
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        row: TableRow,
        columnNames: [String],
        tableName: String,
        onSave: @escaping ([String: String?]) async throws -> Void
    ) {
        self.row = row
        self.columnNames = columnNames
        self.tableName = tableName
        self.onSave = onSave
        _editedValues = State(initialValue: row.values)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Edit Row")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(columnNames, id: \.self) { columnName in
                            formRow(columnName: columnName)
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Error Saving Row", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {
                saveError = nil
            }
        } message: {
            if let error = saveError {
                Text(error)
            }
        }
    }

    private func formRow(columnName: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(columnName)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("", text: Binding(
                    get: {
                        if let value = editedValues[columnName] {
                            return value ?? ""
                        }
                        return ""
                    },
                    set: { newValue in
                        if newValue.isEmpty && editedValues[columnName] != nil {
                            editedValues[columnName] = nil
                        } else {
                            editedValues[columnName] = newValue
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(editedValues[columnName] == nil)

                Toggle("NULL", isOn: Binding(
                    get: {
                        editedValues[columnName] == nil
                    },
                    set: { isNull in
                        if isNull {
                            editedValues[columnName] = nil
                        } else {
                            editedValues[columnName] = ""
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func save() async {
        isSaving = true

        do {
            try await onSave(editedValues)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}

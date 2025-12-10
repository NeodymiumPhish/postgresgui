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
    @State private var textValues: [String: String] = [:]
    @State private var nullFlags: [String: Bool] = [:]
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

        // Initialize text values and null flags
        var initialTextValues: [String: String] = [:]
        var initialNullFlags: [String: Bool] = [:]
        for (key, value) in row.values {
            if let stringValue = value {
                initialTextValues[key] = stringValue
                initialNullFlags[key] = false
            } else {
                initialTextValues[key] = ""
                initialNullFlags[key] = true
            }
        }
        _textValues = State(initialValue: initialTextValues)
        _nullFlags = State(initialValue: initialNullFlags)
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

            HStack(alignment: .center, spacing: 8) {
                TextField("", text: Binding(
                    get: {
                        textValues[columnName] ?? ""
                    },
                    set: { newValue in
                        textValues[columnName] = newValue
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(nullFlags[columnName] ?? false)

                Toggle("NULL", isOn: Binding(
                    get: {
                        nullFlags[columnName] ?? false
                    },
                    set: { isNull in
                        nullFlags[columnName] = isNull
                    }
                ))
                .toggleStyle(.checkbox)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func save() async {
        isSaving = true

        // Combine textValues and nullFlags into editedValues
        var finalValues: [String: String?] = [:]
        for columnName in columnNames {
            if nullFlags[columnName] ?? false {
                finalValues[columnName] = nil
            } else {
                finalValues[columnName] = textValues[columnName] ?? ""
            }
        }

        do {
            try await onSave(finalValues)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}

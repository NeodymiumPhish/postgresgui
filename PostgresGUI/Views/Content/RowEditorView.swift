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
    let columnInfo: [ColumnInfo]
    @Binding var editedValues: [String: String?]
    let onSave: () async throws -> Void

    @State private var textValues: [String: String] = [:]
    @State private var nullFlags: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        row: TableRow,
        columnNames: [String],
        tableName: String,
        columnInfo: [ColumnInfo],
        editedValues: Binding<[String: String?]>,
        onSave: @escaping () async throws -> Void
    ) {
        self.row = row
        self.columnNames = columnNames
        self.tableName = tableName
        self.columnInfo = columnInfo
        self._editedValues = editedValues
        self.onSave = onSave

        // Initialize text values and null flags for all columns
        var initialTextValues: [String: String] = [:]
        var initialNullFlags: [String: Bool] = [:]
        for columnName in columnNames {
            if let value = row.values[columnName] {
                if let stringValue = value {
                    initialTextValues[columnName] = stringValue
                    initialNullFlags[columnName] = false
                } else {
                    initialTextValues[columnName] = ""
                    initialNullFlags[columnName] = true
                }
            } else {
                // Column doesn't exist in row.values, default to empty
                initialTextValues[columnName] = ""
                initialNullFlags[columnName] = false
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
        let column = columnInfo.first { $0.name == columnName }
        let isNullable = column?.isNullable ?? true

        return HStack(alignment: .center, spacing: 12) {
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

                if isNullable {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private func save() async {
        isSaving = true

        print("💾 [RowEditorView.save] START")
        print("  columnNames: \(columnNames)")
        print("  textValues: \(textValues)")
        print("  nullFlags: \(nullFlags)")

        // Combine textValues and nullFlags into editedValues
        var finalValues: [String: String?] = [:]
        for columnName in columnNames {
            if nullFlags[columnName] ?? false {
                print("    Setting \(columnName) = nil")
                finalValues[columnName] = nil
            } else {
                let value = textValues[columnName] ?? ""
                print("    Setting \(columnName) = '\(value)'")
                finalValues[columnName] = value
            }
        }

        print("  finalValues count: \(finalValues.count)")
        print("  finalValues keys: \(finalValues.keys)")
        for (key, value) in finalValues {
            print("    \(key): \(String(describing: value))")
        }

        // Store finalValues in the binding so parent can access it
        editedValues = finalValues
        print("  📤 Stored finalValues in editedValues binding")

        do {
            print("  🔵 About to call onSave (no parameters)")
            // Call onSave with no parameters - it will capture editedValues from parent context
            try await onSave()
            print("  ✅ onSave completed")
            dismiss()
        } catch {
            print("  ❌ onSave failed: \(error)")
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}

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
    let primaryKeyColumns: [String]
    @Binding var editedValues: [String: String?]
    let onSave: () async throws -> Void

    @State private var textValues: [String: String] = [:]
    @State private var nullFlags: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var saveError: String?

    private var primaryKeySet: Set<String> {
        Set(primaryKeyColumns)
    }

    init(
        row: TableRow,
        columnNames: [String],
        tableName: String,
        columnInfo: [ColumnInfo],
        primaryKeyColumns: [String],
        editedValues: Binding<[String: String?]>,
        onSave: @escaping () async throws -> Void
    ) {
        self.row = row
        self.columnNames = columnNames
        self.tableName = tableName
        self.columnInfo = columnInfo
        self.primaryKeyColumns = primaryKeyColumns
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
            .navigationTitle("Edit Row")
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
        let dataType = column?.dataType.lowercased() ?? ""
        let isPrimaryKey = primaryKeySet.contains(columnName)
        let shouldUseTextEditor = dataType == "text" || dataType == "json" || dataType == "jsonb" || dataType == "xml" || dataType.contains("[]")

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(columnName)
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                if isPrimaryKey {
                    Text("Primary Key")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            if isPrimaryKey {
                // Read-only display for primary key columns
                HStack(spacing: 8) {
                    Text(textValues[columnName] ?? "")
                        .frame(maxWidth: 380, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .foregroundColor(.secondary)

                    Spacer()
                }
            } else {
                // Editable field for non-primary-key columns
                HStack(alignment: shouldUseTextEditor ? .top : .center, spacing: 8) {
                    Group {
                        if shouldUseTextEditor {
                            let isDisabled = nullFlags[columnName] ?? false
                            TextEditor(text: Binding(
                                get: {
                                    textValues[columnName] ?? ""
                                },
                                set: { newValue in
                                    if !isDisabled {
                                        textValues[columnName] = newValue
                                    }
                                }
                            ))
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(isDisabled ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.black.opacity(0.1),
                                                Color.clear
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                                    .blendMode(.multiply)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                            .disabled(isDisabled)
                            .opacity(isDisabled ? 0.6 : 1.0)
                        } else {
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
                            .frame(maxWidth: 380)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.black.opacity(0.1),
                                                Color.clear
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                                    .blendMode(.multiply)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                        }
                    }

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
                        .padding(.top, shouldUseTextEditor ? 4 : 0)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func save() async {
        isSaving = true

        DebugLog.print("💾 [RowEditorView.save] START")
        DebugLog.print("  columnNames: \(columnNames)")
        DebugLog.print("  textValues: \(textValues)")
        DebugLog.print("  nullFlags: \(nullFlags)")

        // Combine textValues and nullFlags into editedValues
        var finalValues: [String: String?] = [:]
        for columnName in columnNames {
            if nullFlags[columnName] ?? false {
                DebugLog.print("    Setting \(columnName) = nil")
                finalValues[columnName] = nil
            } else {
                let value = textValues[columnName] ?? ""
                DebugLog.print("    Setting \(columnName) = '\(value)'")
                finalValues[columnName] = value
            }
        }

        DebugLog.print("  finalValues count: \(finalValues.count)")
        DebugLog.print("  finalValues keys: \(finalValues.keys)")
        for (key, value) in finalValues {
            DebugLog.print("    \(key): \(String(describing: value))")
        }

        // Store finalValues in the binding so parent can access it
        editedValues = finalValues
        DebugLog.print("  📤 Stored finalValues in editedValues binding")

        do {
            DebugLog.print("  🔵 About to call onSave (no parameters)")
            // Call onSave with no parameters - it will capture editedValues from parent context
            try await onSave()
            DebugLog.print("  ✅ onSave completed")
            dismiss()
        } catch {
            DebugLog.print("  ❌ onSave failed: \(error)")
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}

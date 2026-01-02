//
//  RowEditorView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI

// MARK: - Column Input Type

private enum ColumnInputType {
    case boolean        // "boolean", "bool"
    case dateOnly       // "date"
    case timeOnly       // "time without time zone", "time with time zone"
    case dateTime       // "timestamp without time zone", "timestamp with time zone"
    case multilineText  // "text", "json", "jsonb", "xml", arrays
    case singleLineText // default

    static func from(dataType: String) -> ColumnInputType {
        let type = dataType.lowercased()

        if type == "boolean" || type == "bool" {
            return .boolean
        }
        if type == "date" {
            return .dateOnly
        }
        if type.contains("time") && !type.contains("timestamp") {
            return .timeOnly
        }
        if type.contains("timestamp") {
            return .dateTime
        }
        if type == "text" || type == "json" || type == "jsonb" || type == "xml" || type.contains("[]") {
            return .multilineText
        }
        return .singleLineText
    }

    /// Convert to DateColumnType for use with DateConversion
    var dateColumnType: DateColumnType? {
        switch self {
        case .dateOnly: return .dateOnly
        case .timeOnly: return .timeOnly
        case .dateTime: return .dateTime
        default: return nil
        }
    }
}

// MARK: - Row Editor View

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
    @State private var dateValues: [String: Date] = [:]
    @State private var booleanValues: [String: Bool?] = [:]  // nil = NULL
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

        // Initialize text values, null flags, date values, and boolean values
        var initialTextValues: [String: String] = [:]
        var initialNullFlags: [String: Bool] = [:]
        var initialDateValues: [String: Date] = [:]
        var initialBooleanValues: [String: Bool?] = [:]

        for columnName in columnNames {
            let column = columnInfo.first { $0.name == columnName }
            let dataType = column?.dataType.lowercased() ?? ""
            let inputType = ColumnInputType.from(dataType: dataType)

            if let value = row.values[columnName] {
                if let stringValue = value {
                    initialTextValues[columnName] = stringValue
                    initialNullFlags[columnName] = false

                    // Parse typed values
                    switch inputType {
                    case .boolean:
                        let lowered = stringValue.lowercased()
                        if lowered == "true" || lowered == "t" || lowered == "1" {
                            initialBooleanValues[columnName] = true
                        } else if lowered == "false" || lowered == "f" || lowered == "0" {
                            initialBooleanValues[columnName] = false
                        } else {
                            initialBooleanValues[columnName] = nil
                        }
                    case .dateOnly, .timeOnly, .dateTime:
                        if let date = Self.parseDate(stringValue, for: inputType) {
                            initialDateValues[columnName] = date
                        }
                    default:
                        break
                    }
                } else {
                    initialTextValues[columnName] = ""
                    initialNullFlags[columnName] = true
                    if inputType == .boolean {
                        initialBooleanValues[columnName] = nil
                    }
                }
            } else {
                // Column doesn't exist in row.values, default to empty
                initialTextValues[columnName] = ""
                initialNullFlags[columnName] = false
                if inputType == .boolean {
                    initialBooleanValues[columnName] = false
                }
            }
        }
        _textValues = State(initialValue: initialTextValues)
        _nullFlags = State(initialValue: initialNullFlags)
        _dateValues = State(initialValue: initialDateValues)
        _booleanValues = State(initialValue: initialBooleanValues)
    }

    // MARK: - Date Helpers (delegate to DateConversion)

    private static func parseDate(_ string: String, for inputType: ColumnInputType) -> Date? {
        guard let dateType = inputType.dateColumnType else { return nil }
        return DateConversion.parse(string, type: dateType)
    }

    private func formatDate(_ date: Date, for inputType: ColumnInputType) -> String {
        guard let dateType = inputType.dateColumnType else { return "" }
        return DateConversion.format(date, type: dateType)
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
        let inputType = ColumnInputType.from(dataType: dataType)

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
                primaryKeyDisplay(columnName: columnName)
            } else {
                editableField(columnName: columnName, inputType: inputType, isNullable: isNullable)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Primary Key Display

    @ViewBuilder
    private func primaryKeyDisplay(columnName: String) -> some View {
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
    }

    // MARK: - Editable Field Router

    @ViewBuilder
    private func editableField(columnName: String, inputType: ColumnInputType, isNullable: Bool) -> some View {
        let isNull = nullFlags[columnName] ?? false

        HStack(alignment: inputType == .multilineText ? .top : .center, spacing: 8) {
            Group {
                switch inputType {
                case .boolean:
                    booleanPicker(columnName: columnName, isNullable: isNullable)
                case .dateOnly:
                    datePicker(columnName: columnName, displayedComponents: .date, inputType: inputType)
                case .timeOnly:
                    datePicker(columnName: columnName, displayedComponents: .hourAndMinute, inputType: inputType)
                case .dateTime:
                    datePicker(columnName: columnName, displayedComponents: [.date, .hourAndMinute], inputType: inputType)
                case .multilineText:
                    multilineTextField(columnName: columnName, isDisabled: isNull)
                case .singleLineText:
                    singleLineTextField(columnName: columnName, isDisabled: isNull)
                }
            }

            // NULL checkbox for non-boolean nullable columns
            // Boolean has NULL built into its picker
            if isNullable && inputType != .boolean {
                Toggle("NULL", isOn: Binding(
                    get: { nullFlags[columnName] ?? false },
                    set: { isNull in
                        nullFlags[columnName] = isNull
                        if isNull {
                            dateValues.removeValue(forKey: columnName)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .padding(.top, inputType == .multilineText ? 4 : 0)
            }
        }
    }

    // MARK: - Boolean Picker

    @ViewBuilder
    private func booleanPicker(columnName: String, isNullable: Bool) -> some View {
        let currentValue = booleanValues[columnName] ?? nil

        Picker("", selection: Binding(
            get: { currentValue },
            set: { newValue in
                booleanValues[columnName] = newValue
                // Sync to textValues and nullFlags
                if let value = newValue {
                    nullFlags[columnName] = false
                    textValues[columnName] = value ? "true" : "false"
                } else {
                    nullFlags[columnName] = true
                    textValues[columnName] = ""
                }
            }
        )) {
            if isNullable {
                Text("NULL").tag(Bool?.none)
            }
            Text("true").tag(Bool?.some(true))
            Text("false").tag(Bool?.some(false))
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .labelsHidden()
    }

    // MARK: - Date Picker

    @ViewBuilder
    private func datePicker(columnName: String, displayedComponents: DatePicker.Components, inputType: ColumnInputType) -> some View {
        let isNull = nullFlags[columnName] ?? false
        let defaultDate = Date()
        let currentDate = dateValues[columnName] ?? defaultDate

        HStack(spacing: 8) {
            DatePicker(
                "",
                selection: Binding(
                    get: { currentDate },
                    set: { newDate in
                        dateValues[columnName] = newDate
                        textValues[columnName] = formatDate(newDate, for: inputType)
                        nullFlags[columnName] = false
                    }
                ),
                displayedComponents: displayedComponents
            )
            .labelsHidden()
            .disabled(isNull)
            .opacity(isNull ? 0.5 : 1.0)
        }
    }

    // MARK: - Text Fields

    @ViewBuilder
    private func singleLineTextField(columnName: String, isDisabled: Bool) -> some View {
        TextField("", text: Binding(
            get: { textValues[columnName] ?? "" },
            set: { textValues[columnName] = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .disabled(isDisabled)
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

    @ViewBuilder
    private func multilineTextField(columnName: String, isDisabled: Bool) -> some View {
        TextEditor(text: Binding(
            get: { textValues[columnName] ?? "" },
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
    }

    private func save() async {
        isSaving = true

        DebugLog.print("💾 [RowEditorView.save] START")

        // Sync date values to textValues before saving
        for (columnName, date) in dateValues {
            let column = columnInfo.first { $0.name == columnName }
            let dataType = column?.dataType.lowercased() ?? ""
            let inputType = ColumnInputType.from(dataType: dataType)
            textValues[columnName] = formatDate(date, for: inputType)
        }

        // Sync boolean values to textValues and nullFlags before saving
        for (columnName, boolValue) in booleanValues {
            if let value = boolValue {
                textValues[columnName] = value ? "true" : "false"
                nullFlags[columnName] = false
            } else {
                textValues[columnName] = ""
                nullFlags[columnName] = true
            }
        }

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

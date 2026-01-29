//
//  JSONViewerView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JSONViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingExporter = false
    let selectedRowIDs: Set<UUID>

    private var selectedRows: [TableRow] {
        appState.query.queryResults.filter { selectedRowIDs.contains($0.id) }
    }

    private var csvString: String {
        CSVExporter.toCSV(rows: selectedRows, columns: appState.query.queryColumnNames)
    }
    
    private var jsonString: String {
        // Convert rows to array of dictionaries
        let rowsAsDicts = selectedRows.map { row in
            row.values.mapValues { value -> Any in
                if let stringValue = value {
                    return stringValue
                } else {
                    return NSNull()
                }
            }
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: rowsAsDicts, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "Error encoding JSON: \(error.localizedDescription)"
        }
    }
    
    var body: some View {
        NavigationStack {
            TextEditor(text: Binding(
                get: { jsonString },
                set: { _ in } // Read-only
            ))
            .font(.system(.body, design: .monospaced))
            .navigationTitle("JSON View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Download CSV") {
                            showingExporter = true
                        }

                        Button("Copy JSON") {
                            copyToClipboard()
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(minWidth: 600, minHeight: 500)
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: csvString),
            contentType: .commaSeparatedText,
            defaultFilename: appState.connection.selectedTable?.name ?? "export"
        ) { _ in }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
    }
}

// MARK: - CSV Document

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

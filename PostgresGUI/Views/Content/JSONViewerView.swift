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
    let selectedRowIDs: Set<UUID>
    
    private var selectedRows: [TableRow] {
        appState.query.queryResults.filter { selectedRowIDs.contains($0.id) }
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
                    Button("Download CSV") {
                        downloadAsCSV()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy JSON") {
                        copyToClipboard()
                    }
                }
            }
            .padding(4)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
    }

    private func downloadAsCSV() {
        let csvString = CSVExporter.toCSV(rows: selectedRows)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "export.csv"
        savePanel.title = "Save CSV"
        savePanel.message = "Choose a location to save the CSV file"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try csvString.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Error handling could be enhanced with alert
                print("Failed to save CSV: \(error.localizedDescription)")
            }
        }
    }
}

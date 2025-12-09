//
//  JSONViewerView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit

struct JSONViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let selectedRowIDs: Set<UUID>
    
    private var selectedRows: [TableRow] {
        appState.queryResults.filter { selectedRowIDs.contains($0.id) }
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
            ScrollView {
                Text(jsonString)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("JSON View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy JSON") {
                        copyToClipboard()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
    }
}

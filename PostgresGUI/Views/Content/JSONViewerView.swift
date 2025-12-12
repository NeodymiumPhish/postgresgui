//
//  JSONViewerView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit
import CodeEditorView
import LanguageSupport

struct JSONViewerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let selectedRowIDs: Set<UUID>
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
    
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
            CodeEditor(
                text: Binding(
                    get: { jsonString },
                    set: { _ in } // Read-only
                ),
                position: $position,
                messages: $messages
            )
            .environment(\.codeEditorLayoutConfiguration,
                CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: true)
            )
            .environment(\.codeEditorTheme,
                         colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
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

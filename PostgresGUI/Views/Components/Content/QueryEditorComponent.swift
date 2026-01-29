//
//  QueryEditorComponent.swift
//  PostgresGUI
//
//  Presentational component for the query editor.
//  Receives data and callbacks - does not access AppState directly.
//

import SwiftUI

struct QueryEditorComponent: View {
    // Data
    let isExecuting: Bool
    let statusMessage: String?
    let lastExecutedAt: Date?
    let displayedElapsedTime: TimeInterval
    
    // Bindings
    @Binding var queryText: String
    
    // Callbacks
    let onRunQuery: () -> Void
    let onCancelQuery: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with execute/cancel button and stats
            HStack(spacing: 4) {
                if isExecuting {
                    // Cancel Query button when this query is executing
                    Button(action: onCancelQuery) {
                        Label {
                            Text("Cancel Query")
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                    .buttonStyle(.glass)
                    .clipShape(Capsule())
                    .tint(.red)
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    // Run Query button when not executing
                    Button(action: onRunQuery) {
                        Label {
                            Text("Run Query")
                        } icon: {
                            Image(systemName: "play.circle.fill")
                        }
                    }
                    .buttonStyle(.glass)
                    .clipShape(Capsule())
                    .tint(.green)
                    .keyboardShortcut(.return, modifiers: [.command])
                }

                Spacer()

                // Dynamic status display
                statusView
            }
            .padding(Constants.Spacing.small)
            .background(Color(NSColor.controlBackgroundColor))

            // Syntax highlighted editor
            SyntaxHighlightedEditor(text: $queryText)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if isExecuting {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text(QueryState.formatElapsedTime(displayedElapsedTime))
                    .foregroundColor(.secondary)
                    .font(.system(size: Constants.FontSize.small, design: .monospaced))
            }
        } else if let statusMessage = statusMessage {
            Text(statusMessage)
                .foregroundColor(.secondary)
                .font(.system(size: Constants.FontSize.small))
                .lineLimit(1)
        } else if let lastExecutedAt = lastExecutedAt {
            Text("Last Executed: \(lastExecutedAt.formatted(date: .abbreviated, time: .shortened))")
                .foregroundColor(.secondary)
                .font(.system(size: Constants.FontSize.small))
        }
    }
}

//
//  QueryEditorView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with execute button and stats
            HStack {
                Button(action: executeQuery) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                        Text("Run Query")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
                .tint(.primary)
                .clipShape(Capsule())
                .keyboardShortcut(.return, modifiers: [.command])

                Spacer()

                // Stats on the right
                if appState.showQueryResults {
                    HStack(spacing: 8) {
                        if appState.queryError != nil {
                            Label("Error", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        } else {
                            Text("\(appState.queryResults.count) rows")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            
                            if let executionTime = appState.queryExecutionTime {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(formatExecutionTime(executionTime))
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding(Constants.Spacing.small)
            .background(Color(NSColor.controlBackgroundColor))

            // Syntax highlighted editor
            SyntaxHighlightedEditor(text: Binding(
                get: { appState.queryText },
                set: { appState.queryText = $0 }
            ))
        }
    }

    private func executeQuery() {
        DebugLog.print("🎬 [QueryEditorView] Execute button clicked")
        Task {
            // Set loading state - but keep previous results visible to prevent flicker
            appState.isExecutingQuery = true
            appState.queryError = nil
            appState.queryExecutionTime = nil
            // Keep showQueryResults true and don't clear results - show previous results until new ones arrive

            let startTime = Date()

            do {
                DebugLog.print("📊 [QueryEditorView] Executing query...")
                let (results, columnNames) = try await appState.databaseService.executeQuery(appState.queryText)
                // Update results atomically - this prevents empty state flash
                appState.queryResults = results
                appState.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.showQueryResults = true
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                DebugLog.print("✅ [QueryEditorView] Query executed successfully, showing results")
            } catch {
                appState.queryError = error.localizedDescription
                appState.queryColumnNames = nil
                appState.showQueryResults = true
                // Don't clear results on error - keep previous results visible
                
                let endTime = Date()
                appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
                
                DebugLog.print("❌ [QueryEditorView] Query execution failed: \(error)")
            }

            appState.isExecutingQuery = false
        }
    }
    
    private func formatExecutionTime(_ timeInterval: TimeInterval) -> String {
        if timeInterval >= 1.0 {
            return String(format: "%.1fs", timeInterval)
        } else {
            let milliseconds = timeInterval * 1000
            return String(format: "%.0fms", milliseconds)
        }
    }
}

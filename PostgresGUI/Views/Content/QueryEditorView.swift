//
//  QueryEditorView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import SwiftData

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext
    @State private var showNoDatabaseAlert = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with execute button and stats
            HStack(spacing: 16) {
                Button(action: executeQuery) {
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

                Button(action: saveQuery) {
                    Text("Save Query")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: [.command])

                Spacer()

                // Show saved timestamp on the right
                if let savedAt = appState.lastSavedAt {
                    Text("Saved \(savedAt.formatted(date: .omitted, time: .shortened))")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
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
        .alert("No Database Selected", isPresented: $showNoDatabaseAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select a database from the sidebar before running queries.")
        }
        .onChange(of: appState.queryText) { _, newText in
            // Debounced save of query text to tab state
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                guard !Task.isCancelled else { return }
                tabManager.updateActiveTab(connectionId: nil, databaseName: nil, queryText: newText)
            }
        }
    }

    private func saveQuery() {
        let queryText = appState.queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't save empty queries
        guard !queryText.isEmpty else {
            DebugLog.print("💾 [QueryEditorView] Save skipped - empty query")
            return
        }

        let now = Date()

        // Check if we're updating an existing saved query
        if let existingId = appState.currentSavedQueryId {
            // Update existing query
            let descriptor = FetchDescriptor<SavedQuery>(
                predicate: #Predicate { $0.id == existingId }
            )
            if let existingQuery = try? modelContext.fetch(descriptor).first {
                existingQuery.queryText = queryText
                existingQuery.updatedAt = now
                DebugLog.print("💾 [QueryEditorView] Updated existing query: \(existingQuery.name)")
            }
        } else {
            // Create new saved query
            let queryName = SavedQuery.generateName(from: queryText)
            let savedQuery = SavedQuery(
                name: queryName,
                queryText: queryText,
                connectionId: appState.currentConnection?.id,
                databaseName: appState.selectedDatabase?.name
            )
            modelContext.insert(savedQuery)

            // Update state to track this query
            appState.currentSavedQueryId = savedQuery.id

            DebugLog.print("💾 [QueryEditorView] Saved new query: \(queryName)")
        }

        // Update saved timestamp
        appState.lastSavedAt = now

        // Save context
        do {
            try modelContext.save()
        } catch {
            DebugLog.print("❌ [QueryEditorView] Failed to save query: \(error)")
        }
    }

    private func executeQuery() {
        DebugLog.print("🎬 [QueryEditorView] Execute button clicked")

        // Check if database is selected
        guard appState.selectedDatabase != nil else {
            showNoDatabaseAlert = true
            DebugLog.print("⚠️ [QueryEditorView] No database selected")
            return
        }

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
}

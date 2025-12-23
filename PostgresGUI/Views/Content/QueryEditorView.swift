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
            HStack(spacing: 4) {
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
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                .keyboardShortcut("s", modifiers: [.command])

                Spacer()

                // Dynamic status display
                statusView
            }
            .padding(Constants.Spacing.small)
            .background(Color(NSColor.controlBackgroundColor))

            // Syntax highlighted editor
            SyntaxHighlightedEditor(text: Binding(
                get: { appState.query.queryText },
                set: { appState.query.queryText = $0 }
            ))
        }
        .alert("No Database Selected", isPresented: $showNoDatabaseAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select a database from the sidebar before running queries.")
        }
        .onChange(of: appState.query.queryText) { _, newText in
            // Debounced save of query text to tab state
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                guard !Task.isCancelled else { return }
                tabManager.updateActiveTab(connectionId: nil, databaseName: nil, queryText: newText)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if appState.query.isExecutingQuery {
            Text("Running...")
                .foregroundColor(.secondary)
                .font(.subheadline)
        } else if let statusMessage = appState.query.statusMessage {
            Text(statusMessage)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
        } else if let queryName = appState.query.currentQueryName {
            Text(queryName)
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }

    private func saveQuery() {
        let queryText = appState.query.queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't save empty queries
        guard !queryText.isEmpty else {
            DebugLog.print("💾 [QueryEditorView] Save skipped - empty query")
            return
        }

        let now = Date()
        var savedQueryName: String?

        // Check if we're updating an existing saved query
        if let existingId = appState.query.currentSavedQueryId {
            // Update existing query
            let descriptor = FetchDescriptor<SavedQuery>(
                predicate: #Predicate { $0.id == existingId }
            )
            if let existingQuery = try? modelContext.fetch(descriptor).first {
                existingQuery.queryText = queryText
                existingQuery.updatedAt = now
                savedQueryName = existingQuery.name
                DebugLog.print("💾 [QueryEditorView] Updated existing query: \(existingQuery.name)")
            }
        } else {
            // Create new saved query
            let queryName = SavedQuery.generateName(from: queryText)
            let savedQuery = SavedQuery(
                name: queryName,
                queryText: queryText,
                connectionId: appState.connection.currentConnection?.id,
                databaseName: appState.connection.selectedDatabase?.name
            )
            modelContext.insert(savedQuery)

            // Update state to track this query
            appState.query.currentSavedQueryId = savedQuery.id
            savedQueryName = queryName

            DebugLog.print("💾 [QueryEditorView] Saved new query: \(queryName)")
        }

        // Update saved timestamp
        appState.query.lastSavedAt = now

        // Update query name for idle display
        appState.query.currentQueryName = savedQueryName

        // Show saved status with time including seconds
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        let timeString = formatter.string(from: now)
        appState.query.setTemporaryStatus("Saved \(timeString)")

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
        guard let database = appState.connection.selectedDatabase else {
            showNoDatabaseAlert = true
            DebugLog.print("⚠️ [QueryEditorView] No database selected")
            return
        }

        let queryText = appState.query.queryText

        Task {
            // Set loading state - but keep previous results visible to prevent flicker
            appState.query.isExecutingQuery = true
            appState.query.queryError = nil
            appState.query.queryExecutionTime = nil
            // Keep showQueryResults true and don't clear results - show previous results until new ones arrive

            let startTime = Date()

            do {
                DebugLog.print("📊 [QueryEditorView] Executing query...")
                let (results, columnNames) = try await appState.connection.databaseService.executeQuery(queryText)
                // Update results atomically - this prevents empty state flash
                appState.query.queryResults = results
                appState.query.queryColumnNames = columnNames.isEmpty ? nil : columnNames
                appState.query.showQueryResults = true

                let endTime = Date()
                let executionTime = endTime.timeIntervalSince(startTime)
                appState.query.queryExecutionTime = executionTime

                // Show success status with execution time
                appState.query.setTemporaryStatus("Executed in \(QueryState.formatExecutionTime(executionTime))")

                DebugLog.print("✅ [QueryEditorView] Query executed successfully, showing results")

                // Refresh tables list if query modified schema
                if Self.isSchemaModifyingQuery(queryText) {
                    await refreshTables(database: database)
                }
            } catch {
                appState.query.queryError = error
                appState.query.queryColumnNames = nil
                appState.query.showQueryResults = true
                // Don't clear results on error - keep previous results visible

                let endTime = Date()
                appState.query.queryExecutionTime = endTime.timeIntervalSince(startTime)

                // Show truncated error message
                let errorMessage = PostgresError.extractDetailedMessage(error)
                let truncatedError = errorMessage.count > 50
                    ? String(errorMessage.prefix(47)) + "..."
                    : errorMessage
                appState.query.setTemporaryStatus("Error: \(truncatedError)")

                DebugLog.print("❌ [QueryEditorView] Query execution failed: \(error)")
            }

            appState.query.isExecutingQuery = false
        }
    }

    /// Check if SQL contains schema-modifying statements that affect the tables list
    private static func isSchemaModifyingQuery(_ sql: String) -> Bool {
        let upperSQL = sql.uppercased()
        let patterns = [
            "CREATE\\s+TABLE",
            "DROP\\s+TABLE",
            "ALTER\\s+TABLE",
            "CREATE\\s+TEMP(ORARY)?\\s+TABLE"
        ]
        return patterns.contains { pattern in
            upperSQL.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Refresh the tables list for the current database
    private func refreshTables(database: DatabaseInfo) async {
        do {
            appState.connection.tables = try await appState.connection.databaseService.fetchTables(
                database: database.name
            )
            DebugLog.print("🔄 [QueryEditorView] Tables list refreshed after schema change")
        } catch {
            DebugLog.print("⚠️ [QueryEditorView] Failed to refresh tables: \(error)")
        }
    }
}

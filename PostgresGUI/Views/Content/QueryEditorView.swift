//
//  QueryEditorView.swift
//  PostgresGUI
//
//  Query editor with syntax highlighting. Delegates business logic to QueryEditorViewModel.
//

import SwiftUI
import SwiftData

struct QueryEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: QueryEditorViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with execute button and stats
            HStack(spacing: 4) {
                Button(action: {
                    Task {
                        await viewModel?.executeQuery()
                    }
                }) {
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
        .onAppear {
            viewModel = QueryEditorViewModel(
                appState: appState,
                tabManager: tabManager,
                modelContext: modelContext
            )
        }
        .alert("No Database Selected", isPresented: Binding(
            get: { viewModel?.showNoDatabaseAlert ?? false },
            set: { viewModel?.showNoDatabaseAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Select a database from the sidebar before running queries.")
        }
        .alert("Failed to Save Query", isPresented: Binding(
            get: { viewModel?.showSaveErrorAlert ?? false },
            set: { viewModel?.showSaveErrorAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel?.saveErrorMessage ?? "")
        }
        .alert("Query Timed Out", isPresented: Binding(
            get: { appState.query.showTimeoutAlert },
            set: { appState.query.showTimeoutAlert = $0 }
        )) {
            Button("Try Again") {
                appState.query.showTimeoutAlert = false
                appState.query.queryError = nil
                Task {
                    await viewModel?.executeQuery()
                }
            }
            Button("Cancel", role: .cancel) {
                appState.query.showTimeoutAlert = false
            }
        } message: {
            Text("The query took longer than \(Int(Constants.Timeout.databaseOperation)) seconds. The database may be slow or unresponsive.")
        }
        .onChange(of: appState.query.queryText) { _, newText in
            viewModel?.handleQueryTextChange(newText)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if appState.query.isExecutingQuery {
            Text("Running...")
                .foregroundColor(.secondary)
                .font(.system(size: Constants.FontSize.small))
        } else if let statusMessage = appState.query.statusMessage {
            Text(statusMessage)
                .foregroundColor(.secondary)
                .font(.system(size: Constants.FontSize.small))
                .lineLimit(1)
        } else if let lastExecutedAt = appState.query.lastExecutedAt {
            Text("Last Executed: \(lastExecutedAt.formatted(date: .abbreviated, time: .shortened))")
                .foregroundColor(.secondary)
                .font(.system(size: Constants.FontSize.small))
        }
    }
}

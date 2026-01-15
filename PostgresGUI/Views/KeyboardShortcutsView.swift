//
//  KeyboardShortcutsView.swift
//  PostgresGUI
//

import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.Spacing.large) {
                    ShortcutSection(title: "General") {
                        ShortcutRow(keys: "⌘ T", description: "New Tab")
                        ShortcutRow(keys: "⌘ W", description: "Close Tab")
                    }

                    ShortcutSection(title: "Query Editor") {
                        ShortcutRow(keys: "⌘ ↵", description: "Run Query")
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts")
        }
        .frame(width: 320, height: 280)
    }
}

private struct ShortcutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.small) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: Constants.Spacing.small) {
                content
            }
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
    }
}

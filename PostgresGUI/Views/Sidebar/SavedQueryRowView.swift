//
//  SavedQueryRowView.swift
//  PostgresGUI
//

import SwiftUI

struct SavedQueryRowView: View {
    let query: SavedQuery
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        NavigationLink(value: query.id) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(query.name)
                            .lineLimit(1)

                        Text(query.queryText.prefix(50) + (query.queryText.count > 50 ? "..." : ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "text.document")
                }
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Rename...", systemImage: "pencil")
            }

            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete...", systemImage: "trash")
            }
        }
    }
}

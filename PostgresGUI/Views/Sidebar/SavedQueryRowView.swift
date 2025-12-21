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

    @State private var isHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(query.name)
                        .lineLimit(1)
                    Text(query.queryText.prefix(50) + (query.queryText.count > 50 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isHovered {
                menuButton
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .tag(query.id)
        .onHover { isHovered = $0 }
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

    private var menuButton: some View {
        Menu {
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
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(isButtonHovered ? .primary : .secondary)
                .padding(6)
                .background(isButtonHovered ? Color.secondary.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isButtonHovered = $0 }
    }
}

//
//  SavedQueryRowView.swift
//  PostgresGUI
//

import SwiftUI

struct SavedQueryRowView: View {
    let query: SavedQuery
    let isSelected: Bool
    let selectedCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDeleteSelected: () -> Void
    let onDuplicate: () -> Void
    let onMoveToFolder: () -> Void

    @State private var isHovered = false
    @State private var isButtonHovered = false

    private var showMultiSelectActions: Bool {
        isSelected && selectedCount > 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
            Text(query.name)
                .lineLimit(1)
            Spacer()
            menuButton
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .tag(query.id)
        .onHover { isHovered = $0 }
        .contextMenu {
            if !showMultiSelectActions {
                Button {
                    DebugLog.print("✏️ [SavedQueryRowView] Rename tapped for: \(query.name)")
                    onEdit()
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }

                Button {
                    DebugLog.print("📋 [SavedQueryRowView] Duplicate tapped for: \(query.name)")
                    onDuplicate()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }

                Divider()
            }

            Button {
                DebugLog.print("📁 [SavedQueryRowView] Move to folder tapped for: \(showMultiSelectActions ? "\(selectedCount) queries" : query.name)")
                onMoveToFolder()
            } label: {
                Label(showMultiSelectActions ? "Move \(selectedCount) to Folder..." : "Move to Folder...", systemImage: "folder")
            }

            Divider()

            if showMultiSelectActions {
                Button(role: .destructive) {
                    DebugLog.print("🗑️ [SavedQueryRowView] Delete \(selectedCount) selected queries tapped")
                    onDeleteSelected()
                } label: {
                    Label("Delete \(selectedCount) Queries...", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    DebugLog.print("🗑️ [SavedQueryRowView] Delete tapped for: \(query.name)")
                    onDelete()
                } label: {
                    Label("Delete...", systemImage: "trash")
                }
            }
        }
    }

    private var menuButton: some View {
        Menu {
            if !showMultiSelectActions {
                Button {
                    DebugLog.print("✏️ [SavedQueryRowView] Rename tapped for: \(query.name)")
                    onEdit()
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }

                Button {
                    DebugLog.print("📋 [SavedQueryRowView] Duplicate tapped for: \(query.name)")
                    onDuplicate()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }

                Divider()
            }

            Button {
                DebugLog.print("📁 [SavedQueryRowView] Move to folder tapped for: \(showMultiSelectActions ? "\(selectedCount) queries" : query.name)")
                onMoveToFolder()
            } label: {
                Label(showMultiSelectActions ? "Move \(selectedCount) to Folder..." : "Move to Folder...", systemImage: "folder")
            }

            Divider()

            if showMultiSelectActions {
                Button(role: .destructive) {
                    DebugLog.print("🗑️ [SavedQueryRowView] Delete \(selectedCount) selected queries tapped")
                    onDeleteSelected()
                } label: {
                    Label("Delete \(selectedCount) Queries...", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    DebugLog.print("🗑️ [SavedQueryRowView] Delete tapped for: \(query.name)")
                    onDelete()
                } label: {
                    Label("Delete...", systemImage: "trash")
                }
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

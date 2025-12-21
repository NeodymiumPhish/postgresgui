//
//  MoveToFolderSheet.swift
//  PostgresGUI
//

import SwiftUI
import SwiftData

struct MoveToFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let queries: [SavedQuery]
    let folders: [QueryFolder]

    @State private var selectedFolderId: UUID?
    @State private var isCreatingNewFolder = false
    @State private var newFolderName = ""
    @FocusState private var isNewFolderFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(queries.count == 1 ? "Move Query to Folder" : "Move \(queries.count) Queries to Folder")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Folder list
            ScrollView {
                VStack(spacing: 2) {
                    // No folder option (remove from folder)
                    Button {
                        selectedFolderId = nil
                        moveToFolder(nil)
                    } label: {
                        HStack {
                            Image(systemName: "tray")
                                .foregroundColor(.secondary)
                            Text("No Folder")
                            Spacer()
                            if queries.allSatisfy({ $0.folder == nil }) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Existing folders
                    ForEach(folders.sorted(by: { $0.name < $1.name })) { folder in
                        Button {
                            selectedFolderId = folder.id
                            moveToFolder(folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.secondary)
                                Text(folder.name)
                                Spacer()
                                if queries.allSatisfy({ $0.folder?.id == folder.id }) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // Create new folder option
                    if isCreatingNewFolder {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.secondary)
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                                .focused($isNewFolderFocused)
                                .onSubmit {
                                    createAndMoveToNewFolder()
                                }
                            Button("Create") {
                                createAndMoveToNewFolder()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button {
                                isCreatingNewFolder = false
                                newFolderName = ""
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    } else {
                        Button {
                            isCreatingNewFolder = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNewFolderFocused = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(.accentColor)
                                Text("New Folder...")
                                    .foregroundColor(.accentColor)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 300)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 350)
    }

    private func moveToFolder(_ folder: QueryFolder?) {
        for query in queries {
            query.folder = folder
            query.updatedAt = Date()
        }

        do {
            try modelContext.save()
            DebugLog.print("📁 [MoveToFolderSheet] Moved \(queries.count) queries to folder: \(folder?.name ?? "None")")
            dismiss()
        } catch {
            DebugLog.print("❌ [MoveToFolderSheet] Failed to move queries: \(error)")
        }
    }

    private func createAndMoveToNewFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let newFolder = QueryFolder(name: trimmedName)
        modelContext.insert(newFolder)

        for query in queries {
            query.folder = newFolder
            query.updatedAt = Date()
        }

        do {
            try modelContext.save()
            DebugLog.print("📁 [MoveToFolderSheet] Created folder '\(trimmedName)' and moved \(queries.count) queries")
            dismiss()
        } catch {
            DebugLog.print("❌ [MoveToFolderSheet] Failed to create folder and move queries: \(error)")
        }
    }
}

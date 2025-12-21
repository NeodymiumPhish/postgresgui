//
//  EditFolderSheet.swift
//  PostgresGUI
//

import SwiftUI
import SwiftData

struct EditFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var folder: QueryFolder

    @State private var folderName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Folder")
                .font(.headline)

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    saveChanges()
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            folderName = folder.name
        }
    }

    private func saveChanges() {
        let trimmedName = folderName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        folder.name = trimmedName
        folder.updatedAt = Date()
        dismiss()
    }
}

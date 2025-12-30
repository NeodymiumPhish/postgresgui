//
//  ConnectionDatabasePicker.swift
//  PostgresGUI
//

import SwiftUI

/// Font sizes used in the connection/database picker
private enum PickerFontSize {
    static let label: CGFloat = Constants.FontSize.small
    static let separator: CGFloat = 9
    static let chevron: CGFloat = 8
    static let dropdownItem: CGFloat = 12
    static let checkmark: CGFloat = Constants.FontSize.smallIcon
    static let deleteIcon: CGFloat = Constants.FontSize.small
}

/// Compact picker showing current connection and database with dropdown
struct ConnectionDatabasePicker: View {
    @Environment(AppState.self) private var appState

    @Binding var showDatabaseDropdown: Bool
    let onShowConnectionsList: () -> Void
    let onSelectDatabase: (DatabaseInfo) -> Void
    let onDeleteDatabase: (DatabaseInfo) -> Void
    let onCreateDatabase: () -> Void
    let onDeleteError: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            connectionButton
            separatorChevron
            databasePickerButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(nsColor: .quaternarySystemFill))
    }

    // MARK: - Connection Button

    private var connectionButton: some View {
        Button {
            onShowConnectionsList()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(appState.connection.currentConnection?.displayName ?? "No Connection")
                    .font(.system(size: PickerFontSize.label))
                    .foregroundColor(
                        appState.connection.currentConnection != nil ? .primary : .secondary
                    )
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Separator

    private var separatorChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: PickerFontSize.separator))
            .foregroundStyle(.secondary)
    }

    // MARK: - Database Picker

    private var databasePickerButton: some View {
        Button {
            showDatabaseDropdown.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(appState.connection.selectedDatabase?.name ?? "No Database")
                    .font(.system(size: PickerFontSize.label))
                    .foregroundColor(
                        appState.connection.selectedDatabase != nil ? .primary : .secondary
                    )
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: PickerFontSize.chevron))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!appState.connection.isConnected)
        .popover(isPresented: $showDatabaseDropdown, arrowEdge: .bottom) {
            databaseDropdownContent
        }
    }

    // MARK: - Database Dropdown

    private var databaseDropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.connection.databases.isEmpty {
                Text("No databases")
                    .font(.system(size: PickerFontSize.dropdownItem))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.connection.databases.sorted { $0.name < $1.name }) { database in
                            databaseRow(database)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()
                .padding(.vertical, 4)

            createDatabaseButton
        }
        .padding(.vertical, 8)
        .frame(minWidth: 200)
    }

    private var createDatabaseButton: some View {
        Button {
            showDatabaseDropdown = false
            onCreateDatabase()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: PickerFontSize.dropdownItem))
                Text("Create Database")
                    .font(.system(size: PickerFontSize.dropdownItem))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!appState.connection.isConnected)
    }

    @ViewBuilder
    private func databaseRow(_ database: DatabaseInfo) -> some View {
        let isSelected = appState.connection.selectedDatabase?.id == database.id

        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.system(size: PickerFontSize.checkmark, weight: .semibold))
                .frame(width: 12)
                .foregroundColor(.accentColor)

            Text(database.name)
                .font(.system(size: PickerFontSize.dropdownItem))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if isSelected {
                    onDeleteError("Cannot delete '\(database.name)' because it is currently selected. Please select a different database first.")
                } else {
                    showDatabaseDropdown = false
                    onDeleteDatabase(database)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: PickerFontSize.deleteIcon))
                    .foregroundColor(isSelected ? .secondary.opacity(0.5) : .secondary)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Cannot delete selected database" : "Delete database")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectDatabase(database)
            showDatabaseDropdown = false
        }
    }
}

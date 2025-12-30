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

    // Connection dropdown
    @Binding var showConnectionDropdown: Bool
    let connections: [ConnectionProfile]
    let onSelectConnection: (ConnectionProfile) -> Void
    let onEditConnection: (ConnectionProfile) -> Void
    let onDeleteConnection: (ConnectionProfile) -> Void
    let onCreateConnection: () -> Void

    // Database dropdown
    @Binding var showDatabaseDropdown: Bool
    let onSelectDatabase: (DatabaseInfo) -> Void
    let onDeleteDatabase: (DatabaseInfo) -> Void
    let onCreateDatabase: () -> Void
    let onDeleteError: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            connectionButton
            if hasConnection {
                separatorChevron
                databasePickerButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color(nsColor: .quaternarySystemFill))
    }
    
    private var hasConnection: Bool {
        appState.connection.currentConnection != nil
    }

    // MARK: - Connection Button

    private var noConnectionSelected: Bool {
        !hasConnection
    }

    @ViewBuilder
    private var connectionButton: some View {
        Button {
            showConnectionDropdown.toggle()
        } label: {
            if noConnectionSelected {
                PhaseAnimator([0.4, 1.0]) { phase in
                    connectionButtonContent(opacity: phase)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            } else {
                connectionButtonContent(opacity: 1.0)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showConnectionDropdown, arrowEdge: .bottom) {
            connectionDropdownContent
        }
    }
    
    private func connectionButtonContent(opacity: Double) -> some View {
        HStack(spacing: 6) {
            if hasConnection {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                Text("⚠️")
                    .font(.system(size: 12))
            }
            Text(appState.connection.currentConnection?.displayName ?? "Select Connection")
                .font(.system(size: PickerFontSize.label))
                .foregroundColor(
                    appState.connection.currentConnection != nil ? .primary : .secondary
                )
                .opacity(opacity)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: PickerFontSize.chevron))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Connection Dropdown

    private var connectionDropdownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if connections.isEmpty {
                Text("No connections")
                    .font(.system(size: PickerFontSize.dropdownItem))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(connections.sorted { $0.displayName < $1.displayName }) { connection in
                            connectionRow(connection)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()
                .padding(.vertical, 4)

            newConnectionButton
        }
        .padding(.vertical, 8)
        .frame(minWidth: 200)
    }

    private var newConnectionButton: some View {
        Button {
            showConnectionDropdown = false
            onCreateConnection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: PickerFontSize.dropdownItem))
                Text("New Connection")
                    .font(.system(size: PickerFontSize.dropdownItem))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func connectionRow(_ connection: ConnectionProfile) -> some View {
        let isActive = appState.connection.currentConnection?.id == connection.id

        HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark" : "")
                .font(.system(size: PickerFontSize.checkmark, weight: .semibold))
                .frame(width: 12)
                .foregroundColor(.accentColor)

            Text(connection.displayName)
                .font(.system(size: PickerFontSize.dropdownItem))
                .frame(maxWidth: 200, alignment: .leading)
                .lineLimit(1)

            Button {
                showConnectionDropdown = false
                onEditConnection(connection)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: PickerFontSize.deleteIcon))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit connection")

            Button {
                showConnectionDropdown = false
                onDeleteConnection(connection)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: PickerFontSize.deleteIcon))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete connection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                onSelectConnection(connection)
                showConnectionDropdown = false
            }
        }
    }

    // MARK: - Separator

    private var separatorChevron: some View {
        Text("|")
            .font(.system(size: PickerFontSize.label, weight: .light))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Database Picker

    private var noDatabaseSelected: Bool {
        appState.connection.isConnected && appState.connection.selectedDatabase == nil
    }

    @ViewBuilder
    private var databasePickerButton: some View {
        Button {
            showDatabaseDropdown.toggle()
        } label: {
            if noDatabaseSelected {
                PhaseAnimator([0.4, 1.0]) { phase in
                    databaseButtonContent(opacity: phase)
                } animation: { _ in
                    .easeInOut(duration: 0.8)
                }
            } else {
                databaseButtonContent(opacity: 1.0)
            }
        }
        .buttonStyle(.plain)
        .disabled(!appState.connection.isConnected)
        .popover(isPresented: $showDatabaseDropdown, arrowEdge: .bottom) {
            databaseDropdownContent
        }
    }

    private func databaseButtonContent(opacity: Double) -> some View {
        HStack(spacing: 6) {
            if let database = appState.connection.selectedDatabase {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(database.name)
                    .font(.system(size: PickerFontSize.label))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            } else {
                Text("⚠️ No Database")
                    .font(.system(size: PickerFontSize.label))
                    .foregroundColor(.secondary)
                    .opacity(opacity)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: PickerFontSize.chevron))
                .foregroundColor(.secondary)
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

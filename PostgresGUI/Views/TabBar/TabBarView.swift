//
//  TabBarView.swift
//  PostgresGUI
//
//  Created by ghazi on 12/20/25.
//

import SwiftUI
import SwiftData

struct TabBarView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(AppState.self) private var appState
    @Query private var connections: [ConnectionProfile]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabManager.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTab?.id,
                            connectionName: connectionName(for: tab),
                            onSelect: { selectTab(tab) },
                            onClose: { closeTab(tab) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            Button(action: addNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func connectionName(for tab: TabState) -> String {
        if let connectionId = tab.connectionId,
           let connection = connections.first(where: { $0.id == connectionId }) {
            if let dbName = tab.databaseName {
                return "\(connection.displayName) / \(dbName)"
            }
            return connection.displayName
        }
        return "New Tab"
    }

    private func selectTab(_ tab: TabState) {
        guard tab.id != tabManager.activeTab?.id else { return }

        // Save current state before switching
        tabManager.updateActiveTab(
            connectionId: appState.currentConnection?.id,
            databaseName: appState.selectedDatabase?.name,
            queryText: appState.queryText
        )

        // Switch to new tab
        tabManager.switchToTab(tab)

        // Notify that tab changed - the view will need to reload
        NotificationCenter.default.post(name: .tabDidChange, object: tab)
    }

    private func closeTab(_ tab: TabState) {
        tabManager.closeTab(tab)

        // If we closed the active tab, notify to reload
        if tab.id == tabManager.activeTab?.id {
            NotificationCenter.default.post(name: .tabDidChange, object: tabManager.activeTab)
        }
    }

    private func addNewTab() {
        tabManager.createNewTab(inheritingFrom: tabManager.activeTab)
        NotificationCenter.default.post(name: .tabDidChange, object: tabManager.activeTab)
    }
}

struct TabItemView: View {
    let tab: TabState
    let isActive: Bool
    let connectionName: String
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(connectionName)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(isActive ? .primary : .secondary)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.secondary.opacity(0.3) : (isHovered ? Color.secondary.opacity(0.15) : Color.clear))
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

extension Notification.Name {
    static let tabDidChange = Notification.Name("tabDidChange")
}

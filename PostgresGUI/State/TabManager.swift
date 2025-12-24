//
//  TabManager.swift
//  PostgresGUI
//
//  Created by ghazi on 12/20/25.
//

import Foundation
import SwiftData

@Observable
@MainActor
class TabManager {
    var tabs: [TabState] = []
    var activeTab: TabState?

    private var tabService: TabServiceProtocol?

    func initialize(with modelContext: ModelContext) {
        self.tabService = TabService(modelContext: modelContext)
        loadTabs()
    }

    func loadTabs() {
        guard let tabService = tabService else { return }

        tabs = tabService.loadAllTabs()
        activeTab = tabService.getActiveTab()

        DebugLog.print("📑 [TabManager] Loaded \(tabs.count) tabs, activeTab: \(activeTab?.id.uuidString ?? "nil")")
        for tab in tabs {
            DebugLog.print("   Tab: \(tab.id) - connection: \(tab.connectionId?.uuidString ?? "nil"), db: \(tab.databaseName ?? "nil"), active: \(tab.isActive)")
        }

        // If no tabs exist, create one
        if tabs.isEmpty {
            DebugLog.print("📑 [TabManager] No tabs found, creating new one")
            let newTab = tabService.createTab(inheritingFrom: nil)
            tabService.setActiveTab(newTab)
            tabs = [newTab]
            activeTab = newTab
        }

        // If no active tab but tabs exist, set first as active
        if activeTab == nil, let firstTab = tabs.first {
            DebugLog.print("📑 [TabManager] No active tab, setting first as active")
            tabService.setActiveTab(firstTab)
            activeTab = firstTab
        }
    }

    func createNewTab(inheritingFrom tab: TabState? = nil) {
        guard let tabService = tabService else { return }

        let sourceTab = tab ?? activeTab
        let newTab = tabService.createTab(inheritingFrom: sourceTab)
        tabService.setActiveTab(newTab)

        tabs = tabService.loadAllTabs()
        activeTab = newTab
    }

    func switchToTab(_ tab: TabState) {
        guard let tabService = tabService else { return }

        tabService.setActiveTab(tab)
        activeTab = tab
    }

    func closeTab(_ tab: TabState) {
        guard let tabService = tabService else { return }

        let wasActive = tab.isActive
        tabService.deleteTab(tab)
        tabs = tabService.loadAllTabs()

        // If we closed the active tab, activate the most recently used one
        if wasActive {
            if let mruTab = tabs.max(by: { $0.lastAccessedAt < $1.lastAccessedAt }) {
                tabService.setActiveTab(mruTab)
                activeTab = mruTab
            } else {
                // No tabs left, create a new one
                let newTab = tabService.createTab(inheritingFrom: nil)
                tabService.setActiveTab(newTab)
                tabs = [newTab]
                activeTab = newTab
            }
        }
    }

    func updateActiveTab(connectionId: UUID? = nil, databaseName: String? = nil, queryText: String? = nil, savedQueryId: UUID? = nil) {
        guard let tabService = tabService, let activeTab = activeTab else { return }
        tabService.updateTab(activeTab, connectionId: connectionId, databaseName: databaseName, queryText: queryText, savedQueryId: savedQueryId)
    }

    func clearActiveTabSavedQueryId() {
        guard let tabService = tabService, let activeTab = activeTab else { return }
        tabService.clearSavedQueryId(activeTab)
    }

    func saveCurrentState() {
        guard let tabService = tabService else { return }
        tabService.save()
    }
}

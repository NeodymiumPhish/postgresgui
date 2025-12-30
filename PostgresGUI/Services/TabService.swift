//
//  TabService.swift
//  PostgresGUI
//
//  Service for managing tab state persistence with SwiftData.
//  Handles creation, updates, and restoration of query tabs.
//
//  Design: Conforms to TabServiceProtocol for dependency injection and testing.
//  Protocol is defined in Services/Protocols/TabServiceProtocol.swift.
//

import Foundation
import SwiftData

@MainActor
class TabService: TabServiceProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadAllTabs() -> [TabState] {
        let descriptor = FetchDescriptor<TabState>(
            sortBy: [SortDescriptor(\.order, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            DebugLog.print("Failed to load tabs: \(error)")
            return []
        }
    }

    func getActiveTab() -> TabState? {
        let descriptor = FetchDescriptor<TabState>(
            predicate: #Predicate<TabState> { $0.isActive == true }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            DebugLog.print("Failed to get active tab: \(error)")
            return nil
        }
    }

    func setActiveTab(_ tab: TabState) {
        // Deactivate all tabs first
        let allTabs = loadAllTabs()
        for t in allTabs {
            t.isActive = false
        }
        // Activate the selected tab and update last accessed time
        tab.isActive = true
        tab.lastAccessedAt = Date()
        save()
    }

    func createTab(inheritingFrom tab: TabState? = nil) -> TabState {
        let allTabs = loadAllTabs()
        let maxOrder = allTabs.map(\.order).max() ?? -1

        let newTab = TabState(
            connectionId: tab?.connectionId,
            databaseName: tab?.databaseName,
            queryText: "",
            isActive: false,
            order: maxOrder + 1
        )

        modelContext.insert(newTab)
        save()
        return newTab
    }

    func updateTab(_ tab: TabState, connectionId: UUID?, databaseName: String?, queryText: String?, savedQueryId: UUID?) {
        if let connectionId = connectionId {
            tab.connectionId = connectionId
        }
        if let databaseName = databaseName {
            tab.databaseName = databaseName
        }
        if let queryText = queryText {
            tab.queryText = queryText
        }
        if let savedQueryId = savedQueryId {
            tab.savedQueryId = savedQueryId
        }
        save()
    }

    func updateTabTableSelection(_ tab: TabState, schema: String?, name: String?) {
        tab.selectedTableSchema = schema
        tab.selectedTableName = name
        save()
    }

    func updateTabResults(_ tab: TabState, results: [TableRow]?, columnNames: [String]?) {
        tab.setCachedResults(results, columnNames: columnNames)
        save()
    }

    func clearSavedQueryId(_ tab: TabState) {
        tab.savedQueryId = nil
        save()
    }

    func deleteTab(_ tab: TabState) {
        modelContext.delete(tab)
        save()
    }

    func save() {
        do {
            try modelContext.save()
        } catch {
            DebugLog.print("Failed to save tab state: \(error)")
        }
    }
}

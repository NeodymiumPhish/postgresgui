//
//  ConnectionState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Manages database connection state and data caches
@Observable
@MainActor
class ConnectionState {
    // Connection state
    var currentConnection: ConnectionProfile?

    // Computed property - delegates to DatabaseService
    var isConnected: Bool {
        databaseService.isConnected
    }

    // Database service dependency - injected for testability
    var databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    convenience init() {
        self.init(databaseService: DatabaseService())
    }

    // Current selections
    var selectedDatabase: DatabaseInfo?
    var selectedTable: TableInfo?

    // Data caches (populated by DatabaseService)
    var databases: [DatabaseInfo] = []
    var tables: [TableInfo] = []
    var isLoadingTables: Bool = false

    /// Clean up resources when window is closing
    func cleanupOnWindowClose() async {
        guard isConnected else { return }

        DebugLog.print("🧹 Window closing, cleaning up connection...")

        // Disconnect database (awaits proper shutdown)
        await databaseService.disconnect()

        // Reset state
        currentConnection = nil
        selectedDatabase = nil
        selectedTable = nil
        databases = []
        tables = []

        DebugLog.print("✅ Cleanup completed")
    }
}

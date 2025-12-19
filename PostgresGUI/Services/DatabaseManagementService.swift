//
//  DatabaseManagementService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import Logging

/// Service for database management operations
@MainActor
class DatabaseManagementService: DatabaseManagementServiceProtocol {
    private let connectionManager: ConnectionManagerProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.dbmanagementservice")

    // Reference to database service to check if we're deleting the current database
    private weak var databaseService: (any DatabaseServiceProtocol)?

    init(connectionManager: ConnectionManagerProtocol, databaseService: (any DatabaseServiceProtocol)? = nil) {
        self.connectionManager = connectionManager
        self.databaseService = databaseService
    }

    /// Create a new database
    func createDatabase(name: String) async throws {
        logger.info("Creating database: \(name)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.createDatabase(connection: conn, name: name)
        }
    }

    /// Delete a database
    func deleteDatabase(name: String) async throws {
        logger.info("Deleting database: \(name)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.dropDatabase(connection: conn, name: name)
        }

        // If we deleted the current database, disconnect
        if databaseService?.connectedDatabase == name {
            await databaseService?.disconnect()
        }
    }
}

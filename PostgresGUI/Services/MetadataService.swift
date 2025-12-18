//
//  MetadataService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import Logging

/// Service for database metadata operations
@MainActor
class MetadataService: MetadataServiceProtocol {
    private let connectionManager: PostgresConnectionManager
    private let logger = Logger.debugLogger(label: "com.postgresgui.metadataservice")

    init(connectionManager: PostgresConnectionManager) {
        self.connectionManager = connectionManager
    }

    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        logger.debug("Fetching databases")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchDatabases(connection: conn)
        }
    }

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        logger.debug("Fetching primary keys for \(schema).\(table)")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchPrimaryKeys(connection: conn, schema: schema, table: table)
        }
    }

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        logger.debug("Fetching column info for \(schema).\(table)")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchColumns(connection: conn, schema: schema, table: table)
        }
    }
}

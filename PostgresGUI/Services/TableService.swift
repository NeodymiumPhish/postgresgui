//
//  TableService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import Logging

/// Service for table operations
@MainActor
class TableService: TableServiceProtocol {
    private let connectionManager: ConnectionManagerProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.tableservice")

    init(connectionManager: ConnectionManagerProtocol) {
        self.connectionManager = connectionManager
    }

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo] {
        logger.debug("Fetching tables for database: \(database)")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchTables(connection: conn)
        }
    }

    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow] {
        logger.debug("Fetching table data: \(schema).\(table)")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchTableData(
                connection: conn,
                schema: schema,
                table: table,
                limit: limit,
                offset: offset
            )
        }
    }

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws {
        logger.info("Deleting table: \(schema).\(table)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.dropTable(connection: conn, schema: schema, table: table)
        }
    }
}

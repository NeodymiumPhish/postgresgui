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
    private let queryExecutor: QueryExecutorProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.tableservice")

    init(connectionManager: ConnectionManagerProtocol, queryExecutor: QueryExecutorProtocol) {
        self.connectionManager = connectionManager
        self.queryExecutor = queryExecutor
    }

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo] {
        logger.debug("Fetching tables for database: \(database)")

        return try await connectionManager.withConnection { conn in
            try await self.queryExecutor.fetchTables(connection: conn)
        }
    }

    /// Fetch list of schemas in the connected database
    func fetchSchemas(database: String) async throws -> [String] {
        logger.debug("Fetching schemas for database: \(database)")

        return try await connectionManager.withConnection { conn in
            try await self.queryExecutor.fetchSchemas(connection: conn)
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
            try await self.queryExecutor.fetchTableData(
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
            try await self.queryExecutor.dropTable(connection: conn, schema: schema, table: table)
        }
    }
}

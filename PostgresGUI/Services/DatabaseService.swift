//
//  DatabaseService.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import Logging

@MainActor
class DatabaseService {
    // Connection manager (actor-isolated)
    private let connectionManager = PostgresConnectionManager()
    private let logger = Logger(label: "com.postgresgui.service")

    // Connection state (tracked synchronously for UI access)
    private var currentDatabase: String?
    private var _isConnected: Bool = false

    var isConnected: Bool {
        _isConnected
    }

    init() {
        logger.info("DatabaseService initialized")
    }

    // MARK: - Connection Management

    /// Connect to PostgreSQL database
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws {
        // Validate inputs
        guard !host.isEmpty else {
            throw ConnectionError.invalidHost(host)
        }

        guard port > 0 && port <= 65535 else {
            throw ConnectionError.invalidPort
        }

        logger.info("Connecting to \(host):\(port), database: \(database)")

        // Get TLS configuration from SSLMode
        let tlsConfig = sslMode.nioTLSConfiguration

        do {
            try await connectionManager.connect(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tlsConfiguration: tlsConfig
            )

            currentDatabase = database
            _isConnected = true
            logger.info("Successfully connected")
        } catch {
            logger.error("Connection failed: \(error)")
            _isConnected = false
            throw error
        }
    }

    /// Disconnect from database
    func disconnect() async {
        logger.info("Disconnecting")
        await connectionManager.disconnect()
        currentDatabase = nil
        _isConnected = false
    }

    /// Test connection without saving (static method - doesn't require instance)
    nonisolated static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws -> Bool {
        let tlsConfig = sslMode.nioTLSConfiguration

        return try await PostgresConnectionManager.testConnection(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tlsConfiguration: tlsConfig
        )
    }

    // MARK: - Database Operations

    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.debug("Fetching databases")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchDatabases(connection: conn)
        }
    }

    /// Create a new database
    func createDatabase(name: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.info("Creating database: \(name)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.createDatabase(connection: conn, name: name)
        }
    }

    /// Delete a database
    func deleteDatabase(name: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.info("Deleting database: \(name)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.dropDatabase(connection: conn, name: name)
        }

        // If we deleted the current database, disconnect
        if currentDatabase == name {
            await disconnect()
        }
    }

    // MARK: - Table Operations

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

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
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

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
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.info("Deleting table: \(schema).\(table)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.dropTable(connection: conn, schema: schema, table: table)
        }
    }

    // MARK: - Query Execution

    /// Execute arbitrary SQL query and return results along with column names
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.info("Executing query")
        logger.debug("SQL: \(sql.prefix(200))")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.executeQuery(connection: conn, sql: sql)
        }
    }

    // MARK: - Metadata Operations

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.debug("Fetching primary keys for \(schema).\(table)")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchPrimaryKeys(connection: conn, schema: schema, table: table)
        }
    }

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        logger.debug("Fetching column info for \(schema).\(table)")

        return try await connectionManager.withConnection { conn in
            try await QueryExecutor.fetchColumns(connection: conn, schema: schema, table: table)
        }
    }

    // MARK: - Row Operations

    /// Delete rows from a table using primary key values
    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        logger.info("Deleting \(rows.count) rows from \(schema).\(table)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.deleteRows(
                connection: conn,
                schema: schema,
                table: table,
                primaryKeyColumns: primaryKeyColumns,
                rows: rows
            )
        }
    }

    /// Update a row in a table using primary key values
    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: String?]
    ) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        logger.info("Updating row in \(schema).\(table)")

        try await connectionManager.withConnection { conn in
            try await QueryExecutor.updateRow(
                connection: conn,
                schema: schema,
                table: table,
                primaryKeyColumns: primaryKeyColumns,
                originalRow: originalRow,
                updatedValues: updatedValues
            )
        }
    }
}

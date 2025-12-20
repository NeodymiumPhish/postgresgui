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
    // MARK: - Core Dependencies

    // Connection manager (actor-isolated) - protocol for testability
    private let connectionManager: ConnectionManagerProtocol
    private let queryExecutor: QueryExecutorProtocol
    private let logger = Logger.debugLogger(label: "com.postgresgui.service")

    // Specialized services (lazy to avoid circular dependencies)
    private lazy var tableService = TableService(connectionManager: connectionManager, queryExecutor: queryExecutor)
    private lazy var metadataService = MetadataService(connectionManager: connectionManager, queryExecutor: queryExecutor)
    private lazy var databaseManagementService = DatabaseManagementService(
        connectionManager: connectionManager,
        queryExecutor: queryExecutor,
        databaseService: self
    )

    // MARK: - Connection State

    // Connection state (tracked synchronously for UI access)
    // NOTE: This is the single source of truth for connection state
    // AppState.isConnected is a computed property that reads from this
    private var currentDatabase: String?
    private var _isConnected: Bool = false

    var isConnected: Bool {
        _isConnected
    }

    var connectedDatabase: String? {
        currentDatabase
    }

    init(
        connectionManager: ConnectionManagerProtocol = PostgresConnectionManager(),
        queryExecutor: QueryExecutorProtocol? = nil
    ) {
        self.connectionManager = connectionManager
        self.queryExecutor = queryExecutor ?? PostgresQueryExecutor.shared
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

    // MARK: - Database Operations (Delegated to DatabaseManagementService)

    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await metadataService.fetchDatabases()
    }

    /// Create a new database
    func createDatabase(name: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        try await databaseManagementService.createDatabase(name: name)
    }

    /// Delete a database
    func deleteDatabase(name: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        try await databaseManagementService.deleteDatabase(name: name)
    }

    // MARK: - Table Operations (Delegated to TableService)

    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await tableService.fetchTables(database: database)
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

        return try await tableService.fetchTableData(
            schema: schema,
            table: table,
            offset: offset,
            limit: limit
        )
    }

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        try await tableService.deleteTable(schema: schema, table: table)
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
            try await self.queryExecutor.executeQuery(connection: conn, sql: sql)
        }
    }

    // MARK: - Metadata Operations (Delegated to MetadataService)

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await metadataService.fetchPrimaryKeyColumns(schema: schema, table: table)
    }

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        guard _isConnected else {
            throw ConnectionError.notConnected
        }

        return try await metadataService.fetchColumnInfo(schema: schema, table: table)
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
            try await self.queryExecutor.deleteRows(
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
            try await self.queryExecutor.updateRow(
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

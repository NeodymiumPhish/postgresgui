//
//  PostgresQueryExecutor.swift
//  PostgresGUI
//
//  PostgresNIO-specific implementation of QueryExecutorProtocol.
//  Executes queries and delegates result mapping to ResultMapperProtocol.
//

import Foundation
import PostgresNIO
import Logging

/// PostgresNIO implementation of QueryExecutorProtocol
struct PostgresQueryExecutor: QueryExecutorProtocol {

    private let logger = Logger.debugLogger(label: "com.postgresgui.query")
    private let resultMapper: ResultMapperProtocol

    // MARK: - Initialization

    init(resultMapper: ResultMapperProtocol = PostgresResultMapper()) {
        self.resultMapper = resultMapper
    }

    // MARK: - Database Operations

    func fetchDatabases(connection: DatabaseConnectionProtocol) async throws -> [DatabaseInfo] {
        let sql = """
        SELECT datname
        FROM pg_database
        WHERE datistemplate = false
        ORDER BY datname
        """

        logger.debug("Fetching databases")

        let rows = try await connection.executeQuery(sql)
        var databases: [DatabaseInfo] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let db = try resultMapper.mapToDatabaseInfo(dbRow)
            databases.append(db)
        }

        logger.info("Fetched \(databases.count) databases")
        return databases
    }

    func createDatabase(connection: DatabaseConnectionProtocol, name: String) async throws {
        let sanitizedName = sanitizeIdentifier(name)
        let sql = "CREATE DATABASE \(sanitizedName)"

        logger.info("Creating database: \(sanitizedName)")

        _ = try await connection.executeQuery(sql)
        logger.info("Database created successfully")
    }

    func dropDatabase(connection: DatabaseConnectionProtocol, name: String) async throws {
        let sanitizedName = sanitizeIdentifier(name)
        let sql = "DROP DATABASE \(sanitizedName)"

        logger.info("Dropping database: \(sanitizedName)")

        _ = try await connection.executeQuery(sql)
        logger.info("Database dropped successfully")
    }

    // MARK: - Table Operations

    func fetchTables(connection: DatabaseConnectionProtocol) async throws -> [TableInfo] {
        let sql = """
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, tablename
        """

        logger.debug("Fetching tables")

        let rows = try await connection.executeQuery(sql)
        var tables: [TableInfo] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let table = try resultMapper.mapToTableInfo(dbRow)
            tables.append(table)
        }

        logger.info("Fetched \(tables.count) tables")
        return tables
    }

    func fetchTableData(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow] {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "SELECT * FROM \(qualifiedTable) LIMIT \(limit) OFFSET \(offset)"

        logger.debug("Fetching table data: \(qualifiedTable), limit: \(limit), offset: \(offset)")

        let rows = try await connection.executeQuery(sql)
        let tableRows = try await resultMapper.mapRowsToTableRows(rows)

        logger.info("Fetched \(tableRows.count) rows from \(qualifiedTable)")
        return tableRows
    }

    func dropTable(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "DROP TABLE \(qualifiedTable)"

        logger.info("Dropping table: \(qualifiedTable)")

        _ = try await connection.executeQuery(sql)
        logger.info("Table dropped successfully")
    }

    // MARK: - Column Metadata

    func fetchColumns(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> [ColumnInfo] {
        let sql = """
        SELECT
            column_name,
            data_type,
            is_nullable,
            column_default
        FROM information_schema.columns
        WHERE table_schema = '\(schema)' AND table_name = '\(table)'
        ORDER BY ordinal_position
        """

        logger.debug("Fetching columns for \(schema).\(table)")

        let rows = try await connection.executeQuery(sql)
        var columns: [ColumnInfo] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let column = try resultMapper.mapToColumnInfo(dbRow)
            columns.append(column)
        }

        logger.info("Fetched \(columns.count) columns for \(schema).\(table)")
        return columns
    }

    func fetchPrimaryKeys(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String
    ) async throws -> [String] {
        let sql = """
        SELECT a.attname
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = ('\(schema).\(table)')::regclass AND i.indisprimary
        """

        logger.debug("Fetching primary keys for \(schema).\(table)")

        let rows = try await connection.executeQuery(sql)
        var primaryKeys: [String] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            // Use the protocol's decode method via the "attname" column
            let pkColumn = try dbRow.decode(String.self, column: "attname")
            primaryKeys.append(pkColumn)
        }

        logger.info("Found \(primaryKeys.count) primary key columns for \(schema).\(table)")
        return primaryKeys
    }

    // MARK: - Query Execution

    func executeQuery(
        connection: DatabaseConnectionProtocol,
        sql: String
    ) async throws -> ([TableRow], [String]) {
        logger.info("Executing query: \(sql.prefix(100))...")

        let startTime = Date()

        let rows = try await connection.executeQuery(sql)

        var tableRows: [TableRow] = []
        var columnNames: [String] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            if columnNames.isEmpty {
                columnNames = dbRow.columnNames
            }

            let tableRow = try resultMapper.mapRowToTableRow(dbRow)
            tableRows.append(tableRow)
        }

        let executionTime = Date().timeIntervalSince(startTime)
        logger.info("Query executed in \(String(format: "%.3f", executionTime))s, returned \(tableRows.count) rows")

        return (tableRows, columnNames)
    }

    // MARK: - Row Operations

    func updateRow(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: String?]
    ) async throws {
        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"

        var setClauses: [String] = []
        for (column, value) in updatedValues {
            if let val = value {
                setClauses.append("\(sanitizeIdentifier(column)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
            } else {
                setClauses.append("\(sanitizeIdentifier(column)) = NULL")
            }
        }

        var whereClauses: [String] = []
        for pkColumn in primaryKeyColumns {
            guard let pkValue = originalRow.values[pkColumn] else {
                throw DatabaseError.missingPrimaryKeyValue(column: pkColumn)
            }

            if let val = pkValue {
                whereClauses.append("\(sanitizeIdentifier(pkColumn)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
            } else {
                whereClauses.append("\(sanitizeIdentifier(pkColumn)) IS NULL")
            }
        }

        let sql = """
        UPDATE \(qualifiedTable)
        SET \(setClauses.joined(separator: ", "))
        WHERE \(whereClauses.joined(separator: " AND "))
        """

        logger.info("Updating row in \(qualifiedTable)")
        logger.debug("SQL: \(sql)")

        _ = try await connection.executeQuery(sql)
        logger.info("Row updated successfully")
    }

    func deleteRows(
        connection: DatabaseConnectionProtocol,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"

        for row in rows {
            var whereClauses: [String] = []

            for pkColumn in primaryKeyColumns {
                guard let pkValue = row.values[pkColumn] else {
                    throw DatabaseError.missingPrimaryKeyValue(column: pkColumn)
                }

                if let val = pkValue {
                    whereClauses.append("\(sanitizeIdentifier(pkColumn)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
                } else {
                    whereClauses.append("\(sanitizeIdentifier(pkColumn)) IS NULL")
                }
            }

            let sql = """
            DELETE FROM \(qualifiedTable)
            WHERE \(whereClauses.joined(separator: " AND "))
            """

            logger.debug("Deleting row from \(qualifiedTable)")
            _ = try await connection.executeQuery(sql)
        }

        logger.info("Deleted \(rows.count) row(s) from \(qualifiedTable)")
    }

    // MARK: - Helpers

    /// Sanitize SQL identifier (table name, column name, etc.)
    private func sanitizeIdentifier(_ identifier: String) -> String {
        let escaped = identifier.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

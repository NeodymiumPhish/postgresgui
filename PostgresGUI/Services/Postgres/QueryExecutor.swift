//
//  QueryExecutor.swift
//  PostgresGUI
//
//  Executes queries and returns structured results
//

import Foundation
import PostgresNIO
import Logging

/// Executes PostgreSQL queries and returns structured results
enum QueryExecutor {

    private static let logger = Logger(label: "com.postgresgui.query")

    // MARK: - Database Operations

    /// Fetch all non-template databases
    /// - Parameter connection: Active PostgresConnection
    /// - Returns: Array of DatabaseInfo
    static func fetchDatabases(connection: PostgresConnection) async throws -> [DatabaseInfo] {
        let sql = """
        SELECT datname
        FROM pg_database
        WHERE datistemplate = false
        ORDER BY datname
        """

        logger.debug("Fetching databases")

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var databases: [DatabaseInfo] = []

        for try await row in rows {
            let db = try ResultMapper.mapToDatabaseInfo(row)
            databases.append(db)
        }

        logger.info("Fetched \(databases.count) databases")
        return databases
    }

    /// Create a new database
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - name: Name of the database to create
    static func createDatabase(connection: PostgresConnection, name: String) async throws {
        // Database names can't be parameterized, but we need to sanitize
        let sanitizedName = sanitizeIdentifier(name)
        let sql = "CREATE DATABASE \(sanitizedName)"

        logger.info("Creating database: \(sanitizedName)")

        _ = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        logger.info("Database created successfully")
    }

    /// Drop a database
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - name: Name of the database to drop
    static func dropDatabase(connection: PostgresConnection, name: String) async throws {
        let sanitizedName = sanitizeIdentifier(name)
        let sql = "DROP DATABASE \(sanitizedName)"

        logger.info("Dropping database: \(sanitizedName)")

        _ = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        logger.info("Database dropped successfully")
    }

    // MARK: - Table Operations

    /// Fetch all tables from user schemas (excluding system schemas)
    /// - Parameter connection: Active PostgresConnection
    /// - Returns: Array of TableInfo
    static func fetchTables(connection: PostgresConnection) async throws -> [TableInfo] {
        let sql = """
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY schemaname, tablename
        """

        logger.debug("Fetching tables")

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var tables: [TableInfo] = []

        for try await row in rows {
            let table = try ResultMapper.mapToTableInfo(row)
            tables.append(table)
        }

        logger.info("Fetched \(tables.count) tables")
        return tables
    }

    /// Fetch table data with pagination
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - schema: Schema name
    ///   - table: Table name
    ///   - limit: Maximum rows to fetch
    ///   - offset: Number of rows to skip
    /// - Returns: Array of TableRow
    static func fetchTableData(
        connection: PostgresConnection,
        schema: String,
        table: String,
        limit: Int,
        offset: Int
    ) async throws -> [TableRow] {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "SELECT * FROM \(qualifiedTable) LIMIT \(limit) OFFSET \(offset)"

        logger.debug("Fetching table data: \(qualifiedTable), limit: \(limit), offset: \(offset)")

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        let tableRows = try await ResultMapper.mapRowsToTableRows(rows)

        logger.info("Fetched \(tableRows.count) rows from \(qualifiedTable)")
        return tableRows
    }

    /// Helper to fetch column names for a table
    private static func fetchTableColumnNames(connection: PostgresConnection, schema: String, table: String) async throws -> [String] {
        let sql = """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = '\(schema)' AND table_name = '\(table)'
        ORDER BY ordinal_position
        """

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var columnNames: [String] = []

        for try await row in rows {
            let columnName = try row.decode(String.self)
            columnNames.append(columnName)
        }

        return columnNames
    }

    /// Drop a table
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - schema: Schema name
    ///   - table: Table name
    static func dropTable(connection: PostgresConnection, schema: String, table: String) async throws {
        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"
        let sql = "DROP TABLE \(qualifiedTable)"

        logger.info("Dropping table: \(qualifiedTable)")

        _ = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        logger.info("Table dropped successfully")
    }

    // MARK: - Column Metadata

    /// Fetch column information for a table
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - schema: Schema name
    ///   - table: Table name
    /// - Returns: Array of ColumnInfo
    static func fetchColumns(
        connection: PostgresConnection,
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

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var columns: [ColumnInfo] = []

        for try await row in rows {
            let column = try ResultMapper.mapToColumnInfo(row)
            columns.append(column)
        }

        logger.info("Fetched \(columns.count) columns for \(schema).\(table)")
        return columns
    }

    /// Fetch primary key columns for a table
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - schema: Schema name
    ///   - table: Table name
    /// - Returns: Array of primary key column names
    static func fetchPrimaryKeys(
        connection: PostgresConnection,
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

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var primaryKeys: [String] = []

        for try await row in rows {
            let pkColumn = try row.decode(String.self)
            primaryKeys.append(pkColumn)
        }

        logger.info("Found \(primaryKeys.count) primary key columns for \(schema).\(table)")
        return primaryKeys
    }

    // MARK: - Query Execution

    /// Execute arbitrary SQL query
    /// - Parameters:
    ///   - connection: Active PostgresConnection
    ///   - sql: SQL query string
    /// - Returns: Tuple of (rows, column names)
    static func executeQuery(connection: PostgresConnection, sql: String) async throws -> ([TableRow], [String]) {
        logger.info("Executing query: \(sql.prefix(100))...")

        let startTime = Date()

        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)

        var tableRows: [TableRow] = []
        var columnNames: [String] = []

        // Extract column names from the first row and map all rows
        for try await row in rows {
            // Get column names from the first row's cells
            if columnNames.isEmpty {
                columnNames = row.map { $0.columnName }
            }

            let tableRow = try ResultMapper.mapRowToTableRow(row)
            tableRows.append(tableRow)
        }

        let executionTime = Date().timeIntervalSince(startTime)
        logger.info("Query executed in \(String(format: "%.3f", executionTime))s, returned \(tableRows.count) rows")

        return (tableRows, columnNames)
    }

    /// Extract column names from a simple SELECT query
    /// Handles: SELECT col1, col2, col3 FROM table
    /// Does NOT handle: SELECT * (returns empty array)
    private static func extractColumnNamesFromSQL(_ sql: String) -> [String] {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        guard upper.hasPrefix("SELECT") else {
            return []
        }

        // Find SELECT and FROM positions
        guard let selectRange = upper.range(of: "SELECT"),
              let fromRange = upper.range(of: "FROM") else {
            return []
        }

        // Extract the column list between SELECT and FROM
        let startIndex = trimmed.index(selectRange.upperBound, offsetBy: 0)
        let endIndex = fromRange.lowerBound

        guard startIndex < endIndex else {
            return []
        }

        let columnsPart = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)

        // If it's SELECT *, we can't determine column names
        if columnsPart.trimmingCharacters(in: .whitespaces) == "*" {
            return []
        }

        // Split by comma and clean up column names
        let columns = columnsPart.split(separator: ",").map { column in
            var cleaned = String(column).trimmingCharacters(in: .whitespaces)

            // Handle "AS alias" - use the alias
            if let asRange = cleaned.uppercased().range(of: " AS ") {
                cleaned = String(cleaned[asRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            // Remove any table prefixes (table.column -> column)
            if let dotIndex = cleaned.lastIndex(of: ".") {
                cleaned = String(cleaned[cleaned.index(after: dotIndex)...])
            }

            return cleaned
        }

        return columns
    }

    // MARK: - Row Operations

    /// Update a row in a table
    static func updateRow(
        connection: PostgresConnection,
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

        // Build SET clause
        var setClauses: [String] = []
        for (column, value) in updatedValues {
            if let val = value {
                setClauses.append("\(sanitizeIdentifier(column)) = '\(val.replacingOccurrences(of: "'", with: "''"))'")
            } else {
                setClauses.append("\(sanitizeIdentifier(column)) = NULL")
            }
        }

        // Build WHERE clause based on primary keys
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

        _ = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        logger.info("Row updated successfully")
    }

    /// Delete rows from a table
    static func deleteRows(
        connection: PostgresConnection,
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }

        let qualifiedTable = "\(sanitizeIdentifier(schema)).\(sanitizeIdentifier(table))"

        // Delete one row at a time
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
            _ = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        }

        logger.info("Deleted \(rows.count) row(s) from \(qualifiedTable)")
    }

    // MARK: - Helpers

    /// Sanitize SQL identifier (table name, column name, etc.)
    /// Wraps identifier in quotes and escapes internal quotes
    /// - Parameter identifier: Raw identifier string
    /// - Returns: Sanitized identifier safe for SQL
    private static func sanitizeIdentifier(_ identifier: String) -> String {
        // Escape quotes by doubling them, then wrap in quotes
        let escaped = identifier.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

//
//  ResultMapper.swift
//  PostgresGUI
//
//  Transforms PostgresNIO types to app models
//

import Foundation
import PostgresNIO

/// Maps PostgresNIO result types to app models
enum ResultMapper {

    // MARK: - Row Mapping

    /// Map a PostgresRow to TableRow with known column names
    /// Extracts column values from PostgresRow cells
    /// - Parameters:
    ///   - row: The PostgresRow from PostgresNIO
    ///   - columnNames: Array of column names from the query (unused - we get them from row.columns)
    /// - Returns: A TableRow with String values
    static func mapRowToTableRow(_ row: PostgresRow, columnNames: [String]) throws -> TableRow {
        var values: [String: String?] = [:]

        // Iterate through all cells in the row
        for cell in row {
            let columnName = cell.columnName

            // Convert cell bytes to string representation
            if let bytes = cell.bytes {
                // Try to decode as String first
                if let stringValue = try? cell.decode(String.self, context: .default) {
                    values[columnName] = stringValue
                } else {
                    // For non-string types, get a string representation
                    values[columnName] = bytes.getString(at: bytes.readerIndex, length: bytes.readableBytes) ?? "(binary)"
                }
            } else {
                // NULL value
                values[columnName] = nil
            }
        }

        return TableRow(values: values)
    }

    /// Map a PostgresRowSequence to an array of TableRow
    /// - Parameters:
    ///   - rows: The PostgresRowSequence from a query
    ///   - columnNames: Array of column names (from SELECT clause)
    /// - Returns: Array of TableRow objects
    static func mapRowsToTableRows(_ rows: PostgresRowSequence, columnNames: [String]) async throws -> [TableRow] {
        var tableRows: [TableRow] = []

        for try await row in rows {
            let tableRow = try mapRowToTableRow(row, columnNames: columnNames)
            tableRows.append(tableRow)
        }

        return tableRows
    }

    // MARK: - Column Info Mapping

    /// Map information_schema column query result to ColumnInfo
    static func mapToColumnInfo(_ row: PostgresRow) throws -> ColumnInfo {
        // Use tuple decoding for known schema
        let (columnName, dataType, isNullableString, defaultValue) =
            try row.decode((String, String, String, String?).self)

        let isNullable = isNullableString.uppercased() == "YES"

        return ColumnInfo(
            name: columnName,
            dataType: dataType,
            isNullable: isNullable,
            defaultValue: defaultValue,
            isPrimaryKey: false,
            isUnique: false,
            isForeignKey: false
        )
    }

    // MARK: - Database Info Mapping

    /// Map database name from pg_database query to DatabaseInfo
    static func mapToDatabaseInfo(_ row: PostgresRow) throws -> DatabaseInfo {
        // Use tuple decoding
        let databaseName = try row.decode(String.self)
        return DatabaseInfo(name: databaseName)
    }

    // MARK: - Table Info Mapping

    /// Map table information from pg_tables query to TableInfo
    static func mapToTableInfo(_ row: PostgresRow) throws -> TableInfo {
        // Use tuple decoding for (schemaname, tablename)
        let (schemaName, tableName) = try row.decode((String, String).self)
        return TableInfo(name: tableName, schema: schemaName)
    }
}

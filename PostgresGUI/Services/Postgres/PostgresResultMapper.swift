//
//  PostgresResultMapper.swift
//  PostgresGUI
//
//  PostgresNIO-specific implementation of ResultMapperProtocol.
//  Maps PostgresNIO types to app domain models.
//

import Foundation
import PostgresNIO

/// PostgresNIO implementation of ResultMapperProtocol
struct PostgresResultMapper: ResultMapperProtocol {

    // MARK: - Initialization

    init() {}

    // MARK: - ResultMapperProtocol Implementation

    func mapRowToTableRow(_ row: any DatabaseRow) throws -> TableRow {
        // Convert abstract DatabaseRow to PostgresRow for decoding
        // This is a temporary bridge - ideally we'd work directly with DatabaseRow
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }

        return try mapPostgresRowToTableRow(postgresRow.row)
    }

    func mapRowsToTableRows(_ rows: any DatabaseRowSequence) async throws -> [TableRow] {
        var tableRows: [TableRow] = []

        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let tableRow = try mapRowToTableRow(dbRow)
            tableRows.append(tableRow)
        }

        return tableRows
    }

    func mapToColumnInfo(_ row: any DatabaseRow) throws -> ColumnInfo {
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }

        let (columnName, dataType, isNullableString, defaultValue) =
            try postgresRow.row.decode((String, String, String, String?).self)

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

    func mapToDatabaseInfo(_ row: any DatabaseRow) throws -> DatabaseInfo {
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }

        let databaseName = try postgresRow.row.decode(String.self)
        return DatabaseInfo(name: databaseName)
    }

    func mapToTableInfo(_ row: any DatabaseRow) throws -> TableInfo {
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }

        let (schemaName, tableName, tableTypeString) = try postgresRow.row.decode((String, String, String).self)
        let tableType = TableType(rawValue: tableTypeString) ?? .regular
        return TableInfo(name: tableName, schema: schemaName, tableType: tableType)
    }

    // MARK: - Private Helpers

    /// Map a PostgresRow to TableRow (internal helper)
    private func mapPostgresRowToTableRow(_ row: PostgresRow) throws -> TableRow {
        var values: [String: String?] = [:]

        for cell in row {
            let columnName = cell.columnName

            if cell.bytes != nil {
                values[columnName] = decodeRawCellValue(cell)
            } else {
                values[columnName] = nil
            }
        }

        return TableRow(values: values)
    }

    /// Decode a PostgresCell to its raw string representation.
    private func decodeRawCellValue(_ cell: PostgresCell) -> String? {
        if let stringValue = try? cell.decode(String.self, context: .default) {
            return stringValue
        }

        guard let bytes = cell.bytes else {
            return nil
        }

        let byteCount = bytes.readableBytes
        guard byteCount > 0, let byteArray = bytes.getBytes(at: 0, length: byteCount) else {
            return ""
        }

        return String(decoding: byteArray, as: UTF8.self)
    }
}

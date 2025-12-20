//
//  PostgresDatabaseConnection.swift
//  PostgresGUI
//
//  PostgresNIO-specific implementation of DatabaseConnectionProtocol
//

import Foundation
import PostgresNIO
import NIOCore
import NIOFoundationCompat
import Logging

/// PostgresNIO implementation of DatabaseConnectionProtocol
/// Wraps PostgresConnection to provide abstract interface
final class PostgresDatabaseConnection: DatabaseConnectionProtocol {
    private let connection: PostgresConnection
    private let logger: Logger
    
    nonisolated init(connection: PostgresConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
    }
    
    func executeQuery(_ sql: String) async throws -> any DatabaseRowSequence {
        let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        return PostgresDatabaseRowSequence(rows: rows)
    }

    func executeQuery(_ sql: String, parameters: [DatabaseParameter]) async throws -> any DatabaseRowSequence {
        // Convert abstract parameters to PostgresNIO bindings
        var bindings = PostgresBindings()
        for param in parameters {
            switch param.type {
            case .string:
                if let value = param.value as? String {
                    bindings.append(value)
                } else {
                    bindings.append(String?.none)
                }
            case .int:
                if let value = param.value as? Int {
                    bindings.append(value)
                } else if let value = param.value as? Int64 {
                    bindings.append(value)
                } else if let value = param.value as? Int32 {
                    bindings.append(value)
                } else {
                    bindings.append(Int?.none)
                }
            case .double:
                if let value = param.value as? Double {
                    bindings.append(value)
                } else if let value = param.value as? Float {
                    bindings.append(Double(value))
                } else {
                    bindings.append(Double?.none)
                }
            case .bool:
                if let value = param.value as? Bool {
                    bindings.append(value)
                } else {
                    bindings.append(Bool?.none)
                }
            case .data:
                if let value = param.value as? Data {
                    bindings.append(ByteBuffer(data: value))
                } else {
                    bindings.append(ByteBuffer?.none)
                }
            case .null:
                bindings.append(String?.none)
            }
        }

        let query = PostgresQuery(unsafeSQL: sql, binds: bindings)
        let rows = try await connection.query(query, logger: logger)
        return PostgresDatabaseRowSequence(rows: rows)
    }
}

/// PostgresNIO implementation of DatabaseRowSequence
struct PostgresDatabaseRowSequence: DatabaseRowSequence {
    typealias Element = any DatabaseRow
    typealias AsyncIterator = PostgresDatabaseRowIterator
    
    private let rows: PostgresRowSequence
    
    init(rows: PostgresRowSequence) {
        self.rows = rows
    }
    
    func makeAsyncIterator() -> PostgresDatabaseRowIterator {
        PostgresDatabaseRowIterator(rows: rows)
    }
}

struct PostgresDatabaseRowIterator: AsyncIteratorProtocol {
    typealias Element = any DatabaseRow
    
    private let rows: PostgresRowSequence
    private var iterator: PostgresRowSequence.AsyncIterator?
    
    init(rows: PostgresRowSequence) {
        self.rows = rows
        self.iterator = nil
    }
    
    mutating func next() async throws -> (any DatabaseRow)? {
        // Lazy initialization of iterator to avoid actor isolation issues
        if iterator == nil {
            iterator = rows.makeAsyncIterator()
        }
        
        guard var iter = iterator else {
            return nil
        }
        
        let nextRow = try await iter.next()
        iterator = iter
        
        guard let row = nextRow else {
            return nil
        }
        return PostgresDatabaseRow(row: row)
    }
}

/// PostgresNIO implementation of DatabaseRow
struct PostgresDatabaseRow: DatabaseRow {
    typealias Element = DatabaseCell
    typealias Iterator = PostgresDatabaseRowCellIterator

    /// The underlying PostgresNIO row
    /// - Important: This property is intended for use ONLY within the Postgres/ folder.
    ///   Code outside the Postgres implementation should use the DatabaseRow protocol methods.
    ///   Direct access to this property defeats the library-agnostic abstraction.
    internal let row: PostgresRow
    
    init(row: PostgresRow) {
        self.row = row
    }
    
    var columnNames: [String] {
        row.map { $0.columnName }
    }
    
    func cell(named: String) -> DatabaseCell? {
        for cell in row {
            if cell.columnName == named {
                return PostgresDatabaseCell(cell: cell)
            }
        }
        return nil
    }
    
    func decode<T>(_ type: T.Type, column: String) throws -> T where T: Decodable {
        // PostgresNIO's decode method doesn't take a column parameter the way we need
        // We'll use the cell-based approach instead
        guard let cell = cell(named: column) as? PostgresDatabaseCell else {
            throw DatabaseError.unknownError("Column \(column) not found")
        }
        return try cell.decode(type)
    }
    
    func makeIterator() -> PostgresDatabaseRowCellIterator {
        PostgresDatabaseRowCellIterator(row: row)
    }
}

struct PostgresDatabaseRowCellIterator: IteratorProtocol {
    typealias Element = DatabaseCell
    
    private var iterator: PostgresRow.Iterator
    
    init(row: PostgresRow) {
        self.iterator = row.makeIterator()
    }
    
    mutating func next() -> DatabaseCell? {
        guard let cell = iterator.next() else {
            return nil
        }
        return PostgresDatabaseCell(cell: cell)
    }
}

/// PostgresNIO implementation of DatabaseCell
struct PostgresDatabaseCell: DatabaseCell {
    private let cell: PostgresCell
    
    init(cell: PostgresCell) {
        self.cell = cell
    }
    
    var columnName: String {
        cell.columnName
    }
    
    var bytes: Data? {
        guard let bytes = cell.bytes else {
            return nil
        }
        return Data(buffer: bytes)
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        // PostgresNIO requires PostgresDecodable, but we need to support Decodable
        // For now, we'll try to decode as PostgresDecodable first, then fall back
        // This is a limitation of the abstraction - we may need to handle specific types
        if let postgresDecodableType = type as? any PostgresDecodable.Type {
            return try cell.decode(postgresDecodableType, context: .default) as! T
        }
        // For types that don't conform to PostgresDecodable, we'll need to handle them specially
        // For now, throw an error
        throw DatabaseError.unknownError("Type \(type) does not conform to PostgresDecodable")
    }
}


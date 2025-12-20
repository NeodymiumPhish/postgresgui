//
//  DatabaseConnectionProtocol.swift
//  PostgresGUI
//
//  Abstract protocol for database connections
//  Allows swapping between different PostgreSQL libraries
//

import Foundation

/// Abstract protocol representing a database connection
/// Implementations wrap library-specific connection types (e.g., PostgresConnection from PostgresNIO)
protocol DatabaseConnectionProtocol: AnyObject {
    /// Execute a SQL query and return results
    /// - Parameter sql: SQL query string
    /// - Returns: Async sequence of database rows
    func executeQuery(_ sql: String) async throws -> any DatabaseRowSequence
    
    /// Execute a SQL query with parameters
    /// - Parameters:
    ///   - sql: SQL query string
    ///   - parameters: Query parameters
    /// - Returns: Async sequence of database rows
    func executeQuery(_ sql: String, parameters: [DatabaseParameter]) async throws -> any DatabaseRowSequence
}

/// Abstract protocol representing a sequence of database rows
protocol DatabaseRowSequence: AsyncSequence where Element == any DatabaseRow {
}

/// Abstract protocol representing a single database row
protocol DatabaseRow: Sequence where Element == DatabaseCell {
    /// Get all column names in this row
    var columnNames: [String] { get }
    
    /// Get a cell by column name
    func cell(named: String) -> DatabaseCell?
    
    /// Decode a value from the row at a specific column
    func decode<T>(_ type: T.Type, column: String) throws -> T where T: Decodable
}

/// Abstract protocol representing a single cell in a database row
protocol DatabaseCell {
    /// Column name for this cell
    var columnName: String { get }
    
    /// Raw bytes of the cell value (nil if NULL)
    var bytes: Data? { get }
    
    /// Decode the cell value to a specific type
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable
}

/// Abstract type for query parameters
struct DatabaseParameter {
    let value: Any
    let type: DatabaseParameterType
    
    enum DatabaseParameterType {
        case string
        case int
        case double
        case bool
        case data
        case null
    }
}


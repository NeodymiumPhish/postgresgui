//
//  DatabaseServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol defining the interface for database operations
@MainActor
protocol DatabaseServiceProtocol: AnyObject {
    // MARK: - Connection State

    /// The currently connected database name, if any
    var connectedDatabase: String? { get }

    /// Disconnect from the current database
    func disconnect() async

    // MARK: - Query Execution

    /// Execute arbitrary SQL query and return results along with column names
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String])

    // MARK: - Row Operations

    /// Delete rows from a table using primary key values
    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws

    /// Update a row in a table using primary key values
    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: String?]
    ) async throws

    // MARK: - Metadata Operations

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String]

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo]
}

// MARK: - DatabaseService Conformance

extension DatabaseService: DatabaseServiceProtocol {
    // DatabaseService already implements all required methods
    // No additional implementation needed
}

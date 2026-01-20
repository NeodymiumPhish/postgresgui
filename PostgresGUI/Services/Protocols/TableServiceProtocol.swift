//
//  TableServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol for table operations
@MainActor
protocol TableServiceProtocol {
    /// Fetch list of tables in the connected database
    func fetchTables(database: String) async throws -> [TableInfo]

    /// Fetch list of schemas in the connected database
    func fetchSchemas(database: String) async throws -> [String]

    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow]

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws

    /// Truncate a table (delete all rows)
    func truncateTable(schema: String, table: String) async throws

    /// Generate DDL (CREATE TABLE statement) for a table
    func generateDDL(schema: String, table: String) async throws -> String

    /// Fetch all table data (no pagination, for export)
    func fetchAllTableData(schema: String, table: String) async throws -> ([TableRow], [String])
}

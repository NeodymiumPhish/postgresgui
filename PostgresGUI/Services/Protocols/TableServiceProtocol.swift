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

    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow]

    /// Delete a table
    func deleteTable(schema: String, table: String) async throws
}

//
//  MetadataServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol for database metadata operations
@MainActor
protocol MetadataServiceProtocol {
    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo]

    /// Fetch primary key columns for a table
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String]

    /// Fetch column information for a table
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo]
}

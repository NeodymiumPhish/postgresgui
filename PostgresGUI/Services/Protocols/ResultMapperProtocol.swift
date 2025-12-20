//
//  ResultMapperProtocol.swift
//  PostgresGUI
//
//  Abstract protocol for mapping database results to app models
//  Allows swapping between different PostgreSQL libraries
//

import Foundation

/// Protocol defining result mapping operations
/// Implementations convert library-specific row types to app models
protocol ResultMapperProtocol {
    /// Map a database row to TableRow
    func mapRowToTableRow(_ row: any DatabaseRow) throws -> TableRow
    
    /// Map a sequence of database rows to TableRow array
    func mapRowsToTableRows(_ rows: any DatabaseRowSequence) async throws -> [TableRow]
    
    /// Map a database row to ColumnInfo
    func mapToColumnInfo(_ row: any DatabaseRow) throws -> ColumnInfo
    
    /// Map a database row to DatabaseInfo
    func mapToDatabaseInfo(_ row: any DatabaseRow) throws -> DatabaseInfo
    
    /// Map a database row to TableInfo
    func mapToTableInfo(_ row: any DatabaseRow) throws -> TableInfo
}


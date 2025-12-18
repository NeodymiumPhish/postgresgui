//
//  DatabaseManagementServiceProtocol.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Protocol for database management operations (create/delete databases)
@MainActor
protocol DatabaseManagementServiceProtocol {
    /// Create a new database
    func createDatabase(name: String) async throws

    /// Delete a database
    func deleteDatabase(name: String) async throws
}

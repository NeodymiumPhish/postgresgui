//
//  DatabaseService.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

@MainActor
class DatabaseService {
    // Mock connection state
    private var isConnectedState: Bool = false
    private var currentDatabase: String?
    
    // Mock data storage
    private var mockDatabases: [DatabaseInfo] = MockDatabaseData.databases
    private var mockTables: [String: [TableInfo]] = MockDatabaseData.tables
    private var mockTableData: [String: [TableRow]] = [:]
    
    var isConnected: Bool {
        isConnectedState
    }

    init() {
        // Initialize mock table data
        mockTableData = MockDatabaseData.initializeTableData()
    }
    
    /// Connect to PostgreSQL database (mock - always succeeds)
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws {
        // Simulate connection delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Validate inputs
        guard !host.isEmpty else {
            throw ConnectionError.invalidHost(host)
        }

        guard port > 0 && port <= 65535 else {
            throw ConnectionError.invalidPort
        }
        
        // Mock connection - always succeeds
        isConnectedState = true
        currentDatabase = database
    }
    
    /// Disconnect from database
    func disconnect() async {
        isConnectedState = false
        currentDatabase = nil
    }
    
    /// Test connection without saving (static method - doesn't require instance)
    nonisolated static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        sslMode: SSLMode = .default
    ) async throws -> Bool {
        // Simulate connection test delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Mock test - always succeeds
        return true
    }
    
    /// Fetch list of databases (mock data)
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        return mockDatabases
    }
    
    /// Fetch list of tables in a database (mock data)
    func fetchTables(database: String) async throws -> [TableInfo] {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        return mockTables[database] ?? []
    }
    
    /// Fetch table data with pagination (mock data)
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow] {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        let key = "\(schema).\(table)"
        let allRows = mockTableData[key] ?? []
        
        // Apply pagination
        let endIndex = min(offset + limit, allRows.count)
        guard offset < allRows.count else {
            return []
        }
        
        return Array(allRows[offset..<endIndex])
    }

    /// Execute arbitrary SQL query and return results along with column names (mock data)
    func executeQuery(_ sql: String) async throws -> ([TableRow], [String]) {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate query execution delay
        try await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        let upperSQL = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Mock SELECT queries
        if upperSQL.hasPrefix("SELECT") {
            // Try to match against known tables
            for (key, rows) in mockTableData {
                if upperSQL.contains(key.uppercased().replacingOccurrences(of: ".", with: " ")) {
                    // Extract column names from first row
                    if let firstRow = rows.first {
                        let columnNames = Array(firstRow.values.keys).sorted()
                        return (rows, columnNames)
                    }
                }
            }
            
            // Default mock query result
            let mockRows = [
                TableRow(values: ["id": "1", "name": "Sample", "value": "100"]),
                TableRow(values: ["id": "2", "name": "Test", "value": "200"]),
                TableRow(values: ["id": "3", "name": "Demo", "value": "300"])
            ]
            return (mockRows, ["id", "name", "value"])
        }
        
        // For non-SELECT queries, return empty result
        return ([], [])
    }
    
    /// Delete a database (mock - just removes from list)
    func deleteDatabase(name: String) async throws {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        mockDatabases.removeAll { $0.name == name }
        mockTables.removeValue(forKey: name)
        
        // If we deleted the current database, disconnect
        if currentDatabase == name {
            await disconnect()
        }
    }
    
    /// Create a new database (mock - adds to list)
    func createDatabase(name: String) async throws {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Check if database already exists
        if mockDatabases.contains(where: { $0.name == name }) {
            throw ConnectionError.databaseNotFound(name) // Reuse error for "already exists"
        }
        
        mockDatabases.append(DatabaseInfo(name: name))
        mockTables[name] = []
    }
    
    /// Delete a table (mock - removes from list)
    func deleteTable(schema: String, table: String) async throws {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        guard let database = currentDatabase,
              var tables = mockTables[database] else {
            throw ConnectionError.notConnected
        }
        
        tables.removeAll { $0.name == table && $0.schema == schema }
        mockTables[database] = tables
        
        // Remove table data
        let key = "\(schema).\(table)"
        mockTableData.removeValue(forKey: key)
    }

    /// Fetch primary key columns for a table (mock - returns "id" for most tables)
    func fetchPrimaryKeyColumns(schema: String, table: String) async throws -> [String] {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Most tables have "id" as primary key
        return ["id"]
    }

    /// Fetch column information for a table (mock data)
    func fetchColumnInfo(schema: String, table: String) async throws -> [ColumnInfo] {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        let key = "\(schema).\(table)"
        guard let firstRow = mockTableData[key]?.first else {
            return []
        }
        
        // Generate column info from first row
        var columns: [ColumnInfo] = []
        for (columnName, value) in firstRow.values.sorted(by: { $0.key < $1.key }) {
            let isNullable = value == nil
            let dataType: String
            if columnName.lowercased().contains("id") {
                dataType = "integer"
            } else if columnName.lowercased().contains("email") || columnName.lowercased().contains("name") {
                dataType = "character varying"
            } else if columnName.lowercased().contains("price") || columnName.lowercased().contains("amount") || columnName.lowercased().contains("salary") {
                dataType = "numeric"
            } else if columnName.lowercased().contains("date") || columnName.lowercased().contains("created") {
                dataType = "timestamp"
            } else if columnName.lowercased().contains("active") {
                dataType = "boolean"
            } else {
                dataType = "text"
            }
            
            columns.append(ColumnInfo(
                name: columnName,
                dataType: dataType,
                isNullable: isNullable,
                defaultValue: nil
            ))
        }
        
        return columns
    }

    /// Delete rows from a table using primary key values (mock - removes from data)
    func deleteRows(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        rows: [TableRow]
    ) async throws {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }
        
        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        let key = "\(schema).\(table)"
        guard var tableRows = mockTableData[key] else {
            return
        }
        
        // Remove rows matching primary keys
        for rowToDelete in rows {
            if let pkValue = rowToDelete.values[primaryKeyColumns[0]] {
                tableRows.removeAll { existingRow in
                    existingRow.values[primaryKeyColumns[0]] == pkValue
                }
            }
        }
        
        mockTableData[key] = tableRows
    }

    /// Update a row in a table using primary key values (mock - updates in-memory data)
    func updateRow(
        schema: String,
        table: String,
        primaryKeyColumns: [String],
        originalRow: TableRow,
        updatedValues: [String: String?]
    ) async throws {
        guard isConnectedState else {
            throw ConnectionError.notConnected
        }

        guard !primaryKeyColumns.isEmpty else {
            throw DatabaseError.noPrimaryKey
        }
        
        // Simulate delay
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        let key = "\(schema).\(table)"
        guard var tableRows = mockTableData[key] else {
            return
        }
        
        // Find and update the row
        guard let pkValue = originalRow.values[primaryKeyColumns[0]] else {
            throw DatabaseError.missingPrimaryKeyValue(column: primaryKeyColumns[0])
        }
        
        if let index = tableRows.firstIndex(where: { $0.values[primaryKeyColumns[0]] == pkValue }) {
            var updatedRow = tableRows[index]
            var newValues = updatedRow.values
            for (column, newValue) in updatedValues {
                newValues[column] = newValue
            }
            updatedRow = TableRow(values: newValues)
            tableRows[index] = updatedRow
            mockTableData[key] = tableRows
        }
    }
}

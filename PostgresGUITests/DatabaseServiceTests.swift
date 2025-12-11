//
//  DatabaseServiceTests.swift
//  PostgresGUITests
//
//  Created by ghazi
//

import Foundation
import Testing
@testable import PostgresGUI

/// Tests for DatabaseService
@MainActor
struct DatabaseServiceTests {
    
    // MARK: - Connection Tests
    
    @Test("Connect with valid parameters succeeds")
    func testConnectWithValidParameters() async throws {
        // Arrange
        let service = DatabaseService()
        let host = "localhost"
        let port = 5432
        let username = "testuser"
        let password = "testpass"
        let database = "testdb"
        
        // Act
        try await service.connect(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database
        )
        
        // Assert
        #expect(service.isConnected == true)
    }
    
    @Test("Connect with empty host throws error")
    func testConnectWithEmptyHost() async {
        // Arrange
        let service = DatabaseService()
        
        // Act & Assert
        await #expect(throws: ConnectionError.self) {
            try await service.connect(
                host: "",
                port: 5432,
                username: "user",
                password: "pass",
                database: "db"
            )
        }
    }
    
    @Test("Connect with invalid port throws error")
    func testConnectWithInvalidPort() async {
        // Arrange
        let service = DatabaseService()
        
        // Act & Assert
        await #expect(throws: ConnectionError.self) {
            try await service.connect(
                host: "localhost",
                port: 0,
                username: "user",
                password: "pass",
                database: "db"
            )
        }
    }
    
    @Test("Connect with port out of range throws error")
    func testConnectWithPortOutOfRange() async {
        // Arrange
        let service = DatabaseService()
        
        // Act & Assert
        await #expect(throws: ConnectionError.self) {
            try await service.connect(
                host: "localhost",
                port: 65536,
                username: "user",
                password: "pass",
                database: "db"
            )
        }
    }
    
    @Test("Disconnect clears connection state")
    func testDisconnect() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "db"
        )
        #expect(service.isConnected == true)
        
        // Act
        await service.disconnect()
        
        // Assert
        #expect(service.isConnected == false)
    }
    
    @Test("Test connection static method succeeds")
    func testTestConnection() async throws {
        // Act
        let result = try await DatabaseService.testConnection(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "db"
        )
        
        // Assert
        #expect(result == true)
    }
    
    // MARK: - Database Operations Tests
    
    @Test("Fetch databases when connected returns mock databases")
    func testFetchDatabasesWhenConnected() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        
        // Act
        let databases = try await service.fetchDatabases()
        
        // Assert
        #expect(databases.count > 0)
        #expect(databases.contains(where: { $0.name == "postgres" }))
    }
    
    @Test("Fetch databases when not connected throws error")
    func testFetchDatabasesWhenNotConnected() async {
        // Arrange
        let service = DatabaseService()
        
        // Act & Assert
        await #expect(throws: ConnectionError.self) {
            try await service.fetchDatabases()
        }
    }
    
    @Test("Fetch tables for database returns mock tables")
    func testFetchTables() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        
        // Act
        let tables = try await service.fetchTables(database: "postgres")
        
        // Assert
        #expect(tables.count > 0)
        #expect(tables.contains(where: { $0.name == "users" }))
    }
    
    @Test("Fetch tables for non-existent database returns empty array")
    func testFetchTablesForNonExistentDatabase() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        
        // Act
        let tables = try await service.fetchTables(database: "nonexistent")
        
        // Assert
        #expect(tables.isEmpty)
    }
    
    // MARK: - Table Data Tests
    
    @Test("Fetch table data with pagination returns correct subset")
    func testFetchTableDataWithPagination() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        
        // Act
        let rows = try await service.fetchTableData(
            schema: "public",
            table: "users",
            offset: 0,
            limit: 2
        )
        
        // Assert
        #expect(rows.count <= 2)
    }
    
    @Test("Fetch table data with offset beyond data returns empty array")
    func testFetchTableDataWithOffsetBeyondData() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        
        // Act
        let rows = try await service.fetchTableData(
            schema: "public",
            table: "users",
            offset: 1000,
            limit: 10
        )
        
        // Assert
        #expect(rows.isEmpty)
    }
    
    // MARK: - Query Execution Tests
    
    @Test("Execute query when connected returns results")
    func testExecuteQuery() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        
        // Act
        let (_, columns) = try await service.executeQuery("SELECT * FROM users")
        
        // Assert
        #expect(!columns.isEmpty)
    }
    
    @Test("Execute query when not connected throws error")
    func testExecuteQueryWhenNotConnected() async {
        // Arrange
        let service = DatabaseService()
        
        // Act & Assert
        await #expect(throws: ConnectionError.self) {
            try await service.executeQuery("SELECT * FROM users")
        }
    }
    
    // MARK: - Database Management Tests
    
    @Test("Create database adds to list")
    func testCreateDatabase() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        let newDbName = "new_database_\(UUID().uuidString)"
        
        // Act
        try await service.createDatabase(name: newDbName)
        let databases = try await service.fetchDatabases()
        
        // Assert
        #expect(databases.contains(where: { $0.name == newDbName }))
    }
    
    @Test("Delete database removes from list")
    func testDeleteDatabase() async throws {
        // Arrange
        let service = DatabaseService()
        try await service.connect(
            host: "localhost",
            port: 5432,
            username: "user",
            password: "pass",
            database: "postgres"
        )
        let dbName = "testdb"
        
        // Act
        try await service.deleteDatabase(name: dbName)
        let databases = try await service.fetchDatabases()
        
        // Assert
        #expect(!databases.contains(where: { $0.name == dbName }))
    }
}

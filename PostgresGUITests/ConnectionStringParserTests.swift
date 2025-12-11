//
//  ConnectionStringParserTests.swift
//  PostgresGUITests
//
//  Created by ghazi
//

import Testing
@testable import PostgresGUI

/// Tests for ConnectionStringParser utility
struct ConnectionStringParserTests {
    
    // MARK: - Parsing Tests
    
    @Test("Parse valid connection string with all components")
    func testParseValidConnectionStringWithAllComponents() throws {
        // Arrange
        let connectionString = "postgresql://user:password@localhost:5432/mydb?sslmode=require"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.scheme == "postgresql")
        #expect(parsed.username == "user")
        #expect(parsed.password == "password")
        #expect(parsed.host == "localhost")
        #expect(parsed.port == 5432)
        #expect(parsed.database == "mydb")
        #expect(parsed.sslMode == .require)
    }
    
    @Test("Parse connection string with minimal components")
    func testParseMinimalConnectionString() throws {
        // Arrange
        let connectionString = "postgresql://localhost"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.host == "localhost")
        #expect(parsed.port == Constants.PostgreSQL.defaultPort)
        #expect(parsed.username == nil)
        #expect(parsed.password == nil)
        #expect(parsed.database == nil)
        #expect(parsed.sslMode == .default)
    }
    
    @Test("Parse connection string with postgres scheme")
    func testParsePostgresScheme() throws {
        // Arrange
        let connectionString = "postgres://user@localhost:5432/db"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.scheme == "postgres")
        #expect(parsed.host == "localhost")
    }
    
    @Test("Parse connection string with custom port")
    func testParseCustomPort() throws {
        // Arrange
        let connectionString = "postgresql://localhost:5433"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.port == 5433)
    }
    
    @Test("Parse connection string with SSL mode in query")
    func testParseSSLModeFromQuery() throws {
        // Arrange
        let connectionString = "postgresql://localhost?sslmode=verify-full"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.sslMode == .verifyFull)
    }
    
    @Test("Parse connection string with special characters in password")
    func testParsePasswordWithSpecialCharacters() throws {
        // Arrange
        let connectionString = "postgresql://user:p@ssw0rd@localhost/db"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.username == "user")
        #expect(parsed.password == "p@ssw0rd")
    }
    
    @Test("Parse connection string with query parameters")
    func testParseQueryParameters() throws {
        // Arrange
        let connectionString = "postgresql://localhost?param1=value1&param2=value2"
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.queryParameters["param1"] == "value1")
        #expect(parsed.queryParameters["param2"] == "value2")
    }
    
    @Test("Parse connection string trims whitespace")
    func testParseTrimsWhitespace() throws {
        // Arrange
        let connectionString = "  postgresql://localhost  "
        
        // Act
        let parsed = try ConnectionStringParser.parse(connectionString)
        
        // Assert
        #expect(parsed.host == "localhost")
    }
    
    // MARK: - Error Cases
    
    @Test("Parse empty string throws error")
    func testParseEmptyStringThrowsError() {
        // Arrange
        let connectionString = ""
        
        // Act & Assert
        #expect(throws: ConnectionStringParser.ParseError.invalidFormat) {
            try ConnectionStringParser.parse(connectionString)
        }
    }
    
    @Test("Parse invalid scheme throws error")
    func testParseInvalidSchemeThrowsError() {
        // Arrange
        let connectionString = "http://localhost"
        
        // Act & Assert
        #expect(throws: ConnectionStringParser.ParseError.invalidScheme) {
            try ConnectionStringParser.parse(connectionString)
        }
    }
    
    @Test("Parse missing host throws error")
    func testParseMissingHostThrowsError() {
        // Arrange
        let connectionString = "postgresql://"
        
        // Act & Assert
        #expect(throws: ConnectionStringParser.ParseError.emptyHost) {
            try ConnectionStringParser.parse(connectionString)
        }
    }
    
    @Test("Parse invalid port throws error")
    func testParseInvalidPortThrowsError() {
        // Arrange
        let connectionString = "postgresql://localhost:99999"
        
        // Act & Assert
        #expect(throws: ConnectionStringParser.ParseError.invalidPort) {
            try ConnectionStringParser.parse(connectionString)
        }
    }
    
    @Test("Parse zero port throws error")
    func testParseZeroPortThrowsError() {
        // Arrange
        let connectionString = "postgresql://localhost:0"
        
        // Act & Assert
        #expect(throws: ConnectionStringParser.ParseError.invalidPort) {
            try ConnectionStringParser.parse(connectionString)
        }
    }
    
    // MARK: - Building Tests
    
    @Test("Build connection string with all components")
    func testBuildConnectionStringWithAllComponents() {
        // Arrange
        let username = "user"
        let password = "password"
        let host = "localhost"
        let port = 5432
        let database = "mydb"
        let sslMode = SSLMode.require
        
        // Act
        let result = ConnectionStringParser.build(
            username: username,
            password: password,
            host: host,
            port: port,
            database: database,
            sslMode: sslMode
        )
        
        // Assert
        #expect(result.contains("postgresql://"))
        #expect(result.contains("user:password@"))
        #expect(result.contains("localhost"))
        #expect(result.contains("/mydb"))
        #expect(result.contains("sslmode=require"))
    }
    
    @Test("Build connection string with minimal components")
    func testBuildMinimalConnectionString() {
        // Arrange
        let host = "localhost"
        let port = Constants.PostgreSQL.defaultPort
        
        // Act
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: host,
            port: port,
            database: nil,
            sslMode: .default
        )
        
        // Assert
        #expect(result == "postgresql://localhost")
    }
    
    @Test("Build connection string omits default port")
    func testBuildOmitsDefaultPort() {
        // Arrange
        let host = "localhost"
        let port = Constants.PostgreSQL.defaultPort
        
        // Act
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: host,
            port: port,
            database: nil,
            sslMode: .default
        )
        
        // Assert
        #expect(!result.contains(":5432"))
    }
    
    @Test("Build connection string includes non-default port")
    func testBuildIncludesNonDefaultPort() {
        // Arrange
        let host = "localhost"
        let port = 5433
        
        // Act
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: host,
            port: port,
            database: nil,
            sslMode: .default
        )
        
        // Assert
        #expect(result.contains(":5433"))
    }
    
    @Test("Build connection string omits default SSL mode")
    func testBuildOmitsDefaultSSLMode() {
        // Arrange
        let host = "localhost"
        
        // Act
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: host,
            port: Constants.PostgreSQL.defaultPort,
            database: nil,
            sslMode: .default
        )
        
        // Assert
        #expect(!result.contains("sslmode"))
    }
    
    @Test("Build connection string includes non-default SSL mode")
    func testBuildIncludesNonDefaultSSLMode() {
        // Arrange
        let host = "localhost"
        
        // Act
        let result = ConnectionStringParser.build(
            username: nil,
            password: nil,
            host: host,
            port: Constants.PostgreSQL.defaultPort,
            database: nil,
            sslMode: .require
        )
        
        // Assert
        #expect(result.contains("sslmode=require"))
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Parse and build round-trip preserves essential components")
    func testParseAndBuildRoundTrip() throws {
        // Arrange
        let original = "postgresql://user:password@localhost:5432/mydb?sslmode=require"
        
        // Act
        let parsed = try ConnectionStringParser.parse(original)
        let rebuilt = ConnectionStringParser.build(
            username: parsed.username,
            password: parsed.password,
            host: parsed.host,
            port: parsed.port,
            database: parsed.database,
            sslMode: parsed.sslMode
        )
        let reparsed = try ConnectionStringParser.parse(rebuilt)
        
        // Assert
        #expect(reparsed.host == parsed.host)
        #expect(reparsed.port == parsed.port)
        #expect(reparsed.username == parsed.username)
        #expect(reparsed.password == parsed.password)
        #expect(reparsed.database == parsed.database)
        #expect(reparsed.sslMode == parsed.sslMode)
    }
}

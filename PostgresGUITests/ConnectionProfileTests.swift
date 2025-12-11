//
//  ConnectionProfileTests.swift
//  PostgresGUITests
//
//  Created by ghazi
//

import Testing
@testable import PostgresGUI

/// Tests for ConnectionProfile model
struct ConnectionProfileTests {
    
    @Test("ConnectionProfile initializes with required parameters")
    func testConnectionProfileInitialization() {
        // Arrange & Act
        let profile = ConnectionProfile(
            name: "Test Connection",
            host: "localhost",
            username: "testuser"
        )
        
        // Assert
        #expect(profile.name == "Test Connection")
        #expect(profile.host == "localhost")
        #expect(profile.username == "testuser")
        #expect(profile.port == Constants.PostgreSQL.defaultPort)
        #expect(profile.database == Constants.PostgreSQL.defaultDatabase)
        #expect(profile.isFavorite == false)
    }
    
    @Test("ConnectionProfile uses default values")
    func testConnectionProfileDefaults() {
        // Arrange & Act
        let profile = ConnectionProfile(
            name: "Test",
            host: "localhost",
            username: "user"
        )
        
        // Assert
        #expect(profile.port == Constants.PostgreSQL.defaultPort)
        #expect(profile.database == Constants.PostgreSQL.defaultDatabase)
        #expect(profile.sslModeEnum == .default)
    }
    
    @Test("ConnectionProfile localhost factory creates correct profile")
    func testConnectionProfileLocalhost() {
        // Act
        let profile = ConnectionProfile.localhost()
        
        // Assert
        #expect(profile.name == "localhost")
        #expect(profile.host == "localhost")
        #expect(profile.port == Constants.PostgreSQL.defaultPort)
        #expect(profile.username == Constants.PostgreSQL.defaultUsername)
        #expect(profile.database == Constants.PostgreSQL.defaultDatabase)
    }
    
    @Test("ConnectionProfile sslModeEnum returns correct enum")
    func testConnectionProfileSSLModeEnum() {
        // Arrange
        let profile = ConnectionProfile(
            name: "Test",
            host: "localhost",
            username: "user",
            sslMode: .require
        )
        
        // Act & Assert
        #expect(profile.sslModeEnum == .require)
    }
    
    @Test("ConnectionProfile sslModeEnum handles invalid raw value")
    func testConnectionProfileSSLModeEnumInvalidValue() {
        // Arrange
        let profile = ConnectionProfile(
            name: "Test",
            host: "localhost",
            username: "user"
        )
        // Manually set invalid SSL mode
        profile.sslMode = "invalid"
        
        // Act & Assert
        #expect(profile.sslModeEnum == .default)
    }
    
    @Test("ConnectionProfile from connection string parses correctly")
    func testConnectionProfileFromConnectionString() throws {
        // Arrange
        let connectionString = "postgresql://user:password@localhost:5432/mydb?sslmode=require"
        
        // Act
        let (profile, password) = try ConnectionProfile.from(
            connectionString: connectionString,
            name: "Parsed Connection"
        )
        
        // Assert
        #expect(profile.host == "localhost")
        #expect(profile.port == 5432)
        #expect(profile.username == "user")
        #expect(profile.database == "mydb")
        #expect(profile.sslModeEnum == .require)
        #expect(password == "password")
    }
    
    @Test("ConnectionProfile from invalid connection string throws error")
    func testConnectionProfileFromInvalidConnectionString() {
        // Arrange
        let connectionString = "invalid://connection"
        
        // Act & Assert
        #expect(throws: ConnectionStringParser.ParseError.self) {
            try ConnectionProfile.from(
                connectionString: connectionString,
                name: "Invalid"
            )
        }
    }
    
    @Test("ConnectionProfile toConnectionString builds correctly")
    func testConnectionProfileToConnectionString() {
        // Arrange
        let profile = ConnectionProfile(
            name: "Test",
            host: "localhost",
            port: 5432,
            username: "user",
            database: "mydb",
            sslMode: .require
        )
        
        // Act
        let connectionString = profile.toConnectionString()
        
        // Assert
        #expect(connectionString.contains("postgresql://"))
        #expect(connectionString.contains("user@"))
        #expect(connectionString.contains("localhost"))
        #expect(connectionString.contains("/mydb"))
        #expect(connectionString.contains("sslmode=require"))
    }
}

//
//  ErrorTests.swift
//  PostgresGUITests
//
//  Created by ghazi
//

import Testing
@testable import PostgresGUI

/// Tests for error types
struct ErrorTests {
    
    // MARK: - ConnectionError Tests
    
    @Test("ConnectionError invalidHost has correct description")
    func testConnectionErrorInvalidHost() {
        // Arrange
        let error = ConnectionError.invalidHost("")
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description?.contains("Invalid host") == true)
    }
    
    @Test("ConnectionError invalidPort has correct description")
    func testConnectionErrorInvalidPort() {
        // Arrange
        let error = ConnectionError.invalidPort
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description == "Invalid port number")
    }
    
    @Test("ConnectionError notConnected has correct description")
    func testConnectionErrorNotConnected() {
        // Arrange
        let error = ConnectionError.notConnected
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description == "Not connected to database.")
    }
    
    @Test("ConnectionError has recovery suggestions")
    func testConnectionErrorRecoverySuggestions() {
        // Arrange
        let error = ConnectionError.invalidPort
        
        // Act
        let suggestion = error.recoverySuggestion
        
        // Assert
        #expect(suggestion != nil)
        #expect(suggestion?.isEmpty == false)
    }
    
    // MARK: - DatabaseError Tests
    
    @Test("DatabaseError noPrimaryKey has correct description")
    func testDatabaseErrorNoPrimaryKey() {
        // Arrange
        let error = DatabaseError.noPrimaryKey
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description?.contains("no primary key") == true)
    }
    
    @Test("DatabaseError missingPrimaryKeyValue has correct description")
    func testDatabaseErrorMissingPrimaryKeyValue() {
        // Arrange
        let error = DatabaseError.missingPrimaryKeyValue(column: "id")
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description?.contains("id") == true)
        #expect(description?.contains("Missing primary key value") == true)
    }
    
    // MARK: - KeychainError Tests
    
    @Test("KeychainError saveFailed has correct description")
    func testKeychainErrorSaveFailed() {
        // Arrange
        let error = KeychainError.saveFailed(12345)
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description?.contains("Failed to save password") == true)
        #expect(description?.contains("12345") == true)
    }
    
    @Test("KeychainError invalidData has correct description")
    func testKeychainErrorInvalidData() {
        // Arrange
        let error = KeychainError.invalidData
        
        // Act
        let description = error.errorDescription
        
        // Assert
        #expect(description == "Invalid password data in Keychain")
    }
}

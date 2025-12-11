//
//  PostgresGUITests.swift
//  PostgresGUITests
//
//  Created by ghazi on 11/28/25.
//

import Testing
@testable import PostgresGUI

/// Main test suite for PostgresGUI
/// 
/// This file serves as the entry point for all unit tests.
/// Individual test suites are organized in separate files:
/// - ConnectionStringParserTests.swift - Tests for connection string parsing and building
/// - SSLModeTests.swift - Tests for SSL mode enum
/// - DatabaseServiceTests.swift - Tests for database service operations
/// - ConnectionProfileTests.swift - Tests for connection profile model
/// - ErrorTests.swift - Tests for error types
struct PostgresGUITests {
    
    @Test("Test suite is properly configured")
    func testSuiteConfiguration() {
        // This test verifies the test suite is set up correctly
        #expect(true)
    }
}

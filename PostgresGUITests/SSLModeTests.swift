//
//  SSLModeTests.swift
//  PostgresGUITests
//
//  Created by ghazi
//

import Testing
@testable import PostgresGUI

/// Tests for SSLMode enum
struct SSLModeTests {
    
    @Test("SSLMode has correct raw values")
    func testSSLModeRawValues() {
        // Assert
        #expect(SSLMode.disable.rawValue == "disable")
        #expect(SSLMode.allow.rawValue == "allow")
        #expect(SSLMode.prefer.rawValue == "prefer")
        #expect(SSLMode.require.rawValue == "require")
        #expect(SSLMode.verifyCA.rawValue == "verify-ca")
        #expect(SSLMode.verifyFull.rawValue == "verify-full")
    }
    
    @Test("SSLMode can be initialized from raw value")
    func testSSLModeFromRawValue() {
        // Act & Assert
        #expect(SSLMode(rawValue: "disable") == .disable)
        #expect(SSLMode(rawValue: "allow") == .allow)
        #expect(SSLMode(rawValue: "prefer") == .prefer)
        #expect(SSLMode(rawValue: "require") == .require)
        #expect(SSLMode(rawValue: "verify-ca") == .verifyCA)
        #expect(SSLMode(rawValue: "verify-full") == .verifyFull)
    }
    
    @Test("SSLMode returns nil for invalid raw value")
    func testSSLModeInvalidRawValue() {
        // Act & Assert
        #expect(SSLMode(rawValue: "invalid") == nil)
        #expect(SSLMode(rawValue: "") == nil)
    }
    
    @Test("SSLMode default is prefer")
    func testSSLModeDefault() {
        // Assert
        #expect(SSLMode.default == .prefer)
    }
}

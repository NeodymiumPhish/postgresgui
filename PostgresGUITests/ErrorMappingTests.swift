//
//  ErrorMappingTests.swift
//  PostgresGUITests
//
//  Unit tests for error mapping and error descriptions.
//

import Foundation
import Testing
@testable import PostgresGUI

// MARK: - ConnectionError Tests

@Suite("ConnectionError")
struct ConnectionErrorTests {

    @Suite("Error Descriptions")
    struct ErrorDescriptionTests {

        @Test func invalidHostHasDescription() {
            let error = ConnectionError.invalidHost("bad-host")
            #expect(error.errorDescription?.contains("bad-host") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func invalidPortHasDescription() {
            let error = ConnectionError.invalidPort
            #expect(error.errorDescription != nil)
            #expect(error.recoverySuggestion?.contains("65535") == true)
        }

        @Test func authenticationFailedHasDescription() {
            let error = ConnectionError.authenticationFailed
            #expect(error.errorDescription?.lowercased().contains("authentication") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func databaseNotFoundHasDescription() {
            let error = ConnectionError.databaseNotFound("mydb")
            #expect(error.errorDescription?.contains("mydb") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func timeoutHasDescription() {
            let error = ConnectionError.timeout
            #expect(error.errorDescription?.lowercased().contains("timeout") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func networkUnreachableHasDescription() {
            let error = ConnectionError.networkUnreachable
            #expect(error.errorDescription?.lowercased().contains("network") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func notConnectedHasDescription() {
            let error = ConnectionError.notConnected
            #expect(error.errorDescription?.lowercased().contains("not connected") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func connectionCancelledHasDescription() {
            let error = ConnectionError.connectionCancelled
            #expect(error.errorDescription != nil)
            // No recovery suggestion for cancelled
            #expect(error.recoverySuggestion == nil)
        }

        @Test func sslContextCreationFailedHasDescription() {
            let error = ConnectionError.sslContextCreationFailed("cert error")
            #expect(error.errorDescription?.contains("SSL") == true || error.errorDescription?.contains("TLS") == true)
            #expect(error.errorDescription?.contains("cert error") == true)
            #expect(error.recoverySuggestion != nil)
        }

        @Test func unknownErrorWrapsUnderlying() {
            let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test failure"])
            let error = ConnectionError.unknownError(underlying)
            #expect(error.errorDescription?.contains("Connection failed") == true)
        }

        @Test func invalidConnectionStringHasDescription() {
            let parseError = ConnectionStringParser.ParseError.invalidFormat
            let error = ConnectionError.invalidConnectionString(parseError)
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }

        @Test func unsupportedParametersHasDescription() {
            let error = ConnectionError.unsupportedParameters(["connect_timeout", "application_name"])
            #expect(error.errorDescription?.contains("connect_timeout") == true)
            #expect(error.errorDescription?.contains("application_name") == true)
            #expect(error.recoverySuggestion != nil)
        }
    }

    @Suite("Equatable")
    struct EquatableTests {

        @Test func sameInvalidHostAreEqual() {
            let error1 = ConnectionError.invalidHost("localhost")
            let error2 = ConnectionError.invalidHost("localhost")
            #expect(error1 == error2)
        }

        @Test func differentInvalidHostAreNotEqual() {
            let error1 = ConnectionError.invalidHost("localhost")
            let error2 = ConnectionError.invalidHost("remotehost")
            #expect(error1 != error2)
        }

        @Test func sameInvalidPortAreEqual() {
            #expect(ConnectionError.invalidPort == ConnectionError.invalidPort)
        }

        @Test func sameAuthenticationFailedAreEqual() {
            #expect(ConnectionError.authenticationFailed == ConnectionError.authenticationFailed)
        }

        @Test func sameDatabaseNotFoundAreEqual() {
            let error1 = ConnectionError.databaseNotFound("mydb")
            let error2 = ConnectionError.databaseNotFound("mydb")
            #expect(error1 == error2)
        }

        @Test func differentDatabaseNotFoundAreNotEqual() {
            let error1 = ConnectionError.databaseNotFound("db1")
            let error2 = ConnectionError.databaseNotFound("db2")
            #expect(error1 != error2)
        }

        @Test func sameTimeoutAreEqual() {
            #expect(ConnectionError.timeout == ConnectionError.timeout)
        }

        @Test func sameNetworkUnreachableAreEqual() {
            #expect(ConnectionError.networkUnreachable == ConnectionError.networkUnreachable)
        }

        @Test func sameNotConnectedAreEqual() {
            #expect(ConnectionError.notConnected == ConnectionError.notConnected)
        }

        @Test func sameConnectionCancelledAreEqual() {
            #expect(ConnectionError.connectionCancelled == ConnectionError.connectionCancelled)
        }

        @Test func sameSslContextFailedAreEqual() {
            let error1 = ConnectionError.sslContextCreationFailed("error")
            let error2 = ConnectionError.sslContextCreationFailed("error")
            #expect(error1 == error2)
        }

        @Test func differentSslContextFailedAreNotEqual() {
            let error1 = ConnectionError.sslContextCreationFailed("error1")
            let error2 = ConnectionError.sslContextCreationFailed("error2")
            #expect(error1 != error2)
        }

        @Test func unknownErrorsAreNotEqual() {
            // unknownError with different underlying errors always returns false
            let error1 = ConnectionError.unknownError(NSError(domain: "a", code: 1))
            let error2 = ConnectionError.unknownError(NSError(domain: "a", code: 1))
            #expect(error1 != error2)
        }

        @Test func differentErrorTypesAreNotEqual() {
            #expect(ConnectionError.timeout != ConnectionError.networkUnreachable)
            #expect(ConnectionError.invalidPort != ConnectionError.authenticationFailed)
        }
    }
}

// MARK: - NIOConnectionError Tests

@Suite("NIOConnectionError")
struct NIOConnectionErrorTests {

    @Test func timeoutCase() {
        let error = NIOConnectionError.timeout
        #expect("\(error)".contains("timeout"))
    }

    @Test func connectFailedCase() {
        let error = NIOConnectionError.connectFailed
        #expect("\(error)".contains("connectFailed"))
    }

    @Test func tlsErrorCase() {
        let error = NIOConnectionError.tlsError
        #expect("\(error)".contains("tlsError"))
    }

    @Test func otherCase() {
        let underlying = NSError(domain: "test", code: 1)
        let error = NIOConnectionError.other(underlying)
        #expect("\(error)".contains("other"))
    }
}

// MARK: - PostgresError Mapping Tests

@Suite("PostgresError")
struct PostgresErrorTests {

    @Suite("mapError")
    struct MapErrorTests {

        @Test func passesThruConnectionError() {
            let original = ConnectionError.timeout
            let mapped = PostgresError.mapError(original)
            #expect(mapped as? ConnectionError == .timeout)
        }

        @Test func passesThruDatabaseError() {
            // DatabaseError would pass through unchanged
            // (We don't have a DatabaseError to test with here)
        }

        @Test func wrapsUnknownError() {
            let unknown = NSError(domain: "mystery", code: 999)
            let mapped = PostgresError.mapError(unknown)

            if case .unknownError = mapped as? ConnectionError {
                // Expected
            } else {
                #expect(Bool(false), "Expected unknownError case")
            }
        }

        @Test func mapsNIOTimeout() {
            let nioError = NIOConnectionError.timeout
            let mapped = PostgresError.mapError(nioError)
            #expect(mapped as? ConnectionError == .timeout)
        }

        @Test func mapsNIOConnectFailed() {
            let nioError = NIOConnectionError.connectFailed
            let mapped = PostgresError.mapError(nioError)
            #expect(mapped as? ConnectionError == .networkUnreachable)
        }

        @Test func mapsNIOOther() {
            let underlying = NSError(domain: "test", code: 1)
            let nioError = NIOConnectionError.other(underlying)
            let mapped = PostgresError.mapError(nioError)

            if case .unknownError = mapped as? ConnectionError {
                // Expected
            } else {
                #expect(Bool(false), "Expected unknownError case")
            }
        }
    }

    @Suite("extractDetailedMessage from Error")
    struct ExtractDetailedMessageTests {

        @Test func extractsConnectionErrorDescription() {
            let error = ConnectionError.authenticationFailed
            let message = PostgresError.extractDetailedMessage(error)
            #expect(message.lowercased().contains("authentication"))
        }

        @Test func extractsFromUnknownError() {
            let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test message"])
            let error = ConnectionError.unknownError(underlying)
            let message = PostgresError.extractDetailedMessage(error)
            #expect(!message.isEmpty)
        }

        @Test func handlesGenericError() {
            let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generic error"])
            let message = PostgresError.extractDetailedMessage(error)
            #expect(!message.isEmpty)
        }
    }

    @Suite("cleanErrorDescription scenarios")
    struct CleanErrorDescriptionTests {

        // These tests verify the behavior indirectly through extractDetailedMessage

        @Test func handlesConnectionRefused() {
            let error = NSError(domain: "test", code: 61, userInfo: [NSLocalizedDescriptionKey: "Connection refused"])
            let message = PostgresError.extractDetailedMessage(error)
            #expect(message.contains("refused") || message.contains("Connection"))
        }

        @Test func handlesTimeout() {
            let error = NSError(domain: "test", code: 60, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            let message = PostgresError.extractDetailedMessage(error)
            #expect(!message.isEmpty)
        }
    }
}

// MARK: - RowOperationError Tests

@Suite("RowOperationError")
struct RowOperationErrorTests {

    @Test func noTableSelectedHasDescription() {
        let error = RowOperationError.noTableSelected
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("table") == true)
    }

    @Test func noRowsSelectedHasDescription() {
        let error = RowOperationError.noRowsSelected
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("rows") == true)
    }

    @Test func noPrimaryKeyHasDescription() {
        let error = RowOperationError.noPrimaryKey
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("primary key") == true)
    }

    @Test func metadataFetchFailedHasDescription() {
        let error = RowOperationError.metadataFetchFailed("Connection lost")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Connection lost") == true)
    }

    @Test func deleteFailedHasDescription() {
        let error = RowOperationError.deleteFailed("Foreign key constraint")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Foreign key constraint") == true)
    }

    @Test func updateFailedHasDescription() {
        let error = RowOperationError.updateFailed("Unique constraint violation")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Unique constraint violation") == true)
    }
}

// MARK: - KeychainError Tests

@Suite("KeychainError")
struct KeychainErrorTests {

    @Test func saveFailedHasDescription() {
        let error = KeychainError.saveFailed(-25300)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("save") == true)
        #expect(error.errorDescription?.contains("-25300") == true)
    }

    @Test func retrieveFailedHasDescription() {
        let error = KeychainError.retrieveFailed(-25300)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("retrieve") == true)
    }

    @Test func deleteFailedHasDescription() {
        let error = KeychainError.deleteFailed(-25300)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("delete") == true)
    }

    @Test func invalidDataHasDescription() {
        let error = KeychainError.invalidData
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Invalid") == true)
    }
}

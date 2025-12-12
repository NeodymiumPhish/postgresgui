//
//  PostgresError.swift
//  PostgresGUI
//
//  Maps PostgresNIO errors to app-specific error types
//

import Foundation
import PostgresNIO

/// Utility for mapping PostgresNIO errors to app error types
enum PostgresError {

    /// Map a PostgresNIO error to ConnectionError or DatabaseError
    /// - Parameter error: The error to map
    /// - Returns: Mapped ConnectionError, DatabaseError, or the original error if unmappable
    nonisolated static func mapError(_ error: Error) -> Error {
        // Check if it's a PSQLError from PostgresNIO
        if let psqlError = error as? PSQLError {
            return mapPSQLError(psqlError)
        }

        // Check for PostgresNIO connection errors
        if let nioError = error as? NIOConnectionError {
            return mapNIOConnectionError(nioError)
        }

        // Check for known error types
        if error is ConnectionError || error is DatabaseError {
            return error
        }

        // Unknown error - wrap in ConnectionError.unknownError
        return ConnectionError.unknownError(error)
    }

    /// Map PSQLError to ConnectionError or DatabaseError
    private nonisolated static func mapPSQLError(_ error: PSQLError) -> Error {
        // Check the error message for specific cases
        let message = error.serverInfo?[.message]?.lowercased() ?? error.localizedDescription.lowercased()

        // Check for authentication errors
        if message.contains("password") || message.contains("authentication") {
            return ConnectionError.authenticationFailed
        }

        // Check for database not found
        if message.contains("database") && message.contains("does not exist") {
            let dbName = extractDatabaseName(from: error) ?? "unknown"
            return ConnectionError.databaseNotFound(dbName)
        }

        // Check for connection errors
        if message.contains("connection") || message.contains("could not connect") {
            return ConnectionError.networkUnreachable
        }

        // Check for timeout
        if message.contains("timeout") || message.contains("canceled") {
            return ConnectionError.timeout
        }

        // Unknown PostgreSQL error - wrap in unknownError
        return ConnectionError.unknownError(error)
    }

    /// Map NIO connection errors
    private nonisolated static func mapNIOConnectionError(_ error: NIOConnectionError) -> Error {
        switch error {
        case .timeout:
            return ConnectionError.timeout
        case .connectFailed:
            return ConnectionError.networkUnreachable
        default:
            return ConnectionError.unknownError(error)
        }
    }

    /// Extract database name from PSQLError message if available
    private nonisolated static func extractDatabaseName(from error: PSQLError) -> String? {
        // Try to extract from server info
        if let message = error.serverInfo?[.message] {
            // PostgreSQL message format: "database \"dbname\" does not exist"
            let pattern = "database \"([^\"]+)\" does not exist"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) {
                if let range = Range(match.range(at: 1), in: message) {
                    return String(message[range])
                }
            }
        }
        return nil
    }

    /// Extract a user-friendly error message from PSQLError
    nonisolated static func extractMessage(_ error: PSQLError) -> String {
        // Try to get the message from server info
        if let message = error.serverInfo?[.message] {
            return message
        }

        // Fall back to error description
        return error.localizedDescription
    }
}

// MARK: - NIOConnectionError

/// Custom error type for NIO connection failures
enum NIOConnectionError: Error {
    case timeout
    case connectFailed
    case tlsError
    case other(Error)
}

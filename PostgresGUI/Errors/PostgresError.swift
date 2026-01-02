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
        // Check if we have server info (indicates server responded with an error)
        if let serverMessage = error.serverInfo?[.message] {
            let lowerMessage = serverMessage.lowercased()

            // Check for authentication errors
            if lowerMessage.contains("password") || lowerMessage.contains("authentication") {
                return ConnectionError.authenticationFailed
            }

            // Check for database not found
            if lowerMessage.contains("database") && lowerMessage.contains("does not exist") {
                let dbName = extractDatabaseName(from: error) ?? "unknown"
                return ConnectionError.databaseNotFound(dbName)
            }

            // Server responded with an error (SQL error, constraint violation, etc.)
            // Return a DatabaseError to preserve the server message
            return DatabaseError.queryFailed(serverMessage)
        }

        // No server info - this is likely a connection-level error
        // Use String(reflecting:) to get the actual error details
        let detailedDescription = String(reflecting: error)
        let lowerDescription = detailedDescription.lowercased()

        // Check for connection errors
        if lowerDescription.contains("connection") || lowerDescription.contains("could not connect") {
            return ConnectionError.networkUnreachable
        }

        // Check for timeout
        if lowerDescription.contains("timeout") || lowerDescription.contains("canceled") {
            return ConnectionError.timeout
        }

        // Unknown PostgreSQL error - wrap in unknownError with detailed description
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

    /// Extract detailed error info from PSQLError for display in alerts
    nonisolated static func extractDetailedMessage(_ error: PSQLError) -> String {
        // First try server info (available when server responds)
        var parts: [String] = []
        if let message = error.serverInfo?[.message] {
            parts.append(message)
        }
        if let detail = error.serverInfo?[.detail] {
            parts.append(detail)
        }
        if let hint = error.serverInfo?[.hint] {
            parts.append("Hint: \(hint)")
        }
        if !parts.isEmpty {
            return parts.joined(separator: "\n\n")
        }

        // No server info - extract from error description
        return cleanErrorDescription(String(describing: error))
    }

    /// Extract detailed message from any error
    nonisolated static func extractDetailedMessage(_ error: Error) -> String {
        if let psqlError = error as? PSQLError {
            return extractDetailedMessage(psqlError)
        }

        if let databaseError = error as? DatabaseError {
            return databaseError.errorDescription ?? "Query failed"
        }

        if let connectionError = error as? ConnectionError {
            if case .unknownError(let underlying) = connectionError {
                if let psqlError = underlying as? PSQLError {
                    return extractDetailedMessage(psqlError)
                }
                return cleanErrorDescription(String(describing: underlying))
            }
            return connectionError.errorDescription ?? "Connection failed"
        }

        return cleanErrorDescription(String(describing: error))
    }

    /// Clean up raw error descriptions into user-friendly messages
    private nonisolated static func cleanErrorDescription(_ description: String) -> String {
        let lower = description.lowercased()

        if lower.contains("connection refused") || lower.contains("(61)") {
            return "Connection refused"
        }
        if lower.contains("no such host") || lower.contains("nodename nor servname") {
            return "Could not resolve host"
        }
        if lower.contains("timeout") || lower.contains("timed out") || lower.contains("(60)") {
            return "Connection timed out"
        }
        if lower.contains("network is unreachable") {
            return "Network unreachable"
        }
        if lower.contains("ssl") || lower.contains("tls") {
            return "SSL/TLS connection failed"
        }

        return "Connection failed"
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

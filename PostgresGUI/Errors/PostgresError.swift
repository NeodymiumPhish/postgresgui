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

    /// Extract detailed error info from PSQLError for display in alerts
    nonisolated static func extractDetailedMessage(_ error: PSQLError) -> String {
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

        // Try to get a cleaner description from the underlying error
        let description = String(describing: error)

        // Check for common connection-related patterns
        if description.contains("connectionError") || description.contains("Connection") {
            // Try to extract the actual error message from the description
            if description.contains("NIOConnectionError") {
                return "Could not connect to server"
            }
            if description.contains("posix") || description.contains("POSIX") {
                // POSIX errors often have codes like (61) for connection refused
                if description.contains("61") {
                    return "Connection refused"
                }
                if description.contains("60") || description.contains("timeout") || description.contains("Timeout") {
                    return "Connection timed out"
                }
                return "Network error"
            }
        }

        // Check for SSL/TLS errors
        if description.contains("ssl") || description.contains("SSL") || description.contains("tls") || description.contains("TLS") {
            return "SSL/TLS connection failed"
        }

        // Fallback: try to provide something cleaner than the raw error
        return error.localizedDescription
    }

    /// Extract detailed message from any error, handling PSQLError specially
    nonisolated static func extractDetailedMessage(_ error: Error) -> String {
        if let psqlError = error as? PSQLError {
            return extractDetailedMessage(psqlError)
        }

        // For ConnectionError.unknownError, try to unwrap the underlying error
        if let connectionError = error as? ConnectionError,
           case .unknownError(let underlyingError) = connectionError {
            if let psqlError = underlyingError as? PSQLError {
                return extractDetailedMessage(psqlError)
            }
            // Try to get a cleaner message from the underlying error
            return extractCleanErrorMessage(underlyingError)
        }

        // For ConnectionError with proper descriptions, use them
        if let connectionError = error as? ConnectionError {
            return connectionError.errorDescription ?? error.localizedDescription
        }

        return extractCleanErrorMessage(error)
    }

    /// Extract a cleaner error message from a generic error
    private nonisolated static func extractCleanErrorMessage(_ error: Error) -> String {
        let description = String(describing: error)
        let localizedDesc = error.localizedDescription

        // Check for common patterns and provide cleaner messages
        let lowerDesc = description.lowercased()

        if lowerDesc.contains("connection refused") {
            return "Connection refused"
        }
        if lowerDesc.contains("no such host") || lowerDesc.contains("nodename nor servname") {
            return "Could not resolve host"
        }
        if lowerDesc.contains("timeout") || lowerDesc.contains("timed out") {
            return "Connection timed out"
        }
        if lowerDesc.contains("network is unreachable") {
            return "Network unreachable"
        }

        // If localizedDescription is cleaner than the raw description, use it
        // But filter out ugly technical messages
        if !localizedDesc.contains("PSQLError") && !localizedDesc.contains("code:") {
            return localizedDesc
        }

        // Last resort: provide a generic but clean message
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

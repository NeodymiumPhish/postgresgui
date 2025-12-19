//
//  ConnectionManagerProtocol.swift
//  PostgresGUI
//
//  Protocol abstraction for database connection management
//  Enables dependency injection and testability for DatabaseService
//

import Foundation
import PostgresNIO
import NIOSSL

/// Protocol defining connection manager operations
/// Implemented by PostgresConnectionManager for production and MockConnectionManager for testing
protocol ConnectionManagerProtocol: Actor {
    /// Check if currently connected to a database
    var isConnected: Bool { get async }

    /// Connect to PostgreSQL database
    /// - Parameters:
    ///   - host: Database host
    ///   - port: Database port
    ///   - username: Username for authentication
    ///   - password: Password for authentication
    ///   - database: Database name to connect to
    ///   - tlsConfiguration: Optional TLS configuration for encrypted connections
    /// - Throws: ConnectionError if connection fails
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsConfiguration: TLSConfiguration?
    ) async throws

    /// Disconnect from database and cleanup resources
    func disconnect() async

    /// Execute an operation with the active connection
    /// - Parameter operation: Async closure that receives the PostgresConnection
    /// - Returns: Result of the operation
    /// - Throws: ConnectionError.notConnected if not connected, or operation errors
    func withConnection<T>(_ operation: @escaping (PostgresConnection) async throws -> T) async throws -> T
}

//
//  PostgresConnectionManager.swift
//  PostgresGUI
//
//  Manages PostgresNIO connection lifecycle and EventLoopGroup
//

import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

/// Actor-isolated manager for PostgresNIO connections
/// Handles connection lifecycle, EventLoopGroup management, and async/await bridging
actor PostgresConnectionManager {

    // MARK: - Properties

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var connection: PostgresConnection?
    private let logger = Logger.debugLogger(label: "com.postgresgui.connection")

    /// Check if currently connected
    var isConnected: Bool {
        connection != nil
    }

    // MARK: - Initialization

    init() {
        logger.info("PostgresConnectionManager initialized")
    }

    deinit {
        // Capture connection and event loop group to close them
        let conn = connection
        let elg = eventLoopGroup
        let logger = self.logger

        // If we have an active connection or event loop group, clean them up
        if conn != nil || elg != nil {
            logger.warning("PostgresConnectionManager deallocated with active connection - cleaning up")

            // Spawn detached task to close connection and shutdown event loop
            Task.detached {
                if let conn = conn {
                    logger.debug("Closing connection in deinit")
                    try? await conn.close()
                }

                if let elg = elg {
                    logger.debug("Shutting down EventLoopGroup in deinit")
                    try? await elg.shutdownGracefully()
                }

                logger.info("PostgresConnectionManager cleanup completed")
            }
        }
    }

    // MARK: - Connection Management

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
        tlsConfiguration: TLSConfiguration? = nil
    ) async throws {
        logger.info("Connecting to PostgreSQL at \(host):\(port), database: \(database)")

        // Close existing connection if any
        if connection != nil {
            await disconnect()
        }

        // Create EventLoopGroup if not exists
        if eventLoopGroup == nil {
            logger.debug("Creating EventLoopGroup")
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        }

        guard let elg = eventLoopGroup else {
            throw ConnectionError.unknownError(NSError(domain: "PostgresConnectionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create EventLoopGroup"]))
        }

        // Build PostgresNIO configuration
        var config = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )

        // Configure TLS if provided
        if let tlsConfig = tlsConfiguration {
            do {
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                config.tls = .require(sslContext)
            } catch {
                logger.error("Failed to create SSL context: \(error)")
                config.tls = .disable
            }
        }

        do {
            // Connect using PostgresNIO
            logger.debug("Establishing PostgreSQL connection...")
            let newConnection = try await PostgresConnection.connect(
                on: elg.next(),
                configuration: config,
                id: 1,
                logger: logger
            )

            self.connection = newConnection
            logger.info("Successfully connected to PostgreSQL")
        } catch {
            logger.error("Connection failed: \(error)")
            // Shutdown event loop group on failure
            try? await eventLoopGroup?.shutdownGracefully()
            eventLoopGroup = nil
            throw PostgresError.mapError(error)
        }
    }

    /// Disconnect from database and cleanup resources
    func disconnect() async {
        logger.info("Disconnecting from PostgreSQL")

        // Close connection
        if let conn = connection {
            logger.debug("Closing PostgreSQL connection")
            do {
                try await conn.close()
            } catch {
                logger.error("Error closing connection: \(error)")
            }
            connection = nil
        }

        // Shutdown EventLoopGroup
        if let elg = eventLoopGroup {
            logger.debug("Shutting down EventLoopGroup")
            do {
                try await elg.shutdownGracefully()
            } catch {
                logger.error("Error shutting down EventLoopGroup: \(error)")
            }
            eventLoopGroup = nil
        }

        logger.info("Disconnected from PostgreSQL")
    }

    // MARK: - Connection Access

    /// Execute an operation with the active connection
    /// - Parameter operation: Async closure that receives the PostgresConnection
    /// - Returns: Result of the operation
    /// - Throws: ConnectionError.notConnected if not connected, or operation errors
    func withConnection<T>(_ operation: @escaping (PostgresConnection) async throws -> T) async throws -> T {
        guard let conn = connection else {
            logger.error("Attempted to use connection while not connected")
            throw ConnectionError.notConnected
        }

        do {
            let result = try await operation(conn)
            return result
        } catch {
            logger.error("Operation failed: \(error)")
            throw PostgresError.mapError(error)
        }
    }

    // MARK: - Test Connection

    /// Test connection without maintaining it
    /// - Parameters:
    ///   - host: Database host
    ///   - port: Database port
    ///   - username: Username
    ///   - password: Password
    ///   - database: Database name
    ///   - tlsConfiguration: Optional TLS configuration
    /// - Returns: True if connection succeeds
    /// - Throws: ConnectionError if connection fails
    static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsConfiguration: TLSConfiguration? = nil
    ) async throws -> Bool {
        let logger = Logger.debugLogger(label: "com.postgresgui.connection.test")
        logger.info("Testing connection to \(host):\(port)")

        // Create temporary EventLoopGroup
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // Build configuration
        var config = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )

        // Configure TLS if provided
        if let tlsConfig = tlsConfiguration {
            do {
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                config.tls = .require(sslContext)
            } catch {
                logger.error("Failed to create SSL context: \(error)")
                config.tls = .disable
            }
        }

        do {
            // Attempt connection
            let connection = try await PostgresConnection.connect(
                on: elg.next(),
                configuration: config,
                id: 1,
                logger: logger
            )

            // Close immediately
            try await connection.close()

            // Shutdown event loop group
            try await elg.shutdownGracefully()

            logger.info("Connection test successful")
            return true
        } catch {
            // Shutdown event loop group on error
            try? await elg.shutdownGracefully()
            logger.error("Connection test failed: \(error)")
            throw PostgresError.mapError(error)
        }
    }
}

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
actor PostgresConnectionManager: ConnectionManagerProtocol {

    // MARK: - Properties

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var connection: PostgresConnection?
    private var wrappedConnection: PostgresDatabaseConnection?
    private let logger = Logger.debugLogger(label: "com.postgresgui.connection")

    /// Generation counter to detect stale connection attempts
    /// When a new connect() is called, the generation increments.
    /// When an older connect() completes, it checks if it's still current.
    private var connectionGeneration: UInt64 = 0

    /// Check if currently connected
    var isConnected: Bool {
        connection != nil
    }

    // MARK: - Initialization

    init() {
        logger.info("PostgresConnectionManager initialized")
    }

    deinit {
        let conn = connection
        let elg = eventLoopGroup
        let logger = self.logger

        if conn != nil || elg != nil {
            logger.warning("⚠️ PostgresConnectionManager deinit with active resources - cleanup should have been explicit!")

            // Fallback cleanup (fire-and-forget)
            // This should rarely run if explicit cleanup is working
            Task.detached {
                if let conn = conn {
                    logger.debug("Closing connection in deinit (fallback)")
                    try? await conn.close()
                }

                if let elg = elg {
                    logger.debug("Shutting down EventLoopGroup in deinit (fallback)")
                    try? await elg.shutdownGracefully()
                }

                logger.info("Fallback cleanup completed")
            }
        } else {
            logger.debug("PostgresConnectionManager deinit - resources already cleaned up ✅")
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
    ///   - tlsMode: TLS mode for encrypted connections
    /// - Throws: ConnectionError if connection fails
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsMode: DatabaseTLSMode = .disable
    ) async throws {
        logger.info("Connecting to PostgreSQL at \(host):\(port), database: \(database)")

        // Increment generation to invalidate any in-flight connection attempts
        connectionGeneration &+= 1
        let myGeneration = connectionGeneration

        // Close existing connection if any
        if connection != nil {
            await disconnect()
        }

        // Create EventLoopGroup if not exists
        if eventLoopGroup == nil {
            let threadCount = System.coreCount
            logger.debug("Creating EventLoopGroup with \(threadCount) threads")
            eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
            logger.info("✅ EventLoopGroup created successfully")
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

        // Configure TLS based on mode
        if let tlsConfig = Self.makeTLSConfiguration(for: tlsMode) {
            do {
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                config.tls = .require(sslContext)
                logger.debug("SSL context created successfully")
            } catch {
                logger.error("Failed to create SSL context: \(error)")
                // FAIL instead of fallback - security requirement
                throw ConnectionError.sslContextCreationFailed(error.localizedDescription)
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

            // Check if a newer connect() was called while we were awaiting
            // If so, close this connection immediately - it's stale
            guard connectionGeneration == myGeneration else {
                logger.warning("⚠️ Stale connection detected (generation \(myGeneration) vs current \(connectionGeneration)), closing")
                try? await newConnection.close()
                throw ConnectionError.connectionCancelled
            }

            self.connection = newConnection
            self.wrappedConnection = PostgresDatabaseConnection(connection: newConnection, logger: logger)
            logger.info("Successfully connected to PostgreSQL")
        } catch let error as ConnectionError where error == .connectionCancelled {
            // Re-throw cancellation without shutting down ELG (newer connection needs it)
            throw error
        } catch {
            logger.error("Connection failed: \(error)")
            // Shutdown event loop group on failure
            try? await eventLoopGroup?.shutdownGracefully()
            eventLoopGroup = nil
            throw PostgresError.mapError(error)
        }
    }

    // MARK: - TLS Configuration

    /// Convert abstract DatabaseTLSMode to NIOSSL TLSConfiguration
    private static func makeTLSConfiguration(for mode: DatabaseTLSMode) -> TLSConfiguration? {
        switch mode {
        case .disable:
            return nil
        case .require:
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .none
            return config
        case .verifyCA:
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .noHostnameVerification
            return config
        case .verifyFull:
            return TLSConfiguration.makeClientConfiguration()
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
            wrappedConnection = nil
        }

        // Shutdown EventLoopGroup
        if let elg = eventLoopGroup {
            logger.debug("Shutting down EventLoopGroup")

            do {
                try await elg.shutdownGracefully()
                logger.info("✅ EventLoopGroup shutdown completed")
            } catch {
                logger.error("❌ Error shutting down EventLoopGroup: \(error)")
                // Even if shutdown fails, clear reference to prevent reuse
            }

            eventLoopGroup = nil
        }

        logger.info("Disconnected from PostgreSQL")
    }

    // MARK: - Connection Access

    /// Execute an operation with the active connection
    /// - Parameter operation: Async closure that receives the abstract DatabaseConnectionProtocol
    /// - Returns: Result of the operation
    /// - Throws: ConnectionError.notConnected if not connected, or operation errors
    func withConnection<T>(_ operation: @escaping (DatabaseConnectionProtocol) async throws -> T) async throws -> T {
        guard let wrappedConn = wrappedConnection else {
            logger.error("Attempted to use connection while not connected")
            throw ConnectionError.notConnected
        }

        do {
            let result = try await operation(wrappedConn)
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
    ///   - tlsMode: TLS mode for encrypted connections
    /// - Returns: True if connection succeeds
    /// - Throws: ConnectionError if connection fails
    static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String,
        tlsMode: DatabaseTLSMode = .disable
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

        // Configure TLS based on mode
        if let tlsConfig = makeTLSConfiguration(for: tlsMode) {
            do {
                let sslContext = try NIOSSLContext(configuration: tlsConfig)
                config.tls = .require(sslContext)
                logger.debug("SSL context created successfully for test")
            } catch {
                logger.error("Failed to create SSL context for test: \(error)")
                // Cleanup ELG before throwing
                try? await elg.shutdownGracefully()
                throw ConnectionError.sslContextCreationFailed(error.localizedDescription)
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
            logger.debug("Test connection closed")

            // Shutdown event loop group
            logger.debug("Shutting down test EventLoopGroup")
            try await elg.shutdownGracefully()
            logger.info("✅ Test EventLoopGroup shutdown completed")

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

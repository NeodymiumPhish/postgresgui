//
//  ConnectionService.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation

/// Service for managing database connections
/// Consolidates connection logic that was previously duplicated across ConnectionFormView,
/// ConnectionsListView, and ConnectionsDatabasesSidebar
@MainActor
class ConnectionService: ConnectionServiceProtocol {
    private let appState: AppState
    private let keychainService: KeychainServiceProtocol
    private let userDefaults: UserDefaultsProtocol

    init(appState: AppState, keychainService: KeychainServiceProtocol, userDefaults: UserDefaultsProtocol? = nil) {
        self.appState = appState
        self.keychainService = keychainService
        self.userDefaults = userDefaults ?? UserDefaultsWrapper()
    }

    /// Connect to a database using a connection profile
    func connect(
        to connection: ConnectionProfile,
        password: String? = nil,
        saveAsLast: Bool = true
    ) async -> ConnectionResult {
        do {
            DebugLog.print("🔌 [ConnectionService] Connecting to: \(connection.displayName)")

            // Get password from keychain if not provided
            let actualPassword: String
            if let providedPassword = password {
                actualPassword = providedPassword
            } else {
                actualPassword = try keychainService.getPassword(for: connection.id) ?? ""
            }

            // Connect to database
            try await appState.connection.databaseService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: actualPassword,
                database: connection.database,
                sslMode: connection.sslModeEnum
            )

            // Update app state
            appState.connection.currentConnection = connection
            appState.navigation.isShowingWelcomeScreen = false

            // Save last connection ID if requested
            if saveAsLast {
                userDefaults.set(
                    connection.id.uuidString,
                    forKey: Constants.UserDefaultsKeys.lastConnectionId
                )
            }

            // Load databases
            await loadDatabases()

            DebugLog.print("✅ [ConnectionService] Connection successful")
            return .success

        } catch {
            DebugLog.print("❌ [ConnectionService] Connection failed: \(error)")

            // Reset connection state on error
            appState.connection.currentConnection = nil

            return .failure(error)
        }
    }

    /// Disconnect from the current database
    func disconnect() async {
        DebugLog.print("🔌 [ConnectionService] Disconnecting")
        await appState.connection.databaseService.disconnect()
        appState.connection.currentConnection = nil
        appState.connection.databases = []
        appState.connection.tables = []
        appState.connection.selectedDatabase = nil
        appState.connection.selectedTable = nil
    }

    // MARK: - Private Helpers

    private func loadDatabases() async {
        do {
            appState.connection.databases = try await appState.connection.databaseService.fetchDatabases()
        } catch {
            DebugLog.print("⚠️ [ConnectionService] Failed to load databases: \(error)")
            // Don't throw - connection succeeded, just database list failed
        }
    }
}

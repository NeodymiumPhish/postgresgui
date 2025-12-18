//
//  ConnectionFormViewModel.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import Foundation
import SwiftUI
import SwiftData

/// ViewModel for ConnectionFormView
@Observable
@MainActor
class ConnectionFormViewModel {
    private let appState: AppState
    private let connectionService: ConnectionServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let connectionToEdit: ConnectionProfile?

    // Form state - Individual fields
    var individualName: String = ""
    var host: String = "localhost"
    var port: String = "5432"
    var username: String = "postgres"
    var password: String = ""
    var database: String = "postgres"
    var sslMode: SSLMode = .default
    var showPassword: Bool = false

    // Connection string mode
    var connectionString: String = ""
    var connectionStringName: String = ""
    var connectionStringWarnings: [String] = []

    // Connection test state
    var testResult: String?
    var testResultColor: Color = .primary
    var isConnecting: Bool = false
    var connectionTestStatus: ConnectionTestStatus = .idle

    // Password management
    var hasStoredPassword: Bool = false
    var actualStoredPassword: String = ""
    var passwordModified: Bool = false

    // Alert state
    var showKeychainAlert: Bool = false
    var keychainAlertMessage: String = ""

    enum ConnectionTestStatus {
        case idle
        case testing
        case success
        case failure(String)
    }

    init(
        appState: AppState,
        connectionService: ConnectionServiceProtocol,
        keychainService: KeychainServiceProtocol,
        connectionToEdit: ConnectionProfile?
    ) {
        self.appState = appState
        self.connectionService = connectionService
        self.keychainService = keychainService
        self.connectionToEdit = connectionToEdit

        // Load connection data if editing
        if let connection = connectionToEdit {
            loadConnection(connection)
        }
    }

    // MARK: - Connection Testing

    /// Test the connection with current settings
    func testConnection(inputMode: ConnectionInputMode) async {
        isConnecting = true
        testResult = nil
        connectionStringWarnings.removeAll()

        let testStartTime = Date()
        connectionTestStatus = .testing

        DebugLog.print("🧪 [ConnectionFormViewModel] Testing connection...")

        // Parse connection details based on input mode
        let connectionDetails: (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode)?

        if inputMode == .connectionString {
            connectionDetails = parseConnectionString()
        } else {
            connectionDetails = parseIndividualFields()
        }

        guard let details = connectionDetails else {
            isConnecting = false
            return
        }

        // Test connection
        do {
            _ = try await DatabaseService.testConnection(
                host: details.host,
                port: details.port,
                username: details.username,
                password: details.password,
                database: details.database,
                sslMode: details.sslMode
            )

            // Ensure minimum display duration for testing status
            let elapsed = Date().timeIntervalSince(testStartTime)
            if elapsed < 0.5 {
                try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
            }

            connectionTestStatus = .success
            testResult = "Connection successful!"
            testResultColor = .green

            DebugLog.print("✅ [ConnectionFormViewModel] Connection test successful")
        } catch {
            DebugLog.print("❌ [ConnectionFormViewModel] Connection test failed: \(error)")

            let parsedError = parseConnectionError(error)
            connectionTestStatus = .failure(parsedError.message)
            testResult = parsedError.message
            testResultColor = .red
        }

        isConnecting = false
    }

    /// Save the connection
    func saveConnection(inputMode: ConnectionInputMode, modelContext: ModelContext, onSaved: @escaping (ConnectionProfile) -> Void) async {
        // Parse connection details based on input mode
        let connectionDetails: (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode, name: String)?

        if inputMode == .connectionString {
            connectionDetails = parseConnectionStringForSave()
        } else {
            connectionDetails = parseIndividualFieldsForSave()
        }

        guard let details = connectionDetails else {
            return
        }

        // Create or update connection profile
        let profile: ConnectionProfile
        if let existing = connectionToEdit {
            // Update existing
            profile = existing
            profile.name = details.name.isEmpty ? nil : details.name
            profile.host = details.host
            profile.port = details.port
            profile.username = details.username
            profile.database = details.database
            profile.sslMode = details.sslMode.rawValue
        } else {
            // Create new
            profile = ConnectionProfile(
                name: details.name.isEmpty ? nil : details.name,
                host: details.host,
                port: details.port,
                username: details.username,
                database: details.database,
                sslMode: details.sslMode
            )
            modelContext.insert(profile)
        }

        // Save password to keychain
        do {
            try keychainService.savePassword(details.password, for: profile.id)
        } catch {
            DebugLog.print("❌ Failed to save password to keychain: \(error)")
            keychainAlertMessage = "Failed to save password securely: \(error.localizedDescription)"
            showKeychainAlert = true
        }

        // Save to SwiftData
        do {
            try modelContext.save()
            DebugLog.print("✅ Connection saved successfully")
            onSaved(profile)
        } catch {
            DebugLog.print("❌ Failed to save connection: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func loadConnection(_ connection: ConnectionProfile) {
        individualName = connection.name ?? ""
        connectionStringName = connection.name ?? ""
        host = connection.host
        port = String(connection.port)
        username = connection.username
        database = connection.database
        sslMode = connection.sslModeEnum

        // Load password from keychain
        do {
            if let storedPassword = try keychainService.getPassword(for: connection.id) {
                hasStoredPassword = true
                actualStoredPassword = storedPassword
                password = String(repeating: "•", count: 12) // Placeholder
            }
        } catch {
            DebugLog.print("⚠️ Failed to load password from keychain: \(error)")
        }
    }

    private func parseConnectionString() -> (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode)? {
        do {
            let parsed = try ConnectionStringParser.parse(connectionString)

            // Show warnings for unsupported parameters
            if !parsed.unsupportedParameters.isEmpty {
                let params = parsed.unsupportedParameters.joined(separator: ", ")
                connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
            }

            return (
                host: parsed.host,
                port: parsed.port,
                username: parsed.username ?? "postgres",
                password: parsed.password ?? "",
                database: parsed.database ?? "postgres",
                sslMode: parsed.sslMode
            )
        } catch {
            testResult = error.localizedDescription
            testResultColor = .red
            return nil
        }
    }

    private func parseIndividualFields() -> (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode)? {
        guard let portInt = Int(port) else {
            testResult = "Invalid port number"
            testResultColor = .red
            return nil
        }

        let actualPassword = getActualPassword()

        return (
            host: host,
            port: portInt,
            username: username,
            password: actualPassword,
            database: database,
            sslMode: sslMode
        )
    }

    private func parseConnectionStringForSave() -> (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode, name: String)? {
        guard let details = parseConnectionString() else {
            return nil
        }
        return (details.host, details.port, details.username, details.password, details.database, details.sslMode, connectionStringName)
    }

    private func parseIndividualFieldsForSave() -> (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode, name: String)? {
        guard let details = parseIndividualFields() else {
            return nil
        }
        return (details.host, details.port, details.username, details.password, details.database, details.sslMode, individualName)
    }

    private func getActualPassword() -> String {
        if connectionToEdit != nil {
            // Always get from keychain if not modified
            if hasStoredPassword && !passwordModified {
                return actualStoredPassword
            }
        }
        // User has entered a new password
        return password
    }

    /// Parse connection error and return user-friendly message with suggestions
    private func parseConnectionError(_ error: Error) -> (message: String, suggestions: [String]) {
        let errorMessage = error.localizedDescription.lowercased()
        let nsError = error as NSError

        // Connection refused errors
        if errorMessage.contains("connection refused") ||
           errorMessage.contains("could not connect") ||
           nsError.domain.contains("NIOConnectionError") {
            return (
                message: "Could not connect to server",
                suggestions: [
                    "Check if PostgreSQL is running",
                    "Verify host and port are correct",
                    "Check firewall settings"
                ]
            )
        }

        // Timeout errors
        if errorMessage.contains("timeout") ||
           errorMessage.contains("timed out") {
            return (
                message: "Connection timeout",
                suggestions: [
                    "Check your network connection",
                    "Verify firewall settings",
                    "Try increasing connection timeout"
                ]
            )
        }

        // Authentication errors
        if errorMessage.contains("password") ||
           errorMessage.contains("authentication") ||
           errorMessage.contains("invalid credentials") {
            return (
                message: "Authentication failed",
                suggestions: [
                    "Verify username and password",
                    "Check user permissions in PostgreSQL",
                    "Ensure the user exists and has access to the database"
                ]
            )
        }

        // Database not found errors
        if errorMessage.contains("database") && (errorMessage.contains("does not exist") || errorMessage.contains("not found")) {
            return (
                message: "Database not found",
                suggestions: [
                    "Check database name spelling",
                    "Verify database exists on server",
                    "Ensure you have permission to access the database"
                ]
            )
        }

        // SSL errors
        if errorMessage.contains("ssl") ||
           errorMessage.contains("tls") ||
           errorMessage.contains("certificate") {
            return (
                message: "SSL connection failed",
                suggestions: [
                    "Check SSL mode setting",
                    "Verify server SSL configuration",
                    "Try changing SSL mode to 'disable' or 'prefer'"
                ]
            )
        }

        // Host resolution errors
        if errorMessage.contains("could not resolve") ||
           errorMessage.contains("host") && errorMessage.contains("not found") {
            return (
                message: "Could not resolve host",
                suggestions: [
                    "Check host address spelling",
                    "Verify network connectivity",
                    "Try using IP address instead of hostname"
                ]
            )
        }

        // Generic error
        return (
            message: error.localizedDescription,
            suggestions: [
                "Check your connection settings",
                "Verify PostgreSQL server is running",
                "Review error details above"
            ]
        )
    }

    enum ConnectionInputMode {
        case individual
        case connectionString
    }
}

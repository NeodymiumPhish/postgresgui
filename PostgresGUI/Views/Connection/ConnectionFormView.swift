//
//  ConnectionFormView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData
import AppKit

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    var connectionToEdit: ConnectionProfile?

    // Separate connection names for each tab
    @State private var individualName: String = ""
    @State private var connectionStringName: String = ""
    @State private var showIndividualNameField: Bool = false
    @State private var showConnectionStringNameField: Bool = false

    // Individual fields
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var username: String = "postgres"
    @State private var password: String = ""
    @State private var database: String = "postgres"
    @State private var showPassword: Bool = false
    @State private var hasStoredPassword: Bool = false
    @State private var actualStoredPassword: String = ""
    @State private var passwordModified: Bool = false

    @State private var testResult: String?
    @State private var testResultColor: Color = .primary
    @State private var isConnecting: Bool = false
    
    // Connection test status for inline banner
    @State private var connectionTestStatus: ConnectionTestStatus = .idle
    
    // Alert state for keychain errors (separate from connection test)
    @State private var showKeychainAlert: Bool = false
    @State private var keychainAlertMessage: String = ""

    @State private var inputMode: ConnectionInputMode = .individual
    @State private var connectionString: String = ""
    @State private var connectionStringWarnings: [String] = []
    @State private var copyButtonLabel: String = "Copy"
    @State private var keychainAccessError: String? = nil

    enum ConnectionInputMode {
        case individual
        case connectionString
    }

    init(connectionToEdit: ConnectionProfile? = nil) {
        self.connectionToEdit = connectionToEdit
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if inputMode == .individual {
                            individualFieldsView
                        } else {
                            connectionStringView
                        }
                        
                        // Connection status banner
                        if connectionTestStatus != .idle {
                            VStack(spacing: 0) {
                                Spacer()
                                    .frame(height: 16)
                                
                                // Align banner with form field content (label width 120 + spacing 12 = 132px)
                                ConnectionStatusBanner(status: connectionTestStatus) {
                                    connectionTestStatus = .idle
                                }
                                .padding(.leading, 132)
                            }
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .onAppear {
                if let connection = connectionToEdit {
                    // Populate both name fields with the same value initially
                    individualName = connection.name ?? ""
                    connectionStringName = connection.name ?? ""
                    host = connection.host
                    port = String(connection.port)
                    username = connection.username
                    database = connection.database

                    // Password is always stored in Keychain
                    // Don't access keychain on form load (UX improvement - avoid passive popup)
                    // Just indicate that a password exists, will load on-demand when user shows password
                    hasStoredPassword = true
                    actualStoredPassword = ""  // Will be loaded when user clicks "Show Password"
                    passwordModified = false
                    // Show asterisks to indicate password exists (password is hidden by default)
                    password = String(repeating: "•", count: 8)

                    // Show name fields when editing only if name is not nil
                    showIndividualNameField = connection.name != nil
                    showConnectionStringNameField = connection.name != nil

                    // If in connection string mode, populate the connection string
                    if inputMode == .connectionString {
                        connectionString = generateConnectionStringFromCurrentConnection()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        // If editing, show connections list after dismissing
                        if connectionToEdit != nil {
                            appState.showConnectionsList()
                        }
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Toggle(connectionToEdit != nil ? "View Connection String" : "Use Connection String", isOn: Binding(
                        get: { inputMode == .connectionString },
                        set: { newValue in
                            let oldMode = inputMode
                            let newMode: ConnectionInputMode = newValue ? .connectionString : .individual
                            handleInputModeChange(from: oldMode, to: newMode)
                            inputMode = newMode
                        }
                    ))
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Test") {
                            Task {
                                await testConnection()
                            }
                        }
                        .disabled(isConnecting)

                        Button("Save") {
                            Task {
                                await connect()
                            }
                        }
                        .disabled(isConnecting)
                    }
                }
            }
            .navigationTitle(connectionToEdit == nil ? "Create New Connection" : "Edit Connection")
        }
        .frame(width: 500, height: 440)
        .alert("Keychain Access Denied", isPresented: $showKeychainAlert) {
            Button("OK") {
                showKeychainAlert = false
            }
        } message: {
            Text(keychainAlertMessage)
        }
    }

    // MARK: - Individual Fields View

    private var individualFieldsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if connectionToEdit != nil {
                if showIndividualNameField {
                    formRow(label: "Name") {
                        HStack(spacing: 8) {
                            TextField("", text: $individualName)
                                .textFieldStyle(.roundedBorder)

                            Button(action: {
                                showIndividualNameField = false
                                individualName = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove custom name")
                        }
                    }
                } else {
                    formRow(label: "Name") {
                        Button(action: {
                            showIndividualNameField = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.secondary)
                                Text("Add Connection Name")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            formRow(label: "Host") {
                TextEditor(text: $host)
                    .font(.body)
                    .frame(height: 40)
                    .padding(4)
                    .background(Color(nsColor: connectionToEdit != nil ? .controlBackgroundColor : .textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            formRow(label: "Port") {
                TextField("5432", text: $port)
                    .textFieldStyle(.roundedBorder)
            }

            formRow(label: "Username") {
                TextField("postgres", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            formRow(label: "Password") {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("", text: Binding(
                                get: {
                                    // If showing password and it hasn't been modified, show actual stored password
                                    if hasStoredPassword && !passwordModified {
                                        return actualStoredPassword
                                    }
                                    return password
                                },
                                set: { newValue in
                                    password = newValue
                                    // User is modifying the password
                                    if hasStoredPassword && !passwordModified {
                                        passwordModified = true
                                    }
                                }
                            ))
                        } else {
                            SecureField("", text: Binding(
                                get: {
                                    // If hidden and not modified, show asterisks
                                    if hasStoredPassword && !passwordModified {
                                        return String(repeating: "•", count: 8)
                                    }
                                    return password
                                },
                                set: { newValue in
                                    password = newValue
                                    // User is modifying the password
                                    if hasStoredPassword && !passwordModified {
                                        passwordModified = true
                                    }
                                }
                            ))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    
                    Button(action: {
                        // Load from keychain on-demand when user first shows password
                        if !showPassword && hasStoredPassword && actualStoredPassword.isEmpty {
                            if let connection = connectionToEdit {
                                // Load password from keychain now (with user context - they clicked show)
                                do {
                                    if let keychainPassword = try KeychainService.getPassword(for: connection.id) {
                                        actualStoredPassword = keychainPassword
                                        keychainAccessError = nil
                                    } else {
                                        // Password not found in keychain
                                        keychainAccessError = "Password not found in keychain"
                                        actualStoredPassword = ""
                                    }
                                } catch {
                                    // Keychain access failed (denied or other error)
                                    keychainAccessError = "Unable to access keychain. Grant permission in System Settings > Privacy & Security."
                                    connectionTestStatus = .error(
                                        message: "Unable to retrieve password from keychain. You may need to grant access in System Settings > Privacy & Security."
                                    )
                                    return  // Don't toggle showPassword if we failed to load
                                }
                            }
                        }
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showPassword ? "Hide password" : "Show password")
                }
            }

            formRow(label: "Database") {
                TextField("postgres", text: $database)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Connection String View

    private var connectionStringView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if connectionToEdit != nil {
                if showConnectionStringNameField {
                    formRow(label: "Name") {
                        HStack(spacing: 8) {
                            TextField("", text: $connectionStringName)
                                .textFieldStyle(.roundedBorder)

                            Button(action: {
                                showConnectionStringNameField = false
                                connectionStringName = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove custom name")
                        }
                    }
                } else {
                    formRow(label: "Name") {
                        Button(action: {
                            showConnectionStringNameField = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.secondary)
                                Text("Add Connection Name")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            formRow(label: "Connection String", alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $connectionString)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .padding(4)
                        .background(Color(nsColor: connectionToEdit != nil ? .controlBackgroundColor : .textBackgroundColor).opacity(connectionToEdit != nil ? 0.6 : 1.0))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .disabled(connectionToEdit != nil)
                        .foregroundColor(connectionToEdit != nil ? .secondary : .primary)
                        .onChange(of: connectionString) { _, _ in
                            validateConnectionString()
                        }

                    if connectionToEdit != nil {
                        HStack(spacing: 6) {
                            Text("Connection string is read-only when editing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                copyButtonLabel = "Copied!"
                                copyConnectionStringToClipboard()
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    copyButtonLabel = "Copy"
                                }
                            }) {
                                Label {
                                    Text(copyButtonLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } icon: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Copy connection string")
                        }
                    }

                    if !connectionStringWarnings.isEmpty {
                        ForEach(connectionStringWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func formRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Computed Properties

    private var currentName: String? {
        if inputMode == .individual {
            return showIndividualNameField && !individualName.isEmpty ? individualName : nil
        } else {
            return showConnectionStringNameField && !connectionStringName.isEmpty ? connectionStringName : nil
        }
    }

    // MARK: - Helper Methods

    private func handleInputModeChange(from oldMode: ConnectionInputMode, to newMode: ConnectionInputMode) {
        // No automatic sync - each tab maintains its own state independently
        // Clear any previous errors when switching tabs
        testResult = nil
        connectionTestStatus = .idle
        connectionStringWarnings.removeAll()
        
        // If switching to connection string mode in edit mode, populate the connection string
        if newMode == .connectionString, connectionToEdit != nil {
            connectionString = generateConnectionStringFromCurrentConnection()
        }
    }

    private func validateConnectionString() {
        connectionStringWarnings.removeAll()

        guard !connectionString.isEmpty else { return }

        do {
            let parsed = try ConnectionStringParser.parse(connectionString)

            // Check for unsupported parameters
            if !parsed.unsupportedParameters.isEmpty {
                let params = parsed.unsupportedParameters.joined(separator: ", ")
                connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
            }

            // Clear any previous parse errors
            if testResultColor == .red {
                testResult = nil
            }
        } catch {
            // Show parse error
            testResult = error.localizedDescription
            testResultColor = .red
        }
    }

    // MARK: - Error Parsing
    
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
    
    private func testConnection() async {
        isConnecting = true
        testResult = nil
        connectionStringWarnings.removeAll()
        
        // Set testing status and record start time for minimum display duration
        let testStartTime = Date()
        connectionTestStatus = .testing

        // Log test context
        DebugLog.print("🧪 [ConnectionFormView] ========== Starting Connection Test ==========")
        DebugLog.print("   Mode: \(inputMode == .connectionString ? "Connection String" : "Individual Fields")")
        if let connection = connectionToEdit {
            DebugLog.print("   Editing existing connection: \(connection.displayName)")
            DebugLog.print("   Connection ID: \(connection.id)")
            DebugLog.print("   Stored connection details:")
            DebugLog.print("     - Host: \(connection.host)")
            DebugLog.print("     - Port: \(connection.port)")
            DebugLog.print("     - Username: \(connection.username)")
            DebugLog.print("     - Database: \(connection.database)")
            DebugLog.print("     - SSL Mode: \(connection.sslModeEnum.rawValue)")
            DebugLog.print("   Password modified: \(passwordModified)")
            DebugLog.print("   Has stored password: \(hasStoredPassword)")
        } else {
            DebugLog.print("   Creating new connection")
        }

        // Parse connection details based on input mode
        let connectionDetails: (host: String, port: Int, username: String, password: String, database: String)

        do {
            if inputMode == .connectionString {
                DebugLog.print("   Parsing connection string...")
                let parsed = try ConnectionStringParser.parse(connectionString)

                // Show warnings for unsupported parameters
                if !parsed.unsupportedParameters.isEmpty {
                    let params = parsed.unsupportedParameters.joined(separator: ", ")
                    connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
                    DebugLog.print("   ⚠️  Unsupported parameters detected: \(params)")
                }

                var parsedPassword = parsed.password ?? ""
                var passwordSource: String

                // When testing an existing connection, if password is "YOUR_PASSWORD" placeholder,
                // replace it with the actual password from keychain
                if let connection = connectionToEdit, parsedPassword == "YOUR_PASSWORD" {
                    if let keychainPassword = try? KeychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                        DebugLog.print("   🔑 Detected 'YOUR_PASSWORD' placeholder, replacing with keychain password")
                        parsedPassword = keychainPassword
                        passwordSource = "keychain (replaced YOUR_PASSWORD placeholder)"
                    } else {
                        passwordSource = "YOUR_PASSWORD placeholder (no keychain password found)"
                    }
                } else {
                    passwordSource = parsedPassword.isEmpty ? "none (from connection string)" : "from connection string"
                }
                
                DebugLog.print("   ✅ Connection string parsed successfully")
                DebugLog.print("   Password source: \(passwordSource)")

                connectionDetails = (
                    host: parsed.host,
                    port: parsed.port,
                    username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
                    password: parsedPassword,
                    database: parsed.database ?? Constants.PostgreSQL.defaultDatabase
                )
            } else {
                // Individual fields mode (existing logic)
                DebugLog.print("   Parsing individual fields...")
                DebugLog.print("   Input fields:")
                DebugLog.print("     - Host: '\(host)'")
                DebugLog.print("     - Port: '\(port)'")
                DebugLog.print("     - Username: '\(username)'")
                DebugLog.print("     - Database: '\(database)'")
                DebugLog.print("     - Password field: \(password.isEmpty ? "empty" : (hasStoredPassword && !passwordModified ? "showing asterisks" : "user entered"))")

                guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
                    DebugLog.print("   ❌ Validation failed: Invalid port number '\(port)'")
                    
                    // Ensure testing state is visible for at least 150ms
                    let elapsedSinceTestStart = Date().timeIntervalSince(testStartTime)
                    let minDisplayDuration: TimeInterval = 0.15 // 150ms
                    if elapsedSinceTestStart < minDisplayDuration {
                        let remainingTime = minDisplayDuration - elapsedSinceTestStart
                        try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
                    }
                    
                    connectionTestStatus = .error(message: "Invalid port number")
                    isConnecting = false
                    return
                }
                DebugLog.print("   ✅ Port validation passed: \(portInt)")

                // Get password based on modifications
                let passwordToUse: String
                let passwordSource: String
                if let connection = connectionToEdit {
                    // For existing connections, always use keychain
                    if let keychainPassword = try? KeychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                        passwordToUse = passwordModified ? password : keychainPassword
                        passwordSource = passwordModified ? "user input (modified)" : "keychain (existing connection)"
                        DebugLog.print("   🔑 Using password from \(passwordModified ? "user input (modified)" : "keychain")")
                    } else {
                        passwordToUse = password
                        passwordSource = "user input (no keychain password)"
                        DebugLog.print("   ⚠️  No keychain password found, using user input")
                    }
                } else {
                    // For new connections, use password field
                    passwordToUse = password
                    passwordSource = passwordToUse.isEmpty ? "none (new connection)" : "user input (new connection)"
                    DebugLog.print("   📝 New connection - password: \(passwordToUse.isEmpty ? "none" : "provided")")
                }

                connectionDetails = (
                    host: host.isEmpty ? "localhost" : host,
                    port: portInt,
                    username: username.isEmpty ? "postgres" : username,
                    password: passwordToUse,
                    database: database.isEmpty ? "postgres" : database
                )
                
                DebugLog.print("   Password source: \(passwordSource)")
            }

            // Get SSL mode
            let sslMode: SSLMode
            let sslModeSource: String
            if inputMode == .connectionString {
                let parsed = try ConnectionStringParser.parse(connectionString)
                sslMode = parsed.sslMode
                sslModeSource = "from connection string"
            } else {
                // Use stored SSL mode if editing existing connection, otherwise use default
                if let connection = connectionToEdit {
                    sslMode = connection.sslModeEnum
                    sslModeSource = "from stored connection"
                } else {
                    sslMode = .default
                    sslModeSource = "default (new connection)"
                }
            }
            DebugLog.print("   SSL Mode: \(sslMode.rawValue) (\(sslModeSource))")

            // Log final connection details (mask password for security)
            let passwordMasked = connectionDetails.password.isEmpty ? "(empty)" : "***"
            DebugLog.print("   ──────────────────────────────────────────")
            DebugLog.print("   Final connection parameters:")
            DebugLog.print("     Host: \(connectionDetails.host)")
            DebugLog.print("     Port: \(connectionDetails.port)")
            DebugLog.print("     Username: \(connectionDetails.username)")
            DebugLog.print("     Password: \(passwordMasked) (length: \(connectionDetails.password.count))")
            DebugLog.print("     Database: \(connectionDetails.database)")
            DebugLog.print("     SSL Mode: \(sslMode.rawValue)")
            DebugLog.print("   ──────────────────────────────────────────")
            
            // Test connection with parsed details
            DebugLog.print("   🔌 Attempting to connect to database...")
            let startTime = Date()
            let success = try await DatabaseService.testConnection(
                host: connectionDetails.host,
                port: connectionDetails.port,
                username: connectionDetails.username,
                password: connectionDetails.password,
                database: connectionDetails.database,
                sslMode: sslMode
            )
            let duration = Date().timeIntervalSince(startTime)
            DebugLog.print("   ⏱️  Connection attempt took \(String(format: "%.2f", duration))s")

            // Ensure testing state is visible for at least 150ms
            let elapsedSinceTestStart = Date().timeIntervalSince(testStartTime)
            let minDisplayDuration: TimeInterval = 0.15 // 150ms
            if elapsedSinceTestStart < minDisplayDuration {
                let remainingTime = minDisplayDuration - elapsedSinceTestStart
                try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
            }

            if success {
                DebugLog.print("   ✅ Connection test successful!")
                DebugLog.print("🧪 [ConnectionFormView] ========== Connection Test PASSED ==========")
                
                // Set success status
                connectionTestStatus = .success
            } else {
                DebugLog.print("   ❌ Connection test failed (returned false)")
                DebugLog.print("🧪 [ConnectionFormView] ========== Connection Test FAILED ==========")
                
                // Set error status
                connectionTestStatus = .error(message: "Could not connect to \(connectionDetails.host):\(connectionDetails.port)")
            }
        } catch {
            DebugLog.print("   ❌ Exception during connection test:")
            DebugLog.print("      Error type: \(type(of: error))")
            DebugLog.print("      Error description: \(error.localizedDescription)")
            let nsError = error as NSError
            DebugLog.print("      Error domain: \(nsError.domain)")
            DebugLog.print("      Error code: \(nsError.code)")
            if !nsError.userInfo.isEmpty {
                DebugLog.print("      Error userInfo: \(nsError.userInfo)")
            }
            DebugLog.print("      Full error: \(String(reflecting: error))")
            DebugLog.print("🧪 [ConnectionFormView] ========== Connection Test ERROR ==========")
            
            // Ensure testing state is visible for at least 150ms
            let elapsedSinceTestStart = Date().timeIntervalSince(testStartTime)
            let minDisplayDuration: TimeInterval = 0.15 // 150ms
            if elapsedSinceTestStart < minDisplayDuration {
                let remainingTime = minDisplayDuration - elapsedSinceTestStart
                try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
            }
            
            // Parse error and set error status
            let (errorMessage, _) = parseConnectionError(error)
            connectionTestStatus = .error(message: errorMessage)
        }

        isConnecting = false
    }

    private func connect() async {
        isConnecting = true
        connectionStringWarnings.removeAll()

        // Parse connection details based on input mode
        let connectionDetails: (host: String, port: Int, username: String, password: String, database: String, sslMode: SSLMode)

        do {
            if inputMode == .connectionString {
                let parsed = try ConnectionStringParser.parse(connectionString)

                // Show warnings for unsupported parameters
                if !parsed.unsupportedParameters.isEmpty {
                    let params = parsed.unsupportedParameters.joined(separator: ", ")
                    connectionStringWarnings.append("Unsupported parameters will be ignored: \(params)")
                }

                var parsedPassword = parsed.password ?? ""

                // When connecting with an existing connection, if password is "YOUR_PASSWORD" placeholder,
                // replace it with the actual password from keychain
                if let connection = connectionToEdit, parsedPassword == "YOUR_PASSWORD" {
                    if let keychainPassword = try? KeychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                        parsedPassword = keychainPassword
                    }
                }

                connectionDetails = (
                    host: parsed.host,
                    port: parsed.port,
                    username: parsed.username ?? Constants.PostgreSQL.defaultUsername,
                    password: parsedPassword,
                    database: parsed.database ?? Constants.PostgreSQL.defaultDatabase,
                    sslMode: parsed.sslMode
                )
            } else {
                // Individual fields mode (existing logic)
                guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
                    testResult = "Invalid port number"
                    testResultColor = .red
                    isConnecting = false
                    return
                }

                let passwordToUse = getActualPassword()

                // Use stored SSL mode if editing existing connection, otherwise use default
                let sslModeForConnection: SSLMode
                if let connection = connectionToEdit {
                    sslModeForConnection = connection.sslModeEnum
                } else {
                    sslModeForConnection = .default
                }

                connectionDetails = (
                    host: host.isEmpty ? "localhost" : host,
                    port: portInt,
                    username: username.isEmpty ? "postgres" : username,
                    password: passwordToUse,
                    database: database.isEmpty ? "postgres" : database,
                    sslMode: sslModeForConnection
                )
            }

            // Log connection details (mask password for security)
            let passwordMasked = connectionDetails.password.isEmpty ? "(empty)" : "***"
            DebugLog.print("🔌 [ConnectionFormView] Connecting to database:")
            DebugLog.print("   Host: \(connectionDetails.host)")
            DebugLog.print("   Port: \(connectionDetails.port)")
            DebugLog.print("   Username: \(connectionDetails.username)")
            DebugLog.print("   Password: \(passwordMasked)")
            DebugLog.print("   Database: \(connectionDetails.database)")
            DebugLog.print("   SSL Mode: \(connectionDetails.sslMode.rawValue)")

            let profile: ConnectionProfile

            if let existingConnection = connectionToEdit {
                // Update existing connection
                DebugLog.print("🔄 [ConnectionFormView] Editing existing connection")
                DebugLog.print("   Password modified: \(passwordModified)")

                profile = existingConnection
                profile.name = currentName
                profile.host = connectionDetails.host
                profile.port = connectionDetails.port
                profile.username = connectionDetails.username
                profile.database = connectionDetails.database
                profile.sslMode = connectionDetails.sslMode.rawValue

                // Update password storage - always save to keychain
                if passwordModified {
                    DebugLog.print("   ✅ ACTION: Saving password to keychain")
                    if !password.isEmpty {
                        do {
                            try KeychainService.savePassword(password, for: profile.id)
                            DebugLog.print("   ✅ Password saved to keychain")
                            profile.password = nil  // Clear from model
                            DebugLog.print("   ✅ Cleared password from model")
                        } catch {
                            DebugLog.print("   ❌ Keychain save failed: \(error)")
                            // Keychain access denied - show error
                            keychainAlertMessage = "Unable to save password securely in the keychain. Please grant access in System Settings > Privacy & Security."
                            showKeychainAlert = true
                            isConnecting = false
                            return
                        }
                    } else {
                        // Empty password - delete from keychain
                        DebugLog.print("   ℹ️  Empty password - deleting from keychain")
                        try? KeychainService.deletePassword(for: profile.id)
                        profile.password = nil
                    }
                }
                DebugLog.print("   Final state: model.password=\(profile.password != nil ? "SET(\(profile.password!.count) chars)" : "nil")")

                // Save changes to SwiftData
                try modelContext.save()

                // If this is the current connection, disconnect and reconnect
                if appState.currentConnection?.id == profile.id {
                    await appState.databaseService.disconnect()
                    appState.isConnected = false
                }
            } else {
                // Create new connection
                DebugLog.print("✨ [ConnectionFormView] Creating new connection")
                DebugLog.print("   Password length: \(connectionDetails.password.count)")

                profile = ConnectionProfile(
                    name: currentName,
                    host: connectionDetails.host,
                    port: connectionDetails.port,
                    username: connectionDetails.username,
                    database: connectionDetails.database,
                    sslMode: connectionDetails.sslMode,
                    password: nil
                )

                // Save password to keychain
                DebugLog.print("   ✅ ACTION: Saving password to keychain")
                if !connectionDetails.password.isEmpty {
                    do {
                        try KeychainService.savePassword(connectionDetails.password, for: profile.id)
                        DebugLog.print("   ✅ Password saved to keychain")
                        profile.password = nil  // Don't store in model
                        DebugLog.print("   ✅ Model password set to nil")
                    } catch {
                        DebugLog.print("   ❌ Keychain save failed: \(error)")
                        // Keychain access denied - show error
                        keychainAlertMessage = "Unable to save password securely in the keychain. Please grant access in System Settings > Privacy & Security."
                        showKeychainAlert = true
                        isConnecting = false
                        return
                    }
                } else {
                    // Empty password - no password to save
                    DebugLog.print("   ℹ️  No password to save to keychain (empty password)")
                }
                DebugLog.print("   Final state: model.password=\(profile.password != nil ? "SET(\(profile.password!.count) chars)" : "nil")")

                // Save profile to SwiftData
                modelContext.insert(profile)
                try modelContext.save()
                
                // If this is the first connection, auto-connect
                let descriptor = FetchDescriptor<ConnectionProfile>()
                let allConnections = try modelContext.fetch(descriptor)
                
                if allConnections.count == 1 {
                    DebugLog.print("🔌 [ConnectionFormView] First connection detected - auto-connecting...")
                    await autoConnect(to: profile, password: connectionDetails.password)
                }
            }

            DebugLog.print("✅ [ConnectionFormView] Connection profile saved successfully")

            // Dismiss the form
            dismiss()
            
            // Show connections list after dismissing (for both creating and editing)
            appState.showConnectionsList()

        } catch {
            DebugLog.print("❌ [ConnectionFormView] Connection error: \(error)")
            testResult = error.localizedDescription
            testResultColor = .red
        }

        isConnecting = false
    }

    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            testResult = "Connected but failed to load databases: \(error.localizedDescription)"
            testResultColor = .orange
        }
    }
    
    /// Automatically connect to a newly saved connection (used when it's the first connection)
    private func autoConnect(to connection: ConnectionProfile, password: String) async {
        do {
            DebugLog.print("🔌 [ConnectionFormView] Auto-connecting to: \(connection.displayName)")
            
            // Connect to database
            try await appState.databaseService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password,
                database: connection.database,
                sslMode: connection.sslModeEnum
            )
            
            // Update app state
            appState.currentConnection = connection
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false
            
            // Save last connection ID
            UserDefaults.standard.set(connection.id.uuidString, forKey: Constants.UserDefaultsKeys.lastConnectionId)
            
            // Load databases
            await loadDatabases()
            
            DebugLog.print("✅ [ConnectionFormView] Auto-connect successful")
        } catch {
            DebugLog.print("❌ [ConnectionFormView] Auto-connect failed: \(error)")
            // Don't show error to user - they can manually connect later
            // Just log the error
        }
    }
    
    /// Get the actual password value, handling the asterisks placeholder
    /// Returns the password from the field if it's been changed, otherwise returns stored password from keychain
    private func getActualPassword() -> String {
        if let connection = connectionToEdit {
            // Always get from keychain
            if hasStoredPassword && !passwordModified {
                return (try? KeychainService.getPassword(for: connection.id)) ?? ""
            }
        }

        // User has entered a new password
        return password
    }
    
    /// Copy the connection string to the clipboard
    private func copyConnectionStringToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connectionString, forType: .string)
    }
    
    /// Generate a connection string from the current connection being edited
    /// Uses "YOUR_PASSWORD" as placeholder since passwords are always stored in keychain
    private func generateConnectionStringFromCurrentConnection() -> String {
        guard let connection = connectionToEdit else {
            return ""
        }

        // Always use "YOUR_PASSWORD" placeholder for existing connections
        // since passwords are always stored in keychain
        let passwordPlaceholder = hasStoredPassword ? "YOUR_PASSWORD" : nil

        return ConnectionStringParser.build(
            username: connection.username,
            password: passwordPlaceholder,
            host: connection.host,
            port: connection.port,
            database: connection.database,
            sslMode: connection.sslModeEnum
        )
    }
}

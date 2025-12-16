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
    @State private var saveInKeychain: Bool = false

    @State private var testResult: String?
    @State private var testResultColor: Color = .primary
    @State private var isConnecting: Bool = false
    
    // Alert state for test results
    @State private var showTestResultAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isSuccessAlert: Bool = false

    @State private var inputMode: ConnectionInputMode = .individual
    @State private var connectionString: String = ""
    @State private var connectionStringWarnings: [String] = []

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

                    // Set the saveInKeychain flag from the connection
                    saveInKeychain = connection.saveInKeychain

                    // Load password based on storage method
                    if connection.saveInKeychain {
                        // Password is stored in Keychain
                        if let storedPassword = try? KeychainService.getPassword(for: connection.id), !storedPassword.isEmpty {
                            hasStoredPassword = true
                            actualStoredPassword = storedPassword
                            passwordModified = false
                            // Show asterisks to indicate password exists (password is hidden by default)
                            password = String(repeating: "•", count: 8)
                        } else {
                            hasStoredPassword = false
                            actualStoredPassword = ""
                            passwordModified = false
                            password = ""
                        }
                    } else {
                        // Password is stored in plain text in the model
                        hasStoredPassword = false
                        actualStoredPassword = ""
                        passwordModified = false
                        password = connection.password ?? ""
                    }

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
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Toggle("Use Connection String", isOn: Binding(
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

                        Button(connectionToEdit == nil ? "Connect" : "Save") {
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
        .alert(alertTitle, isPresented: $showTestResultAlert) {
            Button("OK") {
                showTestResultAlert = false
            }
        } message: {
            Text(alertMessage)
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
            
            Spacer()
            
            HStack {
                Spacer()
                    .frame(width: 132)
                
                HStack(alignment: .top, spacing: 6) {
                    Toggle("", isOn: $saveInKeychain)
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Save Password in Keychain")
                            .font(.body)

                        Text("Storing passwords in the system Keychain provides enhanced security by encrypting credentials and restricting access to this application only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture {
                    saveInKeychain.toggle()
                }
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
                        .background(Color(nsColor: connectionToEdit != nil ? .controlBackgroundColor : .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .disabled(connectionToEdit != nil)
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
                                copyConnectionStringToClipboard()
                            }) {
                                Label {
                                    Text("Copy")
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
            
            Spacer()
            
            HStack {
                Spacer()
                    .frame(width: 132)
                
                HStack(alignment: .top, spacing: 6) {
                    Toggle("", isOn: $saveInKeychain)
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Save Password in Keychain")
                            .font(.body)

                        Text("Storing passwords in the system Keychain provides enhanced security by encrypting credentials and restricting access to this application only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture {
                    saveInKeychain.toggle()
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
        showTestResultAlert = false
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

    private func testConnection() async {
        isConnecting = true
        testResult = nil
        showTestResultAlert = false
        connectionStringWarnings.removeAll()

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
                // replace it with the actual password from storage
                if let connection = connectionToEdit, parsedPassword == "YOUR_PASSWORD" {
                    if connection.saveInKeychain {
                        if let keychainPassword = try? KeychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                            DebugLog.print("   🔑 Detected 'YOUR_PASSWORD' placeholder, replacing with keychain password")
                            parsedPassword = keychainPassword
                            passwordSource = "keychain (replaced YOUR_PASSWORD placeholder)"
                        } else {
                            passwordSource = "YOUR_PASSWORD placeholder (no keychain password found)"
                        }
                    } else {
                        if let modelPassword = connection.password, !modelPassword.isEmpty {
                            DebugLog.print("   📝 Detected 'YOUR_PASSWORD' placeholder, replacing with model password")
                            parsedPassword = modelPassword
                            passwordSource = "model (replaced YOUR_PASSWORD placeholder)"
                        } else {
                            passwordSource = "YOUR_PASSWORD placeholder (no model password found)"
                        }
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
                    alertTitle = "Connection Error"
                    alertMessage = "Invalid port number"
                    isSuccessAlert = false
                    showTestResultAlert = true
                    isConnecting = false
                    return
                }
                DebugLog.print("   ✅ Port validation passed: \(portInt)")

                // Get password based on storage method and modifications
                let passwordToUse: String
                let passwordSource: String
                if let connection = connectionToEdit {
                    // For existing connections, check storage method
                    if connection.saveInKeychain {
                        // Password stored in keychain
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
                        // Password stored in model
                        passwordToUse = passwordModified ? password : (connection.password ?? "")
                        passwordSource = passwordModified ? "user input (modified)" : "model (plain storage)"
                        DebugLog.print("   📝 Using password from \(passwordModified ? "user input (modified)" : "model (plain storage)")")
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

            if success {
                DebugLog.print("   ✅ Connection test successful!")
                DebugLog.print("🧪 [ConnectionFormView] ========== Connection Test PASSED ==========")
                alertTitle = "Connection Successful"
                alertMessage = "The connection test was successful."
                isSuccessAlert = true
                showTestResultAlert = true
            } else {
                DebugLog.print("   ❌ Connection test failed (returned false)")
                DebugLog.print("🧪 [ConnectionFormView] ========== Connection Test FAILED ==========")
                alertTitle = "Connection Failed"
                alertMessage = "The connection test failed. Please check your connection settings."
                isSuccessAlert = false
                showTestResultAlert = true
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
            alertTitle = "Connection Error"
            alertMessage = error.localizedDescription
            isSuccessAlert = false
            showTestResultAlert = true
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
                // replace it with the actual password from storage
                if let connection = connectionToEdit, parsedPassword == "YOUR_PASSWORD" {
                    if connection.saveInKeychain {
                        if let keychainPassword = try? KeychainService.getPassword(for: connection.id), !keychainPassword.isEmpty {
                            parsedPassword = keychainPassword
                        }
                    } else {
                        parsedPassword = connection.password ?? ""
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
                DebugLog.print("🔄 [KEYCHAIN TEST] Editing existing connection")
                DebugLog.print("   Previous saveInKeychain: \(existingConnection.saveInKeychain)")
                DebugLog.print("   Current saveInKeychain: \(saveInKeychain)")
                DebugLog.print("   Password modified: \(passwordModified)")

                profile = existingConnection
                profile.name = currentName
                profile.host = connectionDetails.host
                profile.port = connectionDetails.port
                profile.username = connectionDetails.username
                profile.database = connectionDetails.database
                profile.sslMode = connectionDetails.sslMode.rawValue

                // Check if storage method changed
                let storageMethodChanged = existingConnection.saveInKeychain != saveInKeychain
                DebugLog.print("   Storage method changed: \(storageMethodChanged)")

                // Update password storage based on method and modifications
                if passwordModified || storageMethodChanged {
                    if saveInKeychain {
                        // Moving to or staying in keychain
                        DebugLog.print("   ✅ ACTION: Migrating password TO keychain")
                        if !password.isEmpty {
                            try KeychainService.savePassword(password, for: profile.id)
                            DebugLog.print("   ✅ Password saved to keychain")
                        }
                        profile.password = nil  // Clear from model
                        DebugLog.print("   ✅ Cleared password from model")
                    } else {
                        // Moving to or staying in plain storage
                        DebugLog.print("   📝 ACTION: Migrating password TO plain storage")
                        profile.password = password
                        DebugLog.print("   📝 Password saved to model (length: \(password.count))")
                        try? KeychainService.deletePassword(for: profile.id)
                        DebugLog.print("   📝 Deleted password from keychain")
                    }
                } else {
                    DebugLog.print("   ⏭️  No password migration needed")
                }
                profile.saveInKeychain = saveInKeychain
                DebugLog.print("   Final state: saveInKeychain=\(profile.saveInKeychain), model.password=\(profile.password != nil ? "SET(\(profile.password!.count) chars)" : "nil")")

                // Save changes to SwiftData
                try modelContext.save()

                // If this is the current connection, disconnect and reconnect
                if appState.currentConnection?.id == profile.id {
                    await appState.databaseService.disconnect()
                    appState.isConnected = false
                }
            } else {
                // Create new connection
                DebugLog.print("✨ [KEYCHAIN TEST] Creating new connection")
                DebugLog.print("   saveInKeychain: \(saveInKeychain)")
                DebugLog.print("   Password length: \(connectionDetails.password.count)")

                profile = ConnectionProfile(
                    name: currentName,
                    host: connectionDetails.host,
                    port: connectionDetails.port,
                    username: connectionDetails.username,
                    database: connectionDetails.database,
                    sslMode: connectionDetails.sslMode,
                    password: nil,
                    saveInKeychain: saveInKeychain
                )

                // Save password based on storage method
                if saveInKeychain {
                    // Save to keychain
                    DebugLog.print("   ✅ ACTION: Saving password to keychain")
                    if !connectionDetails.password.isEmpty {
                        try KeychainService.savePassword(connectionDetails.password, for: profile.id)
                        DebugLog.print("   ✅ Password saved to keychain")
                    }
                    profile.password = nil  // Don't store in model
                    DebugLog.print("   ✅ Model password set to nil")
                } else {
                    // Save to model
                    DebugLog.print("   📝 ACTION: Saving password to model (plain text)")
                    profile.password = connectionDetails.password
                    DebugLog.print("   📝 Password saved to model (length: \(connectionDetails.password.count))")
                    // Delete from keychain if it exists
                    try? KeychainService.deletePassword(for: profile.id)
                }
                DebugLog.print("   Final state: saveInKeychain=\(profile.saveInKeychain), model.password=\(profile.password != nil ? "SET(\(profile.password!.count) chars)" : "nil")")

                // Save profile to SwiftData
                modelContext.insert(profile)
                try modelContext.save()
            }

            // Connect to database (for both new and edited connections)
            let passwordToUse: String
            if !connectionDetails.password.isEmpty {
                passwordToUse = connectionDetails.password
            } else {
                // Try to get password from storage based on method
                if profile.saveInKeychain {
                    passwordToUse = (try? KeychainService.getPassword(for: profile.id)) ?? ""
                } else {
                    passwordToUse = profile.password ?? ""
                }
            }

            // Log actual connection parameters being used
            let actualPasswordMasked = passwordToUse.isEmpty ? "(empty)" : "***"
            DebugLog.print("🔌 [ConnectionFormView] Establishing connection with:")
            DebugLog.print("   Host: \(profile.host)")
            DebugLog.print("   Port: \(profile.port)")
            DebugLog.print("   Username: \(profile.username)")
            DebugLog.print("   Password: \(actualPasswordMasked)")
            DebugLog.print("   Database: \(profile.database)")
            DebugLog.print("   SSL Mode: \(profile.sslModeEnum.rawValue)")

            try await appState.databaseService.connect(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                password: passwordToUse,
                database: profile.database,
                sslMode: profile.sslModeEnum
            )

            DebugLog.print("✅ [ConnectionFormView] Successfully connected to database")

            try? modelContext.save()

            // Update app state
            appState.currentConnection = profile
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false

            // Load databases
            await loadDatabases()

            // Dismiss and transition to MainSplitView
            dismiss()

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
    
    /// Get the actual password value, handling the asterisks placeholder
    /// Returns the password from the field if it's been changed, otherwise returns stored password from keychain
    private func getActualPassword() -> String {
        if let connection = connectionToEdit {
            if connection.saveInKeychain {
                // Get from keychain
                if hasStoredPassword && !passwordModified {
                    return (try? KeychainService.getPassword(for: connection.id)) ?? ""
                }
            } else {
                // Get from model
                if !passwordModified {
                    return connection.password ?? ""
                }
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
    /// Uses "YOUR_PASSWORD" as placeholder if password exists, otherwise no password in string
    private func generateConnectionStringFromCurrentConnection() -> String {
        guard let connection = connectionToEdit else {
            return ""
        }
        
        // Check if password exists in keychain
        let hasPassword: Bool
        if let _ = try? KeychainService.getPassword(for: connection.id) {
            hasPassword = true
        } else {
            hasPassword = false
        }
        
        // Use "YOUR_PASSWORD" as placeholder if password exists, otherwise nil
        let passwordPlaceholder = hasPassword ? "YOUR_PASSWORD" : nil
        
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

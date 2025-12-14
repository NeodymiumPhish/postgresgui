//
//  PostgresGUIApp.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData
import AppKit

@main
struct PostgresGUIApp: App {
    @State private var appState = AppState()
    @State private var hasMigrated = UserDefaults.standard.bool(forKey: "didMigrateKeychainFlags_v1")

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConnectionProfile.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, try to delete the old database
            // Critical errors should remain visible in Release builds
            Swift.print("⚠️ Failed to create ModelContainer: \(error)")
            Swift.print("⚠️ Attempting to delete old database and create fresh...")

            // Get the default store URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupportURL.appendingPathComponent("default.store")

            do {
                // Remove all store files
                let storeFiles = [
                    storeURL,
                    storeURL.appendingPathExtension("wal"),
                    storeURL.appendingPathExtension("shm")
                ]

                for file in storeFiles {
                    if FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                        DebugLog.print("✅ Removed: \(file.lastPathComponent)")
                    }
                }

                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after cleanup: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    if !hasMigrated {
                        await migrateKeychainFlags()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(action: {
                    if let url = URL(string: "https://postgresgui.com/support") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Help and Support...", systemImage: "questionmark.circle")
                }
            }
        }
    }

    /// Migrate existing connections to use the saveInKeychain flag
    /// This ensures backward compatibility for connections created before the feature was added
    @MainActor
    private func migrateKeychainFlags() async {
        let context = sharedModelContainer.mainContext

        do {
            let descriptor = FetchDescriptor<ConnectionProfile>()
            let connections = try context.fetch(descriptor)

            var migratedCount = 0

            for connection in connections {
                // Only migrate connections that have default values (not yet migrated)
                if connection.saveInKeychain == false && connection.password == nil {
                    // Check if password exists in Keychain
                    if let _ = try? KeychainService.getPassword(for: connection.id) {
                        // Password exists in Keychain, set flag to true
                        connection.saveInKeychain = true
                        migratedCount += 1
                    }
                }
            }

            if migratedCount > 0 {
                try context.save()
                DebugLog.print("✅ Migrated \(migratedCount) connection(s) to use saveInKeychain flag")
            }

            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: "didMigrateKeychainFlags_v1")
            hasMigrated = true

        } catch {
            DebugLog.print("⚠️ Failed to migrate keychain flags: \(error)")
        }
    }
}

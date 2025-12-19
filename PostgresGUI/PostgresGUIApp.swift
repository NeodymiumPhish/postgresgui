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
    init() {
        // Enable automatic window tabbing
        NSWindow.allowsAutomaticWindowTabbing = true
    }

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
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // Remove Settings menu item (Cmd+,)
            CommandGroup(replacing: .appSettings) { }

            CommandGroup(after: .newItem) {
                Button(action: openNewTab) {
                    Text("New Tab")
                }
                .keyboardShortcut("t", modifiers: [.command])
            }

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

    private func openNewTab() {
        // Capture current connection/database for new tab (read from UserDefaults)
        if let idString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastConnectionId) {
            Constants.TabContext.pendingConnectionId = UUID(uuidString: idString)
            Constants.TabContext.pendingDatabaseName = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.lastDatabaseName)
        }

        if let currentWindow = NSApp.keyWindow,
           let windowController = currentWindow.windowController
        {
            windowController.newWindowForTab(nil)
            if let newWindow = NSApp.keyWindow, currentWindow != newWindow {
                currentWindow.addTabbedWindow(newWindow, ordered: .above)
            }
        }
    }
}

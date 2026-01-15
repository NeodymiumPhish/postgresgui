//
//  AppSettings.swift
//  PostgresGUI
//
//  Observable settings state using @AppStorage for persistence.
//

import SwiftUI

/// Keys for UserDefaults/AppStorage
enum SettingsKeys {
    static let dateFormat = "dateFormat"
}

/// Observable application settings
@Observable
@MainActor
final class AppSettings {
    /// The current date format preference
    var dateFormat: DateFormat {
        didSet {
            UserDefaults.standard.set(dateFormat.rawValue, forKey: SettingsKeys.dateFormat)
        }
    }

    /// Creates a DateFormatService configured with current settings
    var dateFormatService: DateFormatServiceProtocol {
        DateFormatService(dateFormat: dateFormat)
    }

    /// Shared instance for global access
    static let shared = AppSettings()

    private init() {
        // Load from UserDefaults on init
        let rawValue = UserDefaults.standard.string(forKey: SettingsKeys.dateFormat) ?? DateFormat.iso.rawValue
        self.dateFormat = DateFormat(rawValue: rawValue) ?? .iso
    }
}

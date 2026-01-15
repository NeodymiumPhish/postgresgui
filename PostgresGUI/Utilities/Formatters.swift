//
//  Formatters.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

enum Formatters {
    /// Format bytes to human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format number with thousand separators
    static func formatNumber(_ number: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Format PostgreSQL timestamp values using user's preferred format
    static func formatTimestamp(_ value: String) -> String {
        let service = currentDateFormatService()
        return service.formatTimestamp(value)
    }

    /// Creates a DateFormatService based on current user settings
    private static func currentDateFormatService() -> DateFormatServiceProtocol {
        let rawValue = UserDefaults.standard.string(forKey: SettingsKeys.dateFormat) ?? DateFormat.iso.rawValue
        let format = DateFormat(rawValue: rawValue) ?? .iso
        return DateFormatService(dateFormat: format)
    }
}

//
//  DateFormat.swift
//  PostgresGUI
//
//  Defines available date display formats for user preferences.
//

import Foundation

/// Available date display formats
enum DateFormat: String, CaseIterable, Identifiable {
    case iso = "iso"
    case isoDateOnly = "isoDateOnly"
    case us = "us"
    case european = "european"
    case relative = "relative"

    var id: String { rawValue }

    /// Human-readable name for the format
    var displayName: String {
        switch self {
        case .iso: return "ISO 8601"
        case .isoDateOnly: return "ISO 8601 (date only)"
        case .us: return "US"
        case .european: return "European"
        case .relative: return "Relative"
        }
    }

    /// Example of what the format looks like
    var example: String {
        let exampleDate = DateFormat.exampleDate
        return DateFormat.formatExample(exampleDate, format: self)
    }

    /// A fixed example date for consistent previews
    private static var exampleDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 14
        components.hour = 10
        components.minute = 30
        components.second = 45
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Format a date for example display
    private static func formatExample(_ date: Date, format: DateFormat) -> String {
        switch format {
        case .iso:
            return "2026-01-14 10:30:45"
        case .isoDateOnly:
            return "2026-01-14"
        case .us:
            return "01/14/2026 10:30 AM"
        case .european:
            return "14/01/2026 10:30"
        case .relative:
            return "2 hours ago"
        }
    }
}

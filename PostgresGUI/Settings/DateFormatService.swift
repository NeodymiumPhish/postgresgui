//
//  DateFormatService.swift
//  PostgresGUI
//
//  Service for formatting dates according to user preferences.
//

import Foundation

// MARK: - Protocol

/// Protocol for date formatting service
protocol DateFormatServiceProtocol {
    /// Format a Date object according to current settings
    func format(_ date: Date) -> String

    /// Format a timestamp string (parses then formats)
    func formatTimestamp(_ value: String) -> String
}

// MARK: - Implementation

/// Formats dates according to user preferences
final class DateFormatService: DateFormatServiceProtocol {

    private let dateFormat: DateFormat

    // MARK: - Cached Formatters

    private lazy var isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private lazy var isoDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private lazy var usFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy h:mm a"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private lazy var europeanFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        formatter.locale = Locale(identifier: "en_GB")
        return formatter
    }()

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // Fallback formatter for relative dates older than threshold
    private lazy var fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Parsing Formatters

    private lazy var iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private lazy var iso8601NoFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private lazy var postgresTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private lazy var postgresDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Initialization

    init(dateFormat: DateFormat) {
        self.dateFormat = dateFormat
    }

    // MARK: - DateFormatServiceProtocol

    func format(_ date: Date) -> String {
        switch dateFormat {
        case .iso:
            return isoFormatter.string(from: date)
        case .isoDateOnly:
            return isoDateOnlyFormatter.string(from: date)
        case .us:
            return usFormatter.string(from: date)
        case .european:
            return europeanFormatter.string(from: date)
        case .relative:
            return formatRelative(date)
        }
    }

    func formatTimestamp(_ value: String) -> String {
        guard let date = parseDate(value) else {
            return value
        }
        return format(date)
    }

    // MARK: - Private Helpers

    private func formatRelative(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        // Use relative for dates within the last 7 days
        if abs(timeInterval) < 7 * 24 * 60 * 60 {
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }

        // Fall back to medium format for older dates
        return fallbackFormatter.string(from: date)
    }

    private func parseDate(_ value: String) -> Date? {
        // Try ISO8601 with fractional seconds
        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        // Try ISO8601 without fractional seconds
        if let date = iso8601NoFractionFormatter.date(from: value) {
            return date
        }

        // Try PostgreSQL timestamp format
        if let date = postgresTimestampFormatter.date(from: value) {
            return date
        }

        // Try date-only format
        if let date = postgresDateFormatter.date(from: value) {
            return date
        }

        return nil
    }
}

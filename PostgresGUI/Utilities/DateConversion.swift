//
//  DateConversion.swift
//  PostgresGUI
//
//  Bidirectional date/time conversion for row editing.
//  Parses PostgreSQL date strings to Date and formats Date back to PostgreSQL-compatible strings.
//

import Foundation

/// The type of date/time column being edited
enum DateColumnType {
    case dateOnly       // PostgreSQL "date"
    case timeOnly       // PostgreSQL "time", "time without time zone", "time with time zone"
    case dateTime       // PostgreSQL "timestamp", "timestamp with time zone", "timestamptz"
}

/// Pure functions for converting between PostgreSQL date strings and Swift Date objects
enum DateConversion {

    // MARK: - Formatters (lazily initialized, thread-safe)

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let postgresTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Parsing (String → Date)

    /// Parse a PostgreSQL date/time string to a Date object
    /// - Parameters:
    ///   - string: The date string from PostgreSQL (e.g., "2024-01-15", "10:30:00", "2024-01-15T10:30:00.123Z")
    ///   - type: The type of date column
    /// - Returns: A Date if parsing succeeded, nil otherwise
    static func parse(_ string: String, type: DateColumnType) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch type {
        case .dateOnly:
            return dateOnlyFormatter.date(from: trimmed)

        case .timeOnly:
            return timeOnlyFormatter.date(from: trimmed)

        case .dateTime:
            // Try ISO8601 with fractional seconds first
            if let date = iso8601Formatter.date(from: trimmed) {
                return date
            }
            // Try ISO8601 without fractional seconds
            if let date = iso8601FormatterNoFraction.date(from: trimmed) {
                return date
            }
            // Try PostgreSQL timestamp format
            if let date = postgresTimestampFormatter.date(from: trimmed) {
                return date
            }
            return nil
        }
    }

    // MARK: - Formatting (Date → String)

    /// Format a Date to a PostgreSQL-compatible string
    /// - Parameters:
    ///   - date: The Date to format
    ///   - type: The type of date column
    /// - Returns: A string suitable for PostgreSQL insertion/update
    static func format(_ date: Date, type: DateColumnType) -> String {
        switch type {
        case .dateOnly:
            return dateOnlyFormatter.string(from: date)
        case .timeOnly:
            return timeOnlyFormatter.string(from: date)
        case .dateTime:
            return postgresTimestampFormatter.string(from: date)
        }
    }
}

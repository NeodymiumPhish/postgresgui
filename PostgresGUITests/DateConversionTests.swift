//
//  DateConversionTests.swift
//  PostgresGUITests
//
//  Unit tests for DateConversion utility.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("DateConversion")
struct DateConversionTests {

    // MARK: - Parse DateTime Tests

    @Suite("parse dateTime")
    struct ParseDateTimeTests {

        @Test func parsesISO8601WithFractionalSeconds() {
            let result = DateConversion.parse("2024-01-15T10:30:00.123Z", type: .dateTime)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                #expect(components.year == 2024)
                #expect(components.month == 1)
                #expect(components.day == 15)
            }
        }

        @Test func parsesISO8601WithoutFractionalSeconds() {
            let result = DateConversion.parse("2024-01-15T10:30:00Z", type: .dateTime)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                #expect(components.year == 2024)
                #expect(components.month == 1)
                #expect(components.day == 15)
            }
        }

        @Test func parsesPostgresTimestampFormat() {
            let result = DateConversion.parse("2024-01-15 10:30:00", type: .dateTime)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                #expect(components.year == 2024)
                #expect(components.month == 1)
                #expect(components.day == 15)
                #expect(components.hour == 10)
                #expect(components.minute == 30)
            }
        }

        @Test func returnsNilForInvalidFormat() {
            let result = DateConversion.parse("not a date", type: .dateTime)
            #expect(result == nil)
        }

        @Test func returnsNilForEmptyString() {
            let result = DateConversion.parse("", type: .dateTime)
            #expect(result == nil)
        }

        @Test func returnsNilForWhitespaceOnly() {
            let result = DateConversion.parse("   ", type: .dateTime)
            #expect(result == nil)
        }

        @Test func trimsWhitespace() {
            let result = DateConversion.parse("  2024-01-15 10:30:00  ", type: .dateTime)
            #expect(result != nil)
        }
    }

    // MARK: - Parse DateOnly Tests

    @Suite("parse dateOnly")
    struct ParseDateOnlyTests {

        @Test func parsesStandardDateFormat() {
            let result = DateConversion.parse("2024-01-15", type: .dateOnly)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                #expect(components.year == 2024)
                #expect(components.month == 1)
                #expect(components.day == 15)
            }
        }

        @Test func returnsNilForInvalidDate() {
            let result = DateConversion.parse("2024-13-45", type: .dateOnly)
            #expect(result == nil)
        }

        @Test func returnsNilForTimestampFormat() {
            // Full timestamp should not parse as date-only
            let result = DateConversion.parse("2024-01-15 10:30:00", type: .dateOnly)
            #expect(result == nil)
        }
    }

    // MARK: - Parse TimeOnly Tests

    @Suite("parse timeOnly")
    struct ParseTimeOnlyTests {

        @Test func parsesStandardTimeFormat() {
            let result = DateConversion.parse("10:30:00", type: .timeOnly)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.hour, .minute, .second], from: date)
                #expect(components.hour == 10)
                #expect(components.minute == 30)
                #expect(components.second == 0)
            }
        }

        @Test func parsesMidnight() {
            let result = DateConversion.parse("00:00:00", type: .timeOnly)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.hour, .minute], from: date)
                #expect(components.hour == 0)
                #expect(components.minute == 0)
            }
        }

        @Test func parsesEndOfDay() {
            let result = DateConversion.parse("23:59:59", type: .timeOnly)
            #expect(result != nil)

            if let date = result {
                let calendar = Calendar(identifier: .gregorian)
                let components = calendar.dateComponents([.hour, .minute, .second], from: date)
                #expect(components.hour == 23)
                #expect(components.minute == 59)
                #expect(components.second == 59)
            }
        }

        @Test func returnsNilForInvalidTime() {
            let result = DateConversion.parse("25:00:00", type: .timeOnly)
            #expect(result == nil)
        }
    }

    // MARK: - Format DateTime Tests

    @Suite("format dateTime")
    struct FormatDateTimeTests {

        @Test func formatsToPostgresTimestampFormat() {
            // Create a known date
            var components = DateComponents()
            components.year = 2024
            components.month = 1
            components.day = 15
            components.hour = 10
            components.minute = 30
            components.second = 45
            let calendar = Calendar(identifier: .gregorian)
            let date = calendar.date(from: components)!

            let result = DateConversion.format(date, type: .dateTime)
            #expect(result == "2024-01-15 10:30:45")
        }
    }

    // MARK: - Format DateOnly Tests

    @Suite("format dateOnly")
    struct FormatDateOnlyTests {

        @Test func formatsToDateOnlyFormat() {
            var components = DateComponents()
            components.year = 2024
            components.month = 1
            components.day = 15
            let calendar = Calendar(identifier: .gregorian)
            let date = calendar.date(from: components)!

            let result = DateConversion.format(date, type: .dateOnly)
            #expect(result == "2024-01-15")
        }
    }

    // MARK: - Format TimeOnly Tests

    @Suite("format timeOnly")
    struct FormatTimeOnlyTests {

        @Test func formatsToTimeOnlyFormat() {
            var components = DateComponents()
            components.hour = 10
            components.minute = 30
            components.second = 45
            let calendar = Calendar(identifier: .gregorian)
            let date = calendar.date(from: components)!

            let result = DateConversion.format(date, type: .timeOnly)
            #expect(result == "10:30:45")
        }

        @Test func formatsMidnight() {
            var components = DateComponents()
            components.hour = 0
            components.minute = 0
            components.second = 0
            let calendar = Calendar(identifier: .gregorian)
            let date = calendar.date(from: components)!

            let result = DateConversion.format(date, type: .timeOnly)
            #expect(result == "00:00:00")
        }
    }

    // MARK: - Round Trip Tests

    @Suite("Round Trip")
    struct RoundTripTests {

        @Test func dateTimeRoundTrip() {
            let original = "2024-01-15 10:30:45"
            if let parsed = DateConversion.parse(original, type: .dateTime) {
                let formatted = DateConversion.format(parsed, type: .dateTime)
                #expect(formatted == original)
            } else {
                Issue.record("Failed to parse original timestamp")
            }
        }

        @Test func dateOnlyRoundTrip() {
            let original = "2024-01-15"
            if let parsed = DateConversion.parse(original, type: .dateOnly) {
                let formatted = DateConversion.format(parsed, type: .dateOnly)
                #expect(formatted == original)
            } else {
                Issue.record("Failed to parse original date")
            }
        }

        @Test func timeOnlyRoundTrip() {
            let original = "10:30:45"
            if let parsed = DateConversion.parse(original, type: .timeOnly) {
                let formatted = DateConversion.format(parsed, type: .timeOnly)
                #expect(formatted == original)
            } else {
                Issue.record("Failed to parse original time")
            }
        }

        @Test func iso8601ToPostgresConversion() {
            // Parse ISO8601 and format back as PostgreSQL format
            let iso8601 = "2024-01-15T10:30:45Z"
            if let parsed = DateConversion.parse(iso8601, type: .dateTime) {
                let formatted = DateConversion.format(parsed, type: .dateTime)
                // Should be in PostgreSQL format now
                #expect(formatted.contains(" "))  // Space separator instead of T
                #expect(!formatted.contains("T"))
                #expect(!formatted.contains("Z"))
            } else {
                Issue.record("Failed to parse ISO8601 timestamp")
            }
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test func handlesLeapYear() {
            let result = DateConversion.parse("2024-02-29", type: .dateOnly)
            #expect(result != nil)  // 2024 is a leap year
        }

        @Test func rejectsInvalidLeapYear() {
            let result = DateConversion.parse("2023-02-29", type: .dateOnly)
            #expect(result == nil)  // 2023 is not a leap year
        }

        @Test func handlesEndOfMonth() {
            let result = DateConversion.parse("2024-01-31", type: .dateOnly)
            #expect(result != nil)
        }

        @Test func rejectsInvalidDayForMonth() {
            let result = DateConversion.parse("2024-04-31", type: .dateOnly)
            #expect(result == nil)  // April has 30 days
        }

        @Test func handlesNewYearsEve() {
            let result = DateConversion.parse("2024-12-31 23:59:59", type: .dateTime)
            #expect(result != nil)
        }

        @Test func handlesNewYearsDay() {
            let result = DateConversion.parse("2024-01-01 00:00:00", type: .dateTime)
            #expect(result != nil)
        }
    }
}

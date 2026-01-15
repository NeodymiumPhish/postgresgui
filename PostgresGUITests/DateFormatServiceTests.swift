//
//  DateFormatServiceTests.swift
//  PostgresGUITests
//
//  Unit tests for DateFormatService.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("DateFormatService")
struct DateFormatServiceTests {

    // MARK: - Test Date

    /// Fixed test date: 2026-01-14 10:30:45
    private static var testDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 14
        components.hour = 10
        components.minute = 30
        components.second = 45
        components.timeZone = TimeZone.current
        return Calendar.current.date(from: components)!
    }

    // MARK: - Format Tests

    @Suite("ISO Format")
    struct ISOFormatTests {
        @Test func formatsDateInISOFormat() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.format(DateFormatServiceTests.testDate)
            #expect(result == "2026-01-14 10:30:45")
        }

        @Test func formatsTimestampStringInISOFormat() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.formatTimestamp("2026-01-14T10:30:45Z")
            // Date should be present (might be adjusted for local timezone)
            #expect(result.contains("2026-01-1"))
            // Time should be present (format: HH:mm:ss)
            #expect(result.contains(":"))
        }
    }

    @Suite("ISO Date Only Format")
    struct ISODateOnlyFormatTests {
        @Test func formatsDateInISODateOnlyFormat() {
            let service = DateFormatService(dateFormat: .isoDateOnly)
            let result = service.format(DateFormatServiceTests.testDate)
            #expect(result == "2026-01-14")
        }

        @Test func excludesTimeComponent() {
            let service = DateFormatService(dateFormat: .isoDateOnly)
            let result = service.format(DateFormatServiceTests.testDate)
            #expect(!result.contains(":"))
        }
    }

    @Suite("US Format")
    struct USFormatTests {
        @Test func formatsDateInUSFormat() {
            let service = DateFormatService(dateFormat: .us)
            let result = service.format(DateFormatServiceTests.testDate)
            // US format: MM/dd/yyyy h:mm a
            #expect(result.contains("01/14/2026"))
            #expect(result.contains("AM") || result.contains("PM"))
        }

        @Test func usesCorrectSlashSeparator() {
            let service = DateFormatService(dateFormat: .us)
            let result = service.format(DateFormatServiceTests.testDate)
            #expect(result.contains("/"))
        }
    }

    @Suite("European Format")
    struct EuropeanFormatTests {
        @Test func formatsDateInEuropeanFormat() {
            let service = DateFormatService(dateFormat: .european)
            let result = service.format(DateFormatServiceTests.testDate)
            // European format: dd/MM/yyyy HH:mm
            #expect(result.contains("14/01/2026"))
        }

        @Test func uses24HourTime() {
            let service = DateFormatService(dateFormat: .european)
            let result = service.format(DateFormatServiceTests.testDate)
            // Should not contain AM/PM
            #expect(!result.contains("AM") && !result.contains("PM"))
        }
    }

    @Suite("Relative Format")
    struct RelativeFormatTests {
        @Test func formatsRecentDateRelatively() {
            let service = DateFormatService(dateFormat: .relative)
            let recentDate = Date().addingTimeInterval(-3600) // 1 hour ago
            let result = service.format(recentDate)
            // Should contain relative words
            #expect(result.contains("hour") || result.contains("minute") || result.contains("ago"))
        }

        @Test func fallsBackForOldDates() {
            let service = DateFormatService(dateFormat: .relative)
            let oldDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
            let result = service.format(oldDate)
            // Should fall back to medium format (not relative)
            #expect(!result.contains("ago"))
        }
    }

    // MARK: - Parsing Tests

    @Suite("Timestamp Parsing")
    struct TimestampParsingTests {
        @Test func parsesISO8601WithFractionalSeconds() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.formatTimestamp("2024-11-30T12:34:56.789Z")
            #expect(result.contains("2024-11-30"))
        }

        @Test func parsesISO8601WithoutFractionalSeconds() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.formatTimestamp("2024-11-30T12:34:56Z")
            #expect(result.contains("2024-11-30"))
        }

        @Test func parsesPostgresTimestamp() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.formatTimestamp("2024-11-30 12:34:56")
            #expect(result.contains("2024-11-30"))
        }

        @Test func parsesDateOnly() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.formatTimestamp("2024-11-30")
            #expect(result.contains("2024-11-30"))
        }

        @Test func returnsOriginalForInvalidFormat() {
            let service = DateFormatService(dateFormat: .iso)
            let invalid = "not a date"
            let result = service.formatTimestamp(invalid)
            #expect(result == invalid)
        }

        @Test func returnsOriginalForEmptyString() {
            let service = DateFormatService(dateFormat: .iso)
            let result = service.formatTimestamp("")
            #expect(result == "")
        }
    }

    // MARK: - DateFormat Enum Tests

    @Suite("DateFormat Enum")
    struct DateFormatEnumTests {
        @Test func allCasesReturnsAllFormats() {
            #expect(DateFormat.allCases.count == 5)
        }

        @Test func rawValuesAreUnique() {
            let rawValues = DateFormat.allCases.map { $0.rawValue }
            let uniqueRawValues = Set(rawValues)
            #expect(rawValues.count == uniqueRawValues.count)
        }

        @Test func displayNamesAreNotEmpty() {
            for format in DateFormat.allCases {
                #expect(!format.displayName.isEmpty)
            }
        }

        @Test func examplesAreNotEmpty() {
            for format in DateFormat.allCases {
                #expect(!format.example.isEmpty)
            }
        }

        @Test func initFromRawValueWorks() {
            #expect(DateFormat(rawValue: "iso") == .iso)
            #expect(DateFormat(rawValue: "us") == .us)
            #expect(DateFormat(rawValue: "european") == .european)
            #expect(DateFormat(rawValue: "relative") == .relative)
            #expect(DateFormat(rawValue: "isoDateOnly") == .isoDateOnly)
        }

        @Test func initFromInvalidRawValueReturnsNil() {
            #expect(DateFormat(rawValue: "invalid") == nil)
        }
    }
}

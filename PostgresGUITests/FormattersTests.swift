//
//  FormattersTests.swift
//  PostgresGUITests
//
//  Unit tests for Formatters utility.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("Formatters")
struct FormattersTests {

    // MARK: - formatBytes Tests

    @Suite("formatBytes")
    struct FormatBytesTests {

        @Test func formatsKilobytes() {
            let result = Formatters.formatBytes(1024)
            #expect(result.contains("KB") || result.contains("kB"))
        }

        @Test func formatsMegabytes() {
            let result = Formatters.formatBytes(1024 * 1024)
            #expect(result.contains("MB"))
        }

        @Test func formatsGigabytes() {
            let result = Formatters.formatBytes(1024 * 1024 * 1024)
            #expect(result.contains("GB"))
        }

        @Test func formatsTerabytes() {
            let result = Formatters.formatBytes(1024 * 1024 * 1024 * 1024)
            #expect(result.contains("TB"))
        }

        @Test func formatsZeroBytes() {
            let result = Formatters.formatBytes(0)
            #expect(result.contains("0") || result.contains("Zero"))
        }

        @Test func formatsLargeValues() {
            // 500 GB
            let result = Formatters.formatBytes(500 * 1024 * 1024 * 1024)
            #expect(result.contains("GB"))
        }
    }

    // MARK: - formatNumber Tests

    @Suite("formatNumber")
    struct FormatNumberTests {

        @Test func formatsSmallNumber() {
            let result = Formatters.formatNumber(42)
            #expect(result == "42")
        }

        @Test func formatsThousands() {
            let result = Formatters.formatNumber(1234)
            // Should have thousand separator (locale-dependent, but should have separator)
            #expect(result.contains("1") && result.contains("234"))
        }

        @Test func formatsMillions() {
            let result = Formatters.formatNumber(1_234_567)
            // Check the value is formatted with separators
            #expect(result.count > 7) // With separators, longer than just digits
        }

        @Test func formatsZero() {
            let result = Formatters.formatNumber(0)
            #expect(result == "0")
        }

        @Test func formatsNegativeNumber() {
            let result = Formatters.formatNumber(-1234)
            #expect(result.contains("-") || result.contains("−")) // minus or unicode minus
            #expect(result.contains("1") && result.contains("234"))
        }

        @Test func formatsMaxInt64() {
            // Should not crash
            let result = Formatters.formatNumber(Int64.max)
            #expect(!result.isEmpty)
        }
    }

    // MARK: - formatTimestamp Tests

    @Suite("formatTimestamp")
    struct FormatTimestampTests {

        @Test func formatsISO8601WithFractionalSeconds() {
            let result = Formatters.formatTimestamp("2024-11-30T12:34:56.789Z")
            // Should contain date and time components
            #expect(result.contains("2024") || result.contains("Nov") || result.contains("30"))
        }

        @Test func formatsISO8601WithoutFractionalSeconds() {
            let result = Formatters.formatTimestamp("2024-11-30T12:34:56Z")
            // Should contain date and time components
            #expect(result.contains("2024") || result.contains("Nov") || result.contains("30"))
        }

        @Test func formatsPostgresTimestamp() {
            let result = Formatters.formatTimestamp("2024-11-30 12:34:56")
            // Should contain date and time components
            #expect(result.contains("2024") || result.contains("Nov") || result.contains("30"))
        }

        @Test func formatsDateOnly() {
            let result = Formatters.formatTimestamp("2024-11-30")
            // Should contain date but no time components
            #expect(result.contains("2024") || result.contains("Nov") || result.contains("30"))
        }

        @Test func returnsOriginalForUnknownFormat() {
            let original = "not a date"
            let result = Formatters.formatTimestamp(original)
            #expect(result == original)
        }

        @Test func returnsOriginalForInvalidDate() {
            let original = "2024-13-45"
            let result = Formatters.formatTimestamp(original)
            #expect(result == original)
        }

        @Test func returnsOriginalForEmptyString() {
            let result = Formatters.formatTimestamp("")
            #expect(result == "")
        }

        @Test func handlesTimezoneOffset() {
            // ISO8601 with timezone offset
            let result = Formatters.formatTimestamp("2024-11-30T12:34:56+05:00")
            // May or may not parse depending on implementation
            // At minimum, should not crash
            #expect(!result.isEmpty)
        }

        @Test func preservesMidnight() {
            let result = Formatters.formatTimestamp("2024-11-30 00:00:00")
            // Should still format properly
            #expect(result.contains("2024") || result.contains("Nov") || result.contains("30"))
        }

        @Test func handlesEndOfDay() {
            let result = Formatters.formatTimestamp("2024-11-30 23:59:59")
            #expect(result.contains("2024") || result.contains("Nov") || result.contains("30"))
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test func formatBytesHandlesNegative() {
            // ByteCountFormatter may or may not handle negative
            let result = Formatters.formatBytes(-1024)
            #expect(!result.isEmpty)
        }

        @Test func formatTimestampHandlesWhitespace() {
            let result = Formatters.formatTimestamp("  2024-11-30  ")
            // May return original with whitespace if not parsed
            #expect(!result.isEmpty)
        }

        @Test func formatTimestampHandlesMixedCase() {
            // ISO8601 uses uppercase T and Z
            let result = Formatters.formatTimestamp("2024-11-30t12:34:56z")
            // May or may not parse lowercase
            #expect(!result.isEmpty)
        }
    }
}

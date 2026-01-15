//
//  NetworkTypeValidationTests.swift
//  PostgresGUITests
//
//  Unit tests for NetworkTypeValidation utility.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("NetworkTypeValidation")
struct NetworkTypeValidationTests {

    // MARK: - NetworkAddressType.from Tests

    @Suite("NetworkAddressType.from")
    struct NetworkAddressTypeFromTests {

        @Test func parsesInet() {
            #expect(NetworkAddressType.from(dataType: "inet") == .inet)
            #expect(NetworkAddressType.from(dataType: "INET") == .inet)
        }

        @Test func parsesCidr() {
            #expect(NetworkAddressType.from(dataType: "cidr") == .cidr)
            #expect(NetworkAddressType.from(dataType: "CIDR") == .cidr)
        }

        @Test func parsesMacaddr() {
            #expect(NetworkAddressType.from(dataType: "macaddr") == .macaddr)
            #expect(NetworkAddressType.from(dataType: "MACADDR") == .macaddr)
        }

        @Test func parsesMacaddr8() {
            #expect(NetworkAddressType.from(dataType: "macaddr8") == .macaddr8)
            #expect(NetworkAddressType.from(dataType: "MACADDR8") == .macaddr8)
        }

        @Test func returnsNilForUnknownType() {
            #expect(NetworkAddressType.from(dataType: "varchar") == nil)
            #expect(NetworkAddressType.from(dataType: "integer") == nil)
        }
    }

    // MARK: - inet Validation Tests

    @Suite("validate inet")
    struct ValidateInetTests {

        // IPv4 Tests

        @Test func validatesSimpleIPv4() {
            let result = NetworkTypeValidation.validate("192.168.1.1", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv4WithPrefix() {
            let result = NetworkTypeValidation.validate("192.168.1.0/24", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv4HostWithPrefix() {
            // inet allows host bits to be set (unlike cidr)
            let result = NetworkTypeValidation.validate("192.168.1.1/24", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv4AllZeros() {
            let result = NetworkTypeValidation.validate("0.0.0.0", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv4Broadcast() {
            let result = NetworkTypeValidation.validate("255.255.255.255", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv4Localhost() {
            let result = NetworkTypeValidation.validate("127.0.0.1", type: .inet)
            #expect(result.isValid)
        }

        @Test func rejectsIPv4OctetTooLarge() {
            let result = NetworkTypeValidation.validate("192.168.1.256", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("0-255") == true)
        }

        @Test func rejectsIPv4TooFewOctets() {
            let result = NetworkTypeValidation.validate("192.168.1", type: .inet)
            #expect(!result.isValid)
        }

        @Test func rejectsIPv4TooManyOctets() {
            let result = NetworkTypeValidation.validate("192.168.1.1.1", type: .inet)
            #expect(!result.isValid)
        }

        @Test func rejectsIPv4LeadingZeros() {
            let result = NetworkTypeValidation.validate("192.168.01.1", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("leading zeros") == true)
        }

        @Test func rejectsIPv4InvalidPrefix() {
            let result = NetworkTypeValidation.validate("192.168.1.0/33", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("0-32") == true)
        }

        @Test func rejectsIPv4NegativePrefix() {
            let result = NetworkTypeValidation.validate("192.168.1.0/-1", type: .inet)
            #expect(!result.isValid)
        }

        // IPv6 Tests

        @Test func validatesSimpleIPv6() {
            let result = NetworkTypeValidation.validate("2001:db8::1", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesFullIPv6() {
            let result = NetworkTypeValidation.validate("2001:0db8:0000:0000:0000:0000:0000:0001", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv6WithPrefix() {
            let result = NetworkTypeValidation.validate("2001:db8::/32", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv6Localhost() {
            let result = NetworkTypeValidation.validate("::1", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv6AllZeros() {
            let result = NetworkTypeValidation.validate("::", type: .inet)
            #expect(result.isValid)
        }

        @Test func validatesIPv6LinkLocal() {
            let result = NetworkTypeValidation.validate("fe80::1", type: .inet)
            #expect(result.isValid)
        }

        @Test func rejectsIPv6MultipleDoubleColon() {
            let result = NetworkTypeValidation.validate("2001::db8::1", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("one ::") == true)
        }

        @Test func rejectsIPv6GroupTooLong() {
            let result = NetworkTypeValidation.validate("2001:db8:12345::1", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("4 hex digits") == true)
        }

        @Test func rejectsIPv6InvalidPrefix() {
            let result = NetworkTypeValidation.validate("2001:db8::/129", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("0-128") == true)
        }

        @Test func rejectsEmptyString() {
            let result = NetworkTypeValidation.validate("", type: .inet)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("empty") == true)
        }

        @Test func rejectsWhitespaceOnly() {
            let result = NetworkTypeValidation.validate("   ", type: .inet)
            #expect(!result.isValid)
        }

        @Test func trimsWhitespace() {
            let result = NetworkTypeValidation.validate("  192.168.1.1  ", type: .inet)
            #expect(result.isValid)
        }
    }

    // MARK: - cidr Validation Tests

    @Suite("validate cidr")
    struct ValidateCidrTests {

        @Test func validatesNetworkAddress() {
            let result = NetworkTypeValidation.validate("192.168.0.0/24", type: .cidr)
            #expect(result.isValid)
        }

        @Test func validatesClassANetwork() {
            let result = NetworkTypeValidation.validate("10.0.0.0/8", type: .cidr)
            #expect(result.isValid)
        }

        @Test func validatesClassBNetwork() {
            let result = NetworkTypeValidation.validate("172.16.0.0/12", type: .cidr)
            #expect(result.isValid)
        }

        @Test func validatesSlash32() {
            let result = NetworkTypeValidation.validate("192.168.1.1/32", type: .cidr)
            #expect(result.isValid)
        }

        @Test func validatesSlash0() {
            let result = NetworkTypeValidation.validate("0.0.0.0/0", type: .cidr)
            #expect(result.isValid)
        }

        @Test func rejectsHostBitsSet() {
            // 192.168.1.1/24 has host bits set (the .1 in the last octet)
            let result = NetworkTypeValidation.validate("192.168.1.1/24", type: .cidr)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("host bits") == true)
        }

        @Test func rejectsMissingPrefix() {
            let result = NetworkTypeValidation.validate("192.168.0.0", type: .cidr)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("requires") == true)
        }

        @Test func validatesIPv6Network() {
            let result = NetworkTypeValidation.validate("2001:db8::/32", type: .cidr)
            #expect(result.isValid)
        }

        @Test func rejectsIPv6HostBitsSet() {
            let result = NetworkTypeValidation.validate("2001:db8::1/32", type: .cidr)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("host bits") == true)
        }

        @Test func validatesIPv6Slash128() {
            let result = NetworkTypeValidation.validate("2001:db8::1/128", type: .cidr)
            #expect(result.isValid)
        }
    }

    // MARK: - macaddr Validation Tests

    @Suite("validate macaddr")
    struct ValidateMacaddrTests {

        // Standard formats

        @Test func validatesColonSeparated() {
            let result = NetworkTypeValidation.validate("08:00:2b:01:02:03", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesHyphenSeparated() {
            let result = NetworkTypeValidation.validate("08-00-2b-01-02-03", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesDotSeparated() {
            let result = NetworkTypeValidation.validate("0800.2b01.0203", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesNoSeparators() {
            let result = NetworkTypeValidation.validate("08002b010203", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesUppercase() {
            let result = NetworkTypeValidation.validate("08:00:2B:01:02:03", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesMixedCase() {
            let result = NetworkTypeValidation.validate("08:00:2B:01:02:Aa", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesAllZeros() {
            let result = NetworkTypeValidation.validate("00:00:00:00:00:00", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesAllFs() {
            let result = NetworkTypeValidation.validate("ff:ff:ff:ff:ff:ff", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func validatesCompressedColonFormat() {
            // PostgreSQL accepts this format: 08002b:010203
            let result = NetworkTypeValidation.validate("08002b:010203", type: .macaddr)
            #expect(result.isValid)
        }

        // Invalid formats

        @Test func rejectsTooShort() {
            let result = NetworkTypeValidation.validate("08:00:2b:01:02", type: .macaddr)
            #expect(!result.isValid)
        }

        @Test func rejectsTooLong() {
            let result = NetworkTypeValidation.validate("08:00:2b:01:02:03:04", type: .macaddr)
            #expect(!result.isValid)
        }

        @Test func rejectsInvalidHex() {
            let result = NetworkTypeValidation.validate("08:00:2g:01:02:03", type: .macaddr)
            #expect(!result.isValid)
            #expect(result.errorMessage?.contains("hexadecimal") == true)
        }

        @Test func rejectsMixedSeparators() {
            let result = NetworkTypeValidation.validate("08:00-2b:01:02:03", type: .macaddr)
            #expect(!result.isValid)
        }

        @Test func rejectsInconsistentGroupSize() {
            let result = NetworkTypeValidation.validate("08:0:2b:01:02:03", type: .macaddr)
            #expect(!result.isValid)
        }

        @Test func rejectsEmptyString() {
            let result = NetworkTypeValidation.validate("", type: .macaddr)
            #expect(!result.isValid)
        }
    }

    // MARK: - macaddr8 Validation Tests

    @Suite("validate macaddr8")
    struct ValidateMacaddr8Tests {

        // 8-byte formats

        @Test func validatesEUI64ColonSeparated() {
            let result = NetworkTypeValidation.validate("08:00:2b:ff:fe:01:02:03", type: .macaddr8)
            #expect(result.isValid)
        }

        @Test func validatesEUI64HyphenSeparated() {
            let result = NetworkTypeValidation.validate("08-00-2b-ff-fe-01-02-03", type: .macaddr8)
            #expect(result.isValid)
        }

        @Test func validatesEUI64DotSeparated() {
            let result = NetworkTypeValidation.validate("0800.2bff.fe01.0203", type: .macaddr8)
            #expect(result.isValid)
        }

        @Test func validatesEUI64NoSeparators() {
            let result = NetworkTypeValidation.validate("08002bfffe010203", type: .macaddr8)
            #expect(result.isValid)
        }

        // 6-byte formats (auto-expanded by PostgreSQL)

        @Test func accepts6ByteFormat() {
            // PostgreSQL auto-expands 6-byte to 8-byte with FF:FE in the middle
            let result = NetworkTypeValidation.validate("08:00:2b:01:02:03", type: .macaddr8)
            #expect(result.isValid)
        }

        @Test func accepts6ByteNoSeparators() {
            let result = NetworkTypeValidation.validate("08002b010203", type: .macaddr8)
            #expect(result.isValid)
        }

        // Invalid formats

        @Test func rejects7ByteFormat() {
            let result = NetworkTypeValidation.validate("08:00:2b:ff:01:02:03", type: .macaddr8)
            #expect(!result.isValid)
        }

        @Test func rejectsInvalidHex() {
            let result = NetworkTypeValidation.validate("08:00:2b:ff:fe:01:02:0g", type: .macaddr8)
            #expect(!result.isValid)
        }

        @Test func rejectsTooLong() {
            let result = NetworkTypeValidation.validate("08:00:2b:ff:fe:01:02:03:04", type: .macaddr8)
            #expect(!result.isValid)
        }
    }

    // MARK: - ValidationResult Tests

    @Suite("ValidationResult")
    struct ValidationResultTests {

        @Test func validResultIsValid() {
            let result = NetworkValidationResult.valid
            #expect(result.isValid)
            #expect(result.errorMessage == nil)
        }

        @Test func invalidResultIsNotValid() {
            let result = NetworkValidationResult.invalid(reason: "Test error")
            #expect(!result.isValid)
            #expect(result.errorMessage == "Test error")
        }

        @Test func validResultsAreEqual() {
            #expect(NetworkValidationResult.valid == NetworkValidationResult.valid)
        }

        @Test func invalidResultsWithSameReasonAreEqual() {
            let result1 = NetworkValidationResult.invalid(reason: "Same error")
            let result2 = NetworkValidationResult.invalid(reason: "Same error")
            #expect(result1 == result2)
        }

        @Test func invalidResultsWithDifferentReasonsAreNotEqual() {
            let result1 = NetworkValidationResult.invalid(reason: "Error 1")
            let result2 = NetworkValidationResult.invalid(reason: "Error 2")
            #expect(result1 != result2)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test func handlesIPv4MappedIPv6() {
            let result = NetworkTypeValidation.validate("::ffff:192.168.1.1", type: .inet)
            #expect(result.isValid)
        }

        @Test func handlesIPv6WithEmbeddedIPv4() {
            let result = NetworkTypeValidation.validate("::192.168.1.1", type: .inet)
            #expect(result.isValid)
        }

        @Test func handlesPrivateIPv4Ranges() {
            #expect(NetworkTypeValidation.validate("10.0.0.1", type: .inet).isValid)
            #expect(NetworkTypeValidation.validate("172.16.0.1", type: .inet).isValid)
            #expect(NetworkTypeValidation.validate("192.168.0.1", type: .inet).isValid)
        }

        @Test func handlesBroadcastMAC() {
            let result = NetworkTypeValidation.validate("ff:ff:ff:ff:ff:ff", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func handlesMulticastMAC() {
            // Multicast MAC addresses have the least significant bit of the first octet set to 1
            let result = NetworkTypeValidation.validate("01:00:5e:00:00:01", type: .macaddr)
            #expect(result.isValid)
        }

        @Test func handlesLocallyAdministeredMAC() {
            // Locally administered MAC addresses have the second least significant bit of first octet set to 1
            let result = NetworkTypeValidation.validate("02:00:00:00:00:01", type: .macaddr)
            #expect(result.isValid)
        }
    }
}

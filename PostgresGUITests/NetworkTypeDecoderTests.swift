//
//  NetworkTypeDecoderTests.swift
//  PostgresGUITests
//
//  Unit tests for NetworkTypeDecoder - decoding binary network types from PostgreSQL.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("NetworkTypeDecoder")
struct NetworkTypeDecoderTests {

    // MARK: - inet/cidr IPv4 Tests

    @Suite("decodeInetOrCidr IPv4")
    struct DecodeIPv4Tests {

        @Test func decodesSimpleIPv4() {
            // IPv4: 192.168.1.1/32 (host address, no prefix shown)
            // Format: [family=2][prefix=32][is_cidr=0][length=4][192][168][1][1]
            let bytes: [UInt8] = [2, 32, 0, 4, 192, 168, 1, 1]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "192.168.1.1")
        }

        @Test func decodesIPv4WithPrefix() {
            // IPv4: 192.168.1.0/24 (network)
            // Format: [family=2][prefix=24][is_cidr=0][length=4][192][168][1][0]
            let bytes: [UInt8] = [2, 24, 0, 4, 192, 168, 1, 0]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "192.168.1.0/24")
        }

        @Test func decodesCidrIPv4Network() {
            // CIDR: 10.0.0.0/8 (class A network)
            // Format: [family=2][prefix=8][is_cidr=1][length=4][10][0][0][0]
            let bytes: [UInt8] = [2, 8, 1, 4, 10, 0, 0, 0]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "10.0.0.0/8")
        }

        @Test func decodesLocalhost() {
            // IPv4: 127.0.0.1/32
            let bytes: [UInt8] = [2, 32, 0, 4, 127, 0, 0, 1]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "127.0.0.1")
        }

        @Test func decodesBroadcast() {
            // IPv4: 255.255.255.255/32
            let bytes: [UInt8] = [2, 32, 0, 4, 255, 255, 255, 255]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "255.255.255.255")
        }

        @Test func decodesSlash0() {
            // CIDR: 0.0.0.0/0 (default route)
            let bytes: [UInt8] = [2, 0, 1, 4, 0, 0, 0, 0]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "0.0.0.0/0")
        }
    }

    // MARK: - inet/cidr IPv6 Tests

    @Suite("decodeInetOrCidr IPv6")
    struct DecodeIPv6Tests {

        @Test func decodesIPv6Localhost() {
            // IPv6: ::1/128
            // Format: [family=3][prefix=128][is_cidr=0][length=16][16 bytes of address]
            var bytes: [UInt8] = [3, 128, 0, 16]
            bytes.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "::1")
        }

        @Test func decodesIPv6AllZeros() {
            // IPv6: ::/0
            var bytes: [UInt8] = [3, 0, 1, 16]
            bytes.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "::/0")
        }

        @Test func decodesIPv6Network() {
            // IPv6: 2001:db8::/32
            // 2001:0db8:0000:0000:0000:0000:0000:0000
            var bytes: [UInt8] = [3, 32, 1, 16]
            bytes.append(contentsOf: [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "2001:db8::/32")
        }

        @Test func decodesIPv6FullAddress() {
            // IPv6: 2001:db8:85a3:8d3:1319:8a2e:370:7348/128
            var bytes: [UInt8] = [3, 128, 0, 16]
            bytes.append(contentsOf: [0x20, 0x01, 0x0d, 0xb8, 0x85, 0xa3, 0x08, 0xd3,
                                      0x13, 0x19, 0x8a, 0x2e, 0x03, 0x70, 0x73, 0x48])
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "2001:db8:85a3:8d3:1319:8a2e:370:7348")
        }

        @Test func decodesRealWorldCidr() {
            // Based on screenshot: 2a00:2381:3f54::/56
            // This was showing as: 0x033801102a0023813f5400000000000000000000
            // Parsing: 03=family(IPv6), 38=prefix(56), 01=is_cidr, 10=length(16)
            // Address: 2a00:2381:3f54:0000:0000:0000:0000:0000
            var bytes: [UInt8] = [3, 56, 1, 16]
            bytes.append(contentsOf: [0x2a, 0x00, 0x23, 0x81, 0x3f, 0x54, 0x00, 0x00,
                                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "2a00:2381:3f54::/56")
        }

        @Test func decodesIPv6LinkLocal() {
            // IPv6: fe80::1/128
            var bytes: [UInt8] = [3, 128, 0, 16]
            bytes.append(contentsOf: [0xfe, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == "fe80::1")
        }
    }

    // MARK: - macaddr Tests

    @Suite("decodeMacaddr")
    struct DecodeMacaddrTests {

        @Test func decodesStandardMac() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03]
            let result = NetworkTypeDecoder.decodeMacaddr(bytes)
            #expect(result == "08:00:2b:01:02:03")
        }

        @Test func decodesAllZeros() {
            let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            let result = NetworkTypeDecoder.decodeMacaddr(bytes)
            #expect(result == "00:00:00:00:00:00")
        }

        @Test func decodesBroadcast() {
            let bytes: [UInt8] = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]
            let result = NetworkTypeDecoder.decodeMacaddr(bytes)
            #expect(result == "ff:ff:ff:ff:ff:ff")
        }

        @Test func rejectsTooShort() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0x01, 0x02]
            let result = NetworkTypeDecoder.decodeMacaddr(bytes)
            #expect(result == nil)
        }

        @Test func rejectsTooLong() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03, 0x04]
            let result = NetworkTypeDecoder.decodeMacaddr(bytes)
            #expect(result == nil)
        }
    }

    // MARK: - macaddr8 Tests

    @Suite("decodeMacaddr8")
    struct DecodeMacaddr8Tests {

        @Test func decodesEUI64() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0xff, 0xfe, 0x01, 0x02, 0x03]
            let result = NetworkTypeDecoder.decodeMacaddr8(bytes)
            #expect(result == "08:00:2b:ff:fe:01:02:03")
        }

        @Test func decodesAllZeros() {
            let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            let result = NetworkTypeDecoder.decodeMacaddr8(bytes)
            #expect(result == "00:00:00:00:00:00:00:00")
        }

        @Test func rejectsTooShort() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0xff, 0xfe, 0x01, 0x02]
            let result = NetworkTypeDecoder.decodeMacaddr8(bytes)
            #expect(result == nil)
        }

        @Test func rejectsTooLong() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0xff, 0xfe, 0x01, 0x02, 0x03, 0x04]
            let result = NetworkTypeDecoder.decodeMacaddr8(bytes)
            #expect(result == nil)
        }
    }

    // MARK: - decode with OID Tests

    @Suite("decode with OID")
    struct DecodeWithOIDTests {

        @Test func decodesInetByOID() {
            let bytes: [UInt8] = [2, 32, 0, 4, 192, 168, 1, 1]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 869)
            #expect(result == "192.168.1.1")
        }

        @Test func decodesCidrByOID() {
            let bytes: [UInt8] = [2, 24, 1, 4, 192, 168, 0, 0]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 650)
            #expect(result == "192.168.0.0/24")
        }

        @Test func decodesMacaddrByOID() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 829)
            #expect(result == "08:00:2b:01:02:03")
        }

        @Test func decodesMacaddr8ByOID() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0xff, 0xfe, 0x01, 0x02, 0x03]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 774)
            #expect(result == "08:00:2b:ff:fe:01:02:03")
        }

        @Test func returnsNilForUnknownOID() {
            let bytes: [UInt8] = [0x08, 0x00, 0x2b, 0x01, 0x02, 0x03]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 25) // text OID
            #expect(result == nil)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {

        @Test func rejectsEmptyBytes() {
            let result = NetworkTypeDecoder.decodeInetOrCidr([])
            #expect(result == nil)
        }

        @Test func rejectsTooShortForHeader() {
            let bytes: [UInt8] = [2, 32, 0]  // Missing length byte
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == nil)
        }

        @Test func rejectsMismatchedLength() {
            // Claims length 4 but only provides 3 bytes
            let bytes: [UInt8] = [2, 32, 0, 4, 192, 168, 1]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == nil)
        }

        @Test func rejectsUnknownFamily() {
            // Family = 5 is invalid
            let bytes: [UInt8] = [5, 32, 0, 4, 192, 168, 1, 1]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == nil)
        }

        @Test func rejectsWrongLengthForFamily() {
            // IPv4 (family=2) should have length=4, not 16
            let bytes: [UInt8] = [2, 32, 0, 16, 192, 168, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            let result = NetworkTypeDecoder.decodeInetOrCidr(bytes)
            #expect(result == nil)
        }
    }

    // MARK: - INTERVAL Tests

    @Suite("decodeInterval")
    struct DecodeIntervalTests {

        @Test func decodesSimpleTime() {
            // 00:10:33 = 633,000,000 microseconds, 0 days, 0 months
            // 633000000 = 0x0000000025bad040
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x25, 0xba, 0xd0, 0x40,  // 633000000 microseconds (big-endian)
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "00:10:33")
        }

        @Test func decodesZeroInterval() {
            // 00:00:00
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "00:00:00")
        }

        @Test func decodesOneHour() {
            // 01:00:00 = 3,600,000,000 microseconds
            // 3600000000 = 0x00000000D693A400
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0xD6, 0x93, 0xA4, 0x00,  // 3600000000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "01:00:00")
        }

        @Test func decodesDaysOnly() {
            // 5 days, 0 time
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x05,  // 5 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "5 days")
        }

        @Test func decodesSingleDay() {
            // 1 day (singular form)
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x01,  // 1 day
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "1 day")
        }

        @Test func decodesMonthsOnly() {
            // 3 months
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x03   // 3 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "3 mons")
        }

        @Test func decodesSingleMonth() {
            // 1 month (singular form)
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x01   // 1 month
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "1 mon")
        }

        @Test func decodesYearsFromMonths() {
            // 14 months = 1 year 2 months
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x0E   // 14 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "1 year 2 mons")
        }

        @Test func decodesComplexInterval() {
            // 1 year 2 months 3 days 04:05:06
            // 14 months, 3 days, 14706000000 microseconds
            // 04:05:06 = 4*3600 + 5*60 + 6 = 14706 seconds = 14706000000 us
            // 14706000000 = 0x000000036C6C6580
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x03, 0x6C, 0x6C, 0x65, 0x80,  // 14706000000 microseconds
                0x00, 0x00, 0x00, 0x03,  // 3 days
                0x00, 0x00, 0x00, 0x0E   // 14 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "1 year 2 mons 3 days 04:05:06")
        }

        @Test func decodesFractionalSeconds() {
            // 00:00:01.5 = 1,500,000 microseconds
            // 1500000 = 0x000000000016E360
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x16, 0xE3, 0x60,  // 1500000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "00:00:01.5")
        }

        @Test func decodesNegativeTime() {
            // -00:10:33 = -633,000,000 microseconds
            // -633000000 in two's complement = 0xFFFFFFFFDA452FC0
            let bytes: [UInt8] = [
                0xFF, 0xFF, 0xFF, 0xFF, 0xDA, 0x45, 0x2F, 0xC0,  // -633000000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "-00:10:33")
        }

        @Test func decodesNegativeDays() {
            // -3 days
            // -3 in two's complement = 0xFFFFFFFD
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0xFF, 0xFF, 0xFF, 0xFD,  // -3 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "-3 days")
        }

        @Test func decodesDaysWithTime() {
            // 2 days 03:30:00
            // 03:30:00 = 3*3600 + 30*60 = 12600 seconds = 12600000000 us
            // 12600000000 = 0x00000002EF54D400
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x02, 0xEF, 0x54, 0xD4, 0x00,  // 12600000000 microseconds
                0x00, 0x00, 0x00, 0x02,  // 2 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == "2 days 03:30:00")
        }

        @Test func rejectsTooShort() {
            let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == nil)
        }

        @Test func rejectsTooLong() {
            let bytes: [UInt8] = Array(repeating: 0x00, count: 20)
            let result = NetworkTypeDecoder.decodeInterval(bytes)
            #expect(result == nil)
        }
    }

    @Suite("decodeInterval with OID")
    struct DecodeIntervalWithOIDTests {

        @Test func decodesIntervalByOID() {
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x00, 0x25, 0xba, 0xd0, 0x40,  // 633000000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 1186)
            #expect(result == "00:10:33")
        }

        @Test func decodesIntervalArrayByOID() {
            // Array with single interval element: 00:10:33
            // Header: 1 dimension, no nulls, element OID, dimension=1, lower bound=1
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x01,  // 1 dimension
                0x00, 0x00, 0x00, 0x00,  // no null bitmap
                0x00, 0x00, 0x04, 0xA2,  // element OID 1186
                0x00, 0x00, 0x00, 0x01,  // dimension size = 1
                0x00, 0x00, 0x00, 0x01,  // lower bound = 1
                0x00, 0x00, 0x00, 0x10,  // element length = 16
                // interval bytes
                0x00, 0x00, 0x00, 0x00, 0x25, 0xba, 0xd0, 0x40,  // 633000000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 1187)
            #expect(result == "[00:10:33]")
        }

        @Test func decodesIntervalArrayWithMultipleElements() {
            // Array with two interval elements: 00:10:33 and 1 day
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x01,  // 1 dimension
                0x00, 0x00, 0x00, 0x00,  // no null bitmap
                0x00, 0x00, 0x04, 0xA2,  // element OID 1186
                0x00, 0x00, 0x00, 0x02,  // dimension size = 2
                0x00, 0x00, 0x00, 0x01,  // lower bound = 1
                // First element: 00:10:33
                0x00, 0x00, 0x00, 0x10,  // element length = 16
                0x00, 0x00, 0x00, 0x00, 0x25, 0xba, 0xd0, 0x40,  // 633000000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00,  // 0 months
                // Second element: 1 day
                0x00, 0x00, 0x00, 0x10,  // element length = 16
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // 0 microseconds
                0x00, 0x00, 0x00, 0x01,  // 1 day
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 1187)
            #expect(result == "[00:10:33, 1 day]")
        }

        @Test func decodesIntervalArrayWithNull() {
            // Array with NULL and 00:10:33
            let bytes: [UInt8] = [
                0x00, 0x00, 0x00, 0x01,  // 1 dimension
                0x00, 0x00, 0x00, 0x01,  // has null bitmap
                0x00, 0x00, 0x04, 0xA2,  // element OID 1186
                0x00, 0x00, 0x00, 0x02,  // dimension size = 2
                0x00, 0x00, 0x00, 0x01,  // lower bound = 1
                // First element: NULL
                0xFF, 0xFF, 0xFF, 0xFF,  // element length = -1 (NULL)
                // Second element: 00:10:33
                0x00, 0x00, 0x00, 0x10,  // element length = 16
                0x00, 0x00, 0x00, 0x00, 0x25, 0xba, 0xd0, 0x40,  // 633000000 microseconds
                0x00, 0x00, 0x00, 0x00,  // 0 days
                0x00, 0x00, 0x00, 0x00   // 0 months
            ]
            let result = NetworkTypeDecoder.decode(bytes: bytes, dataTypeOID: 1187)
            #expect(result == "[NULL, 00:10:33]")
        }
    }
}

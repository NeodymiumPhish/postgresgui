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
}

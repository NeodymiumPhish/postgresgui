//
//  NetworkTypeDecoder.swift
//  PostgresGUI
//
//  Decodes PostgreSQL network address types (inet, cidr, macaddr, macaddr8) from binary format.
//  PostgresNIO returns these as raw bytes - this decoder converts them to human-readable strings.
//

import Foundation

/// Decodes PostgreSQL network types from binary format to string representation
enum NetworkTypeDecoder {

    // MARK: - Address Family Constants

    private static let AF_INET: UInt8 = 2   // IPv4
    private static let AF_INET6: UInt8 = 3  // IPv6

    // MARK: - Public API

    /// Decode an inet or cidr value from PostgreSQL binary format
    /// Format: [family:1][prefix:1][is_cidr:1][length:1][address:4|16]
    /// - Parameter bytes: Raw bytes from PostgreSQL
    /// - Returns: String representation like "192.168.1.1/24" or nil if invalid
    static func decodeInetOrCidr(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 4 else { return nil }

        let family = bytes[0]
        let prefix = bytes[1]
        let isCidr = bytes[2] == 1
        let length = bytes[3]

        let expectedLength: Int
        switch family {
        case AF_INET:
            expectedLength = 4
        case AF_INET6:
            expectedLength = 16
        default:
            return nil
        }

        guard length == expectedLength else { return nil }
        guard bytes.count >= 4 + Int(length) else { return nil }

        let addressBytes = Array(bytes[4..<(4 + Int(length))])

        let addressString: String
        if family == AF_INET {
            addressString = formatIPv4(addressBytes)
        } else {
            addressString = formatIPv6(addressBytes)
        }

        // For inet with host prefix (32 for IPv4, 128 for IPv6), omit the prefix
        let maxPrefix: UInt8 = family == AF_INET ? 32 : 128
        if !isCidr && prefix == maxPrefix {
            return addressString
        }

        return "\(addressString)/\(prefix)"
    }

    /// Decode a macaddr value from PostgreSQL binary format
    /// Format: 6 bytes of MAC address
    /// - Parameter bytes: Raw bytes from PostgreSQL
    /// - Returns: String representation like "08:00:2b:01:02:03" or nil if invalid
    static func decodeMacaddr(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 6 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Decode a macaddr8 value from PostgreSQL binary format
    /// Format: 8 bytes of MAC address (EUI-64)
    /// - Parameter bytes: Raw bytes from PostgreSQL
    /// - Returns: String representation like "08:00:2b:ff:fe:01:02:03" or nil if invalid
    static func decodeMacaddr8(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 8 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Attempt to decode network type from raw bytes based on data type OID
    /// - Parameters:
    ///   - bytes: Raw bytes from PostgreSQL
    ///   - dataTypeOID: The PostgreSQL OID for the column type
    /// - Returns: Decoded string or nil if not a network type or decoding failed
    static func decode(bytes: [UInt8], dataTypeOID: UInt32) -> String? {
        switch dataTypeOID {
        case 869:  // inet
            return decodeInetOrCidr(bytes)
        case 650:  // cidr
            return decodeInetOrCidr(bytes)
        case 829:  // macaddr
            return decodeMacaddr(bytes)
        case 774:  // macaddr8
            return decodeMacaddr8(bytes)
        default:
            return nil
        }
    }

    // MARK: - IPv4 Formatting

    private static func formatIPv4(_ bytes: [UInt8]) -> String {
        guard bytes.count == 4 else { return "" }
        return bytes.map { String($0) }.joined(separator: ".")
    }

    // MARK: - IPv6 Formatting

    private static func formatIPv6(_ bytes: [UInt8]) -> String {
        guard bytes.count == 16 else { return "" }

        // Convert to 8 groups of 16-bit values
        var groups: [UInt16] = []
        for i in stride(from: 0, to: 16, by: 2) {
            let value = (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
            groups.append(value)
        }

        // Find the longest run of zeros for :: compression
        var longestZeroStart = -1
        var longestZeroLength = 0
        var currentZeroStart = -1
        var currentZeroLength = 0

        for (i, group) in groups.enumerated() {
            if group == 0 {
                if currentZeroStart == -1 {
                    currentZeroStart = i
                    currentZeroLength = 1
                } else {
                    currentZeroLength += 1
                }
            } else {
                if currentZeroLength > longestZeroLength {
                    longestZeroStart = currentZeroStart
                    longestZeroLength = currentZeroLength
                }
                currentZeroStart = -1
                currentZeroLength = 0
            }
        }
        // Check final run
        if currentZeroLength > longestZeroLength {
            longestZeroStart = currentZeroStart
            longestZeroLength = currentZeroLength
        }

        // Build the string with :: compression if there are 2+ consecutive zeros
        if longestZeroLength >= 2 {
            let afterZeros = longestZeroStart + longestZeroLength

            // Special case: all zeros (::)
            if longestZeroStart == 0 && afterZeros == 8 {
                return "::"
            }

            var parts: [String] = []

            // Add groups before the zero run
            for i in 0..<longestZeroStart {
                parts.append(String(groups[i], radix: 16))
            }

            // Add empty string for :: (will result in :: when joined)
            parts.append("")

            // Add groups after the zero run
            for i in afterZeros..<8 {
                parts.append(String(groups[i], radix: 16))
            }

            // Handle edge cases: ::1 or 2001::
            if longestZeroStart == 0 {
                return ":" + parts.joined(separator: ":")
            } else if afterZeros == 8 {
                return parts.joined(separator: ":") + ":"
            }

            return parts.joined(separator: ":")
        } else {
            // No compression, just format all groups
            return groups.map { String($0, radix: 16) }.joined(separator: ":")
        }
    }
}

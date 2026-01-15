//
//  NetworkTypeValidation.swift
//  PostgresGUI
//
//  Validation for PostgreSQL network address types (inet, cidr, macaddr, macaddr8).
//  Provides input validation for row editing.
//

import Foundation

/// The type of network address column being edited
enum NetworkAddressType {
    case inet       // IPv4/IPv6 host or network address
    case cidr       // IPv4/IPv6 network address (strict)
    case macaddr    // 6-byte MAC address
    case macaddr8   // 8-byte MAC address (EUI-64)

    /// Create from PostgreSQL data type string
    static func from(dataType: String) -> NetworkAddressType? {
        switch dataType.lowercased() {
        case "inet": return .inet
        case "cidr": return .cidr
        case "macaddr": return .macaddr
        case "macaddr8": return .macaddr8
        default: return nil
        }
    }
}

/// Result of network address validation
enum NetworkValidationResult: Equatable {
    case valid
    case invalid(reason: String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

/// Pure functions for validating PostgreSQL network address types
enum NetworkTypeValidation {

    // MARK: - Public API

    /// Validate a string for a specific network address type
    /// - Parameters:
    ///   - string: The input string to validate
    ///   - type: The network address type
    /// - Returns: ValidationResult indicating if the input is valid
    static func validate(_ string: String, type: NetworkAddressType) -> NetworkValidationResult {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return .invalid(reason: "Value cannot be empty")
        }

        switch type {
        case .inet:
            return validateInet(trimmed)
        case .cidr:
            return validateCidr(trimmed)
        case .macaddr:
            return validateMacaddr(trimmed)
        case .macaddr8:
            return validateMacaddr8(trimmed)
        }
    }

    // MARK: - inet Validation

    /// Validate an inet address (IPv4 or IPv6 with optional CIDR notation)
    private static func validateInet(_ string: String) -> NetworkValidationResult {
        // Split into address and optional prefix length
        let parts = string.split(separator: "/", maxSplits: 1)
        let addressPart = String(parts[0])

        // Determine if IPv4 or IPv6 based on format
        let isIPv6 = addressPart.contains(":")

        // Validate the address portion based on detected type
        if isIPv6 {
            if let result = validateIPv6Address(addressPart), !result.isValid {
                return result
            }
        } else {
            if let result = validateIPv4Address(addressPart), !result.isValid {
                return result
            }
        }

        // Validate prefix length if present
        if parts.count == 2 {
            let prefixResult = validatePrefixLength(String(parts[1]), isIPv6: isIPv6)
            if !prefixResult.isValid {
                return prefixResult
            }
        }

        return .valid
    }

    // MARK: - cidr Validation

    /// Validate a cidr network address (strict - no host bits allowed)
    private static func validateCidr(_ string: String) -> NetworkValidationResult {
        // CIDR requires the /prefix notation
        let parts = string.split(separator: "/", maxSplits: 1)

        if parts.count != 2 {
            return .invalid(reason: "CIDR requires network prefix (e.g., /24)")
        }

        let addressPart = String(parts[0])
        let prefixPart = String(parts[1])

        // Determine if IPv4 or IPv6
        let isIPv6 = addressPart.contains(":")

        // Validate the address portion
        if isIPv6 {
            if let result = validateIPv6Address(addressPart), !result.isValid {
                return result
            }
        } else {
            if let result = validateIPv4Address(addressPart), !result.isValid {
                return result
            }
        }

        // Validate prefix length
        let prefixResult = validatePrefixLength(prefixPart, isIPv6: isIPv6)
        if !prefixResult.isValid {
            return prefixResult
        }

        // For CIDR, verify no host bits are set
        guard let prefixLength = Int(prefixPart) else {
            return .invalid(reason: "Invalid prefix length")
        }

        let hostBitsResult = validateNoHostBits(addressPart, prefixLength: prefixLength, isIPv6: isIPv6)
        if !hostBitsResult.isValid {
            return hostBitsResult
        }

        return .valid
    }

    // MARK: - macaddr Validation

    /// Validate a 6-byte MAC address
    private static func validateMacaddr(_ string: String) -> NetworkValidationResult {
        // Remove all valid separators and check hex content
        let normalized = normalizeMacAddress(string)

        guard let hexString = normalized else {
            return .invalid(reason: "Invalid MAC address format")
        }

        // Must be exactly 12 hex characters (6 bytes)
        if hexString.count != 12 {
            return .invalid(reason: "MAC address must be 6 bytes (12 hex digits)")
        }

        // Verify all characters are valid hex
        if !hexString.allSatisfy({ $0.isHexDigit }) {
            return .invalid(reason: "MAC address must contain only hexadecimal characters")
        }

        return .valid
    }

    // MARK: - macaddr8 Validation

    /// Validate an 8-byte MAC address (EUI-64)
    private static func validateMacaddr8(_ string: String) -> NetworkValidationResult {
        let normalized = normalizeMacAddress(string)

        guard let hexString = normalized else {
            return .invalid(reason: "Invalid MAC address format")
        }

        // Can be 12 hex chars (6 bytes, will be expanded) or 16 hex chars (8 bytes)
        if hexString.count != 12 && hexString.count != 16 {
            return .invalid(reason: "MAC address must be 6 bytes (12 hex digits) or 8 bytes (16 hex digits)")
        }

        if !hexString.allSatisfy({ $0.isHexDigit }) {
            return .invalid(reason: "MAC address must contain only hexadecimal characters")
        }

        return .valid
    }

    // MARK: - IPv4 Helpers

    /// Validate an IPv4 address
    private static func validateIPv4Address(_ string: String) -> NetworkValidationResult? {
        let octets = string.split(separator: ".")

        // IPv4 must have exactly 4 octets
        guard octets.count == 4 else {
            return .invalid(reason: "IPv4 address must have 4 octets")
        }

        for octet in octets {
            guard let value = Int(octet), value >= 0 && value <= 255 else {
                return .invalid(reason: "IPv4 octet must be 0-255")
            }
            // Check for leading zeros (invalid in strict mode)
            if octet.count > 1 && octet.hasPrefix("0") {
                return .invalid(reason: "IPv4 octets cannot have leading zeros")
            }
        }

        return .valid
    }

    // MARK: - IPv6 Helpers

    /// Validate an IPv6 address
    private static func validateIPv6Address(_ string: String) -> NetworkValidationResult? {
        // Handle IPv4-mapped IPv6 addresses (::ffff:192.168.1.1)
        if string.contains(".") {
            return validateIPv4MappedIPv6(string)
        }

        // Count :: occurrences (only one allowed)
        let doubleColonCount = string.components(separatedBy: "::").count - 1
        if doubleColonCount > 1 {
            return .invalid(reason: "IPv6 address can only have one :: abbreviation")
        }

        // Split on :: first to handle abbreviation
        let parts: [String]
        if string.contains("::") {
            let halves = string.split(separator: "::", omittingEmptySubsequences: false)
            let leftGroups = halves[0].isEmpty ? [] : halves[0].split(separator: ":").map(String.init)
            let rightGroups = halves.count > 1 && !halves[1].isEmpty
                ? halves[1].split(separator: ":").map(String.init)
                : []

            let totalGroups = leftGroups.count + rightGroups.count
            if totalGroups > 7 {
                return .invalid(reason: "IPv6 address has too many groups")
            }

            parts = leftGroups + rightGroups
        } else {
            parts = string.split(separator: ":").map(String.init)
            if parts.count != 8 {
                return .invalid(reason: "IPv6 address must have 8 groups or use :: abbreviation")
            }
        }

        // Validate each group
        for group in parts {
            if group.isEmpty {
                continue
            }
            if group.count > 4 {
                return .invalid(reason: "IPv6 group cannot exceed 4 hex digits")
            }
            if !group.allSatisfy({ $0.isHexDigit }) {
                return .invalid(reason: "IPv6 groups must be hexadecimal")
            }
        }

        return .valid
    }

    /// Validate IPv4-mapped IPv6 address (e.g., ::ffff:192.168.1.1)
    private static func validateIPv4MappedIPv6(_ string: String) -> NetworkValidationResult {
        // Find the last colon before the IPv4 part
        guard let lastColonIndex = string.lastIndex(of: ":") else {
            return .invalid(reason: "Invalid IPv4-mapped IPv6 format")
        }

        let ipv6Part = String(string[..<lastColonIndex])
        let ipv4Part = String(string[string.index(after: lastColonIndex)...])

        // Validate IPv4 portion
        if let ipv4Result = validateIPv4Address(ipv4Part), !ipv4Result.isValid {
            return ipv4Result
        }

        // Validate IPv6 prefix (should be :: or ::ffff: typically)
        if !ipv6Part.isEmpty && ipv6Part != ":" {
            let prefixParts = ipv6Part.split(separator: ":", omittingEmptySubsequences: false)
            for part in prefixParts where !part.isEmpty {
                if part.count > 4 || !part.allSatisfy({ $0.isHexDigit }) {
                    return .invalid(reason: "Invalid IPv6 prefix in mapped address")
                }
            }
        }

        return .valid
    }

    // MARK: - Prefix Length Helpers

    /// Validate network prefix length
    private static func validatePrefixLength(_ string: String, isIPv6: Bool) -> NetworkValidationResult {
        guard let prefix = Int(string) else {
            return .invalid(reason: "Prefix length must be a number")
        }

        let maxPrefix = isIPv6 ? 128 : 32

        if prefix < 0 || prefix > maxPrefix {
            return .invalid(reason: "Prefix length must be 0-\(maxPrefix)")
        }

        return .valid
    }

    /// Check that no host bits are set (for CIDR validation)
    private static func validateNoHostBits(_ address: String, prefixLength: Int, isIPv6: Bool) -> NetworkValidationResult {
        if isIPv6 {
            // IPv6 host bits validation
            guard let bytes = parseIPv6ToBytes(address) else {
                return .invalid(reason: "Could not parse IPv6 address")
            }
            return checkHostBits(bytes: bytes, prefixLength: prefixLength, totalBits: 128)
        } else {
            // IPv4 host bits validation
            guard let bytes = parseIPv4ToBytes(address) else {
                return .invalid(reason: "Could not parse IPv4 address")
            }
            return checkHostBits(bytes: bytes, prefixLength: prefixLength, totalBits: 32)
        }
    }

    /// Check if any host bits are set in the address
    private static func checkHostBits(bytes: [UInt8], prefixLength: Int, totalBits: Int) -> NetworkValidationResult {
        let hostBits = totalBits - prefixLength

        if hostBits == 0 {
            return .valid
        }

        // Calculate which bytes contain host bits
        let fullHostBytes = hostBits / 8
        let partialHostBits = hostBits % 8

        // Check full host bytes from the end
        for i in 0..<fullHostBytes {
            let byteIndex = bytes.count - 1 - i
            if byteIndex >= 0 && bytes[byteIndex] != 0 {
                return .invalid(reason: "CIDR address has host bits set (use inet for host addresses)")
            }
        }

        // Check partial byte if any
        if partialHostBits > 0 {
            let byteIndex = bytes.count - 1 - fullHostBytes
            if byteIndex >= 0 {
                let mask: UInt8 = (1 << partialHostBits) - 1
                if bytes[byteIndex] & mask != 0 {
                    return .invalid(reason: "CIDR address has host bits set (use inet for host addresses)")
                }
            }
        }

        return .valid
    }

    /// Parse IPv4 address to bytes
    private static func parseIPv4ToBytes(_ address: String) -> [UInt8]? {
        let octets = address.split(separator: ".")
        guard octets.count == 4 else { return nil }

        var bytes: [UInt8] = []
        for octet in octets {
            guard let value = UInt8(octet) else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    /// Parse IPv6 address to bytes
    private static func parseIPv6ToBytes(_ address: String) -> [UInt8]? {
        var groups: [UInt16] = []

        if address.contains("::") {
            let halves = address.split(separator: "::", omittingEmptySubsequences: false)
            let leftGroups = halves[0].isEmpty ? [] : halves[0].split(separator: ":").compactMap { UInt16($0, radix: 16) }
            let rightGroups = halves.count > 1 && !halves[1].isEmpty
                ? halves[1].split(separator: ":").compactMap { UInt16($0, radix: 16) }
                : []

            let zerosNeeded = 8 - leftGroups.count - rightGroups.count
            groups = leftGroups + Array(repeating: 0, count: zerosNeeded) + rightGroups
        } else {
            groups = address.split(separator: ":").compactMap { UInt16($0, radix: 16) }
        }

        guard groups.count == 8 else { return nil }

        var bytes: [UInt8] = []
        for group in groups {
            bytes.append(UInt8(group >> 8))
            bytes.append(UInt8(group & 0xFF))
        }
        return bytes
    }

    // MARK: - MAC Address Helpers

    /// Normalize MAC address by removing separators and returning hex string
    /// Returns nil if format is invalid
    private static func normalizeMacAddress(_ string: String) -> String? {
        let input = string.lowercased()

        // Valid formats:
        // 08:00:2b:01:02:03 (colon-separated)
        // 08-00-2b-01-02-03 (hyphen-separated)
        // 0800.2b01.0203 (dot-separated, Cisco style)
        // 08002b010203 (no separators)

        // Check for mixed separators
        let hasColon = input.contains(":")
        let hasHyphen = input.contains("-")
        let hasDot = input.contains(".")

        let separatorCount = [hasColon, hasHyphen, hasDot].filter { $0 }.count
        if separatorCount > 1 {
            return nil // Mixed separators not allowed
        }

        // Remove the separator and validate structure
        if hasColon {
            let parts = input.split(separator: ":")
            // Standard format: 6 or 8 parts of 2 hex digits each
            // Also allow: 2 parts of 6 hex digits each (08002b:010203)
            if parts.count == 6 || parts.count == 8 {
                if !parts.allSatisfy({ $0.count == 2 }) {
                    return nil
                }
            } else if parts.count == 2 {
                if !parts.allSatisfy({ $0.count == 6 }) {
                    return nil
                }
            } else {
                return nil
            }
            return parts.joined()
        } else if hasHyphen {
            let parts = input.split(separator: "-")
            if parts.count == 6 || parts.count == 8 {
                if !parts.allSatisfy({ $0.count == 2 }) {
                    return nil
                }
            } else if parts.count == 2 {
                if !parts.allSatisfy({ $0.count == 6 }) {
                    return nil
                }
            } else {
                return nil
            }
            return parts.joined()
        } else if hasDot {
            let parts = input.split(separator: ".")
            // Cisco format: 3 or 4 parts of 4 hex digits each
            if parts.count == 3 || parts.count == 4 {
                if !parts.allSatisfy({ $0.count == 4 }) {
                    return nil
                }
            } else {
                return nil
            }
            return parts.joined()
        } else {
            // No separators - must be 12 or 16 hex characters
            if input.count != 12 && input.count != 16 {
                return nil
            }
            return input
        }
    }
}

//
//  NetworkTypeDecoder.swift
//  PostgresGUI
//
//  Decodes PostgreSQL binary types that PostgresNIO doesn't handle natively.
//  This includes network address types (inet, cidr, macaddr, macaddr8) and
//  primitive array types (int2[], int4[], int8[], text[], etc.) from binary format.
//

import Foundation

/// Decodes PostgreSQL binary types from raw bytes to string representation
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

    /// Decode a PostgreSQL INTERVAL value from binary format
    /// Format: [microseconds:8][days:4][months:4] - all big-endian
    /// - Parameter bytes: Raw bytes from PostgreSQL (16 bytes)
    /// - Returns: String representation like "00:10:33" or "1 year 2 mons 3 days 04:05:06" or nil if invalid
    static func decodeInterval(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 16 else { return nil }

        // 1. Parse Microseconds (Offset 0-8)
        // Safer than load(as:) for unaligned memory
        var microRaw: UInt64 = 0
        for i in 0..<8 { microRaw = (microRaw << 8) | UInt64(bytes[i]) }
        let microseconds = Int64(bitPattern: microRaw)

        // 2. Parse Days (Offset 8-12)
        var daysRaw: UInt32 = 0
        for i in 8..<12 { daysRaw = (daysRaw << 8) | UInt32(bytes[i]) }
        let days = Int32(bitPattern: daysRaw)

        // 3. Parse Months (Offset 12-16)
        var monthsRaw: UInt32 = 0
        for i in 12..<16 { monthsRaw = (monthsRaw << 8) | UInt32(bytes[i]) }
        let months = Int32(bitPattern: monthsRaw)

        return formatInterval(microseconds: microseconds, days: days, months: months)
    }

    /// Format interval components into PostgreSQL standard interval format
    private static func formatInterval(microseconds: Int64, days: Int32, months: Int32) -> String {
        var parts: [String] = []

        // Handle months component (years and months)
        if months != 0 {
            let years = months / 12
            let remainingMonths = months % 12

            if years != 0 {
                parts.append(abs(years) == 1 ? "\(years) year" : "\(years) years")
            }
            if remainingMonths != 0 {
                parts.append(abs(remainingMonths) == 1 ? "\(remainingMonths) mon" : "\(remainingMonths) mons")
            }
        }

        // Handle days component
        if days != 0 {
            parts.append(abs(days) == 1 ? "\(days) day" : "\(days) days")
        }

        // Handle time component (microseconds)
        if microseconds != 0 || parts.isEmpty {
            let timeString = formatTimePart(microseconds: microseconds)
            parts.append(timeString)
        }

        return parts.joined(separator: " ")
    }

    /// Format microseconds into HH:MM:SS or HH:MM:SS.ffffff format
    private static func formatTimePart(microseconds: Int64) -> String {
        let isNegative = microseconds < 0
        let absMicroseconds = abs(microseconds)

        let totalSeconds = absMicroseconds / 1_000_000
        let remainingMicroseconds = absMicroseconds % 1_000_000

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        let sign = isNegative ? "-" : ""

        if remainingMicroseconds == 0 {
            return String(format: "%@%02lld:%02lld:%02lld", sign, hours, minutes, seconds)
        } else {
            // Format fractional seconds, trimming trailing zeros
            var fraction = String(format: "%06lld", remainingMicroseconds)
            while fraction.hasSuffix("0") && !fraction.isEmpty {
                fraction.removeLast()
            }
            return String(format: "%@%02lld:%02lld:%02lld.%@", sign, hours, minutes, seconds, fraction)
        }
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
        case 1041:  // inet[]
            return decodeNetworkArray(bytes, elementDecoder: decodeInetOrCidr)
        case 651:   // cidr[]
            return decodeNetworkArray(bytes, elementDecoder: decodeInetOrCidr)
        case 1040:  // macaddr[]
            return decodeNetworkArray(bytes, elementDecoder: decodeMacaddr)
        case 775:   // macaddr8[]
            return decodeNetworkArray(bytes, elementDecoder: decodeMacaddr8)

        // Integer array types
        case 1005:  // int2[]
            return decodeIntegerArray(bytes, elementSize: 2)
        case 1007:  // int4[]
            return decodeIntegerArray(bytes, elementSize: 4)
        case 1016:  // int8[]
            return decodeIntegerArray(bytes, elementSize: 8)

        // Text array types
        case 1009:  // text[]
            return decodeTextArray(bytes)
        case 1015:  // varchar[]
            return decodeTextArray(bytes)
        case 1014:  // char[]
            return decodeTextArray(bytes)
        case 1002:  // char(1)[] (bpchar array)
            return decodeTextArray(bytes)

        // UUID array
        case 2951:  // uuid[]
            return decodeUUIDArray(bytes)

        // Boolean array
        case 1000:  // bool[]
            return decodeBoolArray(bytes)

        // Interval types
        case 1186:  // interval
            return decodeInterval(bytes)
        case 1187:  // interval[]
            return decodeIntervalArray(bytes)

        default:
            return nil
        }
    }

    // MARK: - Array Decoding

    /// Decode a PostgreSQL array of network types from binary format
    /// PostgreSQL binary array format:
    /// - 4 bytes: number of dimensions
    /// - 4 bytes: has null bitmap flag
    /// - 4 bytes: element type OID
    /// For each dimension:
    /// - 4 bytes: dimension size
    /// - 4 bytes: lower bound (usually 1)
    /// For each element:
    /// - 4 bytes: element length (-1 for NULL)
    /// - N bytes: element data
    private static func decodeNetworkArray(_ bytes: [UInt8], elementDecoder: ([UInt8]) -> String?) -> String? {
        guard bytes.count >= 12 else { return nil }

        // Read number of dimensions (big-endian)
        let numDimensions = Int32(bigEndian: bytes[0..<4].withUnsafeBytes { $0.load(as: Int32.self) })

        // We only support 1-dimensional arrays
        guard numDimensions == 1 else { return nil }

        // Skip has-null flag (4 bytes) and element OID (4 bytes)
        // Read dimension size
        guard bytes.count >= 20 else { return nil }
        let dimensionSize = Int32(bigEndian: bytes[12..<16].withUnsafeBytes { $0.load(as: Int32.self) })

        // Start reading elements after header (20 bytes for 1D array)
        var offset = 20
        var elements: [String] = []

        for _ in 0..<dimensionSize {
            guard offset + 4 <= bytes.count else { return nil }

            // Read element length
            let elementLength = Int32(bigEndian: bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: Int32.self) })
            offset += 4

            if elementLength == -1 {
                // NULL element
                elements.append("NULL")
            } else {
                guard offset + Int(elementLength) <= bytes.count else { return nil }

                let elementBytes = Array(bytes[offset..<(offset + Int(elementLength))])
                if let decoded = elementDecoder(elementBytes) {
                    elements.append(decoded)
                } else {
                    return nil
                }
                offset += Int(elementLength)
            }
        }

        return "[\(elements.joined(separator: ", "))]"
    }

    /// Decode a PostgreSQL integer array from binary format
    private static func decodeIntegerArray(_ bytes: [UInt8], elementSize: Int) -> String? {
        guard bytes.count >= 12 else { return nil }

        let numDimensions = Int32(bigEndian: bytes[0..<4].withUnsafeBytes { $0.load(as: Int32.self) })
        guard numDimensions == 1 else { return nil }

        guard bytes.count >= 20 else { return nil }
        let dimensionSize = Int32(bigEndian: bytes[12..<16].withUnsafeBytes { $0.load(as: Int32.self) })

        var offset = 20
        var elements: [String] = []

        for _ in 0..<dimensionSize {
            guard offset + 4 <= bytes.count else { return nil }

            let elementLength = Int32(bigEndian: bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: Int32.self) })
            offset += 4

            if elementLength == -1 {
                elements.append("NULL")
            } else {
                guard elementLength == elementSize else { return nil }
                guard offset + elementSize <= bytes.count else { return nil }

                let elementBytes = Array(bytes[offset..<(offset + elementSize)])
                let value: String
                switch elementSize {
                case 2:
                    let int16 = Int16(bigEndian: elementBytes.withUnsafeBytes { $0.load(as: Int16.self) })
                    value = String(int16)
                case 4:
                    let int32 = Int32(bigEndian: elementBytes.withUnsafeBytes { $0.load(as: Int32.self) })
                    value = String(int32)
                case 8:
                    let int64 = Int64(bigEndian: elementBytes.withUnsafeBytes { $0.load(as: Int64.self) })
                    value = String(int64)
                default:
                    return nil
                }
                elements.append(value)
                offset += elementSize
            }
        }

        return "[\(elements.joined(separator: ", "))]"
    }

    /// Decode a PostgreSQL text/varchar array from binary format
    private static func decodeTextArray(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 12 else { return nil }

        let numDimensions = Int32(bigEndian: bytes[0..<4].withUnsafeBytes { $0.load(as: Int32.self) })
        guard numDimensions == 1 else { return nil }

        guard bytes.count >= 20 else { return nil }
        let dimensionSize = Int32(bigEndian: bytes[12..<16].withUnsafeBytes { $0.load(as: Int32.self) })

        var offset = 20
        var elements: [String] = []

        for _ in 0..<dimensionSize {
            guard offset + 4 <= bytes.count else { return nil }

            let elementLength = Int32(bigEndian: bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: Int32.self) })
            offset += 4

            if elementLength == -1 {
                elements.append("NULL")
            } else {
                guard offset + Int(elementLength) <= bytes.count else { return nil }

                let elementBytes = Array(bytes[offset..<(offset + Int(elementLength))])
                if let text = String(bytes: elementBytes, encoding: .utf8) {
                    elements.append("\"\(text)\"")
                } else {
                    return nil
                }
                offset += Int(elementLength)
            }
        }

        return "[\(elements.joined(separator: ", "))]"
    }

    /// Decode a PostgreSQL UUID array from binary format
    private static func decodeUUIDArray(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 12 else { return nil }

        let numDimensions = Int32(bigEndian: bytes[0..<4].withUnsafeBytes { $0.load(as: Int32.self) })
        guard numDimensions == 1 else { return nil }

        guard bytes.count >= 20 else { return nil }
        let dimensionSize = Int32(bigEndian: bytes[12..<16].withUnsafeBytes { $0.load(as: Int32.self) })

        var offset = 20
        var elements: [String] = []

        for _ in 0..<dimensionSize {
            guard offset + 4 <= bytes.count else { return nil }

            let elementLength = Int32(bigEndian: bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: Int32.self) })
            offset += 4

            if elementLength == -1 {
                elements.append("NULL")
            } else {
                guard elementLength == 16 else { return nil }
                guard offset + 16 <= bytes.count else { return nil }

                let uuidBytes = Array(bytes[offset..<(offset + 16)])
                let uuid = NSUUID(uuidBytes: uuidBytes) as UUID
                elements.append(uuid.uuidString)
                offset += 16
            }
        }

        return "[\(elements.joined(separator: ", "))]"
    }

    /// Decode a PostgreSQL boolean array from binary format
    private static func decodeBoolArray(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 12 else { return nil }

        let numDimensions = Int32(bigEndian: bytes[0..<4].withUnsafeBytes { $0.load(as: Int32.self) })
        guard numDimensions == 1 else { return nil }

        guard bytes.count >= 20 else { return nil }
        let dimensionSize = Int32(bigEndian: bytes[12..<16].withUnsafeBytes { $0.load(as: Int32.self) })

        var offset = 20
        var elements: [String] = []

        for _ in 0..<dimensionSize {
            guard offset + 4 <= bytes.count else { return nil }

            let elementLength = Int32(bigEndian: bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: Int32.self) })
            offset += 4

            if elementLength == -1 {
                elements.append("NULL")
            } else {
                guard elementLength == 1 else { return nil }
                guard offset + 1 <= bytes.count else { return nil }

                let value = bytes[offset] != 0
                elements.append(String(value))
                offset += 1
            }
        }

        return "[\(elements.joined(separator: ", "))]"
    }

    /// Decode a PostgreSQL INTERVAL array from binary format
    private static func decodeIntervalArray(_ bytes: [UInt8]) -> String? {
        guard bytes.count >= 12 else { return nil }

        let numDimensions = Int32(bigEndian: bytes[0..<4].withUnsafeBytes { $0.load(as: Int32.self) })
        guard numDimensions == 1 else { return nil }

        guard bytes.count >= 20 else { return nil }
        let dimensionSize = Int32(bigEndian: bytes[12..<16].withUnsafeBytes { $0.load(as: Int32.self) })

        var offset = 20
        var elements: [String] = []

        for _ in 0..<dimensionSize {
            guard offset + 4 <= bytes.count else { return nil }

            let elementLength = Int32(bigEndian: bytes[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: Int32.self) })
            offset += 4

            if elementLength == -1 {
                elements.append("NULL")
            } else {
                guard elementLength == 16 else { return nil }  // INTERVAL is always 16 bytes
                guard offset + 16 <= bytes.count else { return nil }

                let elementBytes = Array(bytes[offset..<(offset + 16)])
                if let decoded = decodeInterval(elementBytes) {
                    elements.append(decoded)
                } else {
                    return nil
                }
                offset += 16
            }
        }

        return "[\(elements.joined(separator: ", "))]"
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

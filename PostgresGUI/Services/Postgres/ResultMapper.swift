//
//  ResultMapper.swift
//  PostgresGUI
//
//  Transforms PostgresNIO types to app models
//

import Foundation
import PostgresNIO

/// Maps PostgresNIO result types to app models
enum ResultMapper {
    
    // MARK: - Constants
    
    /// Maximum size for hex representation of binary data (bytes)
    private static let maxHexDisplaySize = 32
    
    /// Maximum size for processing binary data in fallback handler (bytes)
    private static let maxBinaryProcessingSize = 10000
    
    /// Number of bytes to peek at for binary detection
    private static let binaryDetectionPeekSize = 100
    
    /// Threshold for considering data as containing text (40% of non-null bytes must be printable)
    private static let textDetectionThreshold = 0.4
    
    /// Threshold for considering data as binary (10% null bytes)
    private static let binaryDetectionThreshold = 0.1
    
    /// Threshold for considering a string as valid (80% printable characters)
    private static let validStringThreshold = 0.8
    
    /// Static date formatter for consistent date formatting
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Row Mapping

    /// Map a PostgresRow to TableRow
    /// Extracts column values from PostgresRow cells
    /// - Parameter row: The PostgresRow from PostgresNIO
    /// - Returns: A TableRow with String values
    static func mapRowToTableRow(_ row: PostgresRow) throws -> TableRow {
        var values: [String: String?] = [:]

        // Iterate through all cells in the row
        for cell in row {
            let columnName = cell.columnName

            // Convert cell bytes to string representation
            if cell.bytes != nil {
                // Try to decode various PostgreSQL types in order
                values[columnName] = decodeCellValue(cell)
            } else {
                // NULL value
                values[columnName] = nil
            }
        }

        return TableRow(values: values)
    }
    
    // MARK: - Helper Functions
    
    /// Check if a string contains invalid control characters (binary garbage)
    /// - Parameter string: The string to validate
    /// - Returns: true if the string contains invalid control characters
    private static func containsInvalidControlCharacters(_ string: String) -> Bool {
        string.contains { char in
            char.unicodeScalars.contains { scalar in
                let value = scalar.value
                // Check for null bytes or control characters (except tab, newline, carriage return)
                return value == 0 || ((value < 32 && value != 9 && value != 10 && value != 13) || value == 127)
            }
        }
    }
    
    /// Format an array of strings as a bracketed, comma-separated list
    /// - Parameter elements: Array of string elements to format
    /// - Returns: Formatted string like "[elem1, elem2, elem3]"
    private static func formatArray(_ elements: [String]) -> String {
        "[\(elements.joined(separator: ", "))]"
    }
    
    /// Decode a PostgresCell to a string representation for display in the UI
    ///
    /// This function attempts to decode PostgreSQL data using multiple type decoders in order of likelihood.
    /// PostgreSQL can send data in either text format or binary format, and this function handles both.
    ///
    /// Comprehensive PostgreSQL type support:
    ///
    /// ✅ Fully Decoded (Binary & Text Format):
    /// - Text: VARCHAR, TEXT, CHAR, NAME, BPCHAR
    /// - Numeric: SMALLINT, INT, BIGINT, REAL, DOUBLE PRECISION
    /// - Boolean: BOOLEAN
    /// - UUID: UUID
    /// - Date/Time: TIMESTAMP, TIMESTAMPTZ, DATE, TIME, TIMETZ
    /// - Binary: BYTEA (shown as hex for ≤32 bytes, base64 for larger)
    /// - System: OID, REGPROC, REGCLASS (as Int32/Int64)
    /// - Arrays: All of the above as arrays (e.g., INT[], TEXT[], UUID[], TIMESTAMP[])
    ///
    /// ⚠️ Text Format Support (via String decoder - works when PostgreSQL sends text format):
    /// - Numeric: NUMERIC, DECIMAL (full precision preserved), MONEY
    /// - JSON: JSON, JSONB (shown as-is, not parsed)
    /// - XML: XML
    /// - Network: INET, CIDR, MACADDR, MACADDR8
    /// - Geometric: POINT, LINE, LSEG, BOX, PATH, POLYGON, CIRCLE
    /// - Bit: BIT, BIT VARYING
    /// - Text Search: TSVECTOR, TSQUERY
    /// - Range: INT4RANGE, INT8RANGE, NUMRANGE, TSRANGE, TSTZRANGE, DATERANGE
    /// - Time: INTERVAL
    /// - Custom: ENUM types, Domains
    ///
    /// 🔧 Advanced Types (intelligent fallback handling):
    /// - Composite types: Extracted as string arrays when possible, e.g., ["val1", "val2", "val3"]
    /// - HSTORE: Extracted via text fallback or shown as binary
    /// - PostGIS: GEOMETRY, GEOGRAPHY (binary data with string extraction)
    /// - Arrays of complex types: Extracted when data contains null-terminated strings
    /// - Custom extensions: Via text/binary fallback with intelligent string extraction
    ///
    /// Note: Types marked with ⚠️ work best when PostgreSQL uses text format. Binary format
    /// for these types will either fall back to string extraction or show as "(binary data)".
    ///
    /// For undecodable binary data (e.g., geometry, custom binary formats), the function returns:
    /// - Short data (≤32 bytes): Hex representation (e.g., "0x0a1b2c3d")
    /// - Long data: "(binary data)" placeholder
    /// - Very large data (≥10KB): "(large binary data)" placeholder
    ///
    /// IMPORTANT: This function NEVER returns binary garbage like "\u0000\u0002�v\u0019�"
    /// All binary data is either properly decoded or shown as a readable placeholder.
    ///
    /// - Parameter cell: The PostgresCell containing the data to decode
    /// - Returns: String representation of the value, or nil for NULL
    private static func decodeCellValue(_ cell: PostgresCell) -> String? {
        // Try String first (most common, handles text format for most types including VARCHAR, TEXT, CHAR, etc.)
        // BUT: Validate that the string doesn't contain binary garbage
        if let stringValue = try? cell.decode(String.self, context: .default) {
            // Check if the string contains null bytes or control characters (indicating binary data)
            if !containsInvalidControlCharacters(stringValue) {
                return stringValue
            }
            // Otherwise, fall through to try other decoders (this is likely binary data)
        }

        // Try Bool (for boolean) - check early as it's a simple type
        if let boolValue = try? cell.decode(Bool.self, context: .default) {
            return String(boolValue)
        }

        // Try UUID (for uuid type)
        if let uuid = try? cell.decode(UUID.self, context: .default) {
            return uuid.uuidString
        }

        // Try Integer types (for SMALLINT, INTEGER, BIGINT, OID)
        // Note: PostgreSQL OID is typically Int32 or Int64
        if let intValue = try? cell.decode(Int16.self, context: .default) {
            return String(intValue)
        }

        if let intValue = try? cell.decode(Int32.self, context: .default) {
            return String(intValue)
        }

        if let intValue = try? cell.decode(Int64.self, context: .default) {
            return String(intValue)
        }

        if let intValue = try? cell.decode(Int.self, context: .default) {
            return String(intValue)
        }

        // Try Floating point types (for REAL, DOUBLE PRECISION, NUMERIC, DECIMAL, MONEY)
        // Note: NUMERIC/DECIMAL may lose precision when decoded as Double
        // but PostgresNIO doesn't provide a Decimal decoder
        if let floatValue = try? cell.decode(Float.self, context: .default) {
            return String(floatValue)
        }

        if let doubleValue = try? cell.decode(Double.self, context: .default) {
            return String(doubleValue)
        }

        // Try Date/Time types (for TIMESTAMP, TIMESTAMPTZ, DATE, TIME, TIMETZ)
        if let date = try? cell.decode(Date.self, context: .default) {
            // Format as ISO8601 with fractional seconds
            return dateFormatter.string(from: date)
        }

        // Try Array types BEFORE Data/ByteA - PostgreSQL arrays (INT[], TEXT[], etc.)
        // This is important because binary-formatted arrays can be misidentified as raw BYTEA
        if let array = try? cell.decode([String].self, context: .default) {
            return formatArray(array.map { "\"\($0)\"" })
        }

        if let array = try? cell.decode([Int].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([Int16].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([Int32].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([Int64].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([Float].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([Double].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([Bool].self, context: .default) {
            return formatArray(array.map { String($0) })
        }

        if let array = try? cell.decode([UUID].self, context: .default) {
            return formatArray(array.map { $0.uuidString })
        }

        if let array = try? cell.decode([Date].self, context: .default) {
            return formatArray(array.map { dateFormatter.string(from: $0) })
        }

        // Try ByteA/Data (for BYTEA type - binary data)
        // This comes AFTER arrays to avoid misidentifying binary arrays as BYTEA
        if let data = try? cell.decode(Data.self, context: .default) {
            // Check if this binary data might contain readable strings
            // (This can happen with complex types that PostgresNIO can't decode)
            let bytes = [UInt8](data)

            // Count printable ASCII characters and null bytes
            var printableCount = 0
            var nullCount = 0
            for byte in bytes {
                if byte == 0 {
                    nullCount += 1
                } else if (byte >= 32 && byte <= 126) || byte == 9 || byte == 10 || byte == 13 {
                    printableCount += 1
                }
            }

            // If more than threshold of non-null bytes are printable, it likely contains text
            let nonNullBytes = bytes.count - nullCount
            if nonNullBytes > 0 && Double(printableCount) / Double(nonNullBytes) > textDetectionThreshold {
                // Try to extract readable strings from the binary data
                if let extracted = extractReadableStrings(from: data) {
                    return extracted
                }
            }

            // For pure binary data, show as hex for short data, base64 for medium data, placeholder for large
            if data.count <= maxHexDisplaySize {
                return "0x" + data.map { String(format: "%02x", $0) }.joined()
            } else if data.count >= maxBinaryProcessingSize {
                return "(large binary data)"
            } else {
                return data.base64EncodedString()
            }
        }

        // FALLBACK: Handle unrecognized types and binary data
        // This section handles cases where PostgreSQL sends data in a format that none of the above
        // typed decoders could handle. This can happen with:
        // - Custom PostgreSQL types (ENUM, composite types, etc.)
        // - Binary-formatted data that PostgresNIO doesn't have a decoder for
        // - Corrupted or malformed data
        // - Extensions like PostGIS geometry types, hstore, etc.
        //
        // CRITICAL: We must NEVER display binary garbage (e.g., "\u0000\u0002�v\u0019�") to the user
        if let bytes = cell.bytes {
            var buffer = bytes
            let readableBytes = buffer.readableBytes

            // Limit processing to reasonable sizes to avoid performance issues
            if readableBytes > 0 && readableBytes < maxBinaryProcessingSize {
                // BINARY DETECTION: Check if data contains null bytes or other binary markers
                // Peek at the bytes without consuming the buffer
                let peekLength = min(readableBytes, binaryDetectionPeekSize)
                if let peekBytes = buffer.getBytes(at: 0, length: peekLength) {
                    // Count null bytes in first peekLength bytes
                    let nullByteCount = peekBytes.filter { $0 == 0 }.count

                    // If more than threshold null bytes, treat as binary data
                    if Double(nullByteCount) / Double(peekBytes.count) > binaryDetectionThreshold {
                        // For short binary data, show as hex for debugging
                        if readableBytes <= maxHexDisplaySize {
                            if let allBytes = buffer.getBytes(at: 0, length: readableBytes) {
                                return "0x" + allBytes.map { String(format: "%02x", $0) }.joined()
                            }
                        }
                        // For longer binary data, just indicate it's binary
                        return "(binary data)"
                    }
                }

                // NOT BINARY: Try to read as UTF-8 string (for custom types, ENUMs, etc.)
                if let text = buffer.readString(length: readableBytes) {
                    // Validate that the string doesn't contain control characters
                    // This prevents displaying garbage like "\u0000\u0002�v\u0019�"
                    // If the string is valid and not empty, return it
                    if !containsInvalidControlCharacters(text) && !text.isEmpty {
                        return text
                    }
                }
            }

            // Data is too large or couldn't be read
            if readableBytes >= maxBinaryProcessingSize {
                return "(large binary data)"
            }
        }

        // FINAL FALLBACK: If we can't decode or read the data at all
        return "(unknown data type)"
    }

    /// Extract readable null-terminated strings from binary data
    /// This is useful for PostgreSQL composite types or arrays that PostgresNIO can't decode
    /// - Parameter data: The binary data to extract strings from
    /// - Returns: A formatted string showing the extracted values, or nil if no strings found
    private static func extractReadableStrings(from data: Data) -> String? {
        let bytes = [UInt8](data)
        var strings: [String] = []
        var currentString: [UInt8] = []

        for byte in bytes {
            if byte == 0 {
                // Null terminator - end of string
                if !currentString.isEmpty {
                    // Check if this looks like a valid string (mostly printable chars)
                    let printableCount = currentString.filter { b in
                        (b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13
                    }.count

                    if Double(printableCount) / Double(currentString.count) > validStringThreshold {
                        if let str = String(bytes: currentString, encoding: .utf8), !str.isEmpty {
                            strings.append(str)
                        }
                    }
                    currentString = []
                }
            } else if (byte >= 32 && byte <= 126) || byte == 9 || byte == 10 || byte == 13 {
                // Printable character
                currentString.append(byte)
            } else {
                // Non-printable, non-null byte - might be length prefix or other metadata
                // Keep accumulating if we already have some data
                if !currentString.isEmpty {
                    currentString.append(byte)
                }
            }
        }

        // Don't forget the last string if there's no trailing null
        if !currentString.isEmpty {
            let printableCount = currentString.filter { b in
                (b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13
            }.count

            if Double(printableCount) / Double(currentString.count) > validStringThreshold {
                if let str = String(bytes: currentString, encoding: .utf8), !str.isEmpty {
                    strings.append(str)
                }
            }
        }

        // If we extracted strings, format them as an array-like structure
        if !strings.isEmpty {
            // If it looks like an array of values, format it nicely
            let formatted = strings.map { "\"\($0)\"" }.joined(separator: ", ")
            return "[\(formatted)]"
        }

        return nil
    }

    /// Map a PostgresRowSequence to an array of TableRow
    /// - Parameter rows: The PostgresRowSequence from a query
    /// - Returns: Array of TableRow objects
    static func mapRowsToTableRows(_ rows: PostgresRowSequence) async throws -> [TableRow] {
        var tableRows: [TableRow] = []

        for try await row in rows {
            let tableRow = try mapRowToTableRow(row)
            tableRows.append(tableRow)
        }

        return tableRows
    }

    // MARK: - Column Info Mapping

    /// Map information_schema column query result to ColumnInfo
    static func mapToColumnInfo(_ row: PostgresRow) throws -> ColumnInfo {
        // Use tuple decoding for known schema
        let (columnName, dataType, isNullableString, defaultValue) =
            try row.decode((String, String, String, String?).self)

        let isNullable = isNullableString.uppercased() == "YES"

        return ColumnInfo(
            name: columnName,
            dataType: dataType,
            isNullable: isNullable,
            defaultValue: defaultValue,
            isPrimaryKey: false,
            isUnique: false,
            isForeignKey: false
        )
    }

    // MARK: - Database Info Mapping

    /// Map database name from pg_database query to DatabaseInfo
    static func mapToDatabaseInfo(_ row: PostgresRow) throws -> DatabaseInfo {
        // Use tuple decoding
        let databaseName = try row.decode(String.self)
        return DatabaseInfo(name: databaseName)
    }

    // MARK: - Table Info Mapping

    /// Map table information from pg_tables query to TableInfo
    static func mapToTableInfo(_ row: PostgresRow) throws -> TableInfo {
        // Use tuple decoding for (schemaname, tablename)
        let (schemaName, tableName) = try row.decode((String, String).self)
        return TableInfo(name: tableName, schema: schemaName)
    }
}

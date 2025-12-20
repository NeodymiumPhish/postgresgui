//
//  PostgresResultMapper.swift
//  PostgresGUI
//
//  PostgresNIO-specific implementation of ResultMapperProtocol
//

import Foundation
import PostgresNIO

/// PostgresNIO implementation of ResultMapperProtocol
struct PostgresResultMapper: ResultMapperProtocol {
    
    static let shared = PostgresResultMapper()
    
    private init() {}
    
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
    
    // MARK: - ResultMapperProtocol Implementation
    
    func mapRowToTableRow(_ row: any DatabaseRow) throws -> TableRow {
        // Convert abstract DatabaseRow to PostgresRow for decoding
        // This is a temporary bridge - ideally we'd work directly with DatabaseRow
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }
        
        return try mapPostgresRowToTableRow(postgresRow.row)
    }
    
    func mapRowsToTableRows(_ rows: any DatabaseRowSequence) async throws -> [TableRow] {
        var tableRows: [TableRow] = []
        
        for try await row in rows {
            guard let dbRow = row as? any DatabaseRow else {
                throw DatabaseError.unknownError("Expected DatabaseRow")
            }
            let tableRow = try mapRowToTableRow(dbRow)
            tableRows.append(tableRow)
        }
        
        return tableRows
    }
    
    func mapToColumnInfo(_ row: any DatabaseRow) throws -> ColumnInfo {
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }
        
        let (columnName, dataType, isNullableString, defaultValue) =
            try postgresRow.row.decode((String, String, String, String?).self)
        
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
    
    func mapToDatabaseInfo(_ row: any DatabaseRow) throws -> DatabaseInfo {
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }
        
        let databaseName = try postgresRow.row.decode(String.self)
        return DatabaseInfo(name: databaseName)
    }
    
    func mapToTableInfo(_ row: any DatabaseRow) throws -> TableInfo {
        guard let postgresRow = row as? PostgresDatabaseRow else {
            throw DatabaseError.unknownError("Expected PostgresDatabaseRow")
        }
        
        let (schemaName, tableName) = try postgresRow.row.decode((String, String).self)
        return TableInfo(name: tableName, schema: schemaName)
    }
    
    // MARK: - Private Helpers
    
    /// Map a PostgresRow to TableRow (internal helper)
    private func mapPostgresRowToTableRow(_ row: PostgresRow) throws -> TableRow {
        var values: [String: String?] = [:]
        
        for cell in row {
            let columnName = cell.columnName
            
            if cell.bytes != nil {
                values[columnName] = decodeCellValue(cell)
            } else {
                values[columnName] = nil
            }
        }
        
        return TableRow(values: values)
    }
    
    /// Decode a PostgresCell to a string representation
    private func decodeCellValue(_ cell: PostgresCell) -> String? {
        // Try String first
        if let stringValue = try? cell.decode(String.self, context: .default) {
            if !containsInvalidControlCharacters(stringValue) {
                return stringValue
            }
        }
        
        // Try Bool
        if let boolValue = try? cell.decode(Bool.self, context: .default) {
            return String(boolValue)
        }
        
        // Try UUID
        if let uuid = try? cell.decode(UUID.self, context: .default) {
            return uuid.uuidString
        }
        
        // Try Integer types
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
        
        // Try Floating point types
        if let floatValue = try? cell.decode(Float.self, context: .default) {
            return String(floatValue)
        }
        if let doubleValue = try? cell.decode(Double.self, context: .default) {
            return String(doubleValue)
        }
        
        // Try Date/Time types
        if let date = try? cell.decode(Date.self, context: .default) {
            return PostgresResultMapper.dateFormatter.string(from: date)
        }
        
        // Try Array types
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
            return formatArray(array.map { PostgresResultMapper.dateFormatter.string(from: $0) })
        }
        
        // Try ByteA/Data
        if let data = try? cell.decode(Data.self, context: .default) {
            let bytes = [UInt8](data)
            
            var printableCount = 0
            var nullCount = 0
            for byte in bytes {
                if byte == 0 {
                    nullCount += 1
                } else if (byte >= 32 && byte <= 126) || byte == 9 || byte == 10 || byte == 13 {
                    printableCount += 1
                }
            }
            
            let nonNullBytes = bytes.count - nullCount
            if nonNullBytes > 0 && Double(printableCount) / Double(nonNullBytes) > Self.textDetectionThreshold {
                if let extracted = extractReadableStrings(from: data) {
                    return extracted
                }
            }
            
            if data.count <= Self.maxHexDisplaySize {
                return "0x" + data.map { String(format: "%02x", $0) }.joined()
            } else if data.count >= Self.maxBinaryProcessingSize {
                return "(large binary data)"
            } else {
                return data.base64EncodedString()
            }
        }
        
        // Fallback for unrecognized types
        if let bytes = cell.bytes {
            var buffer = bytes
            let readableBytes = buffer.readableBytes
            
            if readableBytes > 0 && readableBytes < Self.maxBinaryProcessingSize {
                let peekLength = min(readableBytes, Self.binaryDetectionPeekSize)
                if let peekBytes = buffer.getBytes(at: 0, length: peekLength) {
                    let nullByteCount = peekBytes.filter { $0 == 0 }.count
                    
                    if Double(nullByteCount) / Double(peekBytes.count) > Self.binaryDetectionThreshold {
                        if readableBytes <= Self.maxHexDisplaySize {
                            if let allBytes = buffer.getBytes(at: 0, length: readableBytes) {
                                return "0x" + allBytes.map { String(format: "%02x", $0) }.joined()
                            }
                        }
                        return "(binary data)"
                    }
                }
                
                if let text = buffer.readString(length: readableBytes) {
                    if !containsInvalidControlCharacters(text) && !text.isEmpty {
                        return text
                    }
                }
            }
            
            if readableBytes >= Self.maxBinaryProcessingSize {
                return "(large binary data)"
            }
        }
        
        return "(unknown data type)"
    }
    
    private func containsInvalidControlCharacters(_ string: String) -> Bool {
        string.contains { char in
            char.unicodeScalars.contains { scalar in
                let value = scalar.value
                return value == 0 || ((value < 32 && value != 9 && value != 10 && value != 13) || value == 127)
            }
        }
    }
    
    private func formatArray(_ elements: [String]) -> String {
        "[\(elements.joined(separator: ", "))]"
    }
    
    private func extractReadableStrings(from data: Data) -> String? {
        let bytes = [UInt8](data)
        var strings: [String] = []
        var currentString: [UInt8] = []
        
        for byte in bytes {
            if byte == 0 {
                if !currentString.isEmpty {
                    let printableCount = currentString.filter { b in
                        (b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13
                    }.count
                    
                    if Double(printableCount) / Double(currentString.count) > Self.validStringThreshold {
                        if let str = String(bytes: currentString, encoding: .utf8), !str.isEmpty {
                            strings.append(str)
                        }
                    }
                    currentString = []
                }
            } else if (byte >= 32 && byte <= 126) || byte == 9 || byte == 10 || byte == 13 {
                currentString.append(byte)
            } else {
                if !currentString.isEmpty {
                    currentString.append(byte)
                }
            }
        }
        
        if !currentString.isEmpty {
            let printableCount = currentString.filter { b in
                (b >= 32 && b <= 126) || b == 9 || b == 10 || b == 13
            }.count
            
            if Double(printableCount) / Double(currentString.count) > Self.validStringThreshold {
                if let str = String(bytes: currentString, encoding: .utf8), !str.isEmpty {
                    strings.append(str)
                }
            }
        }
        
        if !strings.isEmpty {
            let formatted = strings.map { "\"\($0)\"" }.joined(separator: ", ")
            return "[\(formatted)]"
        }
        
        return nil
    }
}


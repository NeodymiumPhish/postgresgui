//
//  PostgresTypeConverter.swift
//  PostgresGUI
//
//  Converts PostgresData to String representations for UI display
//

import Foundation
import PostgresNIO
import NIOCore
import NIOFoundationCompat

/// Converts PostgreSQL data types to String representations for display in the UI
enum PostgresTypeConverter {

    /// Convert PostgresData to a String representation
    /// - Parameter data: The PostgresData to convert
    /// - Returns: String representation, or nil for NULL values
    static func convertToString(_ data: PostgresData) -> String? {
        // Handle NULL values
        guard let buffer = data.value else {
            return nil
        }

        // Convert based on data type
        return convertByType(data, buffer: buffer)
    }

    /// Convert PostgresData based on its type
    private static func convertByType(_ data: PostgresData, buffer: ByteBuffer) -> String? {
        // For most types, convert the ByteBuffer to String
        // PostgresNIO handles the binary format internally

        // Try to get a readable string representation
        var mutableBuffer = buffer
        if let string = mutableBuffer.readString(length: mutableBuffer.readableBytes) {
            return string.isEmpty ? nil : string
        }

        return nil
    }
}

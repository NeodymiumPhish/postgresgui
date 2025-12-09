//
//  DatabaseError.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import Foundation

enum DatabaseError: Error, LocalizedError {
    case noPrimaryKey
    case missingPrimaryKeyValue(column: String)

    var errorDescription: String? {
        switch self {
        case .noPrimaryKey:
            return "This table has no primary key. DELETE and EDIT operations require a primary key."
        case .missingPrimaryKeyValue(let column):
            return "Missing primary key value for column: \(column)"
        }
    }
}

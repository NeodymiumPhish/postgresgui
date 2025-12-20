//
//  SavedQuery.swift
//  PostgresGUI
//
//  Created by ghazi on 12/19/25.
//

import Foundation
import SwiftData

@Model
final class SavedQuery: Identifiable {
    var id: UUID
    var name: String
    var queryText: String
    var connectionId: UUID?
    var databaseName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        queryText: String,
        connectionId: UUID? = nil,
        databaseName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.queryText = queryText
        self.connectionId = connectionId
        self.databaseName = databaseName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SavedQuery {
    /// Generates a query name with timestamp
    static func generateName(from queryText: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Query \(formatter.string(from: Date()))"
    }
}

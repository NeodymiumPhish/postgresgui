//
//  TabState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/20/25.
//

import Foundation
import SwiftData

@Model
final class TabState: Identifiable {
    var id: UUID
    var connectionId: UUID?
    var databaseName: String?
    var queryText: String
    var isActive: Bool
    var order: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        connectionId: UUID? = nil,
        databaseName: String? = nil,
        queryText: String = "",
        isActive: Bool = false,
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.connectionId = connectionId
        self.databaseName = databaseName
        self.queryText = queryText
        self.isActive = isActive
        self.order = order
        self.createdAt = createdAt
    }
}

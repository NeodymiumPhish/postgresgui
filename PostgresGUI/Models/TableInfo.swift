//
//  TableInfo.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct TableInfo: Identifiable {
    let id: String
    let name: String
    let schema: String
    var primaryKeyColumns: [String]? = nil
    var columnInfo: [ColumnInfo]? = nil

    init(name: String, schema: String = "public", primaryKeyColumns: [String]? = nil, columnInfo: [ColumnInfo]? = nil) {
        self.id = "\(schema).\(name)"
        self.name = name
        self.schema = schema
        self.primaryKeyColumns = primaryKeyColumns
        self.columnInfo = columnInfo
    }
}

// Custom Hashable using only id - prevents List deselection when metadata is updated
extension TableInfo: Equatable {
    static func == (lhs: TableInfo, rhs: TableInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension TableInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

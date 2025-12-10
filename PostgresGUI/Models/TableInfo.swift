//
//  TableInfo.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct TableInfo: Identifiable, Hashable {
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

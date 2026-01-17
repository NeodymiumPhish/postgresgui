//
//  SchemaGroupView.swift
//  PostgresGUI
//
//  Collapsible disclosure group for tables in a schema.
//

import SwiftUI

struct SchemaGroupView: View {
    let group: SchemaGroup
    @Binding var isExpanded: Bool
    @Binding var selectedTable: TableInfo?
    let isExecutingQuery: Bool
    let refreshQueryAction: (TableInfo) async -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(group.tables) { table in
                TableListRowView(
                    table: table,
                    isExecutingQuery: isExecutingQuery,
                    refreshQueryAction: refreshQueryAction,
                    showSchemaPrefix: false
                )
                .tag(table)
                .listRowSeparator(.visible)
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(group.name)
                    .fontWeight(.medium)
                Spacer()
                Text("\(group.tableCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}

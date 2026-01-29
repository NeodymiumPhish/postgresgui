//
//  DesignSystemView.swift
//  PostgresGUI
//
//  Component showcase for the Design System.
//  Displays all components with examples in different states.
//

import SwiftUI

struct DesignSystemView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Primitives") {
                    NavigationLink("Badge") {
                        BadgeShowcase()
                    }
                    NavigationLink("Empty State") {
                        EmptyStateShowcase()
                    }
                    NavigationLink("Loading Overlay") {
                        LoadingOverlayShowcase()
                    }
                    NavigationLink("Syntax Highlighted Editor") {
                        SyntaxEditorShowcase()
                    }
                }
                
                Section("Components - Tables") {
                    NavigationLink("Table Column Row") {
                        TableColumnRowShowcase()
                    }
                    NavigationLink("Schema Group") {
                        SchemaGroupShowcase()
                    }
                }
                
                Section("Components - Connection") {
                    NavigationLink("Connection Status Banner") {
                        ConnectionStatusShowcase()
                    }
                    NavigationLink("Schema Picker") {
                        SchemaPickerShowcase()
                    }
                }
                
                Section("Components - Toast") {
                    NavigationLink("Mutation Toast") {
                        MutationToastShowcase()
                    }
                }
                
                Section("Components - Sheets") {
                    NavigationLink("Edit Folder Sheet") {
                        EditFolderSheetShowcase()
                    }
                    NavigationLink("Edit Query Sheet") {
                        EditQuerySheetShowcase()
                    }
                    NavigationLink("Table DDL Sheet") {
                        TableDDLSheetShowcase()
                    }
                }
            }
            .navigationTitle("Design System")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Showcases

struct BadgeShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Badge")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A small label component used to display status or counts.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Examples")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Badge(text: "Active", color: .green)
                        Badge(text: "Pending", color: .orange)
                        Badge(text: "Error", color: .red)
                        Badge(text: "Info", color: .blue)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Badge")
    }
}

struct EmptyStateShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Empty Query Results View")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Displayed when there are no query results to show.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before Query Execution")
                        .font(.headline)
                    
                    EmptyQueryResultsView(hasExecutedQuery: false)
                        .frame(height: 200)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text("After Query (No Results)")
                        .font(.headline)
                    
                    EmptyQueryResultsView(hasExecutedQuery: true)
                        .frame(height: 200)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .navigationTitle("Empty State")
    }
}

struct LoadingOverlayShowcase: View {
    @State private var phase: LoadingPhase = .connectingToDatabase
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Loading Overlay")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A full-screen overlay shown during loading operations.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Phases")
                        .font(.headline)
                    
                    Picker("Phase", selection: $phase) {
                        Text("Connecting").tag(LoadingPhase.connectingToDatabase)
                        Text("Loading Tables").tag(LoadingPhase.loadingTables)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        LoadingOverlayView(phase: phase)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .navigationTitle("Loading Overlay")
    }
}

struct SyntaxEditorShowcase: View {
    @State private var text = """
        SELECT id, name, email
        FROM users
        WHERE created_at > '2024-01-01'
        ORDER BY name ASC
        LIMIT 100;
        """
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Syntax Highlighted Editor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A SQL editor with syntax highlighting.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Example")
                        .font(.headline)
                    
                    SyntaxHighlightedEditor(text: $text)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .navigationTitle("Syntax Editor")
    }
}

struct TableColumnRowShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Table Column Row")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Displays column information in the sidebar table expansion.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Examples")
                        .font(.headline)
                    
                    VStack(spacing: 0) {
                        TableColumnRowView(column: ColumnInfo(
                            name: "id",
                            dataType: "integer",
                            isNullable: false,
                            isPrimaryKey: true
                        ))
                        TableColumnRowView(column: ColumnInfo(
                            name: "user_id",
                            dataType: "integer",
                            isNullable: false,
                            isForeignKey: true
                        ))
                        TableColumnRowView(column: ColumnInfo(
                            name: "email",
                            dataType: "character varying",
                            isNullable: false
                        ))
                        TableColumnRowView(column: ColumnInfo(
                            name: "created_at",
                            dataType: "timestamp with time zone",
                            isNullable: true
                        ))
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .navigationTitle("Table Column Row")
    }
}

struct SchemaGroupShowcase: View {
    @State private var isExpanded = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Schema Group")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A collapsible group of tables organized by schema.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Example")
                        .font(.headline)
                    
                    Text("Schema groups are used in the tables sidebar when multiple schemas are present.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Schema Group")
    }
}

struct ConnectionStatusShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Connection Status Banner")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Shows connection test results in forms.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("States")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        ConnectionStatusBanner(status: .testing) {}
                        ConnectionStatusBanner(status: .success) {}
                        ConnectionStatusBanner(status: .error(message: "Connection refused: localhost:5432")) {}
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Connection Status")
    }
}

struct SchemaPickerShowcase: View {
    @State private var selectedSchema: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Schema Picker")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A dropdown to filter tables by schema.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Example")
                        .font(.headline)
                    
                    SchemaPicker(
                        schemas: ["public", "auth", "storage", "extensions"],
                        selectedSchema: selectedSchema,
                        onSelect: { selectedSchema = $0 }
                    )
                    .frame(width: 300)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text("Selected: \(selectedSchema ?? "All Schemas")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Schema Picker")
    }
}

struct MutationToastShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Mutation Toast")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A toast notification shown after successful mutations.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Examples")
                        .font(.headline)
                    
                    VStack(alignment: .trailing, spacing: 16) {
                        MutationToastView(
                            data: MutationToastData(
                                title: "Row inserted",
                                tableName: "users",
                                queryType: .insert
                            ),
                            onViewTable: {},
                            onDismiss: {}
                        )
                        
                        MutationToastView(
                            data: MutationToastData(
                                title: "3 rows deleted",
                                tableName: "sessions",
                                queryType: .delete
                            ),
                            onViewTable: {},
                            onDismiss: {}
                        )
                        
                        MutationToastView(
                            data: MutationToastData(
                                title: "Table dropped",
                                tableName: nil,
                                queryType: .dropTable
                            ),
                            onViewTable: {},
                            onDismiss: {}
                        )
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Mutation Toast")
    }
}

struct EditFolderSheetShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Edit Folder Sheet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A sheet for renaming query folders.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                Text("This sheet will be refactored to receive callbacks instead of direct model binding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Edit Folder Sheet")
    }
}

struct EditQuerySheetShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Edit Query Sheet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("A sheet for renaming saved queries.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                Text("This sheet will be refactored to receive callbacks instead of direct model binding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Edit Query Sheet")
    }
}

struct TableDDLSheetShowcase: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Table DDL Sheet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Displays generated DDL for a table.")
                    .foregroundStyle(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Example DDL")
                        .font(.headline)
                    
                    Text("""
                        CREATE TABLE public.users (
                            id SERIAL PRIMARY KEY,
                            email VARCHAR(255) NOT NULL UNIQUE,
                            name VARCHAR(100),
                            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
                        );
                        """)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .navigationTitle("Table DDL Sheet")
    }
}

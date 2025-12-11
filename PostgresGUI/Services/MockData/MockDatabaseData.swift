//
//  MockDatabaseData.swift
//  PostgresGUI
//
//  Created by ghazi
//

import Foundation

/// Mock data provider for DatabaseService during development/testing
enum MockDatabaseData {
    static let databases: [DatabaseInfo] = [
        DatabaseInfo(name: "postgres"),
        DatabaseInfo(name: "testdb"),
        DatabaseInfo(name: "sample_db"),
        DatabaseInfo(name: "demo")
    ]
    
    static let tables: [String: [TableInfo]] = [
        "postgres": [
            TableInfo(name: "users", schema: "public"),
            TableInfo(name: "orders", schema: "public"),
            TableInfo(name: "products", schema: "public")
        ],
        "testdb": [
            TableInfo(name: "customers", schema: "public"),
            TableInfo(name: "invoices", schema: "public")
        ],
        "sample_db": [
            TableInfo(name: "employees", schema: "public"),
            TableInfo(name: "departments", schema: "public"),
            TableInfo(name: "projects", schema: "public")
        ],
        "demo": [
            TableInfo(name: "items", schema: "public")
        ]
    ]
    
    static func initializeTableData() -> [String: [TableRow]] {
        var tableData: [String: [TableRow]] = [:]
        
        // Mock data for users table
        tableData["public.users"] = [
            TableRow(values: ["id": "1", "name": "John Doe", "email": "john@example.com", "age": "30", "active": "true"]),
            TableRow(values: ["id": "2", "name": "Jane Smith", "email": "jane@example.com", "age": "25", "active": "true"]),
            TableRow(values: ["id": "3", "name": "Bob Johnson", "email": "bob@example.com", "age": "35", "active": "false"]),
            TableRow(values: ["id": "4", "name": "Alice Williams", "email": "alice@example.com", "age": "28", "active": "true"]),
            TableRow(values: ["id": "5", "name": "Charlie Brown", "email": "charlie@example.com", "age": "42", "active": "true"])
        ]
        
        // Mock data for orders table
        tableData["public.orders"] = [
            TableRow(values: ["id": "1", "user_id": "1", "product": "Laptop", "amount": "1299.99", "status": "completed", "created_at": "2024-01-15 10:30:00"]),
            TableRow(values: ["id": "2", "user_id": "2", "product": "Mouse", "amount": "29.99", "status": "pending", "created_at": "2024-01-16 14:20:00"]),
            TableRow(values: ["id": "3", "user_id": "1", "product": "Keyboard", "amount": "79.99", "status": "completed", "created_at": "2024-01-17 09:15:00"]),
            TableRow(values: ["id": "4", "user_id": "3", "product": "Monitor", "amount": "299.99", "status": "shipped", "created_at": "2024-01-18 11:45:00"])
        ]
        
        // Mock data for products table
        tableData["public.products"] = [
            TableRow(values: ["id": "1", "name": "Laptop", "price": "1299.99", "stock": "50", "category": "Electronics"]),
            TableRow(values: ["id": "2", "name": "Mouse", "price": "29.99", "stock": "200", "category": "Accessories"]),
            TableRow(values: ["id": "3", "name": "Keyboard", "price": "79.99", "stock": "150", "category": "Accessories"]),
            TableRow(values: ["id": "4", "name": "Monitor", "price": "299.99", "stock": "75", "category": "Electronics"]),
            TableRow(values: ["id": "5", "name": "Webcam", "price": "89.99", "stock": "100", "category": "Accessories"])
        ]
        
        // Mock data for customers table
        tableData["public.customers"] = [
            TableRow(values: ["id": "1", "name": "Acme Corp", "contact": "John Manager", "email": "contact@acme.com", "phone": "555-0101"]),
            TableRow(values: ["id": "2", "name": "Tech Solutions", "contact": "Sarah Director", "email": "sarah@techsol.com", "phone": "555-0102"]),
            TableRow(values: ["id": "3", "name": "Global Inc", "contact": "Mike CEO", "email": "mike@global.com", "phone": "555-0103"])
        ]
        
        // Mock data for employees table
        tableData["public.employees"] = [
            TableRow(values: ["id": "1", "first_name": "Alice", "last_name": "Johnson", "department": "Engineering", "salary": "95000", "hire_date": "2020-03-15"]),
            TableRow(values: ["id": "2", "first_name": "Bob", "last_name": "Smith", "department": "Sales", "salary": "75000", "hire_date": "2021-06-20"]),
            TableRow(values: ["id": "3", "first_name": "Carol", "last_name": "Davis", "department": "Engineering", "salary": "105000", "hire_date": "2019-11-10"])
        ]
        
        return tableData
    }
}

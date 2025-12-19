//
//  PersistenceContextProtocol.swift
//  PostgresGUI
//
//  Protocol abstraction for SwiftData ModelContext operations
//  Enables dependency injection and testability
//

import Foundation
import SwiftData

/// Protocol for persistence context operations
/// Allows injecting a mock implementation for testing without requiring full SwiftData stack
protocol PersistenceContextProtocol {
    /// Save changes to the persistent store
    func save() throws
}

/// Wrapper for SwiftData ModelContext
class SwiftDataPersistenceContext: PersistenceContextProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save() throws {
        try modelContext.save()
    }
}

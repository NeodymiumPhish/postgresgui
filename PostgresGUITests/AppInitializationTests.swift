//
//  AppInitializationTests.swift
//  PostgresGUITests
//
//  Simple smoke tests to verify app launches without crashing
//

import Testing
import SwiftUI
@testable import PostgresGUI

@Test @MainActor
func appStateInitializes() {
    // Verify app can initialize without crashing
    let _ = AppState()
}

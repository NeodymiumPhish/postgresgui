//
//  AppLaunchDecisions.swift
//  PostgresGUI
//
//  Pure functions for app launch logic decisions.
//

import Foundation

// MARK: - Decision Functions

/// Determines whether to show the welcome screen
/// - Parameters:
///   - connectionCount: Number of saved connections
///   - isShowingConnectionForm: Whether connection form is currently showing
/// - Returns: True if welcome screen should be shown
func shouldShowWelcomeScreen(connectionCount: Int, isShowingConnectionForm: Bool) -> Bool {
    connectionCount == 0 && !isShowingConnectionForm
}

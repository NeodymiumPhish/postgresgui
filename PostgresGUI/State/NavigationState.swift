//
//  NavigationState.swift
//  PostgresGUI
//
//  Created by ghazi on 12/17/25.
//

import SwiftUI

/// Manages navigation and modal presentation state
@Observable
@MainActor
class NavigationState {
    // Navigation
    var navigationPath: NavigationPath = NavigationPath()

    // Modal/Sheet state
    var isShowingConnectionForm: Bool = false
    var isShowingWelcomeScreen: Bool = true
    var connectionToEdit: ConnectionProfile? = nil

    // Sheet management helpers
    func showConnectionForm() {
        isShowingConnectionForm = true
    }
}

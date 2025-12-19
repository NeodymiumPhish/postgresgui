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

    // Sidebar view mode
    var sidebarViewMode: SidebarViewMode = .connections

    // Modal/Sheet state
    var isShowingConnectionForm: Bool = false
    var isShowingConnectionsList: Bool = false
    var isShowingWelcomeScreen: Bool = true
    var connectionToEdit: ConnectionProfile? = nil

    // Sheet management helpers - ensure only one sheet is shown at a time
    func showConnectionForm() {
        isShowingConnectionsList = false
        isShowingConnectionForm = true
    }

    func showConnectionsList() {
        isShowingConnectionForm = false
        isShowingConnectionsList = true
    }
}

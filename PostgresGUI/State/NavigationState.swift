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
    var isShowingConnectionsList: Bool = false
    var isShowingWelcomeScreen: Bool = true
    var connectionToEdit: ConnectionProfile? = nil
    var connectionFormOpenedFromList: Bool = false

    // Connection saved alert state
    var showConnectionSavedAlert: Bool = false
    var savedConnection: ConnectionProfile? = nil

    // Sheet management helpers - ensure only one sheet is shown at a time
    func showConnectionForm() {
        // Track if we came from the connections list
        connectionFormOpenedFromList = isShowingConnectionsList
        isShowingConnectionsList = false
        isShowingConnectionForm = true
    }

    func showConnectionsList() {
        isShowingConnectionForm = false
        isShowingConnectionsList = true
    }
}

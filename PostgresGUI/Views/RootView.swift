//
//  RootView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appState = AppState()
    @Query private var connections: [ConnectionProfile]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if appState.isShowingWelcomeScreen && connections.isEmpty {
                WelcomeView()
                    .environment(appState)
            } else {
                MainSplitView()
                    .environment(appState)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingConnectionForm },
            set: { newValue in
                if newValue {
                    // Close other sheet before opening this one
                    appState.isShowingConnectionsList = false
                }
                appState.isShowingConnectionForm = newValue
                if !newValue {
                    // Clear edit state when sheet is dismissed
                    appState.connectionToEdit = nil
                }
            }
        )) {
            ConnectionFormView(connectionToEdit: appState.connectionToEdit)
                .environment(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingConnectionsList },
            set: { newValue in
                if newValue {
                    // Close other sheet before opening this one
                    appState.isShowingConnectionForm = false
                }
                appState.isShowingConnectionsList = newValue
            }
        )) {
            ConnectionsListView()
                .environment(appState)
        }
    }
}

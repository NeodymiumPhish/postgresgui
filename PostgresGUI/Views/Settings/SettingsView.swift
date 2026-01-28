//
//  SettingsView.swift
//  PostgresGUI
//
//  Application settings view.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title2)
            Text("No configurable settings are available.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 220, alignment: .topLeading)
        .padding()
    }
}

#Preview {
    SettingsView()
}

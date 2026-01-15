//
//  SettingsView.swift
//  PostgresGUI
//
//  Application settings view.
//

import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Date Format") {
                Picker("Format", selection: $settings.dateFormat) {
                    ForEach(DateFormat.allCases) { format in
                        HStack {
                            Text(format.displayName)
                            Spacer()
                            Text(format.example)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 220)
        .padding()
    }
}

#Preview {
    SettingsView()
}

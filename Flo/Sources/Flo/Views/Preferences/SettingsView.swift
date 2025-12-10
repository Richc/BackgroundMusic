// SettingsView.swift
// Flo
//
// Advanced settings page: dark/light mode, load/save profiles, routing matrix, help menu

import SwiftUI

struct SettingsView: View {
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    @State private var showHelpMenu = false
    @State private var showRoutingMatrix = false
    @State private var selectedProfile: String = ""
    @State private var profiles: [String] = ["Default", "Profile 1", "Profile 2"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.largeTitle)
                .padding(.bottom, 8)
            
            // Color scheme toggle
            HStack {
                Text("Appearance:")
                Picker("Appearance", selection: $colorScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Divider()
            
            // Profile management
            HStack {
                Text("Profile:")
                Picker("Profile", selection: $selectedProfile) {
                    ForEach(profiles, id: \ .self) { profile in
                        Text(profile)
                    }
                }
                Button("Load") { /* TODO: Load profile */ }
                Button("Save") { /* TODO: Save profile */ }
            }
            
            Divider()
            
            // Routing matrix
            Button("Show Routing Matrix") {
                showRoutingMatrix.toggle()
            }
            if showRoutingMatrix {
                RoutingMatrixView()
            }
            
            Divider()
            
            // Help menu
            Button("Help & Tooltips") {
                showHelpMenu.toggle()
            }
            if showHelpMenu {
                HelpMenuView()
            }
            
            Spacer()
        }
        .padding(24)
    }
}

struct RoutingMatrixView: View {
    // Dummy data for demonstration
    let outputs = ["Out 1", "Out 2", "Out 3"]
    let inputs = ["In 1", "In 2", "In 3"]
    @State private var matrix: [[Bool]] = Array(repeating: Array(repeating: false, count: 3), count: 3)
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Audio I/O Routing Matrix")
                .font(.headline)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(outputs, id: \ .self) { out in
                        Text(out).font(.subheadline)
                    }
                }
                ForEach(inputs.indices, id: \ .self) { i in
                    GridRow {
                        Text(inputs[i]).font(.subheadline)
                        ForEach(outputs.indices, id: \ .self) { j in
                            Toggle("", isOn: $matrix[i][j])
                                .labelsHidden()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }
}

struct HelpMenuView: View {
    @AppStorage("showTooltips") private var showTooltips = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help & Tooltips")
                .font(.headline)
            Toggle("Show hover-over tooltips", isOn: $showTooltips)
            Text("Hover over any control in the app to see a description. You can toggle this setting here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
}

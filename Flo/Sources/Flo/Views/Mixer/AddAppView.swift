//
//  AddAppView.swift
//  Flo
//
//  View for selecting apps and input devices to add to the mixer
//

import SwiftUI
import AppKit

struct AddAppView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var availableApps: [NSRunningApplication] = []
    @State private var selectedTab: AddSourceTab = .apps
    
    enum AddSourceTab: String, CaseIterable {
        case apps = "Apps"
        case inputs = "Inputs"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Source")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(AddSourceTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            switch selectedTab {
            case .apps:
                appsTabView
            case .inputs:
                inputsTabView
            }
        }
        .frame(width: 350, height: 450)
        .onAppear {
            refreshApps()
        }
    }
    
    // MARK: - Apps Tab
    
    private var appsTabView: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            Divider()
            
            // App list
            if filteredApps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No apps available to add")
                        .foregroundColor(.secondary)
                    Text("All running apps are already in the mixer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredApps, id: \.processIdentifier) { app in
                            AppRowView(app: app) {
                                addApp(app)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    // MARK: - Inputs Tab
    
    private var inputsTabView: some View {
        VStack(spacing: 0) {
            // Info header
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Add a microphone or audio input to the mix")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            
            Divider()
            
            if audioEngine.inputDevices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "mic.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No input devices found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(audioEngine.inputDevices) { device in
                            InputDeviceRowView(device: device, isAdded: isInputAdded(device)) {
                                toggleInputDevice(device)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var filteredApps: [NSRunningApplication] {
        if searchText.isEmpty {
            return availableApps
        }
        return availableApps.filter { app in
            (app.localizedName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func refreshApps() {
        availableApps = audioEngine.availableAppsToAdd()
    }
    
    private func addApp(_ app: NSRunningApplication) {
        audioEngine.addManagedApp(from: app)
        refreshApps()
        
        // Dismiss if no more apps to add
        if availableApps.isEmpty {
            dismiss()
        }
    }
    
    private func isInputAdded(_ device: AudioDevice) -> Bool {
        audioEngine.channels.contains { $0.channelType == .inputDevice && $0.identifier == device.id }
    }
    
    private func toggleInputDevice(_ device: AudioDevice) {
        if isInputAdded(device) {
            // Remove input channel
            if let channel = audioEngine.channels.first(where: { $0.channelType == .inputDevice && $0.identifier == device.id }) {
                audioEngine.removeChannel(channel)
            }
        } else {
            // Add input channel
            audioEngine.addInputChannel(device: device)
        }
    }
}

// MARK: - Input Device Row

struct InputDeviceRowView: View {
    let device: AudioDevice
    let isAdded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Mic icon
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundColor(isAdded ? .green : .secondary)
                .frame(width: 32, height: 32)
            
            // Device name
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                Text(isAdded ? "In mixer" : "Tap to add")
                    .font(.caption2)
                    .foregroundColor(isAdded ? .green : .secondary)
            }
            
            Spacer()
            
            // Add/Remove button
            Button {
                onToggle()
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(isAdded ? .green : .accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isAdded ? Color.green.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

struct AppRowView: View {
    let app: NSRunningApplication
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.title)
                    .frame(width: 32, height: 32)
            }
            
            // App name
            VStack(alignment: .leading, spacing: 2) {
                Text(app.localizedName ?? "Unknown")
                    .font(.body)
                if let bundleID = app.bundleIdentifier {
                    Text(bundleID)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Add button
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onAdd()
        }
    }
}

#Preview {
    AddAppView()
        .environmentObject(AudioEngine())
}

//
//  AddAppView.swift
//  Manatee
//
//  View for selecting apps to add to the mixer
//

import SwiftUI
import AppKit

struct AddAppView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var availableApps: [NSRunningApplication] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Application")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
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
        .frame(width: 350, height: 400)
        .onAppear {
            refreshApps()
        }
    }
    
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

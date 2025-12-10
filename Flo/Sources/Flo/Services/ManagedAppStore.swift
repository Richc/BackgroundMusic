//
//  ManagedAppStore.swift
//  Flo
//
//  Persistent storage for user's managed apps
//

import Foundation
import Combine
import AppKit

/// Manages persistence and state of user-selected apps
@MainActor
final class ManagedAppStore: ObservableObject {
    
    // MARK: - Published State
    
    /// List of apps the user wants to manage
    @Published private(set) var managedApps: [ManagedApp] = []
    
    /// Currently running bundle IDs (for checking active state)
    @Published private(set) var runningBundleIDs: Set<String> = []
    
    // MARK: - Private
    
    private let userDefaultsKey = "ManagedApps"
    private var workspaceObserver: Any?
    
    // MARK: - Singleton
    
    static let shared = ManagedAppStore()
    
    private init() {
        loadManagedApps()
        updateRunningApps()
        observeWorkspaceNotifications()
    }
    
    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    // MARK: - Public API
    
    /// Add an app to the managed list
    func addApp(_ app: ManagedApp) {
        guard !managedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        
        var newApp = app
        newApp.sortOrder = managedApps.count
        managedApps.append(newApp)
        saveManagedApps()
        
        print("➕ ManagedAppStore: Added \(app.name)")
    }
    
    /// Add an app from a running application
    func addApp(from runningApp: NSRunningApplication) {
        guard let app = ManagedApp.from(runningApp) else { return }
        addApp(app)
    }
    
    /// Remove an app from the managed list
    func removeApp(bundleID: String) {
        managedApps.removeAll { $0.bundleID == bundleID }
        saveManagedApps()
        
        print("➖ ManagedAppStore: Removed \(bundleID)")
    }
    
    /// Remove an app by ManagedApp
    func removeApp(_ app: ManagedApp) {
        removeApp(bundleID: app.bundleID)
    }
    
    /// Check if an app is currently running
    func isAppRunning(_ bundleID: String) -> Bool {
        runningBundleIDs.contains(bundleID)
    }
    
    /// Reorder apps
    func moveApp(from source: IndexSet, to destination: Int) {
        managedApps.move(fromOffsets: source, toOffset: destination)
        updateSortOrders()
        saveManagedApps()
    }
    
    /// Get all running apps that aren't already managed
    func availableAppsToAdd() -> [NSRunningApplication] {
        let managedBundleIDs = Set(managedApps.map { $0.bundleID })
        
        // Apps that should always be available even if they'd normally be filtered
        let alwaysAllowedApps = ["com.apple.finder"]
        
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            
            // Always allow specific apps like Finder
            if alwaysAllowedApps.contains(bundleID) {
                return !managedBundleIDs.contains(bundleID)
            }
            
            // Skip apps without UI, system apps, and already managed apps
            guard app.activationPolicy == .regular,
                  !managedBundleIDs.contains(bundleID),
                  !isSystemApp(bundleID: bundleID) else { return false }
            
            return true
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    /// Refresh the list of running apps
    func updateRunningApps() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        
        if running != runningBundleIDs {
            runningBundleIDs = running
        }
    }
    
    // MARK: - Persistence
    
    private func loadManagedApps() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("📂 ManagedAppStore: No saved apps found")
            return
        }
        
        do {
            managedApps = try JSONDecoder().decode([ManagedApp].self, from: data)
            managedApps.sort { $0.sortOrder < $1.sortOrder }
            print("📂 ManagedAppStore: Loaded \(managedApps.count) managed apps")
        } catch {
            print("❌ ManagedAppStore: Failed to load managed apps: \(error)")
        }
    }
    
    private func saveManagedApps() {
        do {
            let data = try JSONEncoder().encode(managedApps)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("💾 ManagedAppStore: Saved \(managedApps.count) managed apps")
        } catch {
            print("❌ ManagedAppStore: Failed to save managed apps: \(error)")
        }
    }
    
    private func updateSortOrders() {
        for (index, _) in managedApps.enumerated() {
            managedApps[index].sortOrder = index
        }
    }
    
    // MARK: - Workspace Observation
    
    private func observeWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        
        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateRunningApps()
            }
        }
        
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateRunningApps()
            }
        }
    }
    
    // MARK: - Helpers
    
    private func isSystemApp(bundleID: String) -> Bool {
        let systemPrefixes = [
            "com.apple.systempreferences",
            "com.apple.loginwindow",
            "com.apple.dock",
            // Finder can play audio (Quick Look, preview) so it's allowed
            "com.apple.controlcenter",
            "com.apple.notificationcenterui"
        ]
        
        let excludedApps = [
            "com.flo.Flo",  // Don't control ourselves
            "Flo"  // Also check for bundle without reverse DNS
        ]
        
        if excludedApps.contains(bundleID) { return true }
        return systemPrefixes.contains { bundleID.hasPrefix($0) }
    }
}

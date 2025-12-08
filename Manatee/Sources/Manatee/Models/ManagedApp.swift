//
//  ManagedApp.swift
//  Manatee
//
//  Represents an app that the user has chosen to manage volume for
//

import Foundation
import AppKit

/// Represents an app that the user wants to control
struct ManagedApp: Codable, Identifiable, Hashable {
    /// The app's bundle identifier (used as primary key)
    var id: String { bundleID }
    
    /// Bundle identifier
    let bundleID: String
    
    /// Display name
    let name: String
    
    /// Path to the app (for icon loading)
    let appPath: String?
    
    /// Order in the mixer (for user customization)
    var sortOrder: Int
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case bundleID
        case name
        case appPath
        case sortOrder
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }
    
    static func == (lhs: ManagedApp, rhs: ManagedApp) -> Bool {
        lhs.bundleID == rhs.bundleID
    }
    
    // MARK: - Factory
    
    /// Create from a running application
    static func from(_ app: NSRunningApplication) -> ManagedApp? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        
        return ManagedApp(
            bundleID: bundleID,
            name: app.localizedName ?? bundleID,
            appPath: app.bundleURL?.path,
            sortOrder: 0
        )
    }
    
    /// Create from an installed application URL
    static func from(appURL: URL) -> ManagedApp? {
        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else { return nil }
        
        let name = FileManager.default.displayName(atPath: appURL.path)
        
        return ManagedApp(
            bundleID: bundleID,
            name: name,
            appPath: appURL.path,
            sortOrder: 0
        )
    }
    
    // MARK: - Icon Loading
    
    /// Load the app's icon (not stored, loaded on demand)
    func loadIcon() -> NSImage? {
        if let path = appPath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        
        // Try to find the app by bundle ID
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        
        return nil
    }
    
    // MARK: - Running State
    
    /// Check if this app is currently running
    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
    
    /// Get the running application instance if running
    var runningApplication: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
    
    /// Get the process ID if running
    var processID: pid_t? {
        runningApplication?.processIdentifier
    }
}

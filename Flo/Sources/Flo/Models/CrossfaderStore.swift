//
//  CrossfaderStore.swift
//  Flo
//
//  Simple crossfader that controls volume between two apps
//

import Foundation
import Combine

/// Manages crossfader state - fading between two selected apps
@MainActor
final class CrossfaderStore: ObservableObject {
    
    // MARK: - Published State
    
    /// Is crossfader enabled/visible
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "CrossfaderEnabled")
            // Reset position to center when enabled
            if isEnabled {
                position = 0.0
            }
        }
    }
    
    /// Left side app bundle ID
    @Published var leftAppBundleID: String? = nil {
        didSet {
            UserDefaults.standard.set(leftAppBundleID, forKey: "CrossfaderLeftApp")
            // Capture current volume when app is assigned
            captureLeftAppVolume()
            // Reset position to center when app changes
            position = 0.0
        }
    }
    
    /// Right side app bundle ID
    @Published var rightAppBundleID: String? = nil {
        didSet {
            UserDefaults.standard.set(rightAppBundleID, forKey: "CrossfaderRightApp")
            // Capture current volume when app is assigned
            captureRightAppVolume()
            // Reset position to center when app changes
            position = 0.0
        }
    }
    
    /// Crossfader position: -1.0 = full left, 0.0 = center, 1.0 = full right
    /// At center (0.0), both apps are at their captured volume (no change)
    /// Moving left reduces RIGHT app, moving right reduces LEFT app
    @Published var position: Float = 0.0
    
    /// Captured volume for left app (the level when it was assigned)
    @Published var leftAppBaseVolume: Float = 1.0
    
    /// Captured volume for right app (the level when it was assigned)
    @Published var rightAppBaseVolume: Float = 1.0
    
    /// Reference to audio engine for volume control
    weak var audioEngine: AudioEngine?
    
    /// Whether the crossfader is operational (both apps assigned)
    var isOperational: Bool {
        leftAppBundleID != nil && rightAppBundleID != nil
    }
    
    // MARK: - Singleton
    
    static let shared = CrossfaderStore()
    
    private init() {
        // Load persisted state
        isEnabled = UserDefaults.standard.bool(forKey: "CrossfaderEnabled")
        leftAppBundleID = UserDefaults.standard.string(forKey: "CrossfaderLeftApp")
        rightAppBundleID = UserDefaults.standard.string(forKey: "CrossfaderRightApp")
        // Always start at center
        position = 0.0
    }
    
    // MARK: - Volume Capture
    
    /// Capture the current volume of the left app as its base level
    private func captureLeftAppVolume() {
        guard let engine = audioEngine,
              let leftBundleID = leftAppBundleID,
              let leftChannel = engine.channels.first(where: { $0.identifier == leftBundleID }) else {
            leftAppBaseVolume = 1.0
            return
        }
        leftAppBaseVolume = leftChannel.volume
        print("🎚️ Crossfader: Captured left app volume: \(leftAppBaseVolume)")
    }
    
    /// Capture the current volume of the right app as its base level
    private func captureRightAppVolume() {
        guard let engine = audioEngine,
              let rightBundleID = rightAppBundleID,
              let rightChannel = engine.channels.first(where: { $0.identifier == rightBundleID }) else {
            rightAppBaseVolume = 1.0
            return
        }
        rightAppBaseVolume = rightChannel.volume
        print("🎚️ Crossfader: Captured right app volume: \(rightAppBaseVolume)")
    }
    
    /// Re-capture volumes for both apps (call when audio engine is set)
    func recaptureVolumes() {
        captureLeftAppVolume()
        captureRightAppVolume()
    }
    
    // MARK: - Crossfader Logic
    
    /// Update volumes based on crossfader position
    /// Position: -1.0 = full left, 0.0 = center, 1.0 = full right
    /// At center: both apps stay at their channel strip volume (no modification)
    /// Moving LEFT (negative): reduces RIGHT app volume
    /// Moving RIGHT (positive): reduces LEFT app volume
    /// The channel strip volume is always the "max" - crossfader only reduces from there
    func updateVolumes() {
        guard let engine = audioEngine else { return }
        guard isOperational else { return }  // Only work when both apps assigned
        
        // Get current base volumes from channel strips (these are the "center" volumes)
        // User can adjust channel strip to set the max level
        if let leftBundleID = leftAppBundleID,
           let leftChannel = engine.channels.first(where: { $0.identifier == leftBundleID }) {
            // Update base volume from channel if at center (user may have adjusted it)
            if position == 0 {
                leftAppBaseVolume = leftChannel.volume
            } else {
                // Apply crossfader reduction: moving right reduces left
                let leftMultiplier: Float = position <= 0 ? 1.0 : 1.0 - position
                leftChannel.volume = leftAppBaseVolume * leftMultiplier
            }
        }
        
        if let rightBundleID = rightAppBundleID,
           let rightChannel = engine.channels.first(where: { $0.identifier == rightBundleID }) {
            // Update base volume from channel if at center (user may have adjusted it)
            if position == 0 {
                rightAppBaseVolume = rightChannel.volume
            } else {
                // Apply crossfader reduction: moving left reduces right
                let rightMultiplier: Float = position >= 0 ? 1.0 : 1.0 + position
                rightChannel.volume = rightAppBaseVolume * rightMultiplier
            }
        }
    }
    
    /// Set crossfader position and update volumes
    func setPosition(_ newPosition: Float) {
        guard isOperational else { return }  // Only work when both apps assigned
        
        // If moving away from center, capture current channel volumes as base
        if position == 0 && newPosition != 0 {
            recaptureVolumes()
        }
        
        position = max(-1.0, min(1.0, newPosition))
        updateVolumes()
    }
    
    /// Clear left app assignment and reset position
    func clearLeftApp() {
        leftAppBundleID = nil
        position = 0.0
    }
    
    /// Clear right app assignment and reset position
    func clearRightApp() {
        rightAppBundleID = nil
        position = 0.0
    }
    
    /// Get display name for left app
    func leftAppName(from engine: AudioEngine) -> String? {
        guard let bundleID = leftAppBundleID else { return nil }
        return engine.channels.first(where: { $0.identifier == bundleID })?.name
    }
    
    /// Get display name for right app
    func rightAppName(from engine: AudioEngine) -> String? {
        guard let bundleID = rightAppBundleID else { return nil }
        return engine.channels.first(where: { $0.identifier == bundleID })?.name
    }
}

//
//  AudioChannel.swift
//  Manatee
//
//  Represents a single audio channel (application, device, or bus)
//

import Foundation
import SwiftUI
import Combine

/// Represents the type of audio channel
enum ChannelType: String, Codable, CaseIterable {
    case application    // Per-app audio
    case inputDevice    // Physical input device
    case outputDevice   // Physical output device
    case master         // Master output
    case bus            // Submix bus
}

/// Represents a routing destination for inter-app audio routing
struct AudioRoutingDestination: Identifiable, Hashable {
    let id: UUID
    let channelId: UUID           // Target channel ID
    let channelName: String       // Display name of target
    let inputChannel: Int         // Which input channel (0 = L/1, 1 = R/2, etc)
    var isEnabled: Bool           // Is this route active
    
    init(channelId: UUID, channelName: String, inputChannel: Int, isEnabled: Bool = false) {
        self.id = UUID()
        self.channelId = channelId
        self.channelName = channelName
        self.inputChannel = inputChannel
        self.isEnabled = isEnabled
    }
}

/// Represents output routing configuration for a channel
class AudioRouting: ObservableObject {
    /// Send to master output (always true by default)
    @Published var sendToMaster: Bool = true
    
    /// Routing destinations to other apps' inputs
    /// Key: target channel ID, Value: array of input channel routes (L=0, R=1)
    @Published var appRoutes: [UUID: [Int: Bool]] = [:]  // [targetChannelID: [inputChannel: enabled]]
    
    /// Check if this channel routes to a specific target
    func isRoutedTo(channelId: UUID, inputChannel: Int = 0) -> Bool {
        return appRoutes[channelId]?[inputChannel] ?? false
    }
    
    /// Set routing to a specific target
    func setRoute(to channelId: UUID, inputChannel: Int, enabled: Bool) {
        if appRoutes[channelId] == nil {
            appRoutes[channelId] = [:]
        }
        appRoutes[channelId]?[inputChannel] = enabled
    }
    
    /// Get all active routes
    var activeRoutes: [(channelId: UUID, inputChannel: Int)] {
        var routes: [(UUID, Int)] = []
        for (channelId, inputs) in appRoutes {
            for (input, enabled) in inputs where enabled {
                routes.append((channelId, input))
            }
        }
        return routes
    }
    
    /// Clear all routes to a specific channel
    func clearRoutesTo(channelId: UUID) {
        appRoutes.removeValue(forKey: channelId)
    }
}

/// Represents a single audio channel with volume, mute, pan, and routing
@MainActor
final class AudioChannel: ObservableObject, Identifiable {
    
    // MARK: - Identity
    
    let id: UUID
    let channelType: ChannelType
    
    /// Bundle ID for apps, device UID for devices
    let identifier: String
    
    /// Display name
    @Published var name: String
    
    /// Application or device icon
    @Published var icon: NSImage?
    
    // MARK: - Audio Controls
    
    /// Volume level (0.0 to 1.0 for normal, up to 1.5 for boost)
    @Published var volume: Float = 1.0 {
        didSet {
            volumeDB = Self.linearToDecibels(volume)
            onVolumeChanged?(volume)
        }
    }
    
    /// Volume in decibels (-∞ to +12dB)
    @Published private(set) var volumeDB: Float = 0.0
    
    /// Mute state
    @Published var isMuted: Bool = false {
        didSet {
            onMuteChanged?(isMuted)
        }
    }
    
    /// Solo state (mutes all other non-soloed channels)
    @Published var isSoloed: Bool = false {
        didSet {
            onSoloChanged?(isSoloed)
        }
    }
    
    /// Pan position (-1.0 = left, 0.0 = center, 1.0 = right)
    @Published var pan: Float = 0.0 {
        didSet {
            onPanChanged?(pan)
        }
    }
    
    /// Trim/gain adjustment in dB (-12 to +12)
    @Published var trimDB: Float = 0.0 {
        didSet {
            onTrimChanged?(trimDB)
        }
    }
    
    // MARK: - Per-Channel EQ (-12 to +12 dB)
    
    /// Low band EQ gain (250 Hz shelf)
    @Published var eqLowGain: Float = 0.0 {
        didSet { onEQChanged?(eqLowGain, eqMidGain, eqHighGain) }
    }
    
    /// Mid band EQ gain (1 kHz peak)
    @Published var eqMidGain: Float = 0.0 {
        didSet { onEQChanged?(eqLowGain, eqMidGain, eqHighGain) }
    }
    
    /// High band EQ gain (4 kHz shelf)
    @Published var eqHighGain: Float = 0.0 {
        didSet { onEQChanged?(eqLowGain, eqMidGain, eqHighGain) }
    }
    
    // MARK: - Metering
    
    /// Current peak level for left channel (0.0 to 1.0+)
    @Published var peakLevelLeft: Float = 0.0
    
    /// Current peak level for right channel (0.0 to 1.0+)
    @Published var peakLevelRight: Float = 0.0
    
    /// Is audio currently playing through this channel
    @Published var isActive: Bool = false
    
    // MARK: - Routing
    
    /// Output device UID this channel routes to
    @Published var outputDeviceUID: String?
    
    /// Inter-app audio routing configuration
    @Published var routing: AudioRouting = AudioRouting()
    
    /// Number of input channels this app supports (for apps like Ableton with multiple inputs)
    @Published var inputChannelCount: Int = 2  // Default stereo
    
    /// Number of output channels this app has
    @Published var outputChannelCount: Int = 2  // Default stereo
    
    /// Process ID for this app (if application type)
    @Published var processId: pid_t = 0
    
    // MARK: - Callbacks
    
    var onVolumeChanged: ((Float) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onSoloChanged: ((Bool) -> Void)?
    var onPanChanged: ((Float) -> Void)?
    var onTrimChanged: ((Float) -> Void)?
    var onEQChanged: ((Float, Float, Float) -> Void)?  // (low, mid, high) in dB
    var onRoutingChanged: ((AudioRouting) -> Void)?     // Called when routing changes
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        channelType: ChannelType,
        identifier: String,
        name: String,
        icon: NSImage? = nil,
        processId: pid_t = 0
    ) {
        self.id = id
        self.channelType = channelType
        self.identifier = identifier
        self.name = name
        self.icon = icon
        self.processId = processId
    }
    
    // MARK: - Convenience Initializers
    
    /// Create channel for a running application
    static func forApplication(_ app: NSRunningApplication) -> AudioChannel {
        let channel = AudioChannel(
            channelType: .application,
            identifier: app.bundleIdentifier ?? app.processIdentifier.description,
            name: app.localizedName ?? "Unknown App",
            icon: app.icon,
            processId: app.processIdentifier
        )
        return channel
    }
    
    /// Create master channel
    static func master() -> AudioChannel {
        let channel = AudioChannel(
            channelType: .master,
            identifier: "master",
            name: "Master",
            icon: NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Master")
        )
        return channel
    }
    
    // MARK: - Utility
    
    /// Convert linear volume (0-1+) to decibels
    static func linearToDecibels(_ linear: Float) -> Float {
        if linear <= 0.0001 {
            return -.infinity
        }
        return 20.0 * log10(linear)
    }
    
    /// Convert decibels to linear volume
    static func decibelsToLinear(_ db: Float) -> Float {
        if db <= -80 {
            return 0
        }
        return pow(10, db / 20.0)
    }
    
    /// Format volume as dB string
    var volumeDBFormatted: String {
        if volumeDB <= -60 {
            return "-∞ dB"
        }
        return String(format: "%.1f dB", volumeDB)
    }
}

// MARK: - Hashable

extension AudioChannel: Hashable {
    nonisolated static func == (lhs: AudioChannel, rhs: AudioChannel) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

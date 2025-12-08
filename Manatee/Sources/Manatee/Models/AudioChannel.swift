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
    
    // MARK: - Callbacks
    
    var onVolumeChanged: ((Float) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onSoloChanged: ((Bool) -> Void)?
    var onPanChanged: ((Float) -> Void)?
    var onTrimChanged: ((Float) -> Void)?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        channelType: ChannelType,
        identifier: String,
        name: String,
        icon: NSImage? = nil
    ) {
        self.id = id
        self.channelType = channelType
        self.identifier = identifier
        self.name = name
        self.icon = icon
    }
    
    // MARK: - Convenience Initializers
    
    /// Create channel for a running application
    static func forApplication(_ app: NSRunningApplication) -> AudioChannel {
        let channel = AudioChannel(
            channelType: .application,
            identifier: app.bundleIdentifier ?? app.processIdentifier.description,
            name: app.localizedName ?? "Unknown App",
            icon: app.icon
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

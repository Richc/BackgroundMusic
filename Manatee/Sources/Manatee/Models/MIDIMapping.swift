//
//  MIDIMapping.swift
//  Manatee
//
//  MIDI controller mapping configuration
//

import Foundation

/// Type of MIDI message
enum MIDIMessageType: String, Codable, CaseIterable {
    case controlChange = "CC"
    case noteOn = "Note On"
    case noteOff = "Note Off"
    case programChange = "PC"
    case pitchBend = "Pitch Bend"
    case nrpn = "NRPN"
    case aftertouch = "Aftertouch"
}

/// Behavior of the MIDI mapping
enum MappingBehavior: String, Codable, CaseIterable {
    case absolute       // Value directly maps to control (e.g., fader)
    case relative       // Value is offset (+/- from current)
    case toggle         // Any value toggles state
    case momentary      // Active while held
    case increment      // Each message increments value
    case decrement      // Each message decrements value
}

/// Target control that MIDI message affects
enum ControlTarget: Codable, Hashable {
    case appVolume(bundleID: String)
    case appMute(bundleID: String)
    case appPan(bundleID: String)
    case appSolo(bundleID: String)
    case deviceVolume(deviceUID: String)
    case deviceMute(deviceUID: String)
    case masterVolume
    case masterMute
    case eqLow
    case eqMid
    case eqHigh
    case sceneRecall(index: Int)
    case presetRecall(name: String)
    case bankNext
    case bankPrevious
    case custom(action: String)
    
    var displayName: String {
        switch self {
        case .appVolume(let id): return "App Volume: \(id)"
        case .appMute(let id): return "App Mute: \(id)"
        case .appPan(let id): return "App Pan: \(id)"
        case .appSolo(let id): return "App Solo: \(id)"
        case .deviceVolume(let uid): return "Device Volume: \(uid)"
        case .deviceMute(let uid): return "Device Mute: \(uid)"
        case .masterVolume: return "Master Volume"
        case .masterMute: return "Master Mute"
        case .eqLow: return "EQ Low"
        case .eqMid: return "EQ Mid"
        case .eqHigh: return "EQ High"
        case .sceneRecall(let index): return "Scene \(index)"
        case .presetRecall(let name): return "Preset: \(name)"
        case .bankNext: return "Bank Next"
        case .bankPrevious: return "Bank Previous"
        case .custom(let action): return "Custom: \(action)"
        }
    }
}

/// A MIDI mapping that connects a MIDI message to an audio control
struct MIDIMapping: Identifiable, Codable, Hashable {
    let id: UUID
    
    /// Type of MIDI message to respond to
    let messageType: MIDIMessageType
    
    /// MIDI channel (0-15, or nil for any channel)
    let channel: UInt8?
    
    /// Control number (CC number, note number, etc.)
    let controlNumber: UInt8
    
    /// Target control to affect
    let target: ControlTarget
    
    /// How the MIDI value affects the control
    let behavior: MappingBehavior
    
    /// Input range mapping (min, max MIDI values to respond to)
    let inputRange: ClosedRange<UInt8>
    
    /// Output range mapping (min, max control values)
    let outputRange: ClosedRange<Float>
    
    /// Human-readable name for this mapping
    var name: String
    
    /// Is this mapping enabled
    var isEnabled: Bool
    
    /// Description of the source device
    var sourceDeviceName: String?
    
    init(
        id: UUID = UUID(),
        messageType: MIDIMessageType,
        channel: UInt8? = nil,
        controlNumber: UInt8,
        target: ControlTarget,
        behavior: MappingBehavior = .absolute,
        inputRange: ClosedRange<UInt8> = 0...127,
        outputRange: ClosedRange<Float> = 0...1,
        name: String = "",
        isEnabled: Bool = true,
        sourceDeviceName: String? = nil
    ) {
        self.id = id
        self.messageType = messageType
        self.channel = channel
        self.controlNumber = controlNumber
        self.target = target
        self.behavior = behavior
        self.inputRange = inputRange
        self.outputRange = outputRange
        self.name = name.isEmpty ? target.displayName : name
        self.isEnabled = isEnabled
        self.sourceDeviceName = sourceDeviceName
    }
    
    /// Calculate output value from MIDI input value
    func calculateOutputValue(midiValue: UInt8) -> Float {
        // Clamp input to range
        let clampedInput = max(inputRange.lowerBound, min(inputRange.upperBound, midiValue))
        
        // Normalize to 0-1
        let inputSpan = Float(inputRange.upperBound - inputRange.lowerBound)
        let normalized = inputSpan > 0 ? Float(clampedInput - inputRange.lowerBound) / inputSpan : 0
        
        // Map to output range
        let outputSpan = outputRange.upperBound - outputRange.lowerBound
        return outputRange.lowerBound + (normalized * outputSpan)
    }
}

/// A complete device profile with pre-configured mappings
struct DeviceProfile: Identifiable, Codable {
    let id: UUID
    let name: String
    let manufacturer: String
    let model: String
    let mappings: [MIDIMapping]
    
    /// Feedback capabilities
    let supportsFeedback: Bool
    let feedbackType: FeedbackType?
    
    enum FeedbackType: String, Codable {
        case ledRing
        case motorizedFader
        case buttonLED
        case display
    }
}

// MARK: - Built-in Device Profiles

extension DeviceProfile {
    
    /// Behringer X-Touch Mini profile
    static let xTouchMini = DeviceProfile(
        id: UUID(),
        name: "Behringer X-Touch Mini",
        manufacturer: "Behringer",
        model: "X-Touch Mini",
        mappings: [
            // Rotary encoders 1-8 for volume
            MIDIMapping(messageType: .controlChange, controlNumber: 1, target: .appVolume(bundleID: "slot1"), name: "Encoder 1"),
            MIDIMapping(messageType: .controlChange, controlNumber: 2, target: .appVolume(bundleID: "slot2"), name: "Encoder 2"),
            MIDIMapping(messageType: .controlChange, controlNumber: 3, target: .appVolume(bundleID: "slot3"), name: "Encoder 3"),
            MIDIMapping(messageType: .controlChange, controlNumber: 4, target: .appVolume(bundleID: "slot4"), name: "Encoder 4"),
            MIDIMapping(messageType: .controlChange, controlNumber: 5, target: .appVolume(bundleID: "slot5"), name: "Encoder 5"),
            MIDIMapping(messageType: .controlChange, controlNumber: 6, target: .appVolume(bundleID: "slot6"), name: "Encoder 6"),
            MIDIMapping(messageType: .controlChange, controlNumber: 7, target: .appVolume(bundleID: "slot7"), name: "Encoder 7"),
            MIDIMapping(messageType: .controlChange, controlNumber: 8, target: .masterVolume, name: "Encoder 8 (Master)"),
            // Fader for master
            MIDIMapping(messageType: .controlChange, controlNumber: 9, target: .masterVolume, name: "Fader"),
        ],
        supportsFeedback: true,
        feedbackType: .ledRing
    )
    
    /// Korg nanoKONTROL2 profile
    static let nanoKontrol2 = DeviceProfile(
        id: UUID(),
        name: "Korg nanoKONTROL2",
        manufacturer: "Korg",
        model: "nanoKONTROL2",
        mappings: [
            // Faders 1-8
            MIDIMapping(messageType: .controlChange, controlNumber: 0, target: .appVolume(bundleID: "slot1"), name: "Fader 1"),
            MIDIMapping(messageType: .controlChange, controlNumber: 1, target: .appVolume(bundleID: "slot2"), name: "Fader 2"),
            MIDIMapping(messageType: .controlChange, controlNumber: 2, target: .appVolume(bundleID: "slot3"), name: "Fader 3"),
            MIDIMapping(messageType: .controlChange, controlNumber: 3, target: .appVolume(bundleID: "slot4"), name: "Fader 4"),
            MIDIMapping(messageType: .controlChange, controlNumber: 4, target: .appVolume(bundleID: "slot5"), name: "Fader 5"),
            MIDIMapping(messageType: .controlChange, controlNumber: 5, target: .appVolume(bundleID: "slot6"), name: "Fader 6"),
            MIDIMapping(messageType: .controlChange, controlNumber: 6, target: .appVolume(bundleID: "slot7"), name: "Fader 7"),
            MIDIMapping(messageType: .controlChange, controlNumber: 7, target: .masterVolume, name: "Fader 8 (Master)"),
            // Mute buttons (S buttons)
            MIDIMapping(messageType: .noteOn, controlNumber: 32, target: .appMute(bundleID: "slot1"), behavior: .toggle, name: "Mute 1"),
            MIDIMapping(messageType: .noteOn, controlNumber: 33, target: .appMute(bundleID: "slot2"), behavior: .toggle, name: "Mute 2"),
            MIDIMapping(messageType: .noteOn, controlNumber: 34, target: .appMute(bundleID: "slot3"), behavior: .toggle, name: "Mute 3"),
            MIDIMapping(messageType: .noteOn, controlNumber: 35, target: .appMute(bundleID: "slot4"), behavior: .toggle, name: "Mute 4"),
            MIDIMapping(messageType: .noteOn, controlNumber: 36, target: .appMute(bundleID: "slot5"), behavior: .toggle, name: "Mute 5"),
            MIDIMapping(messageType: .noteOn, controlNumber: 37, target: .appMute(bundleID: "slot6"), behavior: .toggle, name: "Mute 6"),
            MIDIMapping(messageType: .noteOn, controlNumber: 38, target: .appMute(bundleID: "slot7"), behavior: .toggle, name: "Mute 7"),
            MIDIMapping(messageType: .noteOn, controlNumber: 39, target: .masterMute, behavior: .toggle, name: "Mute 8 (Master)"),
        ],
        supportsFeedback: true,
        feedbackType: .buttonLED
    )
}

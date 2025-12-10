//
//  Preset.swift
//  Flo
//
//  Preset and scene management for saving/recalling mixer states
//

import Foundation

/// A snapshot of all channel states
struct ChannelState: Codable {
    let identifier: String
    let channelType: ChannelType
    let volume: Float
    let isMuted: Bool
    let pan: Float
    let trimDB: Float
    let outputDeviceUID: String?
}

/// A complete mixer preset
struct Preset: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var channelStates: [ChannelState]
    var midiMappings: [MIDIMapping]
    var createdAt: Date
    var modifiedAt: Date
    
    /// Is this a factory preset (read-only)
    var isFactory: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        channelStates: [ChannelState] = [],
        midiMappings: [MIDIMapping] = [],
        isFactory: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.channelStates = channelStates
        self.midiMappings = midiMappings
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isFactory = isFactory
    }
}

/// A mixer scene is a lightweight version of a preset for quick switching
/// Note: Named MixerScene to avoid conflict with SwiftUI.Scene protocol
struct MixerScene: Identifiable, Codable {
    let id: UUID
    var name: String
    var index: Int
    var channelStates: [ChannelState]
    
    /// Color for visual identification
    var colorHex: String
    
    init(
        id: UUID = UUID(),
        name: String,
        index: Int,
        channelStates: [ChannelState] = [],
        colorHex: String = "#007AFF"
    ) {
        self.id = id
        self.name = name
        self.index = index
        self.channelStates = channelStates
        self.colorHex = colorHex
    }
}

// MARK: - Preset Storage

@MainActor
final class PresetStore: ObservableObject {
    
    @Published var presets: [Preset] = []
    @Published var scenes: [MixerScene] = []
    @Published var currentPreset: Preset?
    @Published var currentScene: MixerScene?
    
    private let presetsURL: URL
    private let scenesURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let floDir = appSupport.appendingPathComponent("Flo", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: floDir, withIntermediateDirectories: true)
        
        presetsURL = floDir.appendingPathComponent("presets.json")
        scenesURL = floDir.appendingPathComponent("scenes.json")
        
        loadPresets()
        loadScenes()
        
        // Add factory presets if empty
        if presets.isEmpty {
            addFactoryPresets()
        }
    }
    
    // MARK: - Presets
    
    func savePreset(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            var updated = preset
            updated.modifiedAt = Date()
            presets[index] = updated
        } else {
            presets.append(preset)
        }
        persistPresets()
    }
    
    func deletePreset(_ preset: Preset) {
        guard !preset.isFactory else { return }
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }
    
    func recallPreset(_ preset: Preset, to audioEngine: AudioEngine) async {
        currentPreset = preset
        
        for state in preset.channelStates {
            if let channel = audioEngine.channels.first(where: { $0.identifier == state.identifier }) {
                channel.volume = state.volume
                channel.isMuted = state.isMuted
                channel.pan = state.pan
                channel.trimDB = state.trimDB
                channel.outputDeviceUID = state.outputDeviceUID
            }
        }
    }
    
    // MARK: - Scenes
    
    func saveScene(_ scene: MixerScene) {
        print("💾 PresetStore.saveScene: Saving '\(scene.name)' with \(scene.channelStates.count) channel states")
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[index] = scene
            print("💾 Updated existing scene at index \(index)")
        } else {
            scenes.append(scene)
            print("💾 Added new scene, total scenes: \(scenes.count)")
        }
        persistScenes()
    }
    
    func deleteScene(_ scene: MixerScene) {
        scenes.removeAll { $0.id == scene.id }
        persistScenes()
    }
    
    func recallScene(_ scene: MixerScene, to audioEngine: AudioEngine) async {
        currentScene = scene
        
        for state in scene.channelStates {
            if let channel = audioEngine.channels.first(where: { $0.identifier == state.identifier }) {
                channel.volume = state.volume
                channel.isMuted = state.isMuted
                channel.pan = state.pan
            }
        }
    }
    
    // MARK: - Capture Current State
    
    func captureCurrentState(from audioEngine: AudioEngine) -> [ChannelState] {
        audioEngine.channels.map { channel in
            ChannelState(
                identifier: channel.identifier,
                channelType: channel.channelType,
                volume: channel.volume,
                isMuted: channel.isMuted,
                pan: channel.pan,
                trimDB: channel.trimDB,
                outputDeviceUID: channel.outputDeviceUID
            )
        }
    }
    
    // MARK: - Persistence
    
    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: presetsURL)
            presets = try JSONDecoder().decode([Preset].self, from: data)
        } catch {
            print("Failed to load presets: \(error)")
        }
    }
    
    private func persistPresets() {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: presetsURL)
        } catch {
            print("Failed to save presets: \(error)")
        }
    }
    
    private func loadScenes() {
        guard FileManager.default.fileExists(atPath: scenesURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: scenesURL)
            scenes = try JSONDecoder().decode([MixerScene].self, from: data)
        } catch {
            print("Failed to load scenes: \(error)")
        }
    }
    
    private func persistScenes() {
        do {
            let data = try JSONEncoder().encode(scenes)
            try data.write(to: scenesURL)
            print("💾 PresetStore.persistScenes: Saved \(scenes.count) scenes to \(scenesURL.path)")
        } catch {
            print("❌ Failed to save scenes: \(error)")
        }
    }
    
    // MARK: - Factory Presets
    
    private func addFactoryPresets() {
        let defaultPreset = Preset(
            name: "Default",
            description: "Default mixer configuration with all volumes at unity",
            isFactory: true
        )
        
        let lowBackgroundPreset = Preset(
            name: "Low Background Apps",
            description: "Reduces background app volumes while keeping focus app at full volume",
            isFactory: true
        )
        
        presets = [defaultPreset, lowBackgroundPreset]
        persistPresets()
    }
}

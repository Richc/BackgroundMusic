//
//  MIDIService.swift
//  Flo
//
//  MIDI device management and message handling using MIDIKit
//

import Foundation
import Combine
import MIDIKit

/// Service for handling MIDI input/output and device management
@MainActor
final class MIDIService: ObservableObject {
    
    // MARK: - Published State
    
    /// Connected MIDI input devices
    @Published var inputDevices: [MIDIInputEndpoint] = []
    
    /// Connected MIDI output devices
    @Published var outputDevices: [MIDIOutputEndpoint] = []
    
    /// Current MIDI mappings
    @Published var mappings: [MIDIMapping] = []
    
    /// Is MIDI Learn mode active
    @Published var isLearning: Bool = false
    
    /// Control currently being learned
    @Published var learningTarget: ControlTarget?
    
    /// Last received MIDI message (for display/debugging)
    @Published var lastReceivedMessage: String = ""
    
    /// Is the MIDI service running
    @Published var isRunning: Bool = false
    
    // MARK: - Private
    
    private var midiManager: MIDIManager?
    private var inputConnection: MIDIInputConnection?
    
    /// Callback when a control value changes
    var onControlChange: ((ControlTarget, Float) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        loadMappings()
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        print("🎹 MIDIService starting...")
        
        do {
            let manager = MIDIManager(
                clientName: "Flo",
                model: "Flo Audio Controller",
                manufacturer: "Flo"
            )
            
            try manager.start()
            midiManager = manager
            
            // Set up input connection to receive from all devices
            try manager.addInputConnection(
                to: .allOutputs,
                tag: "Flo-Input",
                receiver: .events { [weak self] events, timeStamp, source in
                    Task { @MainActor in
                        for event in events {
                            self?.handleMIDIEvent(event, from: source)
                        }
                    }
                }
            )
            
            inputConnection = manager.managedInputConnections["Flo-Input"]
            
            // Refresh device lists
            refreshDevices()
            
            // Listen for device changes
            // MIDIKit automatically updates when devices connect/disconnect
            
            isRunning = true
            print("✅ MIDIService started with \(inputDevices.count) inputs, \(outputDevices.count) outputs")
            
        } catch {
            print("❌ Failed to start MIDI: \(error)")
        }
    }
    
    func stop() async {
        print("🎹 MIDIService stopping...")
        
        isRunning = false
        isLearning = false
        learningTarget = nil
        
        midiManager = nil
        inputConnection = nil
        
        print("✅ MIDIService stopped")
    }
    
    // MARK: - Device Management
    
    func refreshDevices() {
        guard let manager = midiManager else { return }
        
        inputDevices = manager.endpoints.inputs
        outputDevices = manager.endpoints.outputs
    }
    
    // MARK: - MIDI Learn
    
    func startLearning(for target: ControlTarget) {
        isLearning = true
        learningTarget = target
        print("🎹 MIDI Learn started for: \(target.displayName)")
    }
    
    func cancelLearning() {
        isLearning = false
        learningTarget = nil
        print("🎹 MIDI Learn cancelled")
    }
    
    private func completeLearning(with event: MIDIEvent, from source: MIDIOutputEndpoint?) {
        guard let target = learningTarget else { return }
        
        var mapping: MIDIMapping?
        
        switch event {
        case .cc(let cc):
            mapping = MIDIMapping(
                messageType: .controlChange,
                channel: cc.channel.uInt8Value,
                controlNumber: cc.controller.number.uInt8Value,
                target: target,
                behavior: .absolute,
                name: target.displayName,
                sourceDeviceName: source?.displayName
            )
            
        case .noteOn(let note):
            mapping = MIDIMapping(
                messageType: .noteOn,
                channel: note.channel.uInt8Value,
                controlNumber: note.note.number.uInt8Value,
                target: target,
                behavior: .toggle,
                name: target.displayName,
                sourceDeviceName: source?.displayName
            )
            
        case .pitchBend(let pb):
            mapping = MIDIMapping(
                messageType: .pitchBend,
                channel: pb.channel.uInt8Value,
                controlNumber: 0,
                target: target,
                behavior: .absolute,
                outputRange: 0...1,
                name: target.displayName,
                sourceDeviceName: source?.displayName
            )
            
        default:
            break
        }
        
        if let mapping = mapping {
            // Remove existing mapping for this target
            mappings.removeAll { $0.target == target }
            
            // Add new mapping
            mappings.append(mapping)
            saveMappings()
            
            print("✅ MIDI Learn complete: \(mapping.name)")
        }
        
        isLearning = false
        learningTarget = nil
    }
    
    // MARK: - Event Handling
    
    private func handleMIDIEvent(_ event: MIDIEvent, from source: MIDIOutputEndpoint?) {
        // Update last message display
        updateLastMessage(event, from: source)
        
        // Check if we're in learn mode
        if isLearning {
            completeLearning(with: event, from: source)
            return
        }
        
        // Process through mappings
        processEventWithMappings(event)
    }
    
    private func processEventWithMappings(_ event: MIDIEvent) {
        for mapping in mappings where mapping.isEnabled {
            var matched = false
            var value: Float = 0
            
            switch (mapping.messageType, event) {
            case (.controlChange, .cc(let cc)):
                if cc.controller.number.uInt8Value == mapping.controlNumber {
                    if mapping.channel == nil || mapping.channel == cc.channel.uInt8Value {
                        matched = true
                        value = mapping.calculateOutputValue(midiValue: cc.value.midi1Value.uInt8Value)
                    }
                }
                
            case (.noteOn, .noteOn(let note)):
                if note.note.number.uInt8Value == mapping.controlNumber {
                    if mapping.channel == nil || mapping.channel == note.channel.uInt8Value {
                        matched = true
                        value = mapping.behavior == .toggle ? 1.0 : 
                                mapping.calculateOutputValue(midiValue: note.velocity.midi1Value.uInt8Value)
                    }
                }
                
            case (.noteOff, .noteOff(let note)):
                if note.note.number.uInt8Value == mapping.controlNumber {
                    if mapping.channel == nil || mapping.channel == note.channel.uInt8Value {
                        matched = true
                        value = 0
                    }
                }
                
            case (.pitchBend, .pitchBend(let pb)):
                if mapping.channel == nil || mapping.channel == pb.channel.uInt8Value {
                    matched = true
                    // Pitch bend is 14-bit, convert to 0-1
                    value = Float(pb.value.bipolarUnitIntervalValue + 1.0) / 2.0
                }
                
            default:
                break
            }
            
            if matched {
                applyMapping(mapping, value: value)
            }
        }
    }
    
    private func applyMapping(_ mapping: MIDIMapping, value: Float) {
        switch mapping.behavior {
        case .absolute:
            onControlChange?(mapping.target, value)
            
        case .toggle:
            // Toggle is handled by the target itself
            onControlChange?(mapping.target, value)
            
        case .momentary:
            onControlChange?(mapping.target, value > 0.5 ? 1 : 0)
            
        default:
            onControlChange?(mapping.target, value)
        }
    }
    
    private func updateLastMessage(_ event: MIDIEvent, from source: MIDIOutputEndpoint?) {
        let sourceName = source?.displayName ?? "Unknown"
        
        switch event {
        case .cc(let cc):
            lastReceivedMessage = "CC\(cc.controller.number) = \(cc.value.midi1Value) [Ch \(cc.channel.uInt8Value + 1)] from \(sourceName)"
        case .noteOn(let note):
            lastReceivedMessage = "Note On \(note.note.number) vel=\(note.velocity.midi1Value) [Ch \(note.channel.uInt8Value + 1)] from \(sourceName)"
        case .noteOff(let note):
            lastReceivedMessage = "Note Off \(note.note.number) [Ch \(note.channel.uInt8Value + 1)] from \(sourceName)"
        case .pitchBend(let pb):
            lastReceivedMessage = "Pitch Bend \(pb.value.midi1Value) [Ch \(pb.channel.uInt8Value + 1)] from \(sourceName)"
        default:
            break
        }
    }
    
    // MARK: - MIDI Output / Feedback
    
    func sendFeedback(for target: ControlTarget, value: Float) {
        guard let manager = midiManager else { return }
        
        // Find mapping for this target
        guard let mapping = mappings.first(where: { $0.target == target }),
              let sourceName = mapping.sourceDeviceName,
              let output = outputDevices.first(where: { $0.displayName == sourceName }) else {
            return
        }
        
        // TODO: Send MIDI feedback based on mapping type
        // This would send LED ring updates, etc. back to the controller
    }
    
    // MARK: - Mapping Management
    
    func addMapping(_ mapping: MIDIMapping) {
        mappings.append(mapping)
        saveMappings()
    }
    
    func removeMapping(_ mapping: MIDIMapping) {
        mappings.removeAll { $0.id == mapping.id }
        saveMappings()
    }
    
    func updateMapping(_ mapping: MIDIMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
            saveMappings()
        }
    }
    
    // MARK: - Persistence
    
    private func loadMappings() {
        let url = mappingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            mappings = try JSONDecoder().decode([MIDIMapping].self, from: data)
            print("📂 Loaded \(mappings.count) MIDI mappings")
        } catch {
            print("❌ Failed to load MIDI mappings: \(error)")
        }
    }
    
    private func saveMappings() {
        do {
            let data = try JSONEncoder().encode(mappings)
            try data.write(to: mappingsURL)
            print("💾 Saved \(mappings.count) MIDI mappings")
        } catch {
            print("❌ Failed to save MIDI mappings: \(error)")
        }
    }
    
    private var mappingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Flo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("midi-mappings.json")
    }
    
    // MARK: - Device Profiles
    
    func applyDeviceProfile(_ profile: DeviceProfile) {
        // Remove mappings from this device
        mappings.removeAll { $0.sourceDeviceName == profile.name }
        
        // Add profile mappings
        var newMappings = profile.mappings
        for i in newMappings.indices {
            newMappings[i].sourceDeviceName = profile.name
        }
        mappings.append(contentsOf: newMappings)
        
        saveMappings()
        print("📋 Applied device profile: \(profile.name)")
    }
}

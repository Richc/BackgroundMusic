//
//  ManateeTests.swift
//  ManateeTests
//
//  Unit tests for Manatee audio control application
//

import XCTest
@testable import Manatee

final class ManateeTests: XCTestCase {
    
    // MARK: - AudioChannel Tests
    
    func testAudioChannelDefaultValues() {
        let channel = AudioChannel(
            name: "Test App",
            bundleIdentifier: "com.test.app",
            channelType: .application
        )
        
        XCTAssertEqual(channel.name, "Test App")
        XCTAssertEqual(channel.bundleIdentifier, "com.test.app")
        XCTAssertEqual(channel.channelType, .application)
        XCTAssertEqual(channel.volume, 1.0)
        XCTAssertFalse(channel.isMuted)
        XCTAssertFalse(channel.isSoloed)
        XCTAssertEqual(channel.pan, 0.0)
    }
    
    func testAudioChannelVolumeClamp() {
        let channel = AudioChannel(
            name: "Test",
            bundleIdentifier: "com.test",
            channelType: .application
        )
        
        // Test upper bound
        channel.volume = 2.0
        XCTAssertEqual(channel.volume, 1.5) // Max is 1.5 (+3dB)
        
        // Test lower bound
        channel.volume = -0.5
        XCTAssertEqual(channel.volume, 0.0)
    }
    
    func testLinearToDecibelsConversion() {
        let channel = AudioChannel(
            name: "Test",
            bundleIdentifier: "com.test",
            channelType: .application
        )
        
        // Unity gain should be ~0 dB
        channel.volume = 1.0
        XCTAssertEqual(channel.volumeDB, 0.0, accuracy: 0.1)
        
        // -6 dB should be ~0.5 linear
        channel.volume = 0.5
        XCTAssertEqual(channel.volumeDB, -6.0, accuracy: 0.5)
    }
    
    // MARK: - MIDIMapping Tests
    
    func testMIDIMappingCreation() {
        let mapping = MIDIMapping(
            channel: 1,
            controlNumber: 7,
            messageType: .controlChange,
            target: .volume(channelIndex: 0),
            behavior: .absolute
        )
        
        XCTAssertEqual(mapping.channel, 1)
        XCTAssertEqual(mapping.controlNumber, 7)
        XCTAssertEqual(mapping.messageType, .controlChange)
    }
    
    func testMIDIValueToFloat() {
        let mapping = MIDIMapping(
            channel: 1,
            controlNumber: 1,
            messageType: .controlChange,
            target: .volume(channelIndex: 0),
            behavior: .absolute
        )
        
        // 0 -> 0.0
        XCTAssertEqual(mapping.valueToFloat(0), 0.0)
        
        // 127 -> 1.0
        XCTAssertEqual(mapping.valueToFloat(127), 1.0)
        
        // 64 -> ~0.5
        XCTAssertEqual(mapping.valueToFloat(64), 64.0/127.0, accuracy: 0.01)
    }
    
    // MARK: - Preset Tests
    
    func testPresetSerialization() throws {
        let channelState = ChannelState(
            channelID: UUID(),
            volume: 0.8,
            isMuted: false,
            isSoloed: true,
            pan: -0.5
        )
        
        let preset = Preset(
            name: "Test Preset",
            channelStates: [channelState]
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(preset)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Preset.self, from: data)
        
        XCTAssertEqual(decoded.name, "Test Preset")
        XCTAssertEqual(decoded.channelStates.count, 1)
        XCTAssertEqual(decoded.channelStates[0].volume, 0.8)
    }
    
    // MARK: - AudioDevice Tests
    
    func testAudioDeviceEquality() {
        let device1 = AudioDevice(
            id: 123,
            uid: "device-uid-1",
            name: "Built-in Output",
            isInput: false,
            isOutput: true,
            channelCount: 2,
            sampleRate: 48000
        )
        
        let device2 = AudioDevice(
            id: 123,
            uid: "device-uid-1",
            name: "Built-in Output",
            isInput: false,
            isOutput: true,
            channelCount: 2,
            sampleRate: 48000
        )
        
        XCTAssertEqual(device1.id, device2.id)
        XCTAssertEqual(device1.uid, device2.uid)
    }
}

// MARK: - Mock Objects

class MockAudioEngine: AudioEngine {
    var mockChannels: [AudioChannel] = []
    
    override var channels: [AudioChannel] {
        get { mockChannels }
        set { mockChannels = newValue }
    }
}

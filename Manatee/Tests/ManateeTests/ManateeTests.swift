//
//  ManateeTests.swift
//  ManateeTests
//
//  Unit tests for Manatee audio control application
//

import XCTest
@testable import Manatee

@MainActor
final class ManateeTests: XCTestCase {
    
    // MARK: - AudioChannel Tests
    
    func testAudioChannelDefaultValues() {
        let channel = AudioChannel(
            channelType: .application,
            identifier: "com.test.app",
            name: "Test App"
        )
        
        XCTAssertEqual(channel.name, "Test App")
        XCTAssertEqual(channel.identifier, "com.test.app")
        XCTAssertEqual(channel.channelType, .application)
        XCTAssertEqual(channel.volume, 1.0)
        XCTAssertFalse(channel.isMuted)
        XCTAssertFalse(channel.isSoloed)
        XCTAssertEqual(channel.pan, 0.0)
    }
    
    func testAudioChannelVolumeDB() {
        let channel = AudioChannel(
            channelType: .application,
            identifier: "com.test",
            name: "Test"
        )
        
        // Unity gain should be ~0 dB
        channel.volume = 1.0
        XCTAssertEqual(channel.volumeDB, 0.0, accuracy: 0.1)
        
        // -6 dB should be ~0.5 linear
        channel.volume = 0.5
        XCTAssertEqual(channel.volumeDB, -6.0, accuracy: 0.5)
    }
    
    func testLinearToDecibelsConversion() {
        // Unity gain
        XCTAssertEqual(AudioChannel.linearToDecibels(1.0), 0.0, accuracy: 0.001)
        
        // Half volume ~= -6dB
        XCTAssertEqual(AudioChannel.linearToDecibels(0.5), -6.02, accuracy: 0.1)
        
        // Double volume ~= +6dB
        XCTAssertEqual(AudioChannel.linearToDecibels(2.0), 6.02, accuracy: 0.1)
        
        // Zero should be -infinity
        XCTAssertTrue(AudioChannel.linearToDecibels(0.0).isInfinite)
    }
    
    func testDecibelsToLinearConversion() {
        // 0 dB = unity
        XCTAssertEqual(AudioChannel.decibelsToLinear(0.0), 1.0, accuracy: 0.001)
        
        // -6 dB ~= 0.5
        XCTAssertEqual(AudioChannel.decibelsToLinear(-6.02), 0.5, accuracy: 0.01)
        
        // +6 dB ~= 2.0
        XCTAssertEqual(AudioChannel.decibelsToLinear(6.02), 2.0, accuracy: 0.01)
    }
    
    func testMasterChannelCreation() {
        let master = AudioChannel.master()
        
        XCTAssertEqual(master.channelType, .master)
        XCTAssertEqual(master.identifier, "master")
        XCTAssertEqual(master.name, "Master")
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
    
    // MARK: - ChannelState Tests
    
    func testChannelStateSerialization() throws {
        let channelState = ChannelState(
            identifier: "com.test.app",
            channelType: .application,
            volume: 0.8,
            isMuted: false,
            pan: -0.5,
            trimDB: 3.0,
            outputDeviceUID: nil
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(channelState)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ChannelState.self, from: data)
        
        XCTAssertEqual(decoded.identifier, "com.test.app")
        XCTAssertEqual(decoded.volume, 0.8)
        XCTAssertEqual(decoded.pan, -0.5)
    }
    
    // MARK: - Preset Tests
    
    func testPresetSerialization() throws {
        let channelState = ChannelState(
            identifier: "com.test.app",
            channelType: .application,
            volume: 0.8,
            isMuted: false,
            pan: -0.5,
            trimDB: 0.0,
            outputDeviceUID: nil
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
    
    // MARK: - MixerScene Tests
    
    func testMixerSceneSerialization() throws {
        let scene = MixerScene(
            name: "Test Scene",
            index: 0,
            channelStates: [],
            colorHex: "#FF0000"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(scene)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MixerScene.self, from: data)
        
        XCTAssertEqual(decoded.name, "Test Scene")
        XCTAssertEqual(decoded.colorHex, "#FF0000")
    }
}

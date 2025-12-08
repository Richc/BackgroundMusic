//
//  AudioDevice.swift
//  Manatee
//
//  Represents a physical or virtual audio device
//

import Foundation
import CoreAudio

/// Direction of audio device
enum AudioDeviceDirection: String, Codable {
    case input
    case output
}

/// Represents a CoreAudio device
struct AudioDevice: Identifiable, Hashable {
    
    /// CoreAudio device ID
    let audioObjectID: AudioObjectID
    
    /// Unique identifier string
    let uid: String
    
    /// Display name
    let name: String
    
    /// Manufacturer
    let manufacturer: String
    
    /// Device direction
    let direction: AudioDeviceDirection
    
    /// Number of input channels
    let inputChannelCount: Int
    
    /// Number of output channels
    let outputChannelCount: Int
    
    /// Sample rate
    var sampleRate: Double
    
    /// Is this the current default device
    var isDefault: Bool
    
    /// Is this a virtual device (like Manatee's virtual device)
    let isVirtual: Bool
    
    // MARK: - Identifiable
    
    var id: String { uid }
    
    // MARK: - Convenience
    
    /// Check if this is the Manatee virtual device
    var isManateeDevice: Bool {
        uid.contains("Manatee") || uid.contains("BGM")
    }
}

// MARK: - CoreAudio Helpers

extension AudioDevice {
    
    /// Get a string property from a device
    static func getStringProperty(
        deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return nil }
        
        var cfString: CFString?
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfString)
        guard status == noErr, let string = cfString else { return nil }
        
        return string as String
    }
    
    /// Get all audio devices
    static func getAllDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else { return [] }
        
        let deviceCount = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard status == noErr else { return [] }
        
        // Get default devices
        let defaultOutputID = getDefaultDevice(direction: .output)
        let defaultInputID = getDefaultDevice(direction: .input)
        
        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard let uid = getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let name = getStringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) else {
                return nil
            }
            
            let manufacturer = getStringProperty(
                deviceID: deviceID,
                selector: kAudioObjectPropertyManufacturer
            ) ?? "Unknown"
            
            let inputChannels = getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
            let outputChannels = getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
            
            let direction: AudioDeviceDirection = outputChannels > 0 ? .output : .input
            let isDefault = (direction == .output && deviceID == defaultOutputID) ||
                           (direction == .input && deviceID == defaultInputID)
            
            return AudioDevice(
                audioObjectID: deviceID,
                uid: uid,
                name: name,
                manufacturer: manufacturer,
                direction: direction,
                inputChannelCount: inputChannels,
                outputChannelCount: outputChannels,
                sampleRate: getSampleRate(deviceID: deviceID),
                isDefault: isDefault,
                isVirtual: manufacturer.contains("Background Music") || 
                          manufacturer.contains("Manatee") ||
                          name.contains("Virtual")
            )
        }
    }
    
    /// Get the default device for a direction
    static func getDefaultDevice(direction: AudioDeviceDirection) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: direction == .output ? 
                kAudioHardwarePropertyDefaultOutputDevice : 
                kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        return status == noErr ? deviceID : 0
    }
    
    /// Get channel count for a device
    static func getChannelCount(deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }
        
        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPtr.deallocate() }
        
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPtr)
        guard status == noErr else { return 0 }
        
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    
    /// Get sample rate
    static func getSampleRate(deviceID: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? sampleRate : 44100
    }
}

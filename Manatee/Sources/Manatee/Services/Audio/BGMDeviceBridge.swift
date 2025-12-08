//
//  BGMDeviceBridge.swift
//  Manatee
//
//  Swift bridge to communicate with the BackgroundMusic virtual audio device
//  Uses CoreAudio property APIs to set/get per-app volumes
//

import Foundation
import CoreAudio

/// Custom property selectors for BGMDevice (from BGM_Types.h)
enum BGMDeviceProperty: AudioObjectPropertySelector {
    /// Music player process ID
    case musicPlayerProcessID = 0x6D707069  // 'mppi'
    /// Music player bundle ID
    case musicPlayerBundleID = 0x6D706269   // 'mpbi'
    /// Device audible state
    case deviceAudibleState = 0x64617564    // 'daud'
    /// Is running somewhere other than BGMApp
    case isRunningSomewhereOtherThanBGMApp = 0x72756E6F  // 'runo'
    /// App volumes array
    case appVolumes = 0x61707673            // 'apvs'
    /// Enabled output controls
    case enabledOutputControls = 0x62676374 // 'bgct'
}

/// Volume range constants (from BGM_Types.h)
struct BGMVolumeConstants {
    static let maxRawValue: Int32 = 100
    static let minRawValue: Int32 = 0
    static let minDbValue: Float = -96.0
    static let maxDbValue: Float = 0.0
    
    static let panLeftRawValue: Int32 = -100
    static let panCenterRawValue: Int32 = 0
    static let panRightRawValue: Int32 = 100
}

/// Dictionary keys for app volume data
struct BGMAppVolumeKeys {
    static let relativeVolume = "rvol"
    static let panPosition = "ppos"
    static let processID = "pid"
    static let bundleID = "bid"
}

/// Manatee Device UID constants (must match BGM_Types.h)
struct BGMDeviceUIDs {
    static let main = "ManateeDevice"
    static let uiSounds = "ManateeDevice_UISounds"
    static let nullDevice = "ManateeNullDevice"
}

/// Bridge to communicate with the Manatee virtual audio device
@MainActor
final class BGMDeviceBridge: ObservableObject {
    
    // MARK: - Published State
    
    /// Is the BGM device available
    @Published private(set) var isAvailable: Bool = false
    
    /// BGM device audio object ID
    @Published private(set) var deviceID: AudioObjectID = kAudioObjectUnknown
    
    /// Current app volumes cache
    @Published private(set) var appVolumes: [String: AppVolumeData] = [:]
    
    /// Error message if any
    @Published var errorMessage: String?
    
    // MARK: - Types
    
    struct AppVolumeData {
        var volume: Int32  // 0-100
        var pan: Int32     // -100 to 100
        var processID: pid_t?
        var bundleID: String?
        
        /// Volume as normalized float (0.0 to 1.0)
        var normalizedVolume: Float {
            Float(volume) / Float(BGMVolumeConstants.maxRawValue)
        }
        
        /// Pan as normalized float (-1.0 to 1.0)
        var normalizedPan: Float {
            Float(pan) / Float(BGMVolumeConstants.panRightRawValue)
        }
    }
    
    // MARK: - Private
    
    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    
    // MARK: - Singleton
    
    static let shared = BGMDeviceBridge()
    
    private init() {}
    
    // MARK: - Connection
    
    /// Connect to the BGM device and set it as default output
    func connect() -> Bool {
        print("🔌 BGMDeviceBridge: Connecting to BGM device...")
        
        // Find BGMDevice by UID
        guard let id = findDeviceByUID(BGMDeviceUIDs.main) else {
            errorMessage = "BGMDevice not found. Is the driver installed?"
            print("❌ BGMDeviceBridge: BGMDevice not found")
            return false
        }
        
        deviceID = id
        isAvailable = true
        
        // Set BGMDevice as the default output device so apps route audio through it
        if !setAsDefaultOutputDevice() {
            print("⚠️ BGMDeviceBridge: Could not set BGMDevice as default output")
            // Continue anyway - maybe user wants manual control
        }
        
        // Set up property listener for app volume changes
        setupPropertyListener()
        
        // Load initial app volumes
        refreshAppVolumes()
        
        print("✅ BGMDeviceBridge: Connected to BGMDevice (ID: \(deviceID))")
        return true
    }
    
    /// Disconnect from the BGM device and restore previous default output
    func disconnect() {
        removePropertyListener()
        // Note: We should restore the previous default output device here
        deviceID = kAudioObjectUnknown
        isAvailable = false
        appVolumes = [:]
    }
    
    /// Set BGMDevice as the default audio output device
    func setAsDefaultOutputDevice() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var newDefaultDevice = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &newDefaultDevice
        )
        
        if status == noErr {
            print("✅ BGMDeviceBridge: Set BGMDevice as default output device")
            return true
        } else {
            print("❌ BGMDeviceBridge: Failed to set default output device, status: \(status)")
            return false
        }
    }
    
    /// Get the current default output device
    func getDefaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return status == noErr ? deviceID : nil
    }
    
    // MARK: - App Volume Control
    
    /// Set volume for an app by bundle ID and process ID
    /// - Parameters:
    ///   - volume: Volume 0.0 to 1.0 (1.0 = unity, can go higher for boost)
    ///   - bundleID: App's bundle identifier
    ///   - pid: App's process ID (use -1 if unknown)
    func setVolume(_ volume: Float, forBundleID bundleID: String, pid: pid_t = -1) {
        guard isAvailable else {
            print("⚠️ BGMDeviceBridge: Cannot set volume - not available")
            return
        }
        
        // Convert 0-1 to 0-100 raw value
        let rawVolume = Int32(max(0, min(1, volume)) * Float(BGMVolumeConstants.maxRawValue))
        
        print("🎚️ BGMDeviceBridge.setVolume: \(bundleID) -> \(Int(volume * 100))% (raw: \(rawVolume))")
        
        setAppVolumeProperty(
            volume: rawVolume,
            pan: nil,
            processID: pid,
            bundleID: bundleID
        )
    }
    
    /// Set volume for an app by process ID
    func setVolume(_ volume: Float, forProcessID pid: pid_t) {
        guard isAvailable else { return }
        
        let rawVolume = Int32(max(0, min(1, volume)) * Float(BGMVolumeConstants.maxRawValue))
        
        setAppVolumeProperty(
            volume: rawVolume,
            pan: nil,
            processID: pid,
            bundleID: nil
        )
    }
    
    /// Set pan position for an app
    /// - Parameters:
    ///   - pan: Pan position -1.0 (left) to 1.0 (right)
    ///   - bundleID: App's bundle identifier
    ///   - pid: App's process ID (use -1 if unknown)
    func setPan(_ pan: Float, forBundleID bundleID: String, pid: pid_t = -1) {
        guard isAvailable else {
            print("⚠️ BGMDeviceBridge: Cannot set pan - not available")
            return
        }
        
        let rawPan = Int32(max(-1, min(1, pan)) * Float(BGMVolumeConstants.panRightRawValue))
        
        print("🎚️ BGMDeviceBridge.setPan: \(bundleID) -> \(Int(pan * 100)) (raw: \(rawPan))")
        
        setAppVolumeProperty(
            volume: nil,
            pan: rawPan,
            processID: pid,
            bundleID: bundleID
        )
    }
    
    /// Get current volume for an app
    func getVolume(forBundleID bundleID: String) -> Float? {
        return appVolumes[bundleID]?.normalizedVolume
    }
    
    /// Get current pan for an app
    func getPan(forBundleID bundleID: String) -> Float? {
        return appVolumes[bundleID]?.normalizedPan
    }
    
    /// Refresh app volumes from the device
    func refreshAppVolumes() {
        guard isAvailable else { return }
        
        guard let volumesArray = getAppVolumesProperty() else {
            return
        }
        
        var newVolumes: [String: AppVolumeData] = [:]
        
        for case let volumeDict as [String: Any] in volumesArray {
            let volume = volumeDict[BGMAppVolumeKeys.relativeVolume] as? Int32 ?? Int32(BGMVolumeConstants.maxRawValue)
            let pan = volumeDict[BGMAppVolumeKeys.panPosition] as? Int32 ?? BGMVolumeConstants.panCenterRawValue
            let pid = volumeDict[BGMAppVolumeKeys.processID] as? pid_t
            let bundleID = volumeDict[BGMAppVolumeKeys.bundleID] as? String
            
            let data = AppVolumeData(volume: volume, pan: pan, processID: pid, bundleID: bundleID)
            
            if let bid = bundleID {
                newVolumes[bid] = data
            } else if let p = pid {
                newVolumes["pid:\(p)"] = data
            }
        }
        
        appVolumes = newVolumes
    }
    
    // MARK: - Private - Device Discovery
    
    private func findDeviceByUID(_ uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return nil }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        )
        
        guard status == noErr else { return nil }
        
        // Search for device with matching UID
        for deviceID in devices {
            if let deviceUID = getDeviceUID(deviceID), deviceUID == uid {
                return deviceID
            }
        }
        
        return nil
    }
    
    private func getDeviceUID(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &uid
        )
        
        guard status == noErr, let uidString = uid else { return nil }
        return uidString as String
    }
    
    // MARK: - Private - Property Access
    
    private func getAppVolumesProperty() -> [Any]? {
        var address = AudioObjectPropertyAddress(
            mSelector: BGMDeviceProperty.appVolumes.rawValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        
        guard status == noErr, dataSize > 0 else { return nil }
        
        var cfArray: CFArray?
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfArray)
        
        guard status == noErr, let array = cfArray else { return nil }
        return array as? [Any]
    }
    
    private func setAppVolumeProperty(volume: Int32?, pan: Int32?, processID: pid_t, bundleID: String?) {
        guard deviceID != kAudioObjectUnknown else {
            print("⚠️ BGMDeviceBridge: Cannot set volume - device not connected")
            return
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: BGMDeviceProperty.appVolumes.rawValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Build the dictionary with proper CF types
        // BGMDevice expects both pid and bundleID keys to always be present
        let cfDict = NSMutableDictionary()
        cfDict[BGMAppVolumeKeys.processID] = NSNumber(value: processID)
        cfDict[BGMAppVolumeKeys.bundleID] = (bundleID ?? "") as NSString
        
        if let v = volume {
            cfDict[BGMAppVolumeKeys.relativeVolume] = NSNumber(value: v)
        }
        if let p = pan {
            cfDict[BGMAppVolumeKeys.panPosition] = NSNumber(value: p)
        }
        
        print("🔧 BGMDeviceBridge: Setting property - pid: \(processID), bundleID: \(bundleID ?? "nil"), volume: \(volume ?? -1), pan: \(pan ?? -999)")
        
        // Create CFArray with single dictionary
        let cfArray: CFArray = [cfDict] as CFArray
        
        // Pass the CFArray as a CFTypeRef
        var cfTypeRef: CFTypeRef = cfArray
        let dataSize = UInt32(MemoryLayout<CFTypeRef>.size)
        
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            dataSize,
            &cfTypeRef
        )
        
        if status != noErr {
            print("❌ BGMDeviceBridge: Failed to set app volume, status: \(status) (\(fourCharCodeToString(status)))")
        } else {
            print("✅ BGMDeviceBridge: Successfully set volume for \(bundleID ?? "unknown")")
            // Update local cache
            if let bid = bundleID {
                appVolumes[bid] = AppVolumeData(
                    volume: volume ?? appVolumes[bid]?.volume ?? Int32(BGMVolumeConstants.maxRawValue),
                    pan: pan ?? appVolumes[bid]?.pan ?? BGMVolumeConstants.panCenterRawValue,
                    processID: processID > 0 ? processID : nil,
                    bundleID: bid
                )
            }
            
            // DEBUG: Verify by reading back
            if let bid = bundleID, let volumesArray = getAppVolumesProperty() {
                for case let volumeDict as [String: Any] in volumesArray {
                    if let dictBundleID = volumeDict[BGMAppVolumeKeys.bundleID] as? String,
                       dictBundleID == bid {
                        let readVolume = volumeDict[BGMAppVolumeKeys.relativeVolume] as? Int32 ?? -1
                        print("📖 BGMDeviceBridge: Read back volume for \(bid): \(readVolume)")
                        break
                    }
                }
            }
        }
    }
    
    /// Convert OSStatus to human-readable four-char code
    private func fourCharCodeToString(_ code: OSStatus) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((UInt32(bitPattern: code) >> 24) & 0xFF)!),
            Character(UnicodeScalar((UInt32(bitPattern: code) >> 16) & 0xFF)!),
            Character(UnicodeScalar((UInt32(bitPattern: code) >> 8) & 0xFF)!),
            Character(UnicodeScalar(UInt32(bitPattern: code) & 0xFF)!)
        ]
        return String(chars)
    }
    
    // MARK: - Private - Property Listeners
    
    private func setupPropertyListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: BGMDeviceProperty.appVolumes.rawValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        propertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshAppVolumes()
            }
        }
        
        if let block = propertyListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &address,
                DispatchQueue.main,
                block
            )
        }
    }
    
    private func removePropertyListener() {
        guard deviceID != kAudioObjectUnknown, let block = propertyListenerBlock else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: BGMDeviceProperty.appVolumes.rawValue,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        propertyListenerBlock = nil
    }
}

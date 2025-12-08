//
//  AudioEngine.swift
//  Manatee
//
//  Core audio engine managing devices, channels, and audio routing
//

import Foundation
import CoreAudio
import Combine
import AppKit

/// Main audio engine that manages all audio channels and device communication
@MainActor
final class AudioEngine: ObservableObject {
    
    // MARK: - Published State
    
    /// All audio channels (apps + devices + master)
    @Published var channels: [AudioChannel] = []
    
    /// Available output devices
    @Published var outputDevices: [AudioDevice] = []
    
    /// Available input devices
    @Published var inputDevices: [AudioDevice] = []
    
    /// Currently selected output device
    @Published var selectedOutputDevice: AudioDevice?
    
    /// Currently selected input device  
    @Published var selectedInputDevice: AudioDevice?
    
    /// Master channel
    @Published var masterChannel: AudioChannel?
    
    /// Is the audio engine running
    @Published var isRunning: Bool = false
    
    /// Error message if any
    @Published var errorMessage: String?
    
    /// Is BackgroundMusic driver available
    @Published var isBGMDriverAvailable: Bool = false
    
    // MARK: - Private
    
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var appMonitorTimer: Timer?
    private var meterUpdateTimer: Timer?
    private let bgmBridge = BGMDeviceBridge.shared
    
    // MARK: - Initialization
    
    init() {
        print("🎛️ AudioEngine initializing...")
    }
    
    // MARK: - Lifecycle
    
    func initialize() async {
        print("🎛️ AudioEngine starting initialization...")
        
        // Scan for audio devices FIRST (before changing default output)
        await refreshDevices()
        
        // Debug: Print all output devices and their default status
        print("📻 Output devices found:")
        for device in outputDevices {
            print("   - \(device.name) (ID: \(device.audioObjectID)) default=\(device.isDefault)")
        }
        
        // Remember the current default output device (the real speakers/headphones)
        // If BGMDevice is already default, pick the first non-BGM device
        var realOutputDevice = outputDevices.first { $0.isDefault && !$0.name.contains("Manatee") }
        if realOutputDevice == nil {
            // Fallback: pick the first non-Manatee output device
            realOutputDevice = outputDevices.first { !$0.name.contains("Manatee") }
            print("⚠️ No default non-BGM device, using fallback: \(realOutputDevice?.name ?? "none")")
        }
        
        // Check for BGMDevice driver by attempting to connect
        isBGMDriverAvailable = bgmBridge.connect()
        if isBGMDriverAvailable {
            print("✅ BackgroundMusic driver found")
            
            // Start audio passthrough from BGMDevice to real output
            if let realOutput = realOutputDevice {
                print("🔊 Starting passthrough: BGMDevice (\(bgmBridge.deviceID)) -> \(realOutput.name) (\(realOutput.audioObjectID))")
                let passthroughStarted = AudioPassthrough.shared.start(
                    bgmDevice: bgmBridge.deviceID,
                    outputDevice: realOutput.audioObjectID
                )
                if passthroughStarted {
                    print("✅ Audio passthrough started to \(realOutput.name)")
                } else {
                    print("⚠️ Failed to start audio passthrough")
                    errorMessage = "Failed to start audio passthrough"
                }
            } else {
                print("❌ No real output device found for passthrough!")
            }
        } else {
            print("⚠️ BackgroundMusic driver NOT found - volume control will not work")
            errorMessage = "BackgroundMusic driver not installed. Please install it first."
        }
        
        // Create master channel
        let master = AudioChannel.master()
        masterChannel = master
        channels.append(master)
        
        // Set up device change listener
        setupDeviceListener()
        
        // Start monitoring running applications
        startAppMonitoring()
        
        // Start meter updates
        startMeterUpdates()
        
        // Sync initial volumes from driver
        if isBGMDriverAvailable {
            syncVolumesFromDriver()
        }
        
        isRunning = true
        print("✅ AudioEngine initialized with \(channels.count) channels")
    }
    
    func shutdown() async {
        print("🎛️ AudioEngine shutting down...")
        
        isRunning = false
        
        // Stop audio passthrough
        AudioPassthrough.shared.stop()
        
        // Stop timers
        appMonitorTimer?.invalidate()
        appMonitorTimer = nil
        
        meterUpdateTimer?.invalidate()
        meterUpdateTimer = nil
        
        // Remove device listener
        removeDeviceListener()
        
        channels.removeAll()
        
        print("✅ AudioEngine shutdown complete")
    }
    
    // MARK: - Device Management
    
    func refreshDevices() async {
        let allDevices = AudioDevice.getAllDevices()
        
        outputDevices = allDevices.filter { $0.direction == .output && !$0.isManateeDevice }
        inputDevices = allDevices.filter { $0.direction == .input && !$0.isManateeDevice }
        
        // Update selected devices
        if selectedOutputDevice == nil {
            selectedOutputDevice = outputDevices.first { $0.isDefault }
        }
        if selectedInputDevice == nil {
            selectedInputDevice = inputDevices.first { $0.isDefault }
        }
        
        print("📻 Found \(outputDevices.count) output devices, \(inputDevices.count) input devices")
    }
    
    func selectOutputDevice(_ device: AudioDevice) {
        selectedOutputDevice = device
        print("🔊 Selected output device: \(device.name)")
        
        // TODO: Route audio through this device
    }
    
    func selectInputDevice(_ device: AudioDevice) {
        selectedInputDevice = device
        print("🎤 Selected input device: \(device.name)")
    }
    
    private func setupDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        deviceListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                await self?.refreshDevices()
            }
        }
        
        if let block = deviceListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }
    
    private func removeDeviceListener() {
        guard let block = deviceListenerBlock else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        
        deviceListenerBlock = nil
    }
    
    // MARK: - Application Monitoring
    
    private func startAppMonitoring() {
        // Initial scan
        updateRunningApps()
        
        // Monitor for app changes every 2 seconds
        appMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRunningApps()
            }
        }
    }
    
    private func updateRunningApps() {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications.filter { app in
            // Only include regular applications (not background agents)
            app.activationPolicy == .regular &&
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        
        // Get current app bundle IDs
        let currentAppChannels = channels.filter { $0.channelType == .application }
        let currentBundleIDs = Set(currentAppChannels.map { $0.identifier })
        let runningBundleIDs = Set(runningApps.compactMap { $0.bundleIdentifier })
        
        // Add new apps
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  !currentBundleIDs.contains(bundleID) else { continue }
            
            let channel = AudioChannel.forApplication(app)
            
            // Set up callbacks for volume control via BGMDevice
            channel.onVolumeChanged = { [weak self] volume in
                self?.setAppVolume(bundleID: bundleID, volume: volume)
            }
            channel.onMuteChanged = { [weak self] muted in
                self?.setAppMute(bundleID: bundleID, muted: muted)
            }
            channel.onPanChanged = { [weak self] pan in
                self?.setAppPan(bundleID: bundleID, pan: pan)
            }
            
            // Try to get current volume from driver
            if isBGMDriverAvailable {
                if let driverVolume = bgmBridge.getVolume(forBundleID: bundleID) {
                    channel.volume = driverVolume
                }
                if let driverPan = bgmBridge.getPan(forBundleID: bundleID) {
                    channel.pan = driverPan
                }
            }
            
            channels.append(channel)
            print("➕ Added app channel: \(channel.name)")
        }
        
        // Remove closed apps
        for channel in currentAppChannels {
            if !runningBundleIDs.contains(channel.identifier) {
                channels.removeAll { $0.id == channel.id }
                print("➖ Removed app channel: \(channel.name)")
            }
        }
    }
    
    // MARK: - Meter Updates
    
    private func startMeterUpdates() {
        // Update meters at 30fps
        meterUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeters()
            }
        }
    }
    
    private func updateMeters() {
        // TODO: Get actual audio levels from the driver
        // For now, simulate some activity
        for channel in channels where !channel.isMuted {
            // Decay existing levels
            channel.peakLevelLeft = max(0, channel.peakLevelLeft * 0.9)
            channel.peakLevelRight = max(0, channel.peakLevelRight * 0.9)
            
            // Add some random activity for active channels
            if channel.isActive {
                let noise = Float.random(in: 0...0.3)
                channel.peakLevelLeft = min(1.0, channel.peakLevelLeft + noise * channel.volume)
                channel.peakLevelRight = min(1.0, channel.peakLevelRight + noise * channel.volume)
            }
        }
    }
    
    // MARK: - Volume Control
    
    /// Sync volumes from BGMDevice driver to our channels
    private func syncVolumesFromDriver() {
        guard isBGMDriverAvailable else { return }
        
        // Refresh the bridge's cache
        bgmBridge.refreshAppVolumes()
        
        for channel in channels where channel.channelType == .application {
            if let driverVolume = bgmBridge.getVolume(forBundleID: channel.identifier) {
                channel.volume = driverVolume
            }
            if let driverPan = bgmBridge.getPan(forBundleID: channel.identifier) {
                channel.pan = driverPan
            }
        }
        
        print("📊 Synced app volumes from driver")
    }
    
    func setAppVolume(bundleID: String, pid: pid_t, volume: Float) {
        guard isBGMDriverAvailable else {
            print("⚠️ Cannot set volume - BGMDriver not available")
            return
        }
        
        print("🎚️ AudioEngine.setAppVolume: \(bundleID) (pid: \(pid)) -> \(Int(volume * 100))%")
        bgmBridge.setVolume(volume, forBundleID: bundleID, pid: pid)
    }
    
    func setAppMute(bundleID: String, pid: pid_t, muted: Bool) {
        guard isBGMDriverAvailable else {
            print("⚠️ Cannot set mute - BGMDriver not available")
            return
        }
        
        // Mute is implemented as volume = 0 in BGMDevice
        // Note: We should track the pre-mute volume to restore it, but for now this is simple
        let volume: Float = muted ? 0 : 1.0
        print("🔇 AudioEngine.setAppMute: \(bundleID) (pid: \(pid)) -> \(muted)")
        bgmBridge.setVolume(volume, forBundleID: bundleID, pid: pid)
    }
    
    func setAppPan(bundleID: String, pid: pid_t, pan: Float) {
        guard isBGMDriverAvailable else {
            print("⚠️ Cannot set pan - BGMDriver not available")
            return
        }
        
        print("🎚️ AudioEngine.setAppPan: \(bundleID) (pid: \(pid)) -> \(Int(pan * 100))")
        bgmBridge.setPan(pan, forBundleID: bundleID, pid: pid)
    }
    
    func setAppVolume(bundleID: String, volume: Float) {
        // Get running app with this bundle ID
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            setAppVolume(bundleID: bundleID, pid: app.processIdentifier, volume: volume)
        } else {
            print("⚠️ AudioEngine.setAppVolume: App not found for \(bundleID)")
        }
    }
    
    func setAppMute(bundleID: String, muted: Bool) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            setAppMute(bundleID: bundleID, pid: app.processIdentifier, muted: muted)
        } else {
            print("⚠️ AudioEngine.setAppMute: App not found for \(bundleID)")
        }
    }
    
    func setAppPan(bundleID: String, pan: Float) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            setAppPan(bundleID: bundleID, pid: app.processIdentifier, pan: pan)
        } else {
            print("⚠️ AudioEngine.setAppPan: App not found for \(bundleID)")
        }
    }
    
    func setMasterVolume(_ volume: Float) {
        masterChannel?.volume = volume
        // TODO: Set system volume or driver master volume
        print("🔊 Set master volume: \(volume)")
    }
    
    func setMasterMute(_ muted: Bool) {
        masterChannel?.isMuted = muted
        print("🔇 Set master mute: \(muted)")
    }
    
    // MARK: - Channel Access
    
    /// Get channels for display (sorted appropriately)
    var displayChannels: [AudioChannel] {
        let appChannels = channels
            .filter { $0.channelType == .application }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        let master = channels.filter { $0.channelType == .master }
        
        return appChannels + master
    }
    
    /// Get channel by identifier
    func channel(for identifier: String) -> AudioChannel? {
        channels.first { $0.identifier == identifier }
    }
}

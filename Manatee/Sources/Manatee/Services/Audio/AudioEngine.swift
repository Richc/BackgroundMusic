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
    
    // MARK: - Private
    
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var appMonitorTimer: Timer?
    private var meterUpdateTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        print("🎛️ AudioEngine initializing...")
    }
    
    // MARK: - Lifecycle
    
    func initialize() async {
        print("🎛️ AudioEngine starting initialization...")
        
        // Create master channel
        let master = AudioChannel.master()
        masterChannel = master
        channels.append(master)
        
        // Scan for audio devices
        await refreshDevices()
        
        // Set up device change listener
        setupDeviceListener()
        
        // Start monitoring running applications
        startAppMonitoring()
        
        // Start meter updates
        startMeterUpdates()
        
        isRunning = true
        print("✅ AudioEngine initialized with \(channels.count) channels")
    }
    
    func shutdown() async {
        print("🎛️ AudioEngine shutting down...")
        
        isRunning = false
        
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
            
            // Set up callbacks
            channel.onVolumeChanged = { [weak self] volume in
                self?.setAppVolume(bundleID: bundleID, volume: volume)
            }
            channel.onMuteChanged = { [weak self] muted in
                self?.setAppMute(bundleID: bundleID, muted: muted)
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
    
    func setAppVolume(bundleID: String, volume: Float) {
        // TODO: Communicate with BGMDriver to set app volume
        print("🔊 Set volume for \(bundleID): \(volume)")
    }
    
    func setAppMute(bundleID: String, muted: Bool) {
        // TODO: Communicate with BGMDriver to set app mute
        print("🔇 Set mute for \(bundleID): \(muted)")
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

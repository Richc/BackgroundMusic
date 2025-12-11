//
//  AudioEngine.swift
//  Flo
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
    
    // MARK: - EQ State (3-band: Low/Mid/High, -12 to +12 dB)
    
    @Published var eqLowGain: Float = 0 {
        didSet { AudioPassthrough.shared.setEQLowGain(eqLowGain) }
    }
    @Published var eqMidGain: Float = 0 {
        didSet { AudioPassthrough.shared.setEQMidGain(eqMidGain) }
    }
    @Published var eqHighGain: Float = 0 {
        didSet { AudioPassthrough.shared.setEQHighGain(eqHighGain) }
    }
    
    // MARK: - Private
    
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var bgmVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var appMonitorTimer: Timer?
    private var meterUpdateTimer: Timer?
    private let bgmBridge = BGMDeviceBridge.shared
    private var cancellables = Set<AnyCancellable>()
    
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
        var realOutputDevice = outputDevices.first { $0.isDefault && !$0.name.contains("Flo") }
        if realOutputDevice == nil {
            // Fallback: pick the first non-Flo output device
            realOutputDevice = outputDevices.first { !$0.name.contains("Flo") }
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
        master.onVolumeChanged = { [weak self] volume in
            self?.applyMasterVolume(volume)
        }
        master.onMuteChanged = { [weak self] muted in
            self?.applyMasterMute(muted)
        }
        masterChannel = master
        channels.append(master)
        
        // Set up device change listener
        setupDeviceListener()
        
        // Set up BGMDevice volume listener (for keyboard volume keys)
        if isBGMDriverAvailable {
            setupBGMVolumeListener()
            
            // Subscribe to app volumes changes to mute unmanaged apps
            setupUnmanagedAppMuting()
        }
        
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
        
        // Remove BGM volume listener
        removeBGMVolumeListener()
        
        // Cancel subscriptions
        cancellables.removeAll()
        
        channels.removeAll()
        
        print("✅ AudioEngine shutdown complete")
    }
    
    // MARK: - Device Management
    
    func refreshDevices() async {
        let allDevices = AudioDevice.getAllDevices()
        
        outputDevices = allDevices.filter { $0.direction == .output && !$0.isFloDevice }
        inputDevices = allDevices.filter { $0.direction == .input && !$0.isFloDevice }
        
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
        
        // Restart passthrough with the new output device
        if isBGMDriverAvailable {
            AudioPassthrough.shared.stop()
            let passthroughStarted = AudioPassthrough.shared.start(
                bgmDevice: bgmBridge.deviceID,
                outputDevice: device.audioObjectID
            )
            if passthroughStarted {
                print("✅ Audio passthrough restarted to \(device.name)")
            } else {
                print("⚠️ Failed to restart audio passthrough to \(device.name)")
                errorMessage = "Failed to switch audio output"
            }
        }
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
    
    private func setupBGMVolumeListener() {
        guard bgmBridge.isAvailable else { return }
        
        let deviceID = bgmBridge.deviceID
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        bgmVolumeListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.syncBGMDeviceVolume()
            }
        }
        
        if let block = bgmVolumeListenerBlock {
            let status = AudioObjectAddPropertyListenerBlock(
                deviceID,
                &address,
                DispatchQueue.main,
                block
            )
            
            if status == noErr {
                print("🔊 AudioEngine: Listening for BGMDevice volume changes")
                // Sync initial volume
                syncBGMDeviceVolume()
            } else {
                print("⚠️ AudioEngine: Failed to add BGM volume listener: \(status)")
            }
        }
    }
    
    private func removeBGMVolumeListener() {
        guard let block = bgmVolumeListenerBlock, bgmBridge.isAvailable else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            bgmBridge.deviceID,
            &address,
            DispatchQueue.main,
            block
        )
        
        bgmVolumeListenerBlock = nil
    }
    
    // MARK: - Unmanaged App Muting
    
    /// Set up subscription to mute any app that plays audio but isn't managed
    private func setupUnmanagedAppMuting() {
        // Subscribe to changes in app volumes from the BGM driver
        bgmBridge.$appVolumes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.muteUnmanagedApps()
            }
            .store(in: &cancellables)
        
        // Also mute unmanaged apps immediately on setup
        muteUnmanagedApps()
        
        print("🔇 AudioEngine: Set up unmanaged app muting")
    }
    
    /// Mute any app playing audio that isn't in the managed apps list
    private func muteUnmanagedApps() {
        guard isBGMDriverAvailable else { return }
        
        let managedBundleIDs = Set(appStore.managedApps.map { $0.bundleID })
        let appVolumes = bgmBridge.appVolumes
        
        for (key, volumeData) in appVolumes {
            // Skip pid-only entries
            guard !key.starts(with: "pid:") else { continue }
            
            let bundleID = key
            
            // Check if this app is managed
            if !managedBundleIDs.contains(bundleID) {
                // Check if volume is not already 0
                if volumeData.normalizedVolume > 0 {
                    // Mute this unmanaged app
                    if let pid = volumeData.processID {
                        print("🔇 Muting unmanaged app: \(bundleID) (pid: \(pid))")
                        bgmBridge.setVolume(0, forBundleID: bundleID, pid: pid)
                    }
                }
            }
        }
    }
    
    private func syncBGMDeviceVolume() {
        guard bgmBridge.isAvailable else { return }
        
        let deviceID = bgmBridge.deviceID
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 1.0
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &volume
        )
        
        if status == noErr {
            print("🔊 AudioEngine: BGMDevice volume = \(Int(volume * 100))%")
            AudioPassthrough.shared.setSystemVolume(volume)
        } else {
            print("⚠️ AudioEngine: Failed to get BGM volume: \(status)")
        }
    }
    
    // MARK: - Application Monitoring
    
    private let appStore = ManagedAppStore.shared
    
    private func startAppMonitoring() {
        // Initial scan
        updateManagedAppChannels()
        
        // Monitor for app changes every 2 seconds
        appMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateManagedAppChannels()
            }
        }
    }
    
    /// Update channels based on managed apps (only shows user-selected apps)
    private func updateManagedAppChannels() {
        let managedApps = appStore.managedApps
        appStore.updateRunningApps()
        
        // Get current app channels
        let currentAppChannels = channels.filter { $0.channelType == .application }
        let currentBundleIDs = Set(currentAppChannels.map { $0.identifier })
        let managedBundleIDs = Set(managedApps.map { $0.bundleID })
        
        // Add channels for managed apps that don't have channels yet
        for managedApp in managedApps {
            if !currentBundleIDs.contains(managedApp.bundleID) {
                let channel = createChannelForManagedApp(managedApp)
                channels.append(channel)
                print("➕ Added managed app channel: \(channel.name)")
            }
        }
        
        // Remove channels for apps that are no longer managed
        for channel in currentAppChannels {
            if !managedBundleIDs.contains(channel.identifier) {
                channels.removeAll { $0.id == channel.id }
                print("➖ Removed unmanaged app channel: \(channel.name)")
            }
        }
        
        // Update active state and process ID for all app channels
        for channel in channels where channel.channelType == .application {
            let isRunning = appStore.isAppRunning(channel.identifier)
            channel.isActive = isRunning
            
            // Update process ID from running application
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == channel.identifier }) {
                channel.processId = runningApp.processIdentifier
            } else {
                channel.processId = 0
            }
        }
    }
    
    /// Create a channel for a managed app
    private func createChannelForManagedApp(_ managedApp: ManagedApp) -> AudioChannel {
        let channel = AudioChannel(
            channelType: .application,
            identifier: managedApp.bundleID,
            name: managedApp.name,
            icon: managedApp.loadIcon()
        )
        
        let bundleID = managedApp.bundleID
        
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
        channel.onEQChanged = { [weak self] lowDB, midDB, highDB in
            self?.setAppEQ(bundleID: bundleID, lowDB: lowDB, midDB: midDB, highDB: highDB)
        }
        
        // For newly managed apps, start with full volume (1.0)
        // Don't read from driver since we muted unmanaged apps to 0
        // The channel's default volume of 1.0 is correct
        // Only sync pan from driver (pan isn't affected by muting)
        if isBGMDriverAvailable {
            if let driverPan = bgmBridge.getPan(forBundleID: bundleID) {
                channel.pan = driverPan
            }
        }
        
        // Set initial active state and process ID
        channel.isActive = managedApp.isRunning
        
        // Get process ID if running
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            channel.processId = runningApp.processIdentifier
        }
        
        return channel
    }
    
    /// Add an app to the managed list and create its channel
    func addManagedApp(_ app: ManagedApp) {
        appStore.addApp(app)
        updateManagedAppChannels()
        
        // Unmute the newly added app by restoring its volume to 1.0
        unmuteApp(bundleID: app.bundleID)
    }
    
    /// Add an app from a running application
    func addManagedApp(from runningApp: NSRunningApplication) {
        guard let bundleID = runningApp.bundleIdentifier else { return }
        
        appStore.addApp(from: runningApp)
        updateManagedAppChannels()
        
        // Unmute the newly added app by restoring its volume to 1.0
        unmuteApp(bundleID: bundleID)
    }
    
    /// Restore an app's volume when it becomes managed
    private func unmuteApp(bundleID: String) {
        guard isBGMDriverAvailable else { return }
        
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            let pid = runningApp.processIdentifier
            print("🔊 Unmuting newly managed app: \(bundleID) (pid: \(pid))")
            bgmBridge.setVolume(1.0, forBundleID: bundleID, pid: pid)
        }
    }
    
    /// Remove an app from the managed list
    func removeManagedApp(bundleID: String) {
        // First, mute the app and remove any routes before removing from managed list
        if isBGMDriverAvailable {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                let pid = runningApp.processIdentifier
                print("🔇 Muting removed app: \(bundleID) (pid: \(pid))")
                bgmBridge.setVolume(0, forBundleID: bundleID, pid: pid)
                
                // Remove any routes involving this app
                removeRoutesForApp(pid: pid)
            }
        }
        
        appStore.removeApp(bundleID: bundleID)
        updateManagedAppChannels()
    }
    
    /// Remove all routes where this app is source or destination
    private func removeRoutesForApp(pid: pid_t) {
        // Get all managed apps to remove routes to/from the removed app
        for channel in channels where channel.channelType == .application {
            if channel.processId > 0 {
                // Remove route from removed app to this channel
                bgmBridge.removeRoute(sourcePID: pid, destPID: channel.processId)
                // Remove route from this channel to removed app
                bgmBridge.removeRoute(sourcePID: channel.processId, destPID: pid)
            }
        }
    }
    
    /// Get available apps to add (running apps not yet managed)
    func availableAppsToAdd() -> [NSRunningApplication] {
        appStore.availableAppsToAdd()
    }
    
    // MARK: - Input Channels
    
    /// Add an input device as a channel
    func addInputChannel(device: AudioDevice) {
        // Check if already added
        guard !channels.contains(where: { $0.channelType == .inputDevice && $0.identifier == device.id }) else {
            return
        }
        
        let channel = AudioChannel(
            channelType: .inputDevice,
            identifier: device.id,
            name: device.name,
            icon: NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone")
        )
        // Input devices start muted by default to prevent feedback
        channel.isMuted = true
        channels.append(channel)
        print("🎤 Added input channel: \(device.name) (muted)")
    }
    
    /// Remove a channel from the mixer
    func removeChannel(_ channel: AudioChannel) {
        if channel.channelType == .inputDevice {
            channels.removeAll { $0.id == channel.id }
            print("🎤 Removed input channel: \(channel.name)")
        } else if channel.channelType == .application {
            // For app channels, remove from managed apps
            removeManagedApp(bundleID: channel.identifier)
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
        // Get actual audio levels from the passthrough
        let peaks = AudioPassthrough.shared.getPeakLevelsAndReset()
        
        // Smooth attack, faster decay constants
        let attack: Float = 0.7  // How fast to rise
        let decay: Float = 0.85  // How fast to fall
        
        // Update master channel with real levels
        if let master = masterChannel {
            if peaks.left > master.peakLevelLeft {
                master.peakLevelLeft = master.peakLevelLeft * (1 - attack) + peaks.left * attack
            } else {
                master.peakLevelLeft = master.peakLevelLeft * decay
            }
            
            if peaks.right > master.peakLevelRight {
                master.peakLevelRight = master.peakLevelRight * (1 - attack) + peaks.right * attack
            } else {
                master.peakLevelRight = master.peakLevelRight * decay
            }
        }
        
        // For app channels, we don't have per-app audio levels from the driver
        // Just decay any existing levels to zero - meters only show on master
        for channel in channels where channel.channelType == .application {
            channel.peakLevelLeft = max(0, channel.peakLevelLeft * decay)
            channel.peakLevelRight = max(0, channel.peakLevelRight * decay)
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
        
        // Check if sendToMaster is disabled for this channel
        let channel = channels.first { $0.identifier == bundleID }
        let sendToMaster = channel?.routing.sendToMaster ?? true
        
        if !sendToMaster {
            // If sendToMaster is off, keep volume at 0 (routing only)
            // Don't log this - it happens frequently during slider drags
            return
        }
        
        // Apply master volume and mute
        let masterVolume = (masterChannel?.isMuted == true) ? 0 : (masterChannel?.volume ?? 1.0)
        let effectiveVolume = volume * masterVolume
        
        print("🎚️ AudioEngine.setAppVolume: \(bundleID) (pid: \(pid)) -> \(Int(volume * 100))% (effective: \(Int(effectiveVolume * 100))%)")
        bgmBridge.setVolume(effectiveVolume, forBundleID: bundleID, pid: pid)
    }
    
    func setAppMute(bundleID: String, pid: pid_t, muted: Bool) {
        guard isBGMDriverAvailable else {
            print("⚠️ Cannot set mute - BGMDriver not available")
            return
        }
        
        // Check if sendToMaster is disabled for this channel
        let channel = channels.first { $0.identifier == bundleID }
        let sendToMaster = channel?.routing.sendToMaster ?? true
        
        if !sendToMaster {
            // If sendToMaster is off, keep volume at 0 (routing only)
            return
        }
        
        // Get the channel's current fader volume and apply master volume
        let faderVolume = channel?.volume ?? 1.0
        let masterVolume = (masterChannel?.isMuted == true) ? 0 : (masterChannel?.volume ?? 1.0)
        let effectiveVolume: Float = muted ? 0 : (faderVolume * masterVolume)
        print("🔇 AudioEngine.setAppMute: \(bundleID) (pid: \(pid)) -> \(muted) (effective: \(Int(effectiveVolume * 100))%)")
        bgmBridge.setVolume(effectiveVolume, forBundleID: bundleID, pid: pid)
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
    
    /// Set whether an app's audio goes to master output
    /// When sendToMaster is false, the app's volume is set to 0 but audio is still captured for routing
    func setAppSendToMaster(channel: AudioChannel, sendToMaster: Bool) {
        guard isBGMDriverAvailable else {
            print("⚠️ Cannot set sendToMaster - BGMDriver not available")
            return
        }
        
        let bundleID = channel.identifier
        
        // Update the model
        channel.routing.sendToMaster = sendToMaster
        
        // Get the running app
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            print("⚠️ AudioEngine.setAppSendToMaster: App not found for \(bundleID)")
            return
        }
        
        let pid = app.processIdentifier
        
        if sendToMaster {
            // Restore the app's actual volume
            let faderVolume = channel.isMuted ? 0 : channel.volume
            let masterVolume = (masterChannel?.isMuted == true) ? 0 : (masterChannel?.volume ?? 1.0)
            let effectiveVolume = faderVolume * masterVolume
            print("🔊 AudioEngine.setAppSendToMaster: \(bundleID) -> MASTER ON (volume: \(Int(effectiveVolume * 100))%)")
            bgmBridge.setVolume(effectiveVolume, forBundleID: bundleID, pid: pid)
        } else {
            // Set volume to 0 to mute to master, but audio is still captured in driver for routing
            print("🔇 AudioEngine.setAppSendToMaster: \(bundleID) -> MASTER OFF (routing only)")
            bgmBridge.setVolume(0, forBundleID: bundleID, pid: pid)
        }
    }
    
    /// Helper to update master volume based on sendToMaster state
    private func updateMasterVolumeForChannel(_ channel: AudioChannel) {
        guard isBGMDriverAvailable else { return }
        
        let bundleID = channel.identifier
        let pid = channel.processId
        
        // Fallback to looking up from running apps if processId is 0
        let effectivePID: pid_t
        if pid > 0 {
            effectivePID = pid
        } else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            effectivePID = app.processIdentifier
        } else {
            print("⚠️ updateMasterVolumeForChannel: No valid PID for \(bundleID)")
            return
        }
        
        if channel.routing.sendToMaster {
            // Restore actual volume
            let faderVolume = channel.isMuted ? 0 : channel.volume
            let masterVolume = (masterChannel?.isMuted == true) ? 0 : (masterChannel?.volume ?? 1.0)
            let effectiveVolume = faderVolume * masterVolume
            print("🔊 Routing changed: \(bundleID) (pid: \(effectivePID)) -> DIRECT to master (volume: \(Int(effectiveVolume * 100))%)")
            bgmBridge.setVolume(effectiveVolume, forBundleID: bundleID, pid: effectivePID)
        } else {
            // Mute to master (audio is routed to other apps instead)
            print("🔇 Routing changed: \(bundleID) (pid: \(effectivePID)) -> ROUTED (muted to master)")
            bgmBridge.setVolume(0, forBundleID: bundleID, pid: effectivePID)
        }
    }
    
    /// Set per-app 3-band EQ
    func setAppEQ(bundleID: String, pid: pid_t, lowDB: Float, midDB: Float, highDB: Float) {
        guard isBGMDriverAvailable else {
            print("⚠️ Cannot set EQ - BGMDriver not available")
            return
        }
        
        print("🎛️ AudioEngine.setAppEQ: \(bundleID) (pid: \(pid)) -> L:\(lowDB)dB M:\(midDB)dB H:\(highDB)dB")
        bgmBridge.setAppEQ(lowDB: lowDB, midDB: midDB, highDB: highDB, processID: pid, bundleID: bundleID)
    }
    
    /// Set per-app 3-band EQ (convenience method that looks up PID)
    func setAppEQ(bundleID: String, lowDB: Float, midDB: Float, highDB: Float) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            setAppEQ(bundleID: bundleID, pid: app.processIdentifier, lowDB: lowDB, midDB: midDB, highDB: highDB)
        } else {
            print("⚠️ AudioEngine.setAppEQ: App not found for \(bundleID)")
        }
    }
    
    // MARK: - Master Volume
    
    /// Apply master volume to all app channels (called from callback)
    private func applyMasterVolume(_ volume: Float) {
        print("🔊 Master volume changed: \(Int(volume * 100))%")
        
        // Apply master volume to all app channels
        for channel in channels where channel.channelType == .application && channel.isActive {
            // The effective volume is fader * master
            let effectiveVolume = channel.isMuted ? 0 : channel.volume * volume
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == channel.identifier }) {
                bgmBridge.setVolume(effectiveVolume, forBundleID: channel.identifier, pid: app.processIdentifier)
            }
        }
    }
    
    /// Apply master mute to all channels (called from callback)
    private func applyMasterMute(_ muted: Bool) {
        print("🔇 Master mute changed: \(muted)")
        
        if muted {
            // Mute all apps
            for channel in channels where channel.channelType == .application && channel.isActive {
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == channel.identifier }) {
                    bgmBridge.setVolume(0, forBundleID: channel.identifier, pid: app.processIdentifier)
                }
            }
        } else {
            // Restore all app volumes
            let masterVolume = masterChannel?.volume ?? 1.0
            for channel in channels where channel.channelType == .application && channel.isActive {
                let effectiveVolume = channel.isMuted ? 0 : channel.volume * masterVolume
                if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == channel.identifier }) {
                    bgmBridge.setVolume(effectiveVolume, forBundleID: channel.identifier, pid: app.processIdentifier)
                }
            }
        }
    }
    
    func setMasterVolume(_ volume: Float) {
        masterChannel?.volume = volume
    }
    
    func setMasterMute(_ muted: Bool) {
        masterChannel?.isMuted = muted
    }
    
    // MARK: - Audio Routing
    
    /// Set up routing from one channel to another's input
    /// - Parameters:
    ///   - source: The source channel sending audio
    ///   - targetId: The UUID of the target channel to receive audio
    ///   - inputChannel: Which input channel on the target (0 = L, 1 = R, etc.)
    ///   - enabled: Whether this route is active
    func setRouting(from source: AudioChannel, to targetId: UUID, inputChannel: Int, enabled: Bool) {
        // Update the routing in the source channel's model
        source.routing.setRoute(to: targetId, inputChannel: inputChannel, enabled: enabled)
        
        // Automatically update sendToMaster based on whether there are active routes
        // If there are any active routes, audio should NOT go to master (it goes via routed apps)
        let hasActiveRoutes = !source.routing.activeRoutes.isEmpty
        source.routing.sendToMaster = !hasActiveRoutes
        
        // Find the target channel
        guard let targetChannel = channels.first(where: { $0.id == targetId }) else {
            print("⚠️ AudioEngine.setRouting: Target channel not found for ID \(targetId)")
            return
        }
        
        print("🔀 AudioEngine.setRouting: \(source.name) -> \(targetChannel.name) ch\(inputChannel + 1) = \(enabled)")
        print("   hasActiveRoutes: \(hasActiveRoutes), sendToMaster: \(source.routing.sendToMaster)")
        
        // ALWAYS update the driver volume based on routing state
        // This ensures the source is muted to master when routed
        updateMasterVolumeForChannel(source)
        
        // Notify the routing callback if set
        source.onRoutingChanged?(source.routing)
        
        // Send routing configuration to BGMDriver
        // This requires both source and target to have valid process IDs
        let sourcePID = source.processId
        let targetPID = targetChannel.processId
        
        if sourcePID > 0 && targetPID > 0 {
            // Call the driver to set up the route
            BGMDeviceBridge.shared.setRoute(
                sourcePID: sourcePID,
                destPID: targetPID,
                gain: 1.0,  // Full gain for now
                enabled: enabled
            )
            
            if enabled {
                print("   ✅ Driver route enabled: \(source.identifier) (pid: \(sourcePID)) -> \(targetChannel.identifier) (pid: \(targetPID))")
            } else {
                print("   ❌ Driver route disabled: \(source.identifier) -> \(targetChannel.identifier)")
            }
        } else {
            print("   ⚠️ Cannot set driver route: source PID=\(sourcePID), target PID=\(targetPID) (need valid PIDs)")
        }
        
        // Log current routing state
        logRoutingState(for: source)
    }
    
    /// Log the current routing state for debugging
    private func logRoutingState(for channel: AudioChannel) {
        let routes = channel.routing.activeRoutes
        let toMaster = channel.routing.sendToMaster
        
        print("📊 Routing state for \(channel.name):")
        print("   → Master: \(toMaster ? "✅" : "❌")")
        
        for route in routes {
            if let target = channels.first(where: { $0.id == route.channelId }) {
                print("   → \(target.name) input \(route.inputChannel + 1): ✅")
            }
        }
        
        if routes.isEmpty && toMaster {
            print("   (Default: only to master)")
        }
    }
    
    /// Get all active routing destinations for a channel
    func getActiveRoutes(for channel: AudioChannel) -> [(channel: AudioChannel, inputChannel: Int)] {
        var result: [(AudioChannel, Int)] = []
        
        for route in channel.routing.activeRoutes {
            if let target = channels.first(where: { $0.id == route.channelId }) {
                result.append((target, route.inputChannel))
            }
        }
        
        return result
    }
    
    // MARK: - Channel Access
    
    /// Get channels for display (sorted appropriately)
    var displayChannels: [AudioChannel] {
        let appChannels = channels
            .filter { $0.channelType == .application }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        let inputChannels = channels
            .filter { $0.channelType == .inputDevice }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        let master = channels.filter { $0.channelType == .master }
        
        return appChannels + inputChannels + master
    }
    
    /// Get channel by identifier
    func channel(for identifier: String) -> AudioChannel? {
        channels.first { $0.identifier == identifier }
    }
}

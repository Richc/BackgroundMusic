//
//  FloApp.swift
//  Flo
//
//  macOS Audio Control Application
//  Control volume, mute, and routing for any application with MIDI/OSC support
//

import SwiftUI
import AppKit

@main
struct FloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Mixer window (can be opened from menu bar)
        WindowGroup("Flo Mixer", id: "mixer") {
            MixerView()
                .environmentObject(appDelegate.audioEngine)
                .environmentObject(appDelegate.midiService)
                .environmentObject(appDelegate.oscService)
                .environmentObject(appDelegate.presetStore)
                .frame(minWidth: 500, minHeight: 550)
        }
        .defaultSize(width: 1200, height: 600)
        
        // Settings window
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.audioEngine)
                .environmentObject(appDelegate.midiService)
                .environmentObject(appDelegate.oscService)
        }
        
        // Menu bar item
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appDelegate.audioEngine)
                .environmentObject(appDelegate.midiService)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Core services
    let audioEngine = AudioEngine()
    let midiService = MIDIService()
    let oscService = OSCService()
    let presetStore = PresetStore()
    
    // Settings window
    var settingsWindow: NSWindow?
    
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            print("🐋 Flo v1.0.0 starting...")
            
            // Initialize audio engine
            await audioEngine.initialize()
            
            // Initialize MIDI
            await midiService.start()
            
            // Connect MIDI control changes to audio engine
            midiService.onControlChange = { [weak self] target, value in
                guard let self = self else { return }
                self.handleControlChange(target: target, value: value)
            }
            
            // Initialize OSC server
            await oscService.start(port: 9000)
            
            // Connect OSC control changes to audio engine
            oscService.onControlChange = { [weak self] target, value in
                guard let self = self else { return }
                self.handleControlChange(target: target, value: value)
            }
            
            print("✅ Flo initialized")
        }
    }
    
    /// Handle control changes from MIDI or OSC
    private func handleControlChange(target: ControlTarget, value: Float) {
        print("🎹 Control change: \(target.displayName) = \(value)")
        
        switch target {
        case .masterVolume:
            audioEngine.setMasterVolume(value)
            
        case .masterMute:
            // Toggle mute state when value is 1.0 (button pressed)
            if value > 0.5 {
                if let master = audioEngine.masterChannel {
                    master.isMuted.toggle()
                    print("🔇 Master mute toggled to: \(master.isMuted)")
                }
            }
            
        case .eqLow:
            // Convert 0-1 to -12 to +12 dB
            let dbValue = (value * 24) - 12
            audioEngine.eqLowGain = dbValue
            print("🎛️ EQ Low: \(String(format: "%.1f", dbValue)) dB")
            
        case .eqMid:
            // Convert 0-1 to -12 to +12 dB
            let dbValue = (value * 24) - 12
            audioEngine.eqMidGain = dbValue
            print("🎛️ EQ Mid: \(String(format: "%.1f", dbValue)) dB")
            
        case .eqHigh:
            // Convert 0-1 to -12 to +12 dB
            let dbValue = (value * 24) - 12
            audioEngine.eqHighGain = dbValue
            print("🎛️ EQ High: \(String(format: "%.1f", dbValue)) dB")
            
        case .appVolume(let bundleID):
            // Update both the channel model and the BGM driver
            if let channel = audioEngine.channels.first(where: { $0.identifier == bundleID }) {
                channel.volume = value
                print("🎚️ App volume for \(bundleID): \(Int(value * 100))%")
            }
            audioEngine.setAppVolume(bundleID: bundleID, volume: value)
            
        case .appMute(let bundleID):
            // Toggle mute state when value is 1.0 (button pressed)
            if value > 0.5 {
                if let channel = audioEngine.channels.first(where: { $0.identifier == bundleID }) {
                    channel.isMuted.toggle()
                    print("🔇 App mute for \(bundleID) toggled to: \(channel.isMuted)")
                }
            }
            
        case .appPan(let bundleID):
            if let channel = audioEngine.channels.first(where: { $0.identifier == bundleID }) {
                channel.pan = (value * 2) - 1  // Convert 0-1 to -1 to +1
            }
            
        case .appSolo(let bundleID):
            // Toggle solo state when value is 1.0 (button pressed)
            if value > 0.5 {
                if let channel = audioEngine.channels.first(where: { $0.identifier == bundleID }) {
                    channel.isSoloed.toggle()
                    print("🎤 App solo for \(bundleID) toggled to: \(channel.isSoloed)")
                }
            }
            
        case .deviceVolume(let deviceUID):
            // Device volume control - not yet fully implemented
            print("📢 Device volume change for \(deviceUID): \(value)")
            
        case .deviceMute(let deviceUID):
            // Device mute control - not yet fully implemented
            print("📢 Device mute change for \(deviceUID): \(value > 0.5)")
            
        case .sceneRecall(let index):
            // Recall scene by index
            if index < presetStore.scenes.count {
                let scene = presetStore.scenes[index]
                Task {
                    await presetStore.recallScene(scene, to: audioEngine)
                }
            }
            
        case .presetRecall(let name):
            if let preset = presetStore.presets.first(where: { $0.name == name }) {
                Task {
                    await presetStore.recallPreset(preset, to: audioEngine)
                }
            }
            
        case .bankNext, .bankPrevious:
            // Bank navigation - could be implemented for MIDI controller banks
            break
            
        case .crossfader:
            // Crossfader control - convert 0-1 to -1 to +1
            let position = (value * 2) - 1
            CrossfaderStore.shared.setPosition(position)
            print("🎚️ Crossfader position: \(String(format: "%.2f", position))")
            
        case .custom:
            // Custom actions not yet implemented
            break
        }
    }
    
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            print("🐋 Flo shutting down...")
            
            // Cleanup
            await audioEngine.shutdown()
            await midiService.stop()
            await oscService.stop()
        }
    }
    
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar
        return false
    }
    
    func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let preferencesView = PreferencesView()
            .environmentObject(audioEngine)
            .environmentObject(midiService)
            .environmentObject(oscService)
        
        let hostingController = NSHostingController(rootView: preferencesView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Flo Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

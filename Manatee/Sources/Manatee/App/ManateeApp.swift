//
//  ManateeApp.swift
//  Manatee
//
//  macOS Audio Control Application
//  Control volume, mute, and routing for any application with MIDI/OSC support
//

import SwiftUI
import AppKit

@main
struct ManateeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Mixer window (can be opened from menu bar)
        WindowGroup("Manatee Mixer", id: "mixer") {
            MixerView()
                .environmentObject(appDelegate.audioEngine)
                .environmentObject(appDelegate.midiService)
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
    
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            print("🐋 Manatee v1.0.0 starting...")
            
            // Initialize audio engine
            await audioEngine.initialize()
            
            // Initialize MIDI
            await midiService.start()
            
            // Initialize OSC server
            await oscService.start(port: 9000)
            
            print("✅ Manatee initialized")
        }
    }
    
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            print("🐋 Manatee shutting down...")
            
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
}

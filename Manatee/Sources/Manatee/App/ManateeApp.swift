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
        // Settings window
        Settings {
            PreferencesView()
        }
        
        // Mixer window (can be opened from menu bar)
        Window("Manatee Mixer", id: "mixer") {
            MixerView()
                .environmentObject(appDelegate.audioEngine)
                .environmentObject(appDelegate.midiService)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 600)
        
        // Menu bar item
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(appDelegate.audioEngine)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Core services
    let audioEngine = AudioEngine()
    let midiService = MIDIService()
    let oscService = OSCService()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🐋 Manatee v1.0.0 starting...")
        
        // Initialize audio engine
        Task {
            await audioEngine.initialize()
        }
        
        // Initialize MIDI
        Task {
            await midiService.start()
        }
        
        // Initialize OSC server
        Task {
            await oscService.start(port: 9000)
        }
        
        print("✅ Manatee initialized")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🐋 Manatee shutting down...")
        
        // Cleanup
        Task {
            await audioEngine.shutdown()
            await midiService.stop()
            await oscService.stop()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar
        return false
    }
}

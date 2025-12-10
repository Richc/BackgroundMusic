//
//  MenuBarPopoverView.swift
//  Manatee
//
//  Simple volume control view shown in menu bar popover
//

import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiService: MIDIService
    @State private var showSettings = false
    
    var body: some View {
        if showSettings {
            SettingsPopoverView(showSettings: $showSettings)
                .environmentObject(audioEngine)
                .environmentObject(midiService)
        } else {
            mainView
        }
    }
    
    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // App volume list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(audioEngine.displayChannels) { channel in
                        AppVolumeRow(channel: channel)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Device selection
            deviceSelectionView
            
            Divider()
            
            // Footer buttons
            footerView
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private static let logoImage: NSImage? = {
        let executablePath = Bundle.main.executablePath ?? ""
        let appPath = (executablePath as NSString).deletingLastPathComponent
        let resourcesPath = (appPath as NSString).deletingLastPathComponent + "/Resources"
        let logoPath = resourcesPath + "/ManateeLogo.png"
        return NSImage(contentsOfFile: logoPath)
    }()
    
    private var headerView: some View {
        HStack {
            if let logoImage = Self.logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(ManateeColors.brand)
            }
            
            Text("Manatee")
                .font(.headline)
            
            Spacer()
            
            // MIDI indicator
            if true { // TODO: midiService.isRunning
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("MIDI")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Device Selection
    
    private var deviceSelectionView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.wave.2")
                    .frame(width: 20)
                    .foregroundColor(.secondary)
                
                Text("Output:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: Binding(
                    get: { audioEngine.selectedOutputDevice?.id ?? "" },
                    set: { id in
                        if let device = audioEngine.outputDevices.first(where: { $0.id == id }) {
                            audioEngine.selectOutputDevice(device)
                        }
                    }
                )) {
                    ForEach(audioEngine.outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            
            HStack {
                Image(systemName: "mic")
                    .frame(width: 20)
                    .foregroundColor(.secondary)
                
                Text("Input:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: Binding(
                    get: { audioEngine.selectedInputDevice?.id ?? "" },
                    set: { id in
                        if let device = audioEngine.inputDevices.first(where: { $0.id == id }) {
                            audioEngine.selectInputDevice(device)
                        }
                    }
                )) {
                    ForEach(audioEngine.inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button {
                openMixer()
            } label: {
                Label("Open Mixer", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            
            Spacer()
            
            Button {
                openPreferences()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(12)
    }
    
    // MARK: - Actions
    
    private func openMixer() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "mixer" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open new mixer window
            NSApp.sendAction(Selector(("showMixerWindow:")), to: nil, from: nil)
        }
    }
    
    private func openPreferences() {
        showSettings = true
    }
}

// MARK: - Settings Popover View

struct SettingsPopoverView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiService: MIDIService
    @Binding var showSettings: Bool
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case midi = "MIDI"
        case audio = "Audio"
        case about = "About"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Text("Settings")
                    .font(.headline)
                
                Spacer()
                Spacer().frame(width: 50) // Balance the back button
            }
            .padding(12)
            
            Divider()
            
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            ScrollView {
                switch selectedTab {
                case .general:
                    GeneralSettingsContent()
                case .midi:
                    MIDISettingsContent()
                        .environmentObject(midiService)
                case .audio:
                    AudioSettingsContent()
                        .environmentObject(audioEngine)
                case .about:
                    AboutSettingsContent()
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings Content Views

struct GeneralSettingsContent: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("colorScheme") private var colorScheme = "system"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Show in Dock", isOn: $showInDock)
            
            Divider()
            
            Text("Appearance")
                .font(.headline)
            Picker("", selection: $colorScheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            
            Spacer()
        }
        .padding(16)
    }
}

struct MIDISettingsContent: View {
    @EnvironmentObject var midiService: MIDIService
    @EnvironmentObject var audioEngine: AudioEngine
    @AppStorage("midiEnabled") private var midiEnabled = true
    @AppStorage("midiSendFeedback") private var midiSendFeedback = true
    @State private var showMappingEditor = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable MIDI control", isOn: $midiEnabled)
            Toggle("Send feedback to controllers", isOn: $midiSendFeedback)
            
            Divider()
            
            Text("MIDI Mappings")
                .font(.headline)
            
            Button("Configure Mappings...") {
                showMappingEditor = true
            }
            .sheet(isPresented: $showMappingEditor) {
                MIDIMappingEditorView()
                    .environmentObject(midiService)
                    .environmentObject(audioEngine)
            }
            
            Spacer()
        }
        .padding(16)
    }
}

struct AudioSettingsContent: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @AppStorage("sampleRate") private var sampleRate = 44100
    @AppStorage("bufferSize") private var bufferSize = 512
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Output Device")
                .font(.headline)
            
            Picker("", selection: Binding(
                get: { audioEngine.selectedOutputDevice?.id ?? "" },
                set: { id in
                    if let device = audioEngine.outputDevices.first(where: { $0.id == id }) {
                        audioEngine.selectOutputDevice(device)
                    }
                }
            )) {
                ForEach(audioEngine.outputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()
            
            Divider()
            
            Text("Sample Rate")
                .font(.headline)
            Picker("", selection: $sampleRate) {
                Text("44.1 kHz").tag(44100)
                Text("48 kHz").tag(48000)
                Text("96 kHz").tag(96000)
            }
            .pickerStyle(.segmented)
            
            Text("Buffer Size")
                .font(.headline)
            Picker("", selection: $bufferSize) {
                Text("256").tag(256)
                Text("512").tag(512)
                Text("1024").tag(1024)
            }
            .pickerStyle(.segmented)
            
            Spacer()
        }
        .padding(16)
    }
}

struct AboutSettingsContent: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Manatee")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .foregroundColor(.secondary)
            
            Text("Audio control for macOS")
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("© 2024 Manatee Audio")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(16)
    }
}

// MARK: - App Volume Row

struct AppVolumeRow: View {
    @ObservedObject var channel: AudioChannel
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // App icon
            if let icon = channel.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: iconName)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }
            
            // App name and volume
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                // Volume slider
                HStack(spacing: 8) {
                    Slider(value: $channel.volume, in: 0...1.5)
                        .controlSize(.small)
                    
                    Text(channel.volumeDBFormatted)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 45, alignment: .trailing)
                }
            }
            
            // Mute button
            Button {
                channel.isMuted.toggle()
            } label: {
                Image(systemName: channel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(channel.isMuted ? .red : .secondary)
            .help(channel.isMuted ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var iconName: String {
        switch channel.channelType {
        case .master:
            return "speaker.wave.3.fill"
        case .application:
            return "app.fill"
        case .inputDevice:
            return "mic.fill"
        case .outputDevice:
            return "speaker.wave.2.fill"
        case .bus:
            return "arrow.triangle.branch"
        }
    }
}

// MARK: - Mixer Settings Popover (for use in MixerView)

struct MixerSettingsPopoverView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiService: MIDIService
    @State private var selectedTab: SettingsPopoverView.SettingsTab = .general
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
            }
            .padding(12)
            
            Divider()
            
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsPopoverView.SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            ScrollView {
                switch selectedTab {
                case .general:
                    GeneralSettingsContent()
                case .midi:
                    MIDISettingsContent()
                        .environmentObject(midiService)
                case .audio:
                    AudioSettingsContent()
                        .environmentObject(audioEngine)
                case .about:
                    AboutSettingsContent()
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Preview

#Preview {
    MenuBarPopoverView()
        .environmentObject(AudioEngine())
}

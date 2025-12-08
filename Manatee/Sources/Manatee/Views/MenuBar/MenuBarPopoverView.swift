//
//  MenuBarPopoverView.swift
//  Manatee
//
//  Simple volume control view shown in menu bar popover
//

import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

// MARK: - Preview

#Preview {
    MenuBarPopoverView()
        .environmentObject(AudioEngine())
}

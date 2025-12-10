//
//  PreferencesView.swift
//  Manatee
//
//  Settings and preferences window
//

import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiService: MIDIService
    @EnvironmentObject var oscService: OSCService
    
    @State private var selectedTab: PreferencesTab = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 4) {
                ForEach(PreferencesTab.allCases) { tab in
                    PreferencesTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
            .frame(width: 160)
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                selectedTab.contentView
                    .environmentObject(audioEngine)
                    .environmentObject(midiService)
                    .environmentObject(oscService)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 500)
    }
}

// MARK: - Preferences Tabs

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general = "General"
    case audio = "Audio"
    case midi = "MIDI"
    case osc = "OSC"
    case shortcuts = "Shortcuts"
    case advanced = "Advanced"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .audio: return "speaker.wave.3"
        case .midi: return "pianokeys"
        case .osc: return "network"
        case .shortcuts: return "keyboard"
        case .advanced: return "wrench.and.screwdriver"
        case .settings: return "slider.horizontal.3"
        }
    }
    
    @ViewBuilder
    var contentView: some View {
        switch self {
        case .general: GeneralPreferencesView()
        case .audio: AudioPreferencesView()
        case .midi: MIDIPreferencesView()
        case .osc: OSCPreferencesView()
        case .shortcuts: ShortcutsPreferencesView()
        case .advanced: AdvancedPreferencesView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Tab Button

struct PreferencesTabButton: View {
    let tab: PreferencesTab
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                
                Text(tab.rawValue)
                    .font(.system(size: 13))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? ManateeColors.brand.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("defaultView") private var defaultView = "menubar"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencesSectionHeader(title: "Startup")
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch Manatee at login", isOn: $launchAtLogin)
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Show in Dock", isOn: $showInDock)
            }
            
            Divider()
            
            PreferencesSectionHeader(title: "Default View")
            
            Picker("Open in:", selection: $defaultView) {
                Text("Menu Bar Popover").tag("menubar")
                Text("Mixer Window").tag("mixer")
            }
            .pickerStyle(.radioGroup)
            
            Divider()
            
            PreferencesSectionHeader(title: "Updates")
            
            HStack {
                Button("Check for Updates...") { }
                Spacer()
                Text("Version 1.0.0")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Audio Preferences

struct AudioPreferencesView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    @AppStorage("autoSwitchOutput") private var autoSwitchOutput = true
    @AppStorage("meterRefreshRate") private var meterRefreshRate = 30.0
    @AppStorage("bufferSize") private var bufferSize = 512
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencesSectionHeader(title: "Output Device")
            
            Picker("Default Output:", selection: .constant("")) {
                ForEach(audioEngine.outputDevices, id: \.id) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .frame(maxWidth: 300)
            
            Toggle("Automatically switch when headphones connected", isOn: $autoSwitchOutput)
            
            Divider()
            
            PreferencesSectionHeader(title: "Performance")
            
            HStack {
                Text("Buffer Size:")
                Picker("", selection: $bufferSize) {
                    Text("128 samples").tag(128)
                    Text("256 samples").tag(256)
                    Text("512 samples").tag(512)
                    Text("1024 samples").tag(1024)
                }
                .frame(width: 150)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Meter Refresh Rate:")
                    Text("\(Int(meterRefreshRate)) fps")
                        .foregroundColor(.secondary)
                }
                Slider(value: $meterRefreshRate, in: 10...60, step: 5)
                    .frame(width: 200)
            }
            
            Divider()
            
            PreferencesSectionHeader(title: "Hidden Apps")
            
            Text("Apps that won't appear in the volume control")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                Text("No hidden apps")
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
            .listStyle(.bordered)
            
            Spacer()
        }
    }
}

// MARK: - MIDI Preferences

struct MIDIPreferencesView: View {
    @EnvironmentObject var midiService: MIDIService
    
    @AppStorage("midiEnabled") private var midiEnabled = true
    @AppStorage("midiSendFeedback") private var midiSendFeedback = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencesSectionHeader(title: "MIDI")
            
            Toggle("Enable MIDI control", isOn: $midiEnabled)
            Toggle("Send feedback to controllers (motorized faders, LEDs)", isOn: $midiSendFeedback)
            
            Divider()
            
            PreferencesSectionHeader(title: "Connected Devices")
            
            if midiService.inputDevices.isEmpty {
                Text("No MIDI devices connected")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(midiService.inputDevices, id: \.displayName) { device in
                    HStack {
                        Image(systemName: "pianokeys")
                        Text(device.displayName)
                        Spacer()
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(height: 120)
                .listStyle(.bordered)
            }
            
            Divider()
            
            PreferencesSectionHeader(title: "Device Profile")
            
            Picker("Controller Profile:", selection: .constant("auto")) {
                Text("Auto-Detect").tag("auto")
                Text("Generic MIDI").tag("generic")
                Divider()
                Text("Behringer X-Touch Mini").tag("xtouch-mini")
                Text("Korg nanoKONTROL2").tag("nanokontrol2")
            }
            .frame(width: 250)
            
            HStack {
                Button("Configure Mappings...") { }
                Button("Reset to Default") { }
            }
            
            Spacer()
        }
    }
}

// MARK: - OSC Preferences

struct OSCPreferencesView: View {
    @EnvironmentObject var oscService: OSCService
    
    @AppStorage("oscEnabled") private var oscEnabled = false
    @AppStorage("oscPort") private var oscPort = 9000
    @AppStorage("oscFeedbackPort") private var oscFeedbackPort = 9001
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencesSectionHeader(title: "OSC Server")
            
            Toggle("Enable OSC control", isOn: $oscEnabled)
            
            HStack {
                Text("Listen Port:")
                TextField("", value: $oscPort, format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Feedback Port:")
                TextField("", value: $oscFeedbackPort, format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
            
            PreferencesSectionHeader(title: "Network")
            
            if let ip = getLocalIPAddress() {
                HStack {
                    Text("IP Address:")
                    Text(ip)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ip, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text("Server Status: \(oscService.isRunning ? "Running" : "Stopped")")
                .foregroundColor(oscService.isRunning ? .green : .secondary)
            
            Divider()
            
            PreferencesSectionHeader(title: "OSC Address Reference")
            
            VStack(alignment: .leading, spacing: 4) {
                oscAddressRow("/manatee/app/{bundleID}/volume", "0.0-1.5")
                oscAddressRow("/manatee/app/{bundleID}/mute", "0 or 1")
                oscAddressRow("/manatee/master/volume", "0.0-1.5")
                oscAddressRow("/manatee/master/mute", "0 or 1")
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            
            Spacer()
        }
    }
    
    private func oscAddressRow(_ address: String, _ values: String) -> some View {
        HStack {
            Text(address)
            Spacer()
            Text(values)
                .foregroundColor(.secondary)
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}

// MARK: - Shortcuts Preferences

struct ShortcutsPreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencesSectionHeader(title: "Global Shortcuts")
            
            shortcutRow("Toggle Mute All", "⌥⌘M")
            shortcutRow("Open Mixer", "⌥⌘X")
            shortcutRow("Show Menu Bar Popover", "⌥⌘V")
            
            Divider()
            
            PreferencesSectionHeader(title: "Mixer Shortcuts")
            
            shortcutRow("Next Bank", "→")
            shortcutRow("Previous Bank", "←")
            shortcutRow("Mute Selected", "M")
            shortcutRow("Solo Selected", "S")
            
            Text("Click on a shortcut to customize")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Advanced Preferences

struct AdvancedPreferencesView: View {
    @AppStorage("debugLogging") private var debugLogging = false
    @AppStorage("useVirtualDevice") private var useVirtualDevice = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PreferencesSectionHeader(title: "Audio Driver")
            
            Toggle("Use Manatee virtual audio device", isOn: $useVirtualDevice)
            
            Text("The virtual audio device enables per-app volume control. Disabling this limits functionality to system-wide volume only.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Reinstall Driver...") { }
                Button("Remove Driver...") { }
                    .foregroundColor(.red)
            }
            
            Divider()
            
            PreferencesSectionHeader(title: "Diagnostics")
            
            Toggle("Enable debug logging", isOn: $debugLogging)
            
            HStack {
                Button("Open Log File") { }
                Button("Export Diagnostics...") { }
            }
            
            Divider()
            
            PreferencesSectionHeader(title: "Reset")
            
            Button("Reset All Settings to Default") { }
                .foregroundColor(.red)
            
            Text("This will reset all preferences, MIDI mappings, and presets.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Helper Views

struct PreferencesSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.bottom, 4)
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
        .environmentObject(AudioEngine())
        .environmentObject(MIDIService())
        .environmentObject(OSCService())
}

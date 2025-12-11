//
//  MenuBarPopoverView.swift
//  Flo
//
//  Simple volume control view shown in menu bar popover
//

import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiService: MIDIService
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false
    @State private var isMixerWindowOpen = false
    @State private var showingRecordSettings = false
    @State private var showingAddApp = false
    @State private var recordingFileName = ""
    @State private var recordingPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    @StateObject private var audioRecorder = AudioRecorder.shared
    
    // Timer to check mixer window state
    private let windowCheckTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if showSettings {
            SettingsPopoverView(showSettings: $showSettings)
                .environmentObject(audioEngine)
                .environmentObject(midiService)
        } else {
            mainView
                .onReceive(windowCheckTimer) { _ in
                    updateMixerWindowState()
                }
                .onAppear {
                    updateMixerWindowState()
                }
                .sheet(isPresented: $showingRecordSettings) {
                    MenuRecordSettingsSheet(
                        fileName: $recordingFileName,
                        recordingPath: $recordingPath,
                        onRecord: {
                            startMasterRecording()
                        },
                        onCancel: {
                            showingRecordSettings = false
                        }
                    )
                }
        }
    }
    
    private func updateMixerWindowState() {
        isMixerWindowOpen = NSApp.windows.contains { window in
            (window.title == "Flo Mixer" || (window.title.contains("Flo") && window.title.contains("Mixer"))) && window.isVisible
        }
    }
    
    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Master section with record button
            if let master = audioEngine.masterChannel {
                MenuMasterRow(
                    channel: master,
                    onRecordTapped: {
                        if master.isRecording {
                            stopMasterRecording()
                        } else {
                            showRecordSettingsDialog()
                        }
                    }
                )
                Divider()
            }
            
            // App volume list (excluding master which is shown above)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(audioEngine.displayChannels.filter { $0.channelType != .master }) { channel in
                        AppVolumeRow(
                            channel: channel,
                            allChannels: audioEngine.channels,
                            onRemove: {
                                if channel.channelType == .inputDevice {
                                    audioEngine.removeChannel(channel)
                                } else {
                                    audioEngine.removeManagedApp(bundleID: channel.identifier)
                                }
                            }
                        )
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
        // Try Bundle.module first (SPM resource bundle)
        if let bundleURL = Bundle.main.url(forResource: "Flo_Flo", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL),
           let logoPath = resourceBundle.path(forResource: "flo boombox", ofType: "png"),
           let image = NSImage(contentsOfFile: logoPath) {
            return image
        }
        
        // Also try looking in the same directory as the executable (SPM debug build)
        let executablePath = Bundle.main.executablePath ?? ""
        let execDir = (executablePath as NSString).deletingLastPathComponent
        let spmBundlePath = execDir + "/Flo_Flo.bundle/flo boombox.png"
        if let image = NSImage(contentsOfFile: spmBundlePath) {
            return image
        }
        
        // Fallback to FloLogo.png
        let floLogoPath = execDir + "/Flo_Flo.bundle/FloLogo.png"
        if let image = NSImage(contentsOfFile: floLogoPath) {
            return image
        }
        
        return nil
    }()
    
    private var headerView: some View {
        HStack {
            if let logoImage = Self.logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "waveform")
                    .foregroundColor(FloColors.brand)
            }
            
            Text("Flo")
                .font(.headline)
            
            Spacer()
            
            // Add app button
            Button {
                showingAddApp.toggle()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(FloColors.accentGreen)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingAddApp, arrowEdge: .bottom) {
                MenuAddAppPopover()
                    .environmentObject(audioEngine)
            }
            .help("Add app or input to mixer")
            
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
                toggleMixer()
            } label: {
                Label(isMixerWindowOpen ? "Close Mix Window" : "Open Mix Window", systemImage: "slider.horizontal.3")
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
    
    private func toggleMixer() {
        // Find mixer window by title since SwiftUI WindowGroup uses title not identifier
        if let window = NSApp.windows.first(where: { $0.title == "Flo Mixer" || $0.title.contains("Flo") && $0.title.contains("Mixer") }) {
            if window.isVisible {
                window.close()
                isMixerWindowOpen = false
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                isMixerWindowOpen = true
            }
        } else {
            // Open new mixer window using SwiftUI openWindow
            openWindow(id: "mixer")
            NSApp.activate(ignoringOtherApps: true)
            isMixerWindowOpen = true
        }
    }
    
    private func showRecordSettingsDialog() {
        // Generate default filename with date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        recordingFileName = "Master_\(timestamp)"
        showingRecordSettings = true
    }
    
    private func startMasterRecording() {
        guard let master = audioEngine.masterChannel else { return }
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: recordingPath, withIntermediateDirectories: true)
        
        let finalFileName = recordingFileName.isEmpty ? "Master" : recordingFileName
        let fullPath = recordingPath.appendingPathComponent("\(finalFileName).wav")
        
        do {
            try RecordingContext.shared.startMasterRecording(sampleRate: 44100, savePath: fullPath)
            master.isRecording = true
            master.recordingStartTime = Date()
            print("🔴 Started master recording from menu: \(finalFileName)")
        } catch {
            print("❌ Failed to start master recording: \(error.localizedDescription)")
        }
        
        showingRecordSettings = false
    }
    
    private func stopMasterRecording() {
        guard let master = audioEngine.masterChannel else { return }
        RecordingContext.shared.stopMasterRecording()
        master.isRecording = false
        master.recordingStartTime = nil
        print("⏹️ Stopped master recording from menu")
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
    @AppStorage("showTooltips") private var showTooltips = true
    @ObservedObject private var crossfaderStore = CrossfaderStore.shared
    @State private var isOptionKeyPressed = false
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Show in Dock", isOn: $showInDock)
                .onChange(of: showInDock) { newValue in
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            
            Divider()
            
            Text("Appearance")
                .font(.headline)
            Picker("", selection: $colorScheme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            
            Divider()
            
            Text("Help")
                .font(.headline)
            Toggle("Show Tooltips", isOn: $showTooltips)
                .help("Display helpful tooltips when hovering over controls")
            
            // Crossfader option - only visible when Option key is held
            if isOptionKeyPressed {
                Divider()
                
                Toggle("Enable Crossfader", isOn: $crossfaderStore.isEnabled)
                    .help("Shows a DJ-style crossfader to fade between two apps")
            }
            
            Spacer()
        }
        .padding(16)
        .onAppear {
            // Check current state immediately
            isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)
            
            // Monitor for Option key - use both local and global monitors
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionKeyPressed = event.modifierFlags.contains(.option)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionKeyPressed = event.modifierFlags.contains(.option)
            }
        }
        .onDisappear {
            // Clean up monitors
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = globalMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
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
            
            Text("Recording Sample Rate")
                .font(.headline)
            Picker("", selection: $sampleRate) {
                Text("44.1 kHz").tag(44100)
                Text("48 kHz").tag(48000)
                Text("96 kHz").tag(96000)
            }
            .pickerStyle(.segmented)
            
            Text("Used when recording audio")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(16)
    }
}

struct AboutSettingsContent: View {
    var body: some View {
        VStack(spacing: 16) {
            // Flo logo
            if let logoImage = loadFloLogo() {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            } else {
                Image(systemName: "drop.fill")
                    .font(.system(size: 128))
                    .foregroundColor(.accentColor)
            }
            
            Text("Flo")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .foregroundColor(.secondary)
            
            Text("Audio Flo control for macOS")
                .foregroundColor(.secondary)
            
            Divider()
            
            Text("© 2025 Happy Manatee")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("www.happymanatee.co.uk")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(16)
    }
    
    private func loadFloLogo() -> NSImage? {
        // Try SPM resource bundle first
        if let resourceBundle = Bundle.main.url(forResource: "Flo_Flo", withExtension: "bundle"),
           let bundle = Bundle(url: resourceBundle) {
            // Try "Flo icon.icns" first (best quality, scales nicely)
            if let imageURL = bundle.url(forResource: "Flo icon", withExtension: "icns"),
               let image = NSImage(contentsOf: imageURL) {
                return image
            }
            // Try AppIcon.icns
            if let imageURL = bundle.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: imageURL) {
                return image
            }
        }
        
        // Try direct path to icns in executable directory
        let executablePath = Bundle.main.executablePath ?? ""
        let execDir = (executablePath as NSString).deletingLastPathComponent
        let icnsPath = execDir + "/Flo_Flo.bundle/Flo icon.icns"
        if let image = NSImage(contentsOfFile: icnsPath) {
            return image
        }
        
        // Try AppIcon.icns path
        let appIconPath = execDir + "/Flo_Flo.bundle/AppIcon.icns"
        if let image = NSImage(contentsOfFile: appIconPath) {
            return image
        }
        
        return nil
    }
}

// MARK: - App Volume Row

struct AppVolumeRow: View {
    @ObservedObject var channel: AudioChannel
    var allChannels: [AudioChannel] = []
    var onRemove: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var showRoutingPopover = false
    
    var body: some View {
        HStack(spacing: 8) {
            // App icon - clickable for routing
            Button {
                showRoutingPopover.toggle()
            } label: {
                if let icon = channel.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: iconName)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRoutingPopover, arrowEdge: .leading) {
                MenuRoutingPopover(channel: channel, allChannels: allChannels)
            }
            
            // App name and volume
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                
                // Volume slider
                HStack(spacing: 6) {
                    Slider(value: $channel.volume, in: 0...1.5)
                        .controlSize(.small)
                    
                    // M/S/R buttons - traffic light style
                    HStack(spacing: 3) {
                        // Mute - Green
                        Button {
                            channel.isMuted.toggle()
                        } label: {
                            Text("M")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(channel.isMuted ? Color.green : Color.green.opacity(0.3)))
                        .buttonStyle(.plain)
                        
                        // Solo - Yellow
                        Button {
                            channel.isSoloed.toggle()
                        } label: {
                            Text("S")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(channel.isSoloed ? Color.yellow : Color.yellow.opacity(0.3)))
                        .buttonStyle(.plain)
                    }
                    
                    Text(channel.volumeDBFormatted)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            
            // Remove button (visible on hover)
            if onRemove != nil {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(isHovered ? 0.8 : 0))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isHovered)
            }
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

// MARK: - Menu Master Row

struct MenuMasterRow: View {
    @ObservedObject var channel: AudioChannel
    var onRecordTapped: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Master icon
            Image(systemName: "speaker.wave.3.fill")
                .frame(width: 24, height: 24)
                .foregroundColor(FloColors.brand)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Master")
                    .font(.system(size: 11, weight: .semibold))
                
                HStack(spacing: 6) {
                    Slider(value: $channel.volume, in: 0...1.5)
                        .controlSize(.small)
                    
                    // M and R buttons
                    HStack(spacing: 3) {
                        // Mute - Green
                        Button {
                            channel.isMuted.toggle()
                        } label: {
                            Text("M")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(channel.isMuted ? Color.green : Color.green.opacity(0.3)))
                        .buttonStyle(.plain)
                        
                        // Record - Red
                        Button {
                            onRecordTapped()
                        } label: {
                            Text("R")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(channel.isRecording ? Color.red : Color.red.opacity(0.3)))
                        .buttonStyle(.plain)
                    }
                    
                    Text(channel.volumeDBFormatted)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            
            // Recording duration
            if channel.isRecording, let startTime = channel.recordingStartTime {
                MenuRecordingDurationView(startTime: startTime)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Menu Recording Duration View

struct MenuRecordingDurationView: View {
    let startTime: Date
    
    var body: some View {
        TimelineView(.periodic(from: startTime, by: 1.0)) { context in
            HStack(spacing: 2) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                Text(formattedDuration(at: context.date))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }
    
    private func formattedDuration(at date: Date) -> String {
        let elapsed = date.timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Menu Routing Popover

struct MenuRoutingPopover: View {
    @ObservedObject var channel: AudioChannel
    var allChannels: [AudioChannel]
    @State private var refreshTrigger = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Routing")
                .font(.headline)
                .padding(.bottom, 4)
            
            Text("\(channel.name)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Send to master toggle
            Toggle(isOn: Binding(
                get: { 
                    _ = refreshTrigger
                    return channel.routing.sendToMaster 
                },
                set: { newValue in
                    channel.routing.sendToMaster = newValue
                    channel.objectWillChange.send()
                    refreshTrigger.toggle()
                }
            )) {
                HStack {
                    Image(systemName: "speaker.wave.3.fill")
                        .frame(width: 16)
                    Text("Master Output")
                        .font(.system(size: 11))
                }
            }
            .toggleStyle(.checkbox)
            
            if !availableTargets.isEmpty {
                Divider()
                Text("Route to Apps:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(availableTargets) { target in
                    Toggle(isOn: Binding(
                        get: { 
                            _ = refreshTrigger  // Force refresh
                            // Check if both L and R are routed
                            return channel.routing.isRoutedTo(channelId: target.id, inputChannel: 0) &&
                                   channel.routing.isRoutedTo(channelId: target.id, inputChannel: 1)
                        },
                        set: { enabled in 
                            // Route both L and R channels
                            channel.routing.setRoute(to: target.id, inputChannel: 0, enabled: enabled)
                            channel.routing.setRoute(to: target.id, inputChannel: 1, enabled: enabled)
                            // If routing to an app, optionally turn off master
                            if enabled {
                                channel.routing.sendToMaster = false
                            }
                            // Trigger UI refresh
                            channel.objectWillChange.send()
                            refreshTrigger.toggle()
                        }
                    )) {
                        HStack {
                            if let icon = target.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(target.name)
                                .font(.system(size: 11))
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180)
    }
    
    private var availableTargets: [AudioChannel] {
        allChannels.filter { $0.id != channel.id && $0.channelType == .application }
    }
}

// MARK: - Menu Record Settings Sheet

struct MenuRecordSettingsSheet: View {
    @Binding var fileName: String
    @Binding var recordingPath: URL
    let onRecord: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Record Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("File Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Recording name", text: $fileName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Save Location")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(recordingPath.lastPathComponent)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                    
                    Button("Browse...") {
                        selectFolder()
                    }
                }
            }
            
            HStack {
                Text("Format: WAV (16-bit PCM)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Divider()
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Record") {
                    onRecord()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = recordingPath
        
        if panel.runModal() == .OK, let url = panel.url {
            recordingPath = url
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

// MARK: - Menu Add App Popover

struct MenuAddAppPopover: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Apps").tag(0)
                Text("Inputs").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(8)
            
            Divider()
            
            // Content
            ScrollView {
                LazyVStack(spacing: 4) {
                    if selectedTab == 0 {
                        // Available apps
                        ForEach(availableApps, id: \.processIdentifier) { app in
                            MenuAddAppRow(app: app) {
                                audioEngine.addManagedApp(from: app)
                            }
                        }
                        
                        if availableApps.isEmpty {
                            Text("No apps available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    } else {
                        // Available input devices
                        ForEach(audioEngine.inputDevices, id: \.id) { device in
                            MenuAddInputRow(device: device, isAdded: isInputAdded(device)) {
                                toggleInputDevice(device)
                            }
                        }
                        
                        if audioEngine.inputDevices.isEmpty {
                            Text("No input devices found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 250)
        }
        .frame(width: 220)
    }
    
    private var availableApps: [NSRunningApplication] {
        audioEngine.availableAppsToAdd()
    }
    
    private func isInputAdded(_ device: AudioDevice) -> Bool {
        audioEngine.channels.contains { $0.channelType == .inputDevice && $0.identifier == device.id }
    }
    
    private func toggleInputDevice(_ device: AudioDevice) {
        if isInputAdded(device) {
            if let channel = audioEngine.channels.first(where: { $0.channelType == .inputDevice && $0.identifier == device.id }) {
                audioEngine.removeChannel(channel)
            }
        } else {
            audioEngine.addInputChannel(device: device)
        }
    }
}

struct MenuAddAppRow: View {
    let app: NSRunningApplication
    let onAdd: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            onAdd()
        } label: {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 20, height: 20)
                        .foregroundColor(.secondary)
                }
                
                Text(app.localizedName ?? "Unknown")
                    .font(.system(size: 11))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(FloColors.accentGreen)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct MenuAddInputRow: View {
    let device: AudioDevice
    let isAdded: Bool
    let onToggle: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .frame(width: 20, height: 20)
                    .foregroundColor(isAdded ? FloColors.accentGreen : .secondary)
                
                Text(device.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundColor(isAdded ? FloColors.accentGreen : FloColors.accentGreen.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarPopoverView()
        .environmentObject(AudioEngine())
}

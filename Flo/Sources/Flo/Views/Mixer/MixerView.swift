//
//  MixerView.swift
//  Flo
//
//  Professional mixing console view
//

import SwiftUI

struct MixerView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @EnvironmentObject var midiService: MIDIService
    @EnvironmentObject var oscService: OSCService
    @EnvironmentObject var presetStore: PresetStore
    
    @State private var selectedChannelID: UUID?
    @State private var showingPreferences = false
    @State private var showingAddApp = false
    @State private var showingControlSettings = false
    @State private var showingSaveScene = false
    @State private var newSceneName = ""
    @State private var currentBank = 0
    @State private var channelsPerBank = 8
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            Divider()
            
            // Channel strips
            HStack(spacing: 2) {
                // App channels
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(visibleChannels) { channel in
                            ChannelStripView(
                                channel: channel,
                                isSelected: channel.id == selectedChannelID,
                                onRemove: {
                                    audioEngine.removeManagedApp(bundleID: channel.identifier)
                                },
                                availableTargets: audioEngine.channels.filter { $0.channelType == .application },
                                onRoutingChanged: { source, targetId, inputCh, enabled in
                                    audioEngine.setRouting(from: source, to: targetId, inputChannel: inputCh, enabled: enabled)
                                }
                            )
                            .onTapGesture {
                                selectedChannelID = channel.id
                            }
                        }
                        
                        // Add App button
                        AddAppButton {
                            showingAddApp = true
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                Divider()
                    .frame(height: 350)
                
                // EQ section (3-band)
                EQSectionView()
                
                Divider()
                    .frame(height: 350)
                
                // Master section
                if let master = audioEngine.masterChannel {
                    MasterSectionView(channel: master)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
            .background(FloColors.windowBackground)
            
            Divider()
            
            // Status bar
            statusBarView
        }
        .background(FloColors.windowBackground)
        .sheet(isPresented: $showingAddApp) {
            AddAppView()
                .environmentObject(audioEngine)
        }
        .sheet(isPresented: $showingSaveScene) {
            SaveSceneSheet(
                sceneName: $newSceneName,
                onSave: {
                    let scene = MixerScene(
                        name: newSceneName.isEmpty ? "Scene \(presetStore.scenes.count + 1)" : newSceneName,
                        index: presetStore.scenes.count,
                        channelStates: presetStore.captureCurrentState(from: audioEngine)
                    )
                    presetStore.saveScene(scene)
                    newSceneName = ""
                    showingSaveScene = false
                },
                onCancel: {
                    newSceneName = ""
                    showingSaveScene = false
                }
            )
        }
    }
    
    // MARK: - Visible Channels
    
    private var visibleChannels: [AudioChannel] {
        let appChannels = audioEngine.channels.filter { $0.channelType == .application }
        let startIndex = currentBank * channelsPerBank
        let endIndex = min(startIndex + channelsPerBank, appChannels.count)
        
        guard startIndex < appChannels.count else { return [] }
        return Array(appChannels[startIndex..<endIndex])
    }
    
    private var totalBanks: Int {
        let appCount = audioEngine.channels.filter { $0.channelType == .application }.count
        return max(1, Int(ceil(Double(appCount) / Double(channelsPerBank))))
    }
    
    // MARK: - Control Protocol Status
    
    private var controlProtocolLabel: String {
        if oscService.isRunning && midiService.isRunning {
            return "MIDI/OSC"
        } else if oscService.isRunning {
            return "OSC"
        } else {
            return "MIDI"
        }
    }
    
    private var controlProtocolStatus: Bool {
        midiService.isRunning || oscService.isRunning
    }
    
    // MARK: - Toolbar
    
    private static let logoImage: NSImage? = {
        // Try Bundle.module first (SPM resource bundle)
        if let bundleURL = Bundle.main.url(forResource: "Flo_Flo", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL),
           let logoPath = resourceBundle.path(forResource: "FloLogo", ofType: "png"),
           let image = NSImage(contentsOfFile: logoPath) {
            return image
        }
        
        // Also try looking in the same directory as the executable (SPM debug build)
        let executablePath = Bundle.main.executablePath ?? ""
        let execDir = (executablePath as NSString).deletingLastPathComponent
        let spmBundlePath = execDir + "/Flo_Flo.bundle/FloLogo.png"
        if let image = NSImage(contentsOfFile: spmBundlePath) {
            return image
        }
        
        // Try app bundle Resources folder
        let resourcesPath = (execDir as NSString).deletingLastPathComponent + "/Resources"
        let logoPath = resourcesPath + "/FloLogo.png"
        if let image = NSImage(contentsOfFile: logoPath) {
            return image
        }
        
        // Fallback: try Bundle.main.resourcePath
        if let resourcePath = Bundle.main.resourcePath {
            let fallbackPath = "\(resourcePath)/FloLogo.png"
            if let image = NSImage(contentsOfFile: fallbackPath) {
                return image
            }
        }
        
        return nil
    }()
    
    private var toolbarView: some View {
        HStack {
            // Logo
            if let logoImage = Self.logoImage {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(FloColors.brand)
            }
            
            Text("Flo")
                .font(.headline)
            
            Spacer()
            
            // Scene selector
            Menu {
                if presetStore.scenes.isEmpty {
                    Text("No scenes saved")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(presetStore.scenes) { scene in
                        Button {
                            Task {
                                await presetStore.recallScene(scene, to: audioEngine)
                            }
                        } label: {
                            HStack {
                                Text("Scene \(scene.index + 1): \(scene.name)")
                                if presetStore.currentScene?.id == scene.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Save Current as Scene...") {
                    showingSaveScene = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                    if let current = presetStore.currentScene {
                        Text(current.name)
                    } else {
                        Text("Scene")
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140)
            
            Divider()
                .frame(height: 20)
            
            // Bank navigation
            HStack(spacing: 4) {
                Button {
                    if currentBank > 0 {
                        currentBank -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentBank == 0)
                
                Text("Bank \(currentBank + 1)/\(totalBanks)")
                    .font(.caption)
                    .frame(width: 70)
                
                Button {
                    if currentBank < totalBanks - 1 {
                        currentBank += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentBank >= totalBanks - 1)
            }
            
            Spacer()
            
            // MIDI/OSC settings button
            Button {
                showingControlSettings = true
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(controlProtocolStatus ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(controlProtocolLabel)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingControlSettings) {
                ControlSettingsPopover()
                    .environmentObject(midiService)
                    .environmentObject(oscService)
            }
            
            Button {
                showingPreferences = true
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPreferences) {
                MixerSettingsPopoverView()
                    .environmentObject(audioEngine)
                    .environmentObject(midiService)
                    .environmentObject(oscService)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Status Bar
    
    private var statusBarView: some View {
        HStack {
            // MIDI status
            if !midiService.lastReceivedMessage.isEmpty {
                Text("MIDI: \(midiService.lastReceivedMessage)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Device info
            if let output = audioEngine.selectedOutputDevice {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption2)
                    Text(output.name)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            Text("•")
                .foregroundColor(.secondary)
            
            Text("\(Int(audioEngine.selectedOutputDevice?.sampleRate ?? 44100)) Hz")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Channel Strip View

struct ChannelStripView: View {
    @ObservedObject var channel: AudioChannel
    var isSelected: Bool = false
    var onRemove: (() -> Void)? = nil
    var availableTargets: [AudioChannel] = []  // Other channels that can receive audio
    var onRoutingChanged: ((AudioChannel, UUID, Int, Bool) -> Void)? = nil  // (source, targetId, inputCh, enabled)
    
    @State private var isHovering = false
    @State private var showRoutingPopover = false
    
    private var isInactive: Bool {
        channel.channelType == .application && !channel.isActive
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon and name with remove button - now clickable for routing
            channelHeader
                .zIndex(10)  // Keep header above fader
            
            // Per-channel 3-band EQ (where meters used to be)
            ChannelEQView(channel: channel)
                .opacity(isInactive ? 0.5 : 1.0)
                .allowsHitTesting(!isInactive)
                .zIndex(10)  // Keep EQ above fader
            
            Spacer()
                .frame(height: 12)  // Gap between EQ knobs and fader
            
            // Fader - lower z-index so it doesn't overlap EQ knobs
            FaderView(value: $channel.volume, maxValue: 1.0)
                .frame(height: FloDimensions.faderHeight + 40)
                .opacity(isInactive ? 0.5 : 1.0)
                .allowsHitTesting(!isInactive)
                .zIndex(1)
            
            // Volume display
            Text(channel.volumeDBFormatted)
                .font(FloTypography.volumeValue)
                .foregroundColor(isInactive ? FloColors.textTertiary : FloColors.textSecondary)
            
            // Pan knob (double-click to center)
            KnobView(value: $channel.pan, range: -1...1, defaultValue: 0)
                .frame(width: FloDimensions.knobDiameter, height: FloDimensions.knobDiameter)
                .opacity(isInactive ? 0.5 : 1.0)
                .allowsHitTesting(!isInactive)
            
            Text("Pan")
                .font(.system(size: 8))
                .foregroundColor(FloColors.textTertiary)
            
            // Mute/Solo buttons
            HStack(spacing: 4) {
                Button("M") {
                    channel.isMuted.toggle()
                }
                .buttonStyle(MuteButtonStyle(isActive: channel.isMuted))
                .disabled(isInactive)
                
                Button("S") {
                    channel.isSoloed.toggle()
                }
                .buttonStyle(SoloButtonStyle(isActive: channel.isSoloed))
                .disabled(isInactive)
            }
            .opacity(isInactive ? 0.5 : 1.0)
        }
        .padding(8)
        .channelStripStyle(isSelected: isSelected, isInactive: isInactive)
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(alignment: .topTrailing) {
            // Remove button on hover
            if isHovering && onRemove != nil {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
    }
    
    private var channelHeader: some View {
        VStack(spacing: 4) {
            // Clickable icon area for routing
            Button(action: {
                if channel.channelType == .application && !isInactive {
                    showRoutingPopover = true
                }
            }) {
                ZStack {
                    // Highlight when has active routes
                    if hasActiveRoutes {
                        Circle()
                            .fill(FloColors.accentGreen.opacity(0.2))
                            .frame(width: 34, height: 34)
                    }
                    
                    if let icon = channel.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                            .opacity(isInactive ? 0.5 : 1.0)
                            .saturation(isInactive ? 0.3 : 1.0)
                    } else {
                        Image(systemName: channel.channelType == .master ? "speaker.wave.3.fill" : "app.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isInactive ? FloColors.textTertiary : FloColors.textSecondary)
                    }
                    
                    // Inactive overlay badge
                    if isInactive {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .stroke(FloColors.channelBackground, lineWidth: 1)
                                    )
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    
                    // Routing indicator
                    if hasActiveRoutes && !isInactive {
                        VStack {
                            Spacer()
                            HStack {
                                Circle()
                                    .fill(FloColors.accentGreen)
                                    .frame(width: 6, height: 6)
                                Spacer()
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showRoutingPopover, arrowEdge: .bottom) {
                RoutingPopoverView(
                    sourceChannel: channel,
                    availableTargets: availableTargets.filter { $0.id != channel.id && $0.channelType == .application },
                    onRoutingChanged: { targetId, inputCh, enabled in
                        onRoutingChanged?(channel, targetId, inputCh, enabled)
                    }
                )
            }
            
            Text(channel.name)
                .font(FloTypography.channelName)
                .foregroundColor(isInactive ? FloColors.textTertiary : FloColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }
    
    private var hasActiveRoutes: Bool {
        !channel.routing.activeRoutes.isEmpty || !channel.routing.sendToMaster
    }
}

// MARK: - Routing Popover View (DAW-style Matrix)

struct RoutingPopoverView: View {
    @ObservedObject var sourceChannel: AudioChannel
    let availableTargets: [AudioChannel]
    let onRoutingChanged: (UUID, Int, Bool) -> Void  // (targetId, inputChannel, enabled)
    
    private let cellSize: CGFloat = 28
    private let headerHeight: CGFloat = 60
    private let rowHeight: CGFloat = 32
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with source info
            routingHeader
            
            Divider()
                .padding(.vertical, 8)
            
            // Matrix section
            if availableTargets.isEmpty {
                emptyState
            } else {
                matrixView
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Master output status (automatic based on routing)
            masterOutputStatus

            Divider()
                .padding(.vertical, 8)

            // Legend and help
            legendSection
        }
        .padding(16)
        .frame(width: max(380, CGFloat(maxDestinationInputs * 2 + 1) * cellSize + 180))
    }
    
    // MARK: - Header
    
    private var routingHeader: some View {
        HStack(spacing: 12) {
            // Source app icon
            if let icon = sourceChannel.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(FloColors.brand.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "app.fill")
                            .foregroundColor(FloColors.brand)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceChannel.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FloColors.textPrimary)
                
                HStack(spacing: 4) {
                    Text("ROUTING MATRIX")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(FloColors.brand)
                    
                    Text("•")
                        .foregroundColor(FloColors.textTertiary)
                    
                    Text("\(sourceChannel.outputChannelCount) outputs")
                        .font(.system(size: 9))
                        .foregroundColor(FloColors.textSecondary)
                }
            }
            
            Spacer()
            
            // Active routes badge
            if !sourceChannel.routing.activeRoutes.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(FloColors.accentGreen)
                        .frame(width: 6, height: 6)
                    Text("\(sourceChannel.routing.activeRoutes.count) active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(FloColors.accentGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FloColors.accentGreen.opacity(0.15))
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24))
                .foregroundColor(FloColors.textTertiary)
            Text("No other apps available for routing")
                .font(.caption)
                .foregroundColor(FloColors.textTertiary)
            Text("Add more apps to the mixer to route audio between them")
                .font(.system(size: 10))
                .foregroundColor(FloColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Matrix View
    
    private var matrixView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title
            HStack {
                Text("DESTINATIONS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(FloColors.textTertiary)
                
                Spacer()
                
                // Clear all button
                if !sourceChannel.routing.activeRoutes.isEmpty {
                    Button(action: clearAllRoutes) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 10))
                            Text("Clear All")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
            
            // Matrix grid
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 2) {
                    // Column headers (Source outputs)
                    matrixColumnHeaders
                    
                    // Each row is a destination app
                    ForEach(availableTargets) { target in
                        RoutingMatrixRow(
                            sourceChannel: sourceChannel,
                            targetChannel: target,
                            cellSize: cellSize,
                            onRoutingChanged: onRoutingChanged
                        )
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }
    
    // MARK: - Column Headers
    
    private var matrixColumnHeaders: some View {
        HStack(spacing: 2) {
            // Destination label column
            Text("TO ↓  FROM →")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(FloColors.textTertiary)
                .frame(width: 120, alignment: .leading)
            
            // Source output columns (Out L, Out R, etc.)
            ForEach(0..<sourceChannel.outputChannelCount, id: \.self) { outputIndex in
                Text(outputLabel(outputIndex))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(FloColors.brand)
                    .frame(width: cellSize, height: 20)
                    .background(FloColors.brand.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Spacer()
        }
        .padding(.bottom, 4)
    }
    
    // MARK: - Master Output Status (automatic based on routing)
    
    private var hasActiveRoutes: Bool {
        !sourceChannel.routing.activeRoutes.isEmpty
    }
    
    private var masterOutputStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: hasActiveRoutes ? "arrow.triangle.branch" : "speaker.wave.3.fill")
                .font(.system(size: 16))
                .foregroundColor(hasActiveRoutes ? FloColors.brand : FloColors.accentGreen)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(hasActiveRoutes ? "Routed to Apps" : "Direct to Master")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FloColors.textPrimary)
                
                Text(hasActiveRoutes ? "Audio goes through routed apps first" : "Audio goes directly to output")
                    .font(.system(size: 9))
                    .foregroundColor(FloColors.textTertiary)
            }
            
            Spacer()
            
            // Status indicator (not a toggle)
            Text(hasActiveRoutes ? "ROUTED" : "DIRECT")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(hasActiveRoutes ? FloColors.brand : FloColors.accentGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hasActiveRoutes ? FloColors.brand.opacity(0.15) : FloColors.accentGreen.opacity(0.15))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hasActiveRoutes ? FloColors.brand.opacity(0.05) : FloColors.accentGreen.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasActiveRoutes ? FloColors.brand.opacity(0.2) : FloColors.accentGreen.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Legend
    
    private var legendSection: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                MatrixCellButton(isActive: true, cellSize: 16, action: {})
                    .disabled(true)
                Text("Routed")
                    .font(.system(size: 9))
            }
            
            HStack(spacing: 6) {
                MatrixCellButton(isActive: false, cellSize: 16, action: {})
                    .disabled(true)
                Text("Not routed")
                    .font(.system(size: 9))
            }
            
            Spacer()
            
            Text("Click cells to toggle routes")
                .font(.system(size: 9))
                .foregroundColor(FloColors.textTertiary)
        }
        .foregroundColor(FloColors.textSecondary)
    }
    
    // MARK: - Helpers
    
    private var maxDestinationInputs: Int {
        availableTargets.map { $0.inputChannelCount }.max() ?? 2
    }
    
    private func outputLabel(_ index: Int) -> String {
        if sourceChannel.outputChannelCount == 2 {
            return index == 0 ? "L" : "R"
        }
        return "\(index + 1)"
    }
    
    private func clearAllRoutes() {
        for target in availableTargets {
            for inputIndex in 0..<target.inputChannelCount {
                sourceChannel.routing.setRoute(to: target.id, inputChannel: inputIndex, enabled: false)
                onRoutingChanged(target.id, inputIndex, false)
            }
        }
        sourceChannel.routing.objectWillChange.send()
    }
}

// MARK: - Routing Matrix Row

struct RoutingMatrixRow: View {
    @ObservedObject var sourceChannel: AudioChannel
    let targetChannel: AudioChannel
    let cellSize: CGFloat
    let onRoutingChanged: (UUID, Int, Bool) -> Void
    
    @State private var isExpanded = false
    
    private var hasAnyRoute: Bool {
        for inputIndex in 0..<targetChannel.inputChannelCount {
            if sourceChannel.routing.isRoutedTo(channelId: targetChannel.id, inputChannel: inputIndex) {
                return true
            }
        }
        return false
    }
    
    private var activeRouteCount: Int {
        var count = 0
        for inputIndex in 0..<targetChannel.inputChannelCount {
            if sourceChannel.routing.isRoutedTo(channelId: targetChannel.id, inputChannel: inputIndex) {
                count += 1
            }
        }
        return count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                // Destination app info
                HStack(spacing: 6) {
                    // App icon
                    if let icon = targetChannel.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(FloColors.textTertiary.opacity(0.3))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "app.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(FloColors.textTertiary)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(targetChannel.name)
                            .font(.system(size: 11, weight: hasAnyRoute ? .medium : .regular))
                            .foregroundColor(hasAnyRoute ? FloColors.textPrimary : FloColors.textSecondary)
                            .lineLimit(1)
                        
                        if hasAnyRoute {
                            Text("\(activeRouteCount) route\(activeRouteCount == 1 ? "" : "s")")
                                .font(.system(size: 8))
                                .foregroundColor(FloColors.accentGreen)
                        }
                    }
                }
                .frame(width: 120, alignment: .leading)
                
                // Matrix cells - one for each source output → this destination
                ForEach(0..<sourceChannel.outputChannelCount, id: \.self) { outputIndex in
                    // For now, route each output to corresponding input (1:1 mapping)
                    // Output 0 (L) → Input 0 (L), Output 1 (R) → Input 1 (R)
                    let inputIndex = min(outputIndex, targetChannel.inputChannelCount - 1)
                    let isActive = sourceChannel.routing.isRoutedTo(channelId: targetChannel.id, inputChannel: inputIndex)
                    
                    MatrixCellButton(isActive: isActive, cellSize: cellSize) {
                        let newState = !isActive
                        sourceChannel.routing.setRoute(to: targetChannel.id, inputChannel: inputIndex, enabled: newState)
                        sourceChannel.routing.objectWillChange.send()
                        onRoutingChanged(targetChannel.id, inputIndex, newState)
                    }
                }
                
                Spacer()
                
                // Quick actions
                HStack(spacing: 4) {
                    // Route all outputs to this destination
                    Button(action: {
                        let shouldEnable = !hasAnyRoute
                        for outputIndex in 0..<sourceChannel.outputChannelCount {
                            let inputIndex = min(outputIndex, targetChannel.inputChannelCount - 1)
                            sourceChannel.routing.setRoute(to: targetChannel.id, inputChannel: inputIndex, enabled: shouldEnable)
                            onRoutingChanged(targetChannel.id, inputIndex, shouldEnable)
                        }
                        sourceChannel.routing.objectWillChange.send()
                    }) {
                        Image(systemName: hasAnyRoute ? "xmark.circle" : "arrow.right.circle")
                            .font(.system(size: 12))
                            .foregroundColor(hasAnyRoute ? .red.opacity(0.7) : FloColors.accentGreen.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help(hasAnyRoute ? "Clear routes to this app" : "Route all to this app")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hasAnyRoute ? FloColors.accentGreen.opacity(0.08) : Color.clear)
            )
        }
    }
}

// MARK: - Matrix Cell Button

struct MatrixCellButton: View {
    let isActive: Bool
    let cellSize: CGFloat
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? FloColors.accentGreen : FloColors.channelBackground)
                
                // Border
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isActive ? FloColors.accentGreen : (isHovering ? FloColors.textTertiary : FloColors.channelBackground.opacity(0.5)),
                        lineWidth: 1
                    )
                
                // Checkmark for active state
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: cellSize * 0.4, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Hover indicator
                if isHovering && !isActive {
                    Circle()
                        .fill(FloColors.textTertiary.opacity(0.3))
                        .frame(width: cellSize * 0.3, height: cellSize * 0.3)
                }
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Add App Button

struct AddAppButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .foregroundColor(FloColors.textTertiary)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(FloColors.textTertiary)
                }
                .frame(width: 50, height: 50)
                
                Text("Add App")
                    .font(.caption)
                    .foregroundColor(FloColors.textTertiary)
            }
            .frame(width: FloDimensions.channelWidth)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Master Section View

struct MasterSectionView: View {
    @ObservedObject var channel: AudioChannel
    var isSelected: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(FloColors.brand)
            
            // Larger VU Meters
            HStack(spacing: 3) {
                VUMeterView(level: channel.peakLevelLeft)
                    .frame(width: 12)
                VUMeterView(level: channel.peakLevelRight)
                    .frame(width: 12)
            }
            .frame(height: 140)
            
            // Fader (master keeps boost range)
            FaderView(value: $channel.volume, maxValue: 1.5)
                .frame(height: FloDimensions.faderHeight + 20)
                .zIndex(1)  // Ensure fader stays below other elements
            
            // Volume display
            Text(channel.volumeDBFormatted)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(FloColors.textPrimary)
            
            // Mute button
            Button("M") {
                channel.isMuted.toggle()
            }
            .buttonStyle(MuteButtonStyle(isActive: channel.isMuted))
        }
        .padding(12)
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: FloDimensions.cornerRadius)
                .fill(isSelected ? FloColors.channelBackgroundSelected : FloColors.channelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FloDimensions.cornerRadius)
                        .stroke(isSelected ? FloColors.brand.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - EQ Section View

struct EQSectionView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 8) {
            Text("EQ")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(FloColors.brand)
            
            // High band (4 kHz+)
            VStack(spacing: 2) {
                EQKnobView(
                    value: $audioEngine.eqHighGain,
                    label: "HI",
                    color: .cyan
                )
                Text(formatGain(audioEngine.eqHighGain))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(FloColors.textSecondary)
            }
            
            // Mid band (250 Hz - 4 kHz)
            VStack(spacing: 2) {
                EQKnobView(
                    value: $audioEngine.eqMidGain,
                    label: "MID",
                    color: .yellow
                )
                Text(formatGain(audioEngine.eqMidGain))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(FloColors.textSecondary)
            }
            
            // Low band (<= 250 Hz)
            VStack(spacing: 2) {
                EQKnobView(
                    value: $audioEngine.eqLowGain,
                    label: "LO",
                    color: .orange
                )
                Text(formatGain(audioEngine.eqLowGain))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(FloColors.textSecondary)
            }
            
            Spacer()
            
            // Reset button
            Button("Reset") {
                withAnimation(.easeOut(duration: 0.2)) {
                    audioEngine.eqLowGain = 0
                    audioEngine.eqMidGain = 0
                    audioEngine.eqHighGain = 0
                }
            }
            .font(.system(size: 9))
            .buttonStyle(.plain)
            .foregroundColor(FloColors.textSecondary)
        }
        .padding(8)
        .frame(width: 60)
        .background(FloColors.channelBackground)
        .cornerRadius(FloDimensions.cornerRadius)
    }
    
    private func formatGain(_ gain: Float) -> String {
        if abs(gain) < 0.1 { return "0 dB" }
        let sign = gain > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", gain))"
    }
}

// MARK: - EQ Knob View

struct EQKnobView: View {
    @Binding var value: Float  // -12 to +12 dB
    var label: String
    var color: Color
    
    @State private var isDragging = false
    @State private var dragStartValue: Float = 0
    @State private var dragStartY: CGFloat = 0
    
    private let minValue: Float = -12
    private let maxValue: Float = 12
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(FloColors.textTertiary)
            
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                let normalizedValue = (value - minValue) / (maxValue - minValue)
                let rotation = -135 + Double(normalizedValue) * 270  // -135° to +135°
                
                ZStack {
                    // Knob background
                    Circle()
                        .fill(Color(white: 0.15))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    
                    // Value arc from center (0 dB) to current position
                    if abs(value) > 0.5 {
                        let centerTrim: CGFloat = 0.375  // Center position (0.75 * 0.5)
                        let currentTrim = CGFloat(normalizedValue) * 0.75
                        let fromTrim = min(centerTrim, currentTrim)
                        let toTrim = max(centerTrim, currentTrim)
                        
                        Circle()
                            .trim(from: fromTrim, to: toTrim)
                            .stroke(
                                color.opacity(isDragging ? 1.0 : 0.7),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(135))
                    }
                    
                    // Center line indicator
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: size * 0.3)
                        .offset(y: -size * 0.2)
                        .rotationEffect(.degrees(rotation))
                    
                    // Center dot (indicates zero position)
                    if abs(value) < 0.5 {
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(width: size, height: size)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .contentShape(Circle())
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.easeOut(duration: 0.15)) {
                                value = 0
                            }
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                dragStartValue = value
                                dragStartY = gesture.startLocation.y
                            }
                            
                            let deltaY = dragStartY - gesture.location.y
                            let sensitivity: Float = 0.15  // dB per point
                            let newValue = dragStartValue + Float(deltaY) * sensitivity
                            value = max(minValue, min(maxValue, newValue))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(width: 36, height: 36)
        }
    }
}

// MARK: - Channel EQ View (compact horizontal 3-band EQ for channel strips)

struct ChannelEQView: View {
    @ObservedObject var channel: AudioChannel
    
    var body: some View {
        VStack(spacing: 2) {
            // HI knob
            MiniEQKnob(value: $channel.eqHighGain, label: "H", color: .cyan)
            
            // MID knob
            MiniEQKnob(value: $channel.eqMidGain, label: "M", color: .yellow)
            
            // LO knob
            MiniEQKnob(value: $channel.eqLowGain, label: "L", color: .orange)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mini EQ Knob (compact version for channel strips)

struct MiniEQKnob: View {
    @Binding var value: Float  // -12 to +12 dB
    var label: String
    var color: Color
    
    @State private var isDragging = false
    @State private var dragStartValue: Float = 0
    @State private var dragStartY: CGFloat = 0
    
    private let minValue: Float = -12
    private let maxValue: Float = 12
    private let size: CGFloat = 24
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(FloColors.textTertiary)
                .frame(width: 10)
            
            ZStack {
                let normalizedValue = (value - minValue) / (maxValue - minValue)
                let rotation = -135 + Double(normalizedValue) * 270
                
                // Knob background
                Circle()
                    .fill(Color(white: 0.15))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                
                // Value arc from center (0 dB) to current position
                // Center is at normalized 0.5, which maps to 0.375 in trim space (0.75 * 0.5)
                // Arc goes from center to current value
                if abs(value) > 0.5 {
                    let centerTrim: CGFloat = 0.375  // 0.75 * 0.5 = center position
                    let currentTrim = CGFloat(normalizedValue) * 0.75
                    let fromTrim = min(centerTrim, currentTrim)
                    let toTrim = max(centerTrim, currentTrim)
                    
                    Circle()
                        .trim(from: fromTrim, to: toTrim)
                        .stroke(
                            color.opacity(0.7),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(135))
                }
                
                // Center line indicator
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 1.5, height: size * 0.3)
                    .offset(y: -size * 0.18)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(.easeOut(duration: 0.15)) {
                            value = 0
                        }
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                            dragStartY = gesture.startLocation.y
                        }
                        
                        let deltaY = dragStartY - gesture.location.y
                        let sensitivity: Float = 0.2
                        let newValue = dragStartValue + Float(deltaY) * sensitivity
                        value = max(minValue, min(maxValue, newValue))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}

// MARK: - VU Meter View

struct VUMeterView: View {
    var level: Float
    
    private let segments = 20
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(FloColors.meterBackground)
                
                // Level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(FloColors.meterGradient)
                    .frame(height: geometry.size.height * CGFloat(min(level, 1.0)))
                
                // Clip indicator
                if level > 1.0 {
                    Rectangle()
                        .fill(FloColors.meterClip)
                        .frame(height: 4)
                        .offset(y: -geometry.size.height + 4)
                }
            }
        }
        .frame(width: FloDimensions.meterWidth)
    }
}

// MARK: - Fader View

struct FaderView: View {
    @Binding var value: Float
    var maxValue: Float = 1.5  // 1.0 for app faders (no boost), 1.5 for master (with boost)
    
    @State private var isDragging = false
    @State private var dragStartValue: Float = 0
    @State private var dragStartY: CGFloat = 0
    
    private let trackWidth: CGFloat = 4
    
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let width = geometry.size.width
            let thumbPosition = height - (CGFloat(min(value / maxValue, 1.0)) * height)
            
            ZStack(alignment: .center) {
                // Track background - centered
                RoundedRectangle(cornerRadius: 2)
                    .fill(FloColors.faderTrack)
                    .frame(width: trackWidth, height: height)
                    .position(x: width / 2, y: height / 2)
                
                // Unity mark (0dB) - centered (only show if there's boost range)
                if maxValue > 1.0 {
                    let unityY = height - (CGFloat(1.0 / maxValue) * height)
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 20, height: 1)
                        .position(x: width / 2, y: unityY)
                }
                
                // Thumb - centered horizontally
                RoundedRectangle(cornerRadius: FloDimensions.faderThumbCornerRadius)
                    .fill(isDragging ? FloColors.faderCapActive : FloColors.faderCap)
                    .frame(width: FloDimensions.faderThumbWidth, height: FloDimensions.faderThumbHeight)
                    .shadow(color: FloShadows.subtle, radius: 2, y: 1)
                    .position(x: width / 2, y: thumbPosition)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Direct positioning - click/drag to move fader to that position
                        let newY = min(max(gesture.location.y, 0), height)
                        let newValue = Float(1.0 - newY / height) * maxValue
                        value = min(newValue, maxValue)  // Clamp to max
                        isDragging = true
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: FloDimensions.faderWidth)
    }
}

// MARK: - Knob View

struct KnobView: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var defaultValue: Float? = nil
    
    @State private var isDragging = false
    @State private var dragStartValue: Float = 0
    @State private var dragStartY: CGFloat = 0
    
    private var centerValue: Float {
        defaultValue ?? (range.lowerBound + range.upperBound) / 2
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let normalizedCenter = (centerValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let angle = Angle(degrees: Double(normalizedValue) * 270 - 135)
            
            ZStack {
                // Outer ring
                Circle()
                    .stroke(FloColors.textTertiary, lineWidth: 2)
                
                // Value arc from center to current position
                if abs(value - centerValue) > 0.01 {
                    let centerTrim = CGFloat(normalizedCenter) * 0.75
                    let currentTrim = CGFloat(normalizedValue) * 0.75
                    let fromTrim = min(centerTrim, currentTrim)
                    let toTrim = max(centerTrim, currentTrim)
                    
                    Circle()
                        .trim(from: fromTrim, to: toTrim)
                        .stroke(FloColors.brand, lineWidth: 2)
                        .rotationEffect(.degrees(135))
                }
                
                // Knob body - darker to make indicator visible
                Circle()
                    .fill(isDragging ? Color(white: 0.4) : Color(white: 0.25))
                    .padding(4)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                
                // Indicator line - bright white for visibility
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: size/4)
                    .offset(y: -size/6)
                    .rotationEffect(angle)
            }
            .contentShape(Circle())
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        // Double-click to reset to center/default value
                        withAnimation(.easeOut(duration: 0.15)) {
                            value = centerValue
                        }
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { gesture in
                        if !isDragging {
                            // Store initial state when drag begins
                            isDragging = true
                            dragStartValue = value
                            dragStartY = gesture.startLocation.y
                        }
                        // Calculate delta from drag start position
                        let delta = Float((dragStartY - gesture.location.y) / 100)
                        let newValue = min(max(dragStartValue + delta * (range.upperBound - range.lowerBound), range.lowerBound), range.upperBound)
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}

// MARK: - Control Settings Popover

struct ControlSettingsPopover: View {
    @EnvironmentObject var midiService: MIDIService
    @EnvironmentObject var oscService: OSCService
    
    @AppStorage("midiEnabled") private var midiEnabled = true
    @AppStorage("oscEnabled") private var oscEnabled = false
    @AppStorage("oscPort") private var oscPort = 9000
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Control Settings")
                .font(.headline)
            
            Divider()
            
            // MIDI Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "pianokeys")
                    Text("MIDI")
                        .font(.subheadline.bold())
                    Spacer()
                    Toggle("", isOn: $midiEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
                
                if midiEnabled {
                    HStack {
                        Circle()
                            .fill(midiService.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(midiService.isRunning ? "Connected" : "No devices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !midiService.inputDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Devices:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(midiService.inputDevices.prefix(3), id: \.displayName) { device in
                                Text("• \(device.displayName)")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // OSC Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "network")
                    Text("OSC")
                        .font(.subheadline.bold())
                    Spacer()
                    Toggle("", isOn: $oscEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
                
                if oscEnabled {
                    HStack {
                        Circle()
                            .fill(oscService.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(oscService.isRunning ? "Listening" : "Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Port:")
                            .font(.caption)
                        TextField("", value: $oscPort, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }
            }
            
            Divider()
            
            // Last message
            if !midiService.lastReceivedMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last MIDI:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(midiService.lastReceivedMessage)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
            }
            
            if !oscService.lastReceivedMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last OSC:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(oscService.lastReceivedMessage)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Save Scene Sheet

struct SaveSceneSheet: View {
    @Binding var sceneName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save Scene")
                .font(.headline)
            
            TextField("Scene Name", text: $sceneName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

// MARK: - Preview

#Preview {
    MixerView()
        .environmentObject(AudioEngine())
        .environmentObject(MIDIService())
        .environmentObject(OSCService())
        .environmentObject(PresetStore())
        .frame(width: 1000, height: 500)
}

//
//  MixerView.swift
//  Manatee
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
            .background(ManateeColors.windowBackground)
            
            Divider()
            
            // Status bar
            statusBarView
        }
        .background(ManateeColors.windowBackground)
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
        // Get the executable path and derive Resources path from it
        let executablePath = Bundle.main.executablePath ?? ""
        let appPath = (executablePath as NSString).deletingLastPathComponent
        let resourcesPath = (appPath as NSString).deletingLastPathComponent + "/Resources"
        let logoPath = resourcesPath + "/ManateeLogo.png"
        
        if let image = NSImage(contentsOfFile: logoPath) {
            return image
        }
        
        // Fallback: try Bundle.main.resourcePath
        if let resourcePath = Bundle.main.resourcePath {
            let fallbackPath = "\(resourcePath)/ManateeLogo.png"
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
                    .foregroundColor(ManateeColors.brand)
            }
            
            Text("Manatee")
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
    
    @State private var isHovering = false
    
    private var isInactive: Bool {
        channel.channelType == .application && !channel.isActive
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon and name with remove button
            channelHeader
            
            // Per-channel 3-band EQ (where meters used to be)
            ChannelEQView(channel: channel)
                .opacity(isInactive ? 0.5 : 1.0)
                .allowsHitTesting(!isInactive)
            
            // Fader
            FaderView(value: $channel.volume, maxValue: 1.0)
                .frame(height: ManateeDimensions.faderHeight + 40)
                .opacity(isInactive ? 0.5 : 1.0)
                .allowsHitTesting(!isInactive)
            
            // Volume display
            Text(channel.volumeDBFormatted)
                .font(ManateeTypography.volumeValue)
                .foregroundColor(isInactive ? ManateeColors.textTertiary : ManateeColors.textSecondary)
            
            // Pan knob (double-click to center)
            KnobView(value: $channel.pan, range: -1...1, defaultValue: 0)
                .frame(width: ManateeDimensions.knobDiameter, height: ManateeDimensions.knobDiameter)
                .opacity(isInactive ? 0.5 : 1.0)
                .allowsHitTesting(!isInactive)
            
            Text("Pan")
                .font(.system(size: 8))
                .foregroundColor(ManateeColors.textTertiary)
            
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
            ZStack {
                if let icon = channel.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .opacity(isInactive ? 0.5 : 1.0)
                        .saturation(isInactive ? 0.3 : 1.0)
                } else {
                    Image(systemName: channel.channelType == .master ? "speaker.wave.3.fill" : "app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isInactive ? ManateeColors.textTertiary : ManateeColors.textSecondary)
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
                                        .stroke(ManateeColors.channelBackground, lineWidth: 1)
                                )
                        }
                    }
                    .frame(width: 28, height: 28)
                }
            }
            
            Text(channel.name)
                .font(ManateeTypography.channelName)
                .foregroundColor(isInactive ? ManateeColors.textTertiary : ManateeColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
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
                        .foregroundColor(ManateeColors.textTertiary)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(ManateeColors.textTertiary)
                }
                .frame(width: 50, height: 50)
                
                Text("Add App")
                    .font(.caption)
                    .foregroundColor(ManateeColors.textTertiary)
            }
            .frame(width: ManateeDimensions.channelWidth)
            .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Master Section View

struct MasterSectionView: View {
    @ObservedObject var channel: AudioChannel
    
    var body: some View {
        VStack(spacing: 8) {
            Text("MASTER")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ManateeColors.brand)
            
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
                .frame(height: ManateeDimensions.faderHeight + 20)
            
            // Volume display
            Text(channel.volumeDBFormatted)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(ManateeColors.textPrimary)
            
            // Mute button
            Button("M") {
                channel.isMuted.toggle()
            }
            .buttonStyle(MuteButtonStyle(isActive: channel.isMuted))
        }
        .padding(12)
        .frame(width: 100)
        .background(ManateeColors.channelBackground)
        .cornerRadius(ManateeDimensions.cornerRadius)
    }
}

// MARK: - EQ Section View

struct EQSectionView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 8) {
            Text("EQ")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ManateeColors.brand)
            
            // High band (4 kHz+)
            VStack(spacing: 2) {
                EQKnobView(
                    value: $audioEngine.eqHighGain,
                    label: "HI",
                    color: .cyan
                )
                Text(formatGain(audioEngine.eqHighGain))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(ManateeColors.textSecondary)
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
                    .foregroundColor(ManateeColors.textSecondary)
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
                    .foregroundColor(ManateeColors.textSecondary)
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
            .foregroundColor(ManateeColors.textSecondary)
        }
        .padding(8)
        .frame(width: 60)
        .background(ManateeColors.channelBackground)
        .cornerRadius(ManateeDimensions.cornerRadius)
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
                .foregroundColor(ManateeColors.textTertiary)
            
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
                .foregroundColor(ManateeColors.textTertiary)
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
                    .fill(ManateeColors.meterBackground)
                
                // Level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(ManateeColors.meterGradient)
                    .frame(height: geometry.size.height * CGFloat(min(level, 1.0)))
                
                // Clip indicator
                if level > 1.0 {
                    Rectangle()
                        .fill(ManateeColors.meterClip)
                        .frame(height: 4)
                        .offset(y: -geometry.size.height + 4)
                }
            }
        }
        .frame(width: ManateeDimensions.meterWidth)
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
                    .fill(ManateeColors.faderTrack)
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
                RoundedRectangle(cornerRadius: ManateeDimensions.faderThumbCornerRadius)
                    .fill(isDragging ? ManateeColors.faderCapActive : ManateeColors.faderCap)
                    .frame(width: ManateeDimensions.faderThumbWidth, height: ManateeDimensions.faderThumbHeight)
                    .shadow(color: ManateeShadows.subtle, radius: 2, y: 1)
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
        .frame(width: ManateeDimensions.faderWidth)
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
                    .stroke(ManateeColors.textTertiary, lineWidth: 2)
                
                // Value arc from center to current position
                if abs(value - centerValue) > 0.01 {
                    let centerTrim = CGFloat(normalizedCenter) * 0.75
                    let currentTrim = CGFloat(normalizedValue) * 0.75
                    let fromTrim = min(centerTrim, currentTrim)
                    let toTrim = max(centerTrim, currentTrim)
                    
                    Circle()
                        .trim(from: fromTrim, to: toTrim)
                        .stroke(ManateeColors.brand, lineWidth: 2)
                        .rotationEffect(.degrees(135))
                }
                
                // Knob body
                Circle()
                    .fill(isDragging ? ManateeColors.faderCapActive : ManateeColors.faderCap)
                    .padding(4)
                
                // Indicator line
                Rectangle()
                    .fill(ManateeColors.textPrimary)
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

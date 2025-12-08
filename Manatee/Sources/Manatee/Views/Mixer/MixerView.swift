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
    
    @State private var selectedChannelID: UUID?
    @State private var showingPreferences = false
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
                                isSelected: channel.id == selectedChannelID
                            )
                            .onTapGesture {
                                selectedChannelID = channel.id
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
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
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack {
            // Logo
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(ManateeColors.brand)
            
            Text("Manatee")
                .font(.headline)
            
            Spacer()
            
            // Scene selector
            Menu {
                Button("Scene 1: Default") { }
                Button("Scene 2: Recording") { }
                Button("Scene 3: Streaming") { }
                Divider()
                Button("Save Scene...") { }
            } label: {
                Label("Scene", systemImage: "square.stack.3d.up")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 120)
            
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
            
            // MIDI indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(midiService.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("MIDI")
                    .font(.caption)
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
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon and name
            channelHeader
            
            // VU Meter
            HStack(spacing: 2) {
                VUMeterView(level: channel.peakLevelLeft)
                VUMeterView(level: channel.peakLevelRight)
            }
            .frame(height: 120)
            
            // Fader
            FaderView(value: $channel.volume)
                .frame(height: ManateeDimensions.faderHeight)
            
            // Volume display
            Text(channel.volumeDBFormatted)
                .font(ManateeTypography.volumeValue)
                .foregroundColor(ManateeColors.textSecondary)
            
            // Pan knob
            KnobView(value: $channel.pan, range: -1...1)
                .frame(width: ManateeDimensions.knobDiameter, height: ManateeDimensions.knobDiameter)
            
            Text("Pan")
                .font(.system(size: 8))
                .foregroundColor(ManateeColors.textTertiary)
            
            // Mute/Solo buttons
            HStack(spacing: 4) {
                Button("M") {
                    channel.isMuted.toggle()
                }
                .buttonStyle(MuteButtonStyle(isActive: channel.isMuted))
                
                Button("S") {
                    channel.isSoloed.toggle()
                }
                .buttonStyle(SoloButtonStyle(isActive: channel.isSoloed))
            }
        }
        .padding(8)
        .channelStripStyle(isSelected: isSelected)
    }
    
    private var channelHeader: some View {
        VStack(spacing: 4) {
            if let icon = channel.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: channel.channelType == .master ? "speaker.wave.3.fill" : "app.fill")
                    .font(.system(size: 20))
                    .foregroundColor(ManateeColors.textSecondary)
            }
            
            Text(channel.name)
                .font(ManateeTypography.channelName)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
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
            
            // Fader
            FaderView(value: $channel.volume)
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
    
    @State private var isDragging = false
    
    private let trackWidth: CGFloat = 4
    
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let thumbPosition = height - (CGFloat(min(value / 1.5, 1.0)) * height)
            
            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(ManateeColors.faderTrack)
                    .frame(width: trackWidth)
                
                // Unity mark (0dB)
                let unityY = height - (CGFloat(1.0 / 1.5) * height)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 20, height: 1)
                    .offset(y: unityY - height/2)
                
                // Thumb
                RoundedRectangle(cornerRadius: ManateeDimensions.faderThumbCornerRadius)
                    .fill(isDragging ? ManateeColors.faderCapActive : ManateeColors.faderCap)
                    .frame(width: ManateeDimensions.faderThumbWidth, height: ManateeDimensions.faderThumbHeight)
                    .shadow(color: ManateeShadows.subtle, radius: 2, y: 1)
                    .offset(y: thumbPosition - height/2)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDragging = true
                                let newY = min(max(gesture.location.y, 0), height)
                                let newValue = Float(1.0 - newY / height) * 1.5
                                value = newValue
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
            .frame(width: ManateeDimensions.faderWidth)
        }
    }
}

// MARK: - Knob View

struct KnobView: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    
    @State private var isDragging = false
    @State private var lastDragY: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let angle = Angle(degrees: Double(normalizedValue) * 270 - 135)
            
            ZStack {
                // Outer ring
                Circle()
                    .stroke(ManateeColors.textTertiary, lineWidth: 2)
                
                // Value arc
                Circle()
                    .trim(from: 0, to: CGFloat(normalizedValue) * 0.75)
                    .stroke(ManateeColors.brand, lineWidth: 2)
                    .rotationEffect(.degrees(135))
                
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
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        isDragging = true
                        let delta = Float((lastDragY - gesture.location.y) / 100)
                        let newValue = min(max(value + delta * (range.upperBound - range.lowerBound), range.lowerBound), range.upperBound)
                        value = newValue
                        lastDragY = gesture.location.y
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onAppear {
                lastDragY = geometry.size.height / 2
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MixerView()
        .environmentObject(AudioEngine())
        .environmentObject(MIDIService())
        .frame(width: 1000, height: 500)
}

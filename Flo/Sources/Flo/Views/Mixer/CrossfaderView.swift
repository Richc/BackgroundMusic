//
//  CrossfaderView.swift
//  Flo
//
//  Horizontal crossfader for mixing between two apps
//

import SwiftUI

struct CrossfaderView: View {
    @ObservedObject var crossfaderStore: CrossfaderStore
    @EnvironmentObject var audioEngine: AudioEngine
    
    @State private var showingLeftAppPicker = false
    @State private var showingRightAppPicker = false
    
    var body: some View {
        VStack(spacing: 4) {
            Text("XFADE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(FloColors.brand)
            
            // App icons row
            HStack {
                // Left app button
                appButton(
                    bundleID: crossfaderStore.leftAppBundleID,
                    side: "L",
                    showPicker: $showingLeftAppPicker
                )
                
                Spacer()
                
                // Right app button
                appButton(
                    bundleID: crossfaderStore.rightAppBundleID,
                    side: "R",
                    showPicker: $showingRightAppPicker
                )
            }
            
            // Fader track below icons - full width for maximum travel
            crossfaderSlider
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: FloDimensions.cornerRadius)
                .fill(FloColors.channelBackground)
        )
        .popover(isPresented: $showingLeftAppPicker) {
            appPickerPopover(forSide: .left)
        }
        .popover(isPresented: $showingRightAppPicker) {
            appPickerPopover(forSide: .right)
        }
        .onAppear {
            crossfaderStore.audioEngine = audioEngine
            crossfaderStore.recaptureVolumes()
        }
    }
    
    // MARK: - App Button
    
    private func appButton(bundleID: String?, side: String, showPicker: Binding<Bool>) -> some View {
        Button {
            showPicker.wrappedValue = true
        } label: {
            if let bundleID = bundleID,
               let channel = audioEngine.channels.first(where: { $0.identifier == bundleID }) {
                // Show app icon
                if let icon = channel.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .cornerRadius(3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FloColors.channelBackground)
                        )
                } else {
                    Text(String(channel.name.prefix(1)))
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(FloColors.brand.opacity(0.3))
                        .cornerRadius(3)
                }
            } else {
                // Show plus button
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(FloColors.faderTrack)
                    .cornerRadius(3)
            }
        }
        .buttonStyle(.plain)
        .help(bundleID != nil ? "Change \(side) app" : "Add app to \(side) side")
    }
    
    // MARK: - Crossfader Slider
    
    private var crossfaderSlider: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                // Track line (thin horizontal line spanning full width)
                Rectangle()
                    .fill(crossfaderStore.isOperational ? FloColors.faderTrack : FloColors.faderTrack.opacity(0.5))
                    .frame(height: 3)
                
                // Center tick mark
                Rectangle()
                    .fill(FloColors.brand.opacity(crossfaderStore.isOperational ? 0.6 : 0.2))
                    .frame(width: 2, height: 10)
                
                // Fader thumb (vertical line style)
                let thumbWidth: CGFloat = 6
                let trackWidth = geometry.size.width - thumbWidth
                let thumbX = ((CGFloat(crossfaderStore.position) + 1) / 2) * trackWidth + thumbWidth / 2
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(crossfaderStore.isOperational ? FloColors.brand : FloColors.brand.opacity(0.3))
                    .frame(width: thumbWidth, height: 16)
                    .position(x: thumbX, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard crossfaderStore.isOperational else { return }
                                let thumbWidth: CGFloat = 6
                                let trackWidth = geometry.size.width - thumbWidth
                                let normalizedX = (value.location.x - thumbWidth / 2) / trackWidth
                                let position = Float(normalizedX * 2 - 1)
                                crossfaderStore.setPosition(position)
                            }
                    )
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard crossfaderStore.isOperational else { return }
                    let thumbWidth: CGFloat = 6
                    let trackWidth: CGFloat = 84 - thumbWidth  // Approximate width
                    let normalizedX = (value.location.x - thumbWidth / 2) / trackWidth
                    let position = Float(normalizedX * 2 - 1)
                    crossfaderStore.setPosition(position)
                }
        )
        .help(crossfaderStore.isOperational ? "Drag to crossfade between apps" : "Add apps to both sides to enable")
    }
    
    // MARK: - App Picker Popover
    
    private enum Side {
        case left, right
    }
    
    private func appPickerPopover(forSide side: Side) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(side == .left ? "Left App" : "Right App")
                .font(.headline)
                .padding(.bottom, 4)
            
            // Get available app channels (excluding master and the other side's selection)
            let otherSideBundleID = side == .left ? crossfaderStore.rightAppBundleID : crossfaderStore.leftAppBundleID
            let appChannels = audioEngine.channels.filter { channel in
                channel.channelType == .application &&
                channel.identifier != otherSideBundleID
            }
            
            if appChannels.isEmpty {
                Text("No apps available")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(appChannels) { channel in
                            Button {
                                if side == .left {
                                    crossfaderStore.leftAppBundleID = channel.identifier
                                    showingLeftAppPicker = false
                                } else {
                                    crossfaderStore.rightAppBundleID = channel.identifier
                                    showingRightAppPicker = false
                                }
                            } label: {
                                HStack {
                                    if let icon = channel.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    }
                                    Text(channel.name)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            Divider()
            
            // Clear button if something is selected
            let currentBundleID = side == .left ? crossfaderStore.leftAppBundleID : crossfaderStore.rightAppBundleID
            if currentBundleID != nil {
                Button("Clear") {
                    if side == .left {
                        crossfaderStore.clearLeftApp()
                        showingLeftAppPicker = false
                    } else {
                        crossfaderStore.clearRightApp()
                        showingRightAppPicker = false
                    }
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 180)
    }
}

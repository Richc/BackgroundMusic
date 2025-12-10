//
//  MIDIMappingEditorView.swift
//  Manatee
//
//  MIDI Mapping Editor with MIDI Learn functionality
//

import SwiftUI

/// MIDI Mapping Editor View
/// Allows users to create MIDI mappings using MIDI Learn
struct MIDIMappingEditorView: View {
    @EnvironmentObject var midiService: MIDIService
    @EnvironmentObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCategory: MappableCategory = .master
    @State private var showingDeleteConfirmation = false
    @State private var mappingToDelete: MIDIMapping?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Left sidebar - Categories
                categorySidebar
                    .frame(width: 150)
                
                Divider()
                
                // Right content - Mappable controls
                controlsList
            }
            
            Divider()
            
            // Footer - MIDI activity monitor
            footerView
        }
        .frame(width: 700, height: 500)
        .alert("Delete Mapping?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let mapping = mappingToDelete {
                    midiService.removeMapping(mapping)
                }
            }
        } message: {
            Text("Are you sure you want to delete this MIDI mapping?")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("MIDI Mapping Editor")
                .font(.headline)
            
            Spacer()
            
            // MIDI status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(midiService.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(midiService.isRunning ? "MIDI Active" : "MIDI Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Done") {
                // Cancel any active learning
                if midiService.isLearning {
                    midiService.cancelLearning()
                }
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
    }
    
    // MARK: - Category Sidebar
    
    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CATEGORIES")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            ForEach(MappableCategory.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack {
                        Image(systemName: category.iconName)
                            .frame(width: 20)
                        Text(category.displayName)
                        Spacer()
                        Text("\(mappingCount(for: category))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedCategory == category ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Divider()
                .padding(.horizontal, 8)
            
            // Connected devices
            Text("MIDI DEVICES")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            if midiService.inputDevices.isEmpty {
                Text("No devices connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                ForEach(midiService.inputDevices, id: \.displayName) { device in
                    HStack {
                        Image(systemName: "pianokeys")
                            .frame(width: 20)
                        Text(device.displayName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Controls List
    
    private var controlsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Instructions
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Click \"Learn\" then move a control on your MIDI device to create a mapping")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            
            // Controls for selected category
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(mappableControls(for: selectedCategory), id: \.target) { control in
                        MappableControlRow(
                            control: control,
                            existingMapping: existingMapping(for: control.target),
                            onLearn: {
                                midiService.startLearning(for: control.target)
                            },
                            onDelete: {
                                if let mapping = existingMapping(for: control.target) {
                                    mappingToDelete = mapping
                                    showingDeleteConfirmation = true
                                }
                            }
                        )
                        .environmentObject(midiService)
                    }
                }
                .padding(8)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Learning indicator
            if midiService.isLearning, let target = midiService.learningTarget {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Waiting for MIDI input for: \(target.displayName)")
                        .font(.caption)
                    
                    Button("Cancel") {
                        midiService.cancelLearning()
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(6)
            } else {
                // Last MIDI message
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .foregroundColor(.secondary)
                    Text(midiService.lastReceivedMessage.isEmpty ? "No MIDI activity" : midiService.lastReceivedMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Mapping count
            Text("\(midiService.mappings.count) mappings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Helpers
    
    private func mappingCount(for category: MappableCategory) -> Int {
        let targets = mappableControls(for: category).map { $0.target }
        return midiService.mappings.filter { mapping in
            targets.contains(mapping.target)
        }.count
    }
    
    private func existingMapping(for target: ControlTarget) -> MIDIMapping? {
        midiService.mappings.first { $0.target == target }
    }
    
    private func mappableControls(for category: MappableCategory) -> [MappableControl] {
        switch category {
        case .master:
            return [
                MappableControl(target: .masterVolume, name: "Master Volume", icon: "speaker.wave.3"),
                MappableControl(target: .masterMute, name: "Master Mute", icon: "speaker.slash"),
                MappableControl(target: .eqLow, name: "EQ Low", icon: "dial.low"),
                MappableControl(target: .eqMid, name: "EQ Mid", icon: "dial.medium"),
                MappableControl(target: .eqHigh, name: "EQ High", icon: "dial.high"),
            ]
            
        case .apps:
            // Get running apps from AudioEngine
            return audioEngine.channels
                .filter { $0.channelType == .application }
                .flatMap { channel -> [MappableControl] in
                    let bundleID = channel.identifier
                    return [
                        MappableControl(target: .appVolume(bundleID: bundleID), name: "\(channel.name) Volume", icon: "app"),
                        MappableControl(target: .appMute(bundleID: bundleID), name: "\(channel.name) Mute", icon: "speaker.slash"),
                    ]
                }
            
        case .devices:
            // Get output devices
            return audioEngine.outputDevices.flatMap { device -> [MappableControl] in
                [
                    MappableControl(target: .deviceVolume(deviceUID: device.uid), name: "\(device.name) Volume", icon: "hifispeaker"),
                    MappableControl(target: .deviceMute(deviceUID: device.uid), name: "\(device.name) Mute", icon: "speaker.slash"),
                ]
            }
            
        case .navigation:
            return [
                MappableControl(target: .bankNext, name: "Next Bank", icon: "chevron.right"),
                MappableControl(target: .bankPrevious, name: "Previous Bank", icon: "chevron.left"),
            ]
            
        case .presets:
            // Could be populated from PresetStore
            return [
                MappableControl(target: .sceneRecall(index: 0), name: "Recall Scene 1", icon: "square.grid.2x2"),
                MappableControl(target: .sceneRecall(index: 1), name: "Recall Scene 2", icon: "square.grid.2x2"),
                MappableControl(target: .sceneRecall(index: 2), name: "Recall Scene 3", icon: "square.grid.2x2"),
                MappableControl(target: .sceneRecall(index: 3), name: "Recall Scene 4", icon: "square.grid.2x2"),
            ]
        }
    }
}

// MARK: - Supporting Types

/// Categories of mappable controls
enum MappableCategory: CaseIterable {
    case master
    case apps
    case devices
    case navigation
    case presets
    
    var displayName: String {
        switch self {
        case .master: return "Master"
        case .apps: return "Applications"
        case .devices: return "Devices"
        case .navigation: return "Navigation"
        case .presets: return "Presets"
        }
    }
    
    var iconName: String {
        switch self {
        case .master: return "slider.horizontal.3"
        case .apps: return "app.badge"
        case .devices: return "hifispeaker"
        case .navigation: return "arrow.left.arrow.right"
        case .presets: return "square.grid.2x2"
        }
    }
}

/// A control that can be mapped to MIDI
struct MappableControl {
    let target: ControlTarget
    let name: String
    let icon: String
}

// MARK: - Mappable Control Row

struct MappableControlRow: View {
    @EnvironmentObject var midiService: MIDIService
    
    let control: MappableControl
    let existingMapping: MIDIMapping?
    let onLearn: () -> Void
    let onDelete: () -> Void
    
    private var isLearningThis: Bool {
        midiService.isLearning && midiService.learningTarget == control.target
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Control icon
            Image(systemName: control.icon)
                .frame(width: 24)
                .foregroundColor(.secondary)
            
            // Control name
            VStack(alignment: .leading, spacing: 2) {
                Text(control.name)
                    .font(.system(size: 13))
                
                if let mapping = existingMapping {
                    Text(mappingDescription(mapping))
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Status/Actions
            if isLearningThis {
                // Currently learning this control
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Move a control...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(4)
            } else if existingMapping != nil {
                // Has mapping - show re-learn and delete
                HStack(spacing: 8) {
                    Button {
                        onLearn()
                    } label: {
                        Text("Re-Learn")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                // No mapping - show learn button
                Button {
                    onLearn()
                } label: {
                    Text("Learn")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(midiService.isLearning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isLearningThis ? Color.orange.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
    
    private func mappingDescription(_ mapping: MIDIMapping) -> String {
        var desc = "\(mapping.messageType.rawValue)"
        if let ch = mapping.channel {
            desc += " Ch\(ch + 1)"
        }
        desc += " #\(mapping.controlNumber)"
        if let device = mapping.sourceDeviceName {
            desc += " (\(device))"
        }
        return desc
    }
}

// MARK: - Preview

#Preview {
    MIDIMappingEditorView()
        .environmentObject(MIDIService())
        .environmentObject(AudioEngine())
}

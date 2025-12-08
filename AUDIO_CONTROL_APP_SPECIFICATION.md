# Manatee - macOS Audio Control Application Specification

## Executive Summary

**Application Name:** Manatee  
**Version:** 1.0.0  
**Platform:** macOS 13.0+ (Ventura and later)  
**Language:** Swift 6 with SwiftUI  
**License:** MIT  

Manatee is a native macOS application that provides comprehensive audio volume control, muting, routing, and DSP processing for all applications, input devices, and output devices. It features full plug-and-play support for USB MIDI controllers, OSC protocol, and professional mixing desk interfaces.

---

## Table of Contents

1. [Technology Stack & Justification](#1-technology-stack--justification)
2. [Architecture Overview](#2-architecture-overview)
3. [Core Features](#3-core-features)
4. [User Interface Design](#4-user-interface-design)
5. [MIDI & OSC Implementation](#5-midi--osc-implementation)
6. [Audio Engine Architecture](#6-audio-engine-architecture)
7. [BackgroundMusic Codebase Analysis](#7-backgroundmusic-codebase-analysis)
8. [Build Phases](#8-build-phases)
9. [Project Structure](#9-project-structure)
10. [Development Timeline](#10-development-timeline)
11. [Distribution & Packaging](#11-distribution--packaging)

---

## 1. Technology Stack & Justification

### Primary Language: Swift 6

**Rationale:**
- Native macOS development with best performance
- Swift 6 strict concurrency for audio thread safety
- Modern async/await patterns for UI responsiveness
- Excellent interoperability with Objective-C and C++ (required for CoreAudio)
- Apple's recommended language for all new macOS development

### UI Framework: SwiftUI with AppKit Integration

**Rationale:**
- SwiftUI provides modern, declarative UI development
- Native macOS look and feel with automatic dark mode support
- Built-in accessibility features
- AppKit integration for advanced controls (NSSlider subclasses, custom views)
- Menu bar (NSStatusBar) integration through AppKit

### Core Frameworks

| Framework | Purpose |
|-----------|---------|
| **CoreAudio** | Low-level audio device management, audio processing |
| **AudioToolbox** | Audio Unit hosting, DSP processing |
| **CoreMIDI** | MIDI device detection, message handling |
| **Network** | OSC UDP/TCP communication |
| **Combine** | Reactive data binding between audio engine and UI |
| **SwiftData** | Persistence for presets, device profiles, mappings |

### Third-Party Dependencies (Swift Package Manager)

| Package | Purpose | License |
|---------|---------|---------|
| **[MIDIKit](https://github.com/orchetect/MIDIKit)** | Modern CoreMIDI wrapper with MIDI 2.0 support | MIT |
| **[OSCKit](https://github.com/orchetect/OSCKit)** | Open Sound Control protocol implementation | MIT |
| **Swift Collections** | Advanced data structures for audio buffers | Apache 2.0 |
| **Swift Atomics** | Lock-free audio thread communication | Apache 2.0 |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Manatee Architecture                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│  │   SwiftUI   │   │   AppKit    │   │  Menu Bar   │   │  Floating   │   │
│  │   Views     │   │   Views     │   │    Item     │   │   Window    │   │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   │
│         │                  │                  │                  │         │
│         └──────────────────┴─────────┬────────┴──────────────────┘         │
│                                      │                                      │
│                           ┌──────────▼──────────┐                          │
│                           │   ViewModel Layer   │                          │
│                           │  (ObservableObject) │                          │
│                           └──────────┬──────────┘                          │
│                                      │                                      │
│    ┌─────────────────────────────────┼─────────────────────────────────┐   │
│    │                      Core Services Layer                            │   │
│    ├─────────────────────────────────┼─────────────────────────────────┤   │
│    │                                 │                                   │   │
│    │  ┌─────────────┐  ┌─────────────▼─────────────┐  ┌─────────────┐   │   │
│    │  │   MIDI      │  │      Audio Engine         │  │    OSC      │   │   │
│    │  │   Manager   │──│   (AudioDeviceManager)    │──│   Server    │   │   │
│    │  └──────┬──────┘  └─────────────┬─────────────┘  └──────┬──────┘   │   │
│    │         │                       │                        │          │   │
│    │  ┌──────▼──────┐  ┌─────────────▼─────────────┐  ┌──────▼──────┐   │   │
│    │  │  MIDIKit    │  │   Virtual Audio Driver    │  │   OSCKit    │   │   │
│    │  │  (CoreMIDI) │  │   (AudioServerPlugin)     │  │  (Network)  │   │   │
│    │  └─────────────┘  └───────────────────────────┘  └─────────────┘   │   │
│    └────────────────────────────────────────────────────────────────────┘   │
│                                                                           │
│    ┌────────────────────────────────────────────────────────────────────┐   │
│    │                      Persistence Layer                              │   │
│    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│    │  │   Presets   │  │   Device    │  │   MIDI      │                 │   │
│    │  │   Store     │  │   Profiles  │  │   Mappings  │                 │   │
│    │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│    └────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Design Patterns

1. **MVVM (Model-View-ViewModel)** - Clean separation between UI and business logic
2. **Dependency Injection** - Testable, modular components
3. **Observer Pattern** - Combine publishers for reactive updates
4. **Command Pattern** - MIDI/OSC actions mapped to audio controls
5. **Actor Model** - Swift actors for thread-safe audio state management

---

## 3. Core Features

### 3.1 Audio Control Features

| Feature | Description |
|---------|-------------|
| **Per-Application Volume** | Individual volume control for each running application |
| **Per-Session Volume** | Control volume for each audio session within an application |
| **Per-Device Volume** | Master volume control for input/output devices |
| **Mute Controls** | Per-app, per-session, and per-device muting |
| **Trim/Gain DSP** | -∞ to +12dB trim with soft-knee limiting |
| **Pan Control** | Stereo pan for stereo sources |
| **Audio Routing** | Route any source to any output device |
| **Input Device Monitoring** | Live input level monitoring with VU meters |

### 3.2 MIDI Control Features

| Feature | Description |
|---------|-------------|
| **USB MIDI Support** | Plug-and-play detection of USB MIDI controllers |
| **MIDI Learn** | Click any control, move a MIDI fader to assign |
| **CC Messages** | Control Change message mapping |
| **Note On/Off** | Map notes to mute toggles, scene recalls |
| **Program Change** | Preset/scene switching |
| **NRPN** | High-resolution 14-bit control support |
| **MIDI 2.0** | Full MIDI 2.0 UMP support where available |
| **MIDI Feedback** | LED ring updates, motorized fader feedback |
| **Device Profiles** | Pre-configured mappings for popular controllers |

### 3.3 OSC Control Features

| Feature | Description |
|---------|-------------|
| **UDP Server** | Receive OSC messages over UDP |
| **TCP Server** | Reliable OSC transmission over TCP |
| **Wireless Control** | Control from iOS/iPad apps, TouchOSC, etc. |
| **Bidirectional** | Send current state to OSC clients |
| **Custom Namespaces** | Configurable OSC address patterns |

### 3.4 Preset & Scene Management

| Feature | Description |
|---------|-------------|
| **Presets** | Save/recall complete mixer states |
| **Scenes** | Quick-switch between different configurations |
| **Multi-Page Buses** | Organize channels across pages/banks |
| **Device Profiles** | Controller-specific preset layouts |
| **Import/Export** | Share presets as JSON files |

---

## 4. User Interface Design

### 4.1 Design Philosophy

Following Apple's Human Interface Guidelines for macOS:

- **Native Look & Feel**: Use system colors, vibrancy, and window styles
- **Accessibility**: Full VoiceOver support, keyboard navigation
- **Dark Mode**: Complete dark/light mode support using semantic colors
- **Responsive**: Smooth 60fps animations, no UI blocking

### 4.2 Color Palette

```swift
// Design Tokens
enum DesignTokens {
    // Primary Colors (Audio-inspired)
    static let channelStrip = Color(hue: 0.58, saturation: 0.12, brightness: 0.22) // Dark blue-gray
    static let faderTrack = Color(hue: 0.0, saturation: 0.0, brightness: 0.15)     // Near black
    static let faderCap = Color(hue: 0.58, saturation: 0.08, brightness: 0.75)     // Light silver
    
    // Metering Colors
    static let meterGreen = Color(hue: 0.35, saturation: 0.85, brightness: 0.70)   // -∞ to -12dB
    static let meterYellow = Color(hue: 0.15, saturation: 0.90, brightness: 0.85)  // -12 to -6dB
    static let meterOrange = Color(hue: 0.08, saturation: 0.95, brightness: 0.90)  // -6 to -3dB
    static let meterRed = Color(hue: 0.0, saturation: 0.90, brightness: 0.85)      // -3 to 0dB
    static let meterClip = Color(hue: 0.0, saturation: 1.0, brightness: 1.0)       // Clipping
    
    // UI State Colors
    static let muteActive = Color.red.opacity(0.9)
    static let soloActive = Color.yellow.opacity(0.9)
    static let selectedChannel = Color.accentColor
    
    // Background using vibrancy
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
}
```

### 4.3 View Modes

#### 4.3.1 Simple View (Menu Bar Popover)

Compact interface accessible from the menu bar:

```
┌──────────────────────────────────────┐
│  🔊 Manatee                  ⚙️  ×   │
├──────────────────────────────────────┤
│  System Volume    ████████░░  75%    │
├──────────────────────────────────────┤
│  📱 Safari         ██████░░░░  60%   │
│  🎵 Spotify        ████████░░  80%   │
│  💬 Zoom           ████░░░░░░  40%   │
│  🎮 Steam          ██████░░░░  60%   │
├──────────────────────────────────────┤
│  Output: Built-in Speakers      ▾    │
│  Input:  MacBook Pro Mic        ▾    │
├──────────────────────────────────────┤
│  [ Show Mixer ]  [ Preferences ]     │
└──────────────────────────────────────┘
```

**Features:**
- Quick access to running apps with audio
- Slider + mute button per app
- Output/input device selection
- Link to full mixer view

#### 4.3.2 Mixer View (Professional Console)

Full-window mixing desk interface inspired by Logic Pro X and professional hardware consoles:

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  Manatee                                 Scene: Recording ▾  │ ⬜  ─  ×        │
├─────────────────────────────────────────────────────────────────────────────  ─┤
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐│
│  │  📱    │ │  🎵    │ │  💬    │ │  🎮    │ │  🎧    │ │ Master │ │ Output ││
│  │ Safari │ │Spotify │ │  Zoom  │ │ Steam  │ │ Music  │ │        │ │        ││
│  ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤│
│  │ ▓▓▓▓   │ │ ▓▓▓▓▓▓ │ │ ▓▓     │ │ ▓▓▓    │ │ ▓▓▓▓▓  │ │ ▓▓▓▓▓▓ │ │ ▓▓▓▓▓▓ ││
│  │ ▓▓▓▓   │ │ ▓▓▓▓▓▓ │ │ ▓▓     │ │ ▓▓▓    │ │ ▓▓▓▓▓  │ │ ▓▓▓▓▓▓ │ │ ▓▓▓▓▓▓ ││
│  │ [====] │ │ [====] │ │ [====] │ │ [====] │ │ [====] │ │ [====] │ │ [====] ││
│  │   ║    │ │   ║    │ │   ║    │ │   ║    │ │   ║    │ │   ║    │ │   ║    ││
│  │   ║    │ │   ║    │ │   ║    │ │   ║    │ │   ║    │ │   ║    │ │   ║    ││
│  │   ▼    │ │   ▼    │ │   ▼    │ │   ▼    │ │   ▼    │ │   ▼    │ │   ▼    ││
│  │   ●    │ │   ●    │ │   ●    │ │   ●    │ │   ●    │ │   ●    │ │   ●    ││
│  │  -6dB  │ │   0dB  │ │ -18dB  │ │ -12dB  │ │  -3dB  │ │   0dB  │ │   0dB  ││
│  ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤│
│  │ ◀●▶   │ │ ◀●▶   │ │ ◀●▶   │ │ ◀●▶   │ │ ◀●▶   │ │        │ │        ││
│  ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤│
│  │  Trim  │ │  Trim  │ │  Trim  │ │  Trim  │ │  Trim  │ │ Limit  │ │        ││
│  │ +0.0dB │ │ +3.0dB │ │ +0.0dB │ │ +0.0dB │ │ +6.0dB │ │ On/Off │ │        ││
│  ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤ ├────────┤│
│  │[M][S]  │ │[M][S]  │ │[M][S]  │ │[M][S]  │ │[M][S]  │ │[M]     │ │[M]     ││
│  │ Spkrs ▾│ │ Spkrs ▾│ │ Head ▾ │ │ Spkrs ▾│ │ Spkrs ▾│ │        │ │ Spkrs ▾││
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘│
├──────────────────────────────────────────────────────────────────────────────┤
│  Bank: 1/3  [◀ Prev] [Next ▶]  │  MIDI: Behringer X-Touch ●  │  OSC: ● 9000  │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Channel Strip Components:**
1. **Application Icon & Name** - Visual identification
2. **Stereo VU Meter** - Real-time level visualization
3. **Fader** - Vertical volume control (-∞ to +12dB)
4. **Pan Knob** - Stereo positioning
5. **Trim/Gain Knob** - Input gain adjustment
6. **Mute Button (M)** - Red when active
7. **Solo Button (S)** - Yellow when active (mutes all others)
8. **Output Routing** - Dropdown to select output device

**Master Section:**
- Master fader with stereo metering
- Limiter on/off
- Headroom indicator

### 4.4 Channel Strip Design Best Practices

Based on professional audio software (Logic Pro X, Ableton Live, Pro Tools):

1. **Vertical Fader Orientation** - Standard for mixing consoles
2. **60mm Minimum Fader Length** - Adequate resolution for touch/mouse control
3. **Logarithmic Scaling** - Natural audio perception (dB scale)
4. **Clear dB Markings** - 0dB, -6dB, -12dB, -18dB, -∞
5. **Meter Segmentation** - Distinct color zones for gain staging
6. **Touch-Sensitive Appearance** - Visual feedback on interaction
7. **Grouping** - Related channels can be linked

### 4.5 Preferences Window

```
┌──────────────────────────────────────────────────────────────────┐
│  Preferences                                               ─  ×  │
├──────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐                                                  │
│  │  General    │  ☑ Launch at login                              │
│  ├─────────────┤  ☑ Show in menu bar                             │
│  │  Audio      │  ☐ Start minimized                              │
│  ├─────────────┤  ───────────────────────────────                │
│  │  MIDI       │  Default view: [Simple ▾]                       │
│  ├─────────────┤                                                  │
│  │  OSC        │                                                  │
│  ├─────────────┤                                                  │
│  │  Presets    │                                                  │
│  ├─────────────┤                                                  │
│  │  Advanced   │                                                  │
│  └─────────────┘                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. MIDI & OSC Implementation

### 5.1 MIDI Architecture

```swift
// MIDI Manager using MIDIKit
@MainActor
final class MIDIManager: ObservableObject {
    let midiManager = MIDIKit.MIDIManager(
        clientName: "Manatee",
        model: "Manatee",
        manufacturer: "Developer"
    )
    
    @Published var connectedDevices: [MIDIDevice] = []
    @Published var mappings: [MIDIMapping] = []
    @Published var learningControl: AudioControl?
    
    // Device profiles for popular controllers
    var deviceProfiles: [String: DeviceProfile] = [
        "Behringer X-Touch Mini": .xTouchMini,
        "Novation Launch Control": .launchControl,
        "AKAI APC Mini": .apcMini,
        "Korg nanoKONTROL2": .nanoKontrol2,
        // ... more profiles
    ]
}

// MIDI Mapping Model
struct MIDIMapping: Codable, Identifiable {
    let id: UUID
    let midiMessage: MIDIMessageType
    let channel: UInt8
    let controlNumber: UInt8
    let targetControl: ControlTarget
    let behavior: MappingBehavior
    let range: ClosedRange<Float>
}

enum MIDIMessageType: Codable {
    case controlChange
    case noteOn
    case noteOff
    case programChange
    case nrpn
    case pitchBend
}

enum ControlTarget: Codable {
    case appVolume(bundleID: String)
    case appMute(bundleID: String)
    case appPan(bundleID: String)
    case deviceVolume(deviceUID: String)
    case masterVolume
    case masterMute
    case sceneRecall(sceneIndex: Int)
}
```

### 5.2 MIDI Learn Implementation

```swift
func startMIDILearn(for control: AudioControl) {
    learningControl = control
    // Visual indication: control pulses/highlights
    // Listen for next incoming MIDI message
}

func receivedMIDIMessage(_ message: MIDIEvent) {
    guard let control = learningControl else { return }
    
    let mapping = MIDIMapping(
        id: UUID(),
        midiMessage: message.type,
        channel: message.channel,
        controlNumber: message.controlNumber,
        targetControl: control.target,
        behavior: .absolute,
        range: 0...1
    )
    
    mappings.append(mapping)
    learningControl = nil
    saveMappings()
}
```

### 5.3 MIDI Feedback System

```swift
// Send feedback to controller (LED rings, motorized faders)
func sendMIDIFeedback(for control: ControlTarget, value: Float) {
    guard let mapping = mappings.first(where: { $0.targetControl == control }),
          let profile = currentDeviceProfile else { return }
    
    let feedbackValue = profile.translateValueToFeedback(value, for: mapping)
    
    switch profile.feedbackType {
    case .ledRing(segments: let segments):
        let segment = Int(value * Float(segments))
        sendCC(mapping.controlNumber + 0x20, value: UInt8(segment))
        
    case .motorizedFader:
        sendPitchBend(channel: mapping.channel, value: UInt16(value * 16383))
        
    case .buttonLED:
        sendNoteOn(mapping.controlNumber, velocity: value > 0.5 ? 127 : 0)
    }
}
```

### 5.4 OSC Implementation

```swift
// OSC Server using OSCKit
final class OSCServer: ObservableObject {
    let server = OSCUDPServer(port: 9000)
    let client = OSCUDPClient()
    
    @Published var isRunning = false
    @Published var connectedClients: [OSCClientInfo] = []
    
    // OSC Address Patterns
    // /app/{bundleID}/volume    -> Float 0.0-1.0
    // /app/{bundleID}/mute      -> Bool
    // /app/{bundleID}/pan       -> Float -1.0 to 1.0
    // /device/{uid}/volume      -> Float 0.0-1.0
    // /master/volume            -> Float 0.0-1.0
    // /scene/recall             -> Int index
    
    func handleMessage(_ message: OSCMessage) async {
        let components = message.addressPattern.split(separator: "/")
        
        switch components {
        case ["app", let bundleID, "volume"]:
            if let value = message.values.first as? Float {
                await audioEngine.setAppVolume(String(bundleID), volume: value)
            }
        case ["master", "volume"]:
            if let value = message.values.first as? Float {
                await audioEngine.setMasterVolume(value)
            }
        // ... more patterns
        }
    }
}
```

---

## 6. Audio Engine Architecture

### 6.1 Virtual Audio Device Driver

The application requires a virtual audio device driver (AudioServerPlugin) to intercept system audio. This is the same approach used by BackgroundMusic.

```
┌─────────────────────────────────────────────────────────────────┐
│                     macOS Audio System                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│   Applications                                                    │
│   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐               │
│   │ Safari  │ │ Spotify │ │  Zoom   │ │  Games  │               │
│   └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘               │
│        │           │           │           │                      │
│        └───────────┴─────┬─────┴───────────┘                      │
│                          │                                        │
│                          ▼                                        │
│              ┌───────────────────────┐                            │
│              │    Manatee Device     │  (AudioServerPlugin)       │
│              │  (Virtual Device)     │                            │
│              │                       │                            │
│              │  • Intercepts audio   │                            │
│              │  • Per-app volume     │                            │
│              │  • Applies DSP        │                            │
│              │  • Routes to output   │                            │
│              └───────────┬───────────┘                            │
│                          │                                        │
│                          ▼                                        │
│              ┌───────────────────────┐                            │
│              │   Output Device       │                            │
│              │  (Built-in Speakers,  │                            │
│              │   USB Audio, etc.)    │                            │
│              └───────────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Audio Processing Chain

```swift
// Per-channel audio processing
actor AudioChannel {
    var volume: Float = 1.0        // 0.0 to 1.0+ (with boost)
    var mute: Bool = false
    var pan: Float = 0.0           // -1.0 (L) to 1.0 (R)
    var trim: Float = 0.0          // dB, -12 to +12
    var solo: Bool = false
    
    func process(_ buffer: AudioBuffer) -> AudioBuffer {
        guard !mute else { return silentBuffer }
        
        var output = buffer
        
        // Apply trim (input gain)
        let trimLinear = pow(10, trim / 20)
        output.applyGain(trimLinear)
        
        // Apply volume
        output.applyGain(volume)
        
        // Apply pan (for stereo output)
        output.applyPan(pan)
        
        return output
    }
}
```

### 6.3 Real-Time Safety

Following BackgroundMusic's approach for real-time audio:

```swift
// Real-time safe operations only in audio callbacks
// - No memory allocation
// - No locks (use lock-free queues)
// - No system calls
// - O(1) operations only

final class LockFreeQueue<T> {
    // Ring buffer implementation for audio thread communication
}

// Use Swift Atomics for thread-safe flag updates
import Atomics

final class AudioProcessor {
    private let muted = ManagedAtomic<Bool>(false)
    private let volume = ManagedAtomic<UInt32>(0x3F800000) // Float bits for 1.0
    
    func setMute(_ value: Bool) {
        muted.store(value, ordering: .relaxed)
    }
    
    func getMute() -> Bool {
        muted.load(ordering: .relaxed)
    }
}
```

---

## 7. BackgroundMusic Codebase Analysis

### 7.1 Overview

The BackgroundMusic repository provides a fully functional implementation of:

1. **Virtual Audio Device Driver** (`BGMDriver`) - AudioServerPlugin implementation
2. **Application Volume Control** - Per-app volume adjustment
3. **Audio Passthrough** - Routes audio to real output device
4. **Menu Bar Interface** - Status bar item with volume controls

### 7.2 Reusable Components

| Component | Location | Reusability | Notes |
|-----------|----------|-------------|-------|
| **BGMDriver** | `/BGMDriver/` | ⭐⭐⭐⭐⭐ **High** | Core virtual audio device - essential foundation |
| **BGM_Device** | `/BGMDriver/BGMDriver/BGM_Device.cpp` | ⭐⭐⭐⭐⭐ **High** | Device property handling, IO operations |
| **BGM_Clients** | `/BGMDriver/BGMDriver/DeviceClients/` | ⭐⭐⭐⭐⭐ **High** | Per-client (per-app) audio tracking |
| **BGMPlayThrough** | `/BGMApp/BGMApp/BGMPlayThrough.cpp` | ⭐⭐⭐⭐ **High** | Audio routing to output device |
| **BGMAudioDevice** | `/BGMApp/BGMApp/BGMAudioDevice.cpp` | ⭐⭐⭐⭐ **High** | Audio device abstraction |
| **BGMAppVolumes** | `/BGMApp/BGMApp/BGMAppVolumes.m` | ⭐⭐⭐ **Medium** | UI for app volumes (needs modernization) |
| **BGMStatusBarItem** | `/BGMApp/BGMApp/BGMStatusBarItem.mm` | ⭐⭐ **Low** | Menu bar UI (replace with SwiftUI) |
| **PublicUtility** | `/BGMDriver/PublicUtility/` | ⭐⭐⭐⭐⭐ **High** | Apple's audio utility classes |

### 7.3 Recommendation

**YES - Use BackgroundMusic as the foundation**, specifically:

1. **Fork the BGMDriver** - The virtual audio device driver is the most complex and critical component. It's well-tested and handles macOS's AudioServerPlugin requirements correctly.

2. **Refactor for Modern Swift** - Replace the Objective-C/C++ BGMApp with a Swift/SwiftUI application that communicates with the driver.

3. **Keep These Files:**
   - All of `BGMDriver/` - The complete driver implementation
   - `BGMPlayThrough.cpp/h` - Audio passthrough logic
   - `BGMAudioDevice.cpp/h` - Device abstraction
   - `SharedSource/BGM_Types.h` - Type definitions
   - `PublicUtility/` - Apple's utility classes

4. **Replace These Components:**
   - All UI code → SwiftUI
   - `BGMStatusBarItem` → SwiftUI MenuBarExtra
   - `BGMAppVolumes` → Modern SwiftUI views
   - `BGMAppDelegate` → Swift App lifecycle

### 7.4 Integration Strategy

```swift
// Swift wrapper for the C++ audio device
final class ManateeDevice {
    private let device: BGMAudioDevice
    
    init() throws {
        device = try BGMAudioDevice(uid: kManateeDeviceUID)
    }
    
    func setAppVolume(_ bundleID: String, volume: Float) {
        // Call into BGM_Device's client volume system
        device.setClientVolume(bundleID, volume: volume)
    }
}

// Use bridging header for Objective-C++
// Manatee-Bridging-Header.h
#import "BGMAudioDevice.h"
#import "BGMPlayThrough.h"
```

---

## 8. Build Phases

### Phase 1: Foundation (Weeks 1-3)

| Task | Description | Priority |
|------|-------------|----------|
| 1.1 | Fork BackgroundMusic, rename to ManateeDriver | Critical |
| 1.2 | Create Swift/SwiftUI application project | Critical |
| 1.3 | Set up Swift Package Manager dependencies | Critical |
| 1.4 | Create bridging headers for C++/ObjC code | Critical |
| 1.5 | Implement basic driver communication | Critical |
| 1.6 | Create AudioDeviceManager Swift wrapper | Critical |

### Phase 2: Core Audio Features (Weeks 4-6)

| Task | Description | Priority |
|------|-------------|----------|
| 2.1 | Per-application volume control | Critical |
| 2.2 | Per-application mute functionality | Critical |
| 2.3 | Output device selection | Critical |
| 2.4 | Input device selection | High |
| 2.5 | Basic DSP (trim/gain) | High |
| 2.6 | Pan control implementation | Medium |

### Phase 3: User Interface (Weeks 7-10)

| Task | Description | Priority |
|------|-------------|----------|
| 3.1 | Menu bar status item | Critical |
| 3.2 | Simple view popover | Critical |
| 3.3 | Mixer view - channel strips | High |
| 3.4 | VU meters with real-time updates | High |
| 3.5 | Fader controls with smooth interaction | High |
| 3.6 | Knob controls (pan, trim) | Medium |
| 3.7 | Preferences window | Medium |

### Phase 4: MIDI Implementation (Weeks 11-13)

| Task | Description | Priority |
|------|-------------|----------|
| 4.1 | Integrate MIDIKit | Critical |
| 4.2 | Device detection and enumeration | Critical |
| 4.3 | Basic CC message handling | Critical |
| 4.4 | MIDI Learn functionality | High |
| 4.5 | Note/Program Change handling | High |
| 4.6 | MIDI feedback (LEDs, rings) | Medium |
| 4.7 | Device profiles for popular controllers | Medium |
| 4.8 | NRPN and MIDI 2.0 support | Low |

### Phase 5: OSC Implementation (Weeks 14-15)

| Task | Description | Priority |
|------|-------------|----------|
| 5.1 | Integrate OSCKit | High |
| 5.2 | UDP server implementation | High |
| 5.3 | OSC address namespace design | High |
| 5.4 | Bidirectional communication | Medium |
| 5.5 | TCP server option | Low |

### Phase 6: Presets & Scenes (Weeks 16-17)

| Task | Description | Priority |
|------|-------------|----------|
| 6.1 | SwiftData model for presets | High |
| 6.2 | Preset save/recall UI | High |
| 6.3 | Scene management | Medium |
| 6.4 | Multi-page bus organization | Medium |
| 6.5 | Import/export functionality | Low |

### Phase 7: Polish & Distribution (Weeks 18-20)

| Task | Description | Priority |
|------|-------------|----------|
| 7.1 | App icon and branding | High |
| 7.2 | Installer package creation | Critical |
| 7.3 | Code signing and notarization | Critical |
| 7.4 | Documentation and help | Medium |
| 7.5 | Performance optimization | High |
| 7.6 | Accessibility audit | Medium |
| 7.7 | Beta testing | High |

---

## 9. Project Structure

```
Manatee/
├── Manatee.xcworkspace
├── Package.swift                      # Swift Package dependencies
├── README.md
├── LICENSE
│
├── Manatee/                           # Main Application
│   ├── App/
│   │   ├── ManateeApp.swift           # @main entry point
│   │   └── AppDelegate.swift          # NSApplicationDelegate
│   │
│   ├── Views/
│   │   ├── MenuBar/
│   │   │   ├── MenuBarManager.swift
│   │   │   └── SimpleVolumePopover.swift
│   │   │
│   │   ├── Mixer/
│   │   │   ├── MixerWindow.swift
│   │   │   ├── ChannelStripView.swift
│   │   │   ├── FaderControl.swift
│   │   │   ├── KnobControl.swift
│   │   │   ├── VUMeterView.swift
│   │   │   └── MasterSection.swift
│   │   │
│   │   ├── Preferences/
│   │   │   ├── PreferencesWindow.swift
│   │   │   ├── GeneralPreferences.swift
│   │   │   ├── AudioPreferences.swift
│   │   │   ├── MIDIPreferences.swift
│   │   │   └── OSCPreferences.swift
│   │   │
│   │   └── Common/
│   │       ├── DesignTokens.swift
│   │       └── CustomControls.swift
│   │
│   ├── ViewModels/
│   │   ├── MixerViewModel.swift
│   │   ├── ChannelViewModel.swift
│   │   ├── MIDIViewModel.swift
│   │   └── OSCViewModel.swift
│   │
│   ├── Models/
│   │   ├── AudioChannel.swift
│   │   ├── AudioDevice.swift
│   │   ├── Preset.swift
│   │   ├── Scene.swift
│   │   ├── MIDIMapping.swift
│   │   └── DeviceProfile.swift
│   │
│   ├── Services/
│   │   ├── Audio/
│   │   │   ├── AudioEngine.swift
│   │   │   ├── AudioDeviceManager.swift
│   │   │   └── AppVolumeController.swift
│   │   │
│   │   ├── MIDI/
│   │   │   ├── MIDIService.swift
│   │   │   ├── MIDILearnManager.swift
│   │   │   └── MIDIFeedbackManager.swift
│   │   │
│   │   ├── OSC/
│   │   │   ├── OSCService.swift
│   │   │   └── OSCAddressRouter.swift
│   │   │
│   │   └── Persistence/
│   │       ├── PresetStore.swift
│   │       └── SettingsManager.swift
│   │
│   ├── Bridging/
│   │   ├── Manatee-Bridging-Header.h
│   │   └── AudioDeviceWrapper.swift
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── DeviceProfiles/           # JSON controller profiles
│   │   └── Localizable.strings
│   │
│   └── Info.plist
│
├── ManateeDriver/                     # Virtual Audio Device
│   ├── ManateeDriver.xcodeproj
│   ├── Driver/
│   │   ├── AMX_Device.cpp            # Based on BGM_Device
│   │   ├── AMX_Device.h
│   │   ├── AMX_PlugIn.cpp
│   │   ├── AMX_PlugIn.h
│   │   ├── AMX_PlugInInterface.cpp
│   │   ├── AMX_Stream.cpp
│   │   ├── AMX_VolumeControl.cpp
│   │   ├── AMX_MuteControl.cpp
│   │   ├── AMX_Clients.cpp           # Per-app audio tracking
│   │   └── Info.plist
│   │
│   └── PublicUtility/                # Apple utility classes
│       ├── CAMutex.h
│       ├── CARingBuffer.h
│       └── ...
│
├── SharedSource/
│   ├── AMX_Types.h                   # Shared type definitions
│   └── AMX_Constants.h
│
├── Installer/
│   ├── scripts/
│   │   ├── preinstall
│   │   └── postinstall
│   ├── Distribution.xml
│   └── build_installer.sh
│
└── Tests/
    ├── ManateeTests/
    └── ManateeDriverTests/
```

---

## 10. Development Timeline

```
Week 1-3   [████████████████████] Phase 1: Foundation
Week 4-6   [████████████████████] Phase 2: Core Audio
Week 7-10  [████████████████████████████] Phase 3: UI
Week 11-13 [████████████████████] Phase 4: MIDI
Week 14-15 [████████████] Phase 5: OSC
Week 16-17 [████████████] Phase 6: Presets
Week 18-20 [████████████████████] Phase 7: Polish

Total: ~20 weeks (5 months)
```

### Milestones

| Milestone | Target | Deliverable |
|-----------|--------|-------------|
| **Alpha 1** | Week 6 | Basic app volume control working |
| **Alpha 2** | Week 10 | Full mixer UI functional |
| **Beta 1** | Week 15 | MIDI and OSC working |
| **Beta 2** | Week 17 | Presets functional |
| **RC 1** | Week 19 | Feature complete |
| **Release** | Week 20 | Signed, notarized installer |

---

## 11. Distribution & Packaging

### 11.1 App Bundle Structure

```
Manatee.app/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── Manatee                   # Main executable
│   ├── Resources/
│   │   ├── Assets.car
│   │   ├── DeviceProfiles/
│   │   ├── ManateeDriver.driver/    # Embedded driver
│   │   ├── install_driver.sh
│   │   └── uninstall_driver.sh
│   ├── Frameworks/
│   │   └── (embedded frameworks)
│   └── _CodeSignature/
```

### 11.2 Installer Package

```bash
# Build installer package
pkgbuild --root ./build/Release \
         --scripts ./Installer/scripts \
         --identifier com.developer.manatee.pkg \
         --version 1.0.0 \
         Manatee.pkg

# Create distribution package
productbuild --distribution ./Installer/Distribution.xml \
             --package-path . \
             --resources ./Installer/Resources \
             Manatee-1.0.0.pkg
```

### 11.3 Code Signing Requirements

```bash
# Sign the driver
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         --entitlements ManateeDriver.entitlements \
         ManateeDriver.driver

# Sign the app
codesign --sign "Developer ID Application: Your Name" \
         --options runtime \
         --entitlements Manatee.entitlements \
         --deep \
         "Manatee.app"

# Notarize
xcrun notarytool submit Manatee-1.0.0.pkg \
      --apple-id "you@email.com" \
      --password "@keychain:AC_PASSWORD" \
      --team-id TEAMID \
      --wait
```

### 11.4 Entitlements

```xml
<!-- Manatee.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>  <!-- Required for audio driver interaction -->
    
    <key>com.apple.security.device.audio-input</key>
    <true/>
    
    <key>com.apple.security.device.usb</key>
    <true/>  <!-- For USB MIDI -->
    
    <key>com.apple.security.network.server</key>
    <true/>  <!-- For OSC -->
    
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

---

## 12. Summary & Recommendations

### Key Decisions

1. **Language**: Swift 6 with SwiftUI - Most modern, best Apple integration
2. **Driver**: Fork BackgroundMusic's BGMDriver - Proven, stable foundation
3. **MIDI**: MIDIKit - Modern Swift CoreMIDI wrapper with MIDI 2.0
4. **OSC**: OSCKit - Same author as MIDIKit, excellent Swift integration
5. **UI Framework**: SwiftUI + AppKit hybrid for custom controls
6. **Persistence**: SwiftData for presets and mappings

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Driver complexity | Use proven BGMDriver code as base |
| Real-time audio bugs | Follow BackgroundMusic's patterns, extensive testing |
| macOS API changes | Target specific macOS versions, test on betas |
| MIDI device compatibility | Comprehensive device profiles, MIDI Learn fallback |

### Success Criteria

- [ ] Stable audio passthrough with no glitches
- [ ] Per-app volume works for all applications
- [ ] MIDI Learn works with any USB controller
- [ ] OSC receives commands over network
- [ ] Professional mixer UI at 60fps
- [ ] Signed, notarized installer works on clean macOS

---

*Document Version: 1.0*  
*Last Updated: December 2024*  
*Author: Manatee Development Team*

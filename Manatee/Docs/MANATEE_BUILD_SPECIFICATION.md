# Manatee Audio Mixer - Complete Build Specification

**From Empty Repository to Full Application**

This specification describes how to build Manatee, a professional macOS audio mixer with per-app volume control, EQ, and inter-app audio routing, entirely from scratch.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Overview](#2-architecture-overview)
3. [Phase 1: Core Audio HAL Driver](#3-phase-1-core-audio-hal-driver)
4. [Phase 2: Swift Application Foundation](#4-phase-2-swift-application-foundation)
5. [Phase 3: Audio Engine & Driver Bridge](#5-phase-3-audio-engine--driver-bridge)
6. [Phase 4: User Interface](#6-phase-4-user-interface)
7. [Phase 5: Inter-App Audio Routing](#7-phase-5-inter-app-audio-routing)
8. [Phase 6: Advanced Features](#8-phase-6-advanced-features)
9. [Build & Installation](#9-build--installation)

---

## 1. Project Overview

### What Manatee Does

Manatee is a macOS menu bar application that provides:

- **Per-application volume control** - Individual volume faders for each running app
- **Per-application 3-band EQ** - Low/Mid/High frequency adjustment per app
- **Per-application pan** - Stereo positioning per app
- **Inter-app audio routing** - Route audio from one app into another (e.g., music into Discord)
- **Master volume with global EQ** - Overall system volume and EQ
- **Mute/Solo functionality** - DAW-style channel controls
- **MIDI controller support** - Map physical controls to app volumes

### Technology Stack

| Component | Technology |
|-----------|------------|
| Virtual Audio Driver | C++ CoreAudio HAL Plugin |
| Application | Swift 5.9+ / SwiftUI |
| Driver Bridge | Objective-C++ |
| Build System | Swift Package Manager + Xcode |
| Target OS | macOS 13.0+ (Ventura and later) |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Manatee.app (Swift/SwiftUI)              │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │   MixerView  │  │ AudioEngine  │  │   BGMDeviceBridge.mm   │ │
│  │   (SwiftUI)  │◄─┤   (Swift)    │◄─┤   (Obj-C++ Bridge)     │ │
│  └──────────────┘  └──────────────┘  └───────────┬────────────┘ │
└───────────────────────────────────────────────────┼─────────────┘
                                                    │ HAL Properties
                                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              Manatee Audio Driver (C++ HAL Plugin)              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ BGM_Device  │  │ BGM_Clients │  │  Audio Processing       │  │
│  │ (HAL API)   │◄─┤ (Per-app)   │◄─┤  - Volume/Pan/EQ        │  │
│  └─────────────┘  └─────────────┘  │  - Routing buffers      │  │
│                                    └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                         ┌─────────────────────┐
                         │  Physical Output    │
                         │  (Speakers/DAC)     │
                         └─────────────────────┘
```

### Data Flow

1. **Apps** → Output audio to "Manatee Device" (virtual driver)
2. **Driver** → Tracks which client (app) owns each audio stream
3. **Driver** → Applies per-client volume, pan, EQ, stores in routing buffers
4. **Driver** → Mixes all clients + routed audio → sends to real output
5. **Swift App** → Reads client list, sets properties via HAL API
6. **UI** → Displays faders, responds to user input

---

## 3. Phase 1: Core Audio HAL Driver

### 3.1 Driver Structure

Create an AudioServerPlugIn (HAL plugin) that appears as a virtual audio device.

```
ManateeDriver/
├── ManateeDriver.xcodeproj
├── Info.plist
└── Source/
    ├── Manatee_PlugIn.cpp       # Plugin entry point
    ├── Manatee_Device.cpp       # Main device implementation
    ├── Manatee_Device.h
    ├── Manatee_Stream.cpp       # Audio streams
    ├── Manatee_Stream.h
    ├── Manatee_Clients.cpp      # Per-app client tracking
    ├── Manatee_Clients.h
    ├── Manatee_Client.cpp       # Individual client data
    ├── Manatee_Client.h
    └── Manatee_Types.h          # Shared types and constants
```

### 3.2 Key Driver Components

#### 3.2.1 Plugin Entry Point

```cpp
// Manatee_PlugIn.cpp
extern "C" void* Manatee_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    // Return AudioServerPlugInDriverInterface
    // This is called by coreaudiod when driver loads
}
```

#### 3.2.2 Device Implementation

The device must implement these HAL operations:

| Operation | Purpose |
|-----------|---------|
| `Initialize` | Set up device, create streams |
| `CreateDevice` | Return device object ID |
| `HasProperty` | Report which properties exist |
| `GetPropertyData` | Return property values |
| `SetPropertyData` | Accept property changes |
| `StartIO` | Begin audio processing |
| `StopIO` | End audio processing |
| `DoIOOperation` | Process audio buffers |

#### 3.2.3 Custom HAL Properties

Define custom properties for per-app control:

```cpp
// Manatee_Types.h
enum {
    // Per-app volume: expects CFDictionary with bundleID, pid, volume
    kAudioDeviceCustomPropertyAppVolume = 'apvl',
    
    // Per-app pan: expects CFDictionary with bundleID, pid, pan
    kAudioDeviceCustomPropertyAppPan = 'appn',
    
    // Per-app EQ: expects CFDictionary with bundleID, pid, lowDB, midDB, highDB  
    kAudioDeviceCustomPropertyAppEQ = 'apeq',
    
    // Get list of all clients: returns CFArray of CFDictionary
    kAudioDeviceCustomPropertyClientList = 'clst',
    
    // Inter-app routing: expects CFDictionary with sourcePID, destPID, gain, enabled
    kAudioDeviceCustomPropertyAppRouting = 'aprt',
};

// Dictionary keys
#define kManateeClientKey_BundleID    "bundleID"
#define kManateeClientKey_PID         "pid"
#define kManateeClientKey_Volume      "volume"
#define kManateeClientKey_Pan         "pan"
#define kManateeClientKey_EQLow       "eqLow"
#define kManateeClientKey_EQMid       "eqMid"
#define kManateeClientKey_EQHigh      "eqHigh"
```

#### 3.2.4 Client Tracking

Track each app that outputs audio:

```cpp
// Manatee_Client.h
struct Manatee_Client {
    pid_t           mClientPID;
    CFStringRef     mBundleID;
    
    // Per-client audio settings
    Float32         mVolume;          // 0.0 - 1.0
    Float32         mPan;             // -1.0 (L) to +1.0 (R)
    bool            mMuted;
    
    // 3-band EQ (in dB, -12 to +12)
    Float32         mEQLowGain;
    Float32         mEQMidGain;
    Float32         mEQHighGain;
    
    // Biquad filter state for EQ
    struct BiquadState {
        Float64 x1, x2, y1, y2;
    };
    BiquadState     mLowFilterState[2];   // Stereo
    BiquadState     mMidFilterState[2];
    BiquadState     mHighFilterState[2];
    
    // Routing buffer (for inter-app routing)
    Float32*        mRoutingBuffer;       // Circular buffer
    UInt32          mRoutingBufferSize;
    std::atomic<UInt32> mRoutingWritePos;
};
```

#### 3.2.5 Audio Processing (DoIOOperation)

```cpp
void Manatee_Device::DoIOOperation(
    AudioObjectID inDevice,
    AudioObjectID inStream,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    AudioServerPlugInIOCycleInfo& ioCycleInfo,
    void* ioMainBuffer,
    void* ioSecondaryBuffer)
{
    if (inOperationID == kAudioServerPlugInIOOperationWriteMix) {
        // Get client for this audio
        Manatee_Client* client = mClients.GetClientByPID(inClientID);
        if (!client) return;
        
        Float32* buffer = (Float32*)ioMainBuffer;
        UInt32 frameCount = inIOBufferFrameSize;
        
        // 1. Store pre-volume audio in routing buffer (for inter-app routing)
        client->StoreToRoutingBuffer(buffer, frameCount);
        
        // 2. Apply 3-band EQ
        ApplyEQ(client, buffer, frameCount);
        
        // 3. Apply pan
        ApplyPan(client, buffer, frameCount);
        
        // 4. Apply volume (or 0 if routed elsewhere)
        Float32 volume = client->HasActiveRoutes() ? 0.0f : client->mVolume;
        ApplyVolume(buffer, frameCount, volume);
    }
    
    if (inOperationID == kAudioServerPlugInIOOperationReadInput) {
        // Mix in audio from apps that are routed to this client
        Float32* buffer = (Float32*)ioMainBuffer;
        MixRoutedAudio(inClientID, buffer, inIOBufferFrameSize);
    }
}
```

#### 3.2.6 EQ Implementation (Biquad Filters)

```cpp
// 3-band parametric EQ using biquad filters
void Manatee_Device::ApplyEQ(Manatee_Client* client, Float32* buffer, UInt32 frames) {
    Float64 sampleRate = 48000.0;  // Or get from stream format
    
    // Low shelf: 200 Hz
    BiquadCoeffs lowCoeffs = CalculateLowShelf(200.0, client->mEQLowGain, sampleRate);
    
    // Mid peak: 1000 Hz, Q=1.0
    BiquadCoeffs midCoeffs = CalculatePeaking(1000.0, client->mEQMidGain, 1.0, sampleRate);
    
    // High shelf: 4000 Hz
    BiquadCoeffs highCoeffs = CalculateHighShelf(4000.0, client->mEQHighGain, sampleRate);
    
    for (UInt32 ch = 0; ch < 2; ch++) {
        for (UInt32 i = 0; i < frames; i++) {
            Float32 sample = buffer[i * 2 + ch];
            sample = ProcessBiquad(sample, lowCoeffs, client->mLowFilterState[ch]);
            sample = ProcessBiquad(sample, midCoeffs, client->mMidFilterState[ch]);
            sample = ProcessBiquad(sample, highCoeffs, client->mHighFilterState[ch]);
            buffer[i * 2 + ch] = sample;
        }
    }
}
```

### 3.3 Driver Installation

The driver installs to `/Library/Audio/Plug-Ins/HAL/ManateeDriver.driver`

After installation, restart coreaudiod:
```bash
sudo killall coreaudiod
```

---

## 4. Phase 2: Swift Application Foundation

### 4.1 Project Structure

```
Manatee/
├── Package.swift
└── Sources/
    └── Manatee/
        ├── ManateeApp.swift           # App entry point
        ├── AppDelegate.swift          # NSApplicationDelegate
        ├── Models/
        │   ├── AudioChannel.swift     # Channel data model
        │   ├── AudioRouting.swift     # Routing configuration
        │   └── MIDIMapping.swift      # MIDI bindings
        ├── Services/
        │   ├── Audio/
        │   │   ├── AudioEngine.swift  # Main audio controller
        │   │   └── BGMDeviceBridge.swift  # Obj-C++ bridge
        │   └── MIDI/
        │       └── MIDIManager.swift  # MIDI controller support
        └── Views/
            └── Mixer/
                └── MixerView.swift    # Main UI
```

### 4.2 Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Manatee",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Manatee", targets: ["Manatee"])
    ],
    targets: [
        .executableTarget(
            name: "Manatee",
            dependencies: ["ManateeBridge"],
            path: "Sources/Manatee"
        ),
        .target(
            name: "ManateeBridge",
            path: "Sources/ManateeBridge",
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(["-fmodules", "-fcxx-modules"])]
        )
    ]
)
```

### 4.3 Core Models

#### 4.3.1 AudioChannel

```swift
// AudioChannel.swift
import Foundation
import AppKit
import Combine

class AudioChannel: ObservableObject, Identifiable {
    let id: UUID
    let identifier: String          // Bundle ID or "master"
    let name: String
    let channelType: ChannelType
    
    @Published var volume: Float = 1.0          // 0.0 - 1.0
    @Published var pan: Float = 0.0             // -1.0 to +1.0
    @Published var isMuted: Bool = false
    @Published var isSoloed: Bool = false
    @Published var isActive: Bool = true        // App is running
    
    // Per-channel 3-band EQ (dB)
    @Published var eqLowGain: Float = 0.0       // -12 to +12
    @Published var eqMidGain: Float = 0.0
    @Published var eqHighGain: Float = 0.0
    
    // Routing configuration
    @Published var routing: AudioRouting
    
    // App icon (for applications)
    var icon: NSImage?
    
    // Process ID (for driver communication)
    var processId: pid_t = 0
    
    enum ChannelType {
        case master
        case application
    }
    
    var volumeDB: Float {
        volume > 0 ? 20 * log10(volume) : -Float.infinity
    }
    
    var volumeDBFormatted: String {
        volume > 0 ? String(format: "%.1f dB", volumeDB) : "-∞ dB"
    }
}
```

#### 4.3.2 AudioRouting

```swift
// AudioRouting.swift
import Foundation
import Combine

class AudioRouting: ObservableObject {
    @Published var sendToMaster: Bool = true
    @Published var activeRoutes: [Route] = []
    
    struct Route: Identifiable, Equatable {
        let id = UUID()
        let channelId: UUID       // Target channel
        let inputChannel: Int     // Which input on target (0=L, 1=R)
        var gain: Float = 1.0
    }
    
    func setRoute(to channelId: UUID, inputChannel: Int, enabled: Bool) {
        if enabled {
            if !activeRoutes.contains(where: { $0.channelId == channelId && $0.inputChannel == inputChannel }) {
                activeRoutes.append(Route(channelId: channelId, inputChannel: inputChannel))
            }
        } else {
            activeRoutes.removeAll { $0.channelId == channelId && $0.inputChannel == inputChannel }
        }
        
        // Auto-update sendToMaster based on routes
        sendToMaster = activeRoutes.isEmpty
    }
}
```

---

## 5. Phase 3: Audio Engine & Driver Bridge

### 5.1 Objective-C++ Bridge

Create a bridge to communicate with the C++ driver via CoreAudio HAL API:

```objc
// BGMDeviceBridge.mm
#import "BGMDeviceBridge.h"
#import <CoreAudio/CoreAudio.h>

@implementation BGMDeviceBridge

+ (instancetype)shared {
    static BGMDeviceBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BGMDeviceBridge alloc] init];
    });
    return instance;
}

- (AudioObjectID)findManateeDevice {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 dataSize = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &dataSize);
    
    UInt32 deviceCount = dataSize / sizeof(AudioObjectID);
    AudioObjectID devices[deviceCount];
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &dataSize, devices);
    
    for (UInt32 i = 0; i < deviceCount; i++) {
        CFStringRef name = NULL;
        address.mSelector = kAudioDevicePropertyDeviceNameCFString;
        dataSize = sizeof(CFStringRef);
        AudioObjectGetPropertyData(devices[i], &address, 0, NULL, &dataSize, &name);
        
        if (name && CFStringCompare(name, CFSTR("Manatee Device"), 0) == kCFCompareEqualTo) {
            CFRelease(name);
            return devices[i];
        }
        if (name) CFRelease(name);
    }
    return kAudioObjectUnknown;
}

- (void)setVolume:(float)volume forBundleID:(NSString *)bundleID pid:(pid_t)pid {
    AudioObjectID device = [self findManateeDevice];
    if (device == kAudioObjectUnknown) return;
    
    NSDictionary *dict = @{
        @"bundleID": bundleID,
        @"pid": @(pid),
        @"volume": @(volume)
    };
    CFDictionaryRef cfDict = (__bridge CFDictionaryRef)dict;
    
    AudioObjectPropertyAddress address = {
        kAudioDeviceCustomPropertyAppVolume,  // 'apvl'
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(CFDictionaryRef), &cfDict);
}

- (void)setAppEQLowDB:(float)low midDB:(float)mid highDB:(float)high 
          processID:(pid_t)pid bundleID:(NSString *)bundleID {
    AudioObjectID device = [self findManateeDevice];
    if (device == kAudioObjectUnknown) return;
    
    NSDictionary *dict = @{
        @"bundleID": bundleID,
        @"pid": @(pid),
        @"eqLow": @(low),
        @"eqMid": @(mid),
        @"eqHigh": @(high)
    };
    CFDictionaryRef cfDict = (__bridge CFDictionaryRef)dict;
    
    AudioObjectPropertyAddress address = {
        kAudioDeviceCustomPropertyAppEQ,  // 'apeq'
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(CFDictionaryRef), &cfDict);
}

- (NSArray<NSDictionary *> *)getClientList {
    AudioObjectID device = [self findManateeDevice];
    if (device == kAudioObjectUnknown) return @[];
    
    AudioObjectPropertyAddress address = {
        kAudioDeviceCustomPropertyClientList,  // 'clst'
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    CFArrayRef clients = NULL;
    UInt32 dataSize = sizeof(CFArrayRef);
    OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &dataSize, &clients);
    
    if (status == noErr && clients) {
        NSArray *result = (__bridge_transfer NSArray *)clients;
        return result;
    }
    return @[];
}

- (void)setRoutingFromPID:(pid_t)sourcePID toPID:(pid_t)destPID gain:(float)gain enabled:(BOOL)enabled {
    AudioObjectID device = [self findManateeDevice];
    if (device == kAudioObjectUnknown) return;
    
    NSDictionary *dict = @{
        @"sourcePID": @(sourcePID),
        @"destPID": @(destPID),
        @"gain": @(gain),
        @"enabled": @(enabled)
    };
    CFDictionaryRef cfDict = (__bridge CFDictionaryRef)dict;
    
    AudioObjectPropertyAddress address = {
        kAudioDeviceCustomPropertyAppRouting,  // 'aprt'
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(CFDictionaryRef), &cfDict);
}

@end
```

### 5.2 AudioEngine (Swift)

```swift
// AudioEngine.swift
import Foundation
import AppKit
import Combine

@MainActor
class AudioEngine: ObservableObject {
    static let shared = AudioEngine()
    
    @Published var channels: [AudioChannel] = []
    @Published var masterChannel: AudioChannel?
    @Published var isBGMDriverAvailable: Bool = false
    
    private let bgmBridge = BGMDeviceBridge.shared
    private var pollTimer: Timer?
    private var volumeObservers: [AnyCancellable] = []
    
    init() {
        setupMasterChannel()
        checkDriverAvailability()
        startPollingClients()
        setupVolumeObservers()
    }
    
    private func setupMasterChannel() {
        let master = AudioChannel(
            identifier: "master",
            name: "Master",
            channelType: .master
        )
        masterChannel = master
    }
    
    private func startPollingClients() {
        // Poll every 2 seconds for new/removed apps
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshClientList()
            }
        }
    }
    
    func refreshClientList() {
        guard isBGMDriverAvailable else { return }
        
        let clients = bgmBridge.getClientList()
        
        for clientDict in clients {
            guard let bundleID = clientDict["bundleID"] as? String,
                  let pid = clientDict["pid"] as? Int32 else { continue }
            
            // Skip if already exists
            if channels.contains(where: { $0.identifier == bundleID }) { continue }
            
            // Create new channel
            let channel = AudioChannel(
                identifier: bundleID,
                name: appNameForBundleID(bundleID),
                channelType: .application
            )
            channel.processId = pid
            channel.icon = iconForBundleID(bundleID)
            
            channels.append(channel)
            observeVolumeChanges(for: channel)
        }
        
        // Mark inactive channels
        let activePIDs = Set(clients.compactMap { $0["pid"] as? Int32 })
        for channel in channels where channel.channelType == .application {
            channel.isActive = activePIDs.contains(channel.processId)
        }
    }
    
    private func observeVolumeChanges(for channel: AudioChannel) {
        channel.$volume
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] volume in
                self?.setAppVolume(channel: channel, volume: volume)
            }
            .store(in: &volumeObservers)
        
        // Similar observers for pan, EQ, mute...
    }
    
    func setAppVolume(channel: AudioChannel, volume: Float) {
        guard isBGMDriverAvailable else { return }
        
        // If routed, don't send to master
        let effectiveVolume = channel.routing.sendToMaster ? volume : 0.0
        let masterVolume = masterChannel?.isMuted == true ? 0 : (masterChannel?.volume ?? 1.0)
        let finalVolume = channel.isMuted ? 0 : effectiveVolume * masterVolume
        
        bgmBridge.setVolume(finalVolume, forBundleID: channel.identifier, pid: channel.processId)
    }
    
    func setRouting(from source: AudioChannel, to targetId: UUID, inputChannel: Int, enabled: Bool) {
        // Update model
        source.routing.setRoute(to: targetId, inputChannel: inputChannel, enabled: enabled)
        
        // sendToMaster is auto-updated by AudioRouting
        
        // Update driver volume (0 if routed, normal if not)
        setAppVolume(channel: source, volume: source.volume)
        
        // Set driver routing
        guard let target = channels.first(where: { $0.id == targetId }) else { return }
        bgmBridge.setRouting(
            fromPID: source.processId,
            toPID: target.processId,
            gain: 1.0,
            enabled: enabled
        )
    }
    
    private func appNameForBundleID(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return bundle.infoDictionary?["CFBundleName"] as? String ?? bundleID
        }
        return bundleID
    }
    
    private func iconForBundleID(_ bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
```

---

## 6. Phase 4: User Interface

### 6.1 Main App Entry

```swift
// ManateeApp.swift
import SwiftUI

@main
struct ManateeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { }  // Empty, we use menu bar
    }
}

// AppDelegate.swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Manatee")
            button.action = #selector(togglePopover)
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 800, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MixerView()
                .environmentObject(AudioEngine.shared)
        )
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

### 6.2 MixerView (DAW-style)

```swift
// MixerView.swift
import SwiftUI

struct MixerView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var selectedChannelID: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Channel strips
            HStack(spacing: 2) {
                // App channels (scrollable)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(audioEngine.channels) { channel in
                            ChannelStripView(channel: channel)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                Divider()
                
                // Master channel (fixed)
                if let master = audioEngine.masterChannel {
                    ChannelStripView(channel: master)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var toolbar: some View {
        HStack {
            Text("Manatee")
                .font(.headline)
            Spacer()
            // Output device selector, settings, etc.
        }
        .padding()
    }
}

struct ChannelStripView: View {
    @ObservedObject var channel: AudioChannel
    @State private var showRoutingPopover = false
    
    var body: some View {
        VStack(spacing: 6) {
            // App icon (clickable for routing)
            channelIcon
            
            // Channel name
            Text(channel.name)
                .font(.caption)
                .lineLimit(1)
            
            // 3-band EQ knobs
            ChannelEQView(channel: channel)
            
            // Volume fader
            FaderView(value: $channel.volume)
                .frame(height: 150)
            
            // Volume readout
            Text(channel.volumeDBFormatted)
                .font(.caption2)
            
            // Pan knob
            KnobView(value: $channel.pan, range: -1...1)
                .frame(width: 40, height: 40)
            
            // Mute/Solo
            HStack(spacing: 4) {
                Button("M") { channel.isMuted.toggle() }
                    .buttonStyle(MuteButtonStyle(isActive: channel.isMuted))
                
                Button("S") { channel.isSoloed.toggle() }
                    .buttonStyle(SoloButtonStyle(isActive: channel.isSoloed))
            }
        }
        .padding(8)
        .frame(width: 80)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var channelIcon: some View {
        Button(action: { showRoutingPopover = true }) {
            if let icon = channel.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showRoutingPopover) {
            RoutingPopoverView(channel: channel)
        }
    }
}
```

### 6.3 Custom UI Components

#### FaderView

```swift
struct FaderView: View {
    @Binding var value: Float
    let maxValue: Float = 1.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 8)
                
                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: [.green, .yellow, .red],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(width: 8, height: geo.size.height * CGFloat(value / maxValue))
                
                // Thumb
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .frame(width: 24, height: 12)
                    .shadow(radius: 2)
                    .offset(y: -geo.size.height * CGFloat(value / maxValue) + 6)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let normalized = 1.0 - Float(drag.location.y / geo.size.height)
                        value = max(0, min(maxValue, normalized * maxValue))
                    }
            )
        }
    }
}
```

#### KnobView

```swift
struct KnobView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var defaultValue: Float = 0
    
    @State private var lastAngle: Angle = .zero
    
    private var rotation: Angle {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return Angle(degrees: Double(normalized) * 270 - 135)
    }
    
    var body: some View {
        ZStack {
            // Knob body
            Circle()
                .fill(Color.gray.opacity(0.3))
            
            // Indicator line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 12)
                .offset(y: -10)
                .rotationEffect(rotation)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let delta = Float(-drag.translation.height / 100)
                    value = max(range.lowerBound, min(range.upperBound, value + delta))
                }
        )
        .onTapGesture(count: 2) {
            value = defaultValue
        }
    }
}
```

---

## 7. Phase 5: Inter-App Audio Routing

### 7.1 Routing UI

```swift
struct RoutingPopoverView: View {
    @ObservedObject var channel: AudioChannel
    @EnvironmentObject var audioEngine: AudioEngine
    
    private var availableTargets: [AudioChannel] {
        audioEngine.channels.filter { $0.id != channel.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Route \(channel.name) to:")
                .font(.headline)
            
            // Routing matrix
            ForEach(availableTargets) { target in
                routeRow(to: target)
            }
            
            Divider()
            
            // Status
            HStack {
                Image(systemName: channel.routing.activeRoutes.isEmpty ? "speaker.wave.3.fill" : "arrow.triangle.branch")
                Text(channel.routing.activeRoutes.isEmpty ? "Direct to Master" : "Routed")
            }
            .foregroundColor(channel.routing.activeRoutes.isEmpty ? .green : .purple)
        }
        .padding()
        .frame(width: 300)
    }
    
    private func routeRow(to target: AudioChannel) -> some View {
        HStack {
            if let icon = target.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            
            Text(target.name)
            
            Spacer()
            
            // Input channel buttons (L, R)
            ForEach(0..<2, id: \.self) { inputCh in
                Button(inputCh == 0 ? "L" : "R") {
                    let isActive = channel.routing.activeRoutes.contains {
                        $0.channelId == target.id && $0.inputChannel == inputCh
                    }
                    audioEngine.setRouting(
                        from: channel,
                        to: target.id,
                        inputChannel: inputCh,
                        enabled: !isActive
                    )
                }
                .buttonStyle(RouteButtonStyle(isActive: isRouteActive(to: target.id, input: inputCh)))
            }
        }
    }
    
    private func isRouteActive(to targetId: UUID, input: Int) -> Bool {
        channel.routing.activeRoutes.contains {
            $0.channelId == targetId && $0.inputChannel == input
        }
    }
}
```

### 7.2 Driver-Side Routing

In the driver, implement circular buffers for each client:

```cpp
// When processing audio output from a client
void Manatee_Client::StoreToRoutingBuffer(const Float32* buffer, UInt32 frames) {
    UInt32 writePos = mRoutingWritePos.load(std::memory_order_relaxed);
    
    for (UInt32 i = 0; i < frames * 2; i++) {
        mRoutingBuffer[(writePos + i) % mRoutingBufferSize] = buffer[i];
    }
    
    mRoutingWritePos.store((writePos + frames * 2) % mRoutingBufferSize, 
                           std::memory_order_release);
}

// When processing audio input for a client that receives routed audio
void Manatee_Clients::MixRoutedAudio(pid_t destPID, Float32* buffer, UInt32 frames) {
    for (auto& route : mRoutes) {
        if (route.mDestPID == destPID && route.mEnabled) {
            Manatee_Client* source = GetClientByPID(route.mSourcePID);
            if (!source) continue;
            
            Float32 tempBuffer[frames * 2];
            source->FetchFromRoutingBuffer(tempBuffer, frames);
            
            for (UInt32 i = 0; i < frames * 2; i++) {
                buffer[i] += tempBuffer[i] * route.mGain;
            }
        }
    }
}
```

---

## 8. Phase 6: Advanced Features

### 8.1 MIDI Controller Support

```swift
// MIDIManager.swift
import CoreMIDI

class MIDIManager: ObservableObject {
    @Published var mappings: [MIDIMapping] = []
    
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    
    func start() {
        MIDIClientCreate("Manatee" as CFString, nil, nil, &midiClient)
        
        MIDIInputPortCreate(midiClient, "Input" as CFString, midiReadProc, 
                           Unmanaged.passUnretained(self).toOpaque(), &inputPort)
        
        // Connect to all sources
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, source, nil)
        }
    }
    
    private let midiReadProc: MIDIReadProc = { packetList, refCon, _ in
        let manager = Unmanaged<MIDIManager>.fromOpaque(refCon!).takeUnretainedValue()
        
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let status = packet.data.0 & 0xF0
            let channel = packet.data.0 & 0x0F
            let data1 = packet.data.1
            let data2 = packet.data.2
            
            if status == 0xB0 {  // Control Change
                DispatchQueue.main.async {
                    manager.handleCC(channel: channel, cc: data1, value: data2)
                }
            }
            
            packet = MIDIPacketNext(&packet).pointee
        }
    }
    
    func handleCC(channel: UInt8, cc: UInt8, value: UInt8) {
        let normalized = Float(value) / 127.0
        
        for mapping in mappings {
            if mapping.midiChannel == channel && mapping.ccNumber == cc {
                if let appChannel = AudioEngine.shared.channels.first(where: { $0.id == mapping.channelId }) {
                    switch mapping.parameter {
                    case .volume:
                        appChannel.volume = normalized
                    case .pan:
                        appChannel.pan = (normalized * 2) - 1
                    case .eqLow:
                        appChannel.eqLowGain = (normalized * 24) - 12
                    // etc.
                    }
                }
            }
        }
    }
}

struct MIDIMapping: Identifiable, Codable {
    let id: UUID
    var channelId: UUID
    var parameter: Parameter
    var midiChannel: UInt8
    var ccNumber: UInt8
    
    enum Parameter: String, Codable {
        case volume, pan, mute, eqLow, eqMid, eqHigh
    }
}
```

### 8.2 Settings Persistence

```swift
// SettingsManager.swift
class SettingsManager {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    var managedApps: [String] {
        get { defaults.stringArray(forKey: "managedApps") ?? [] }
        set { defaults.set(newValue, forKey: "managedApps") }
    }
    
    var midiMappings: [MIDIMapping] {
        get {
            guard let data = defaults.data(forKey: "midiMappings") else { return [] }
            return (try? JSONDecoder().decode([MIDIMapping].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: "midiMappings")
        }
    }
    
    func saveChannelSettings(_ channel: AudioChannel) {
        let settings: [String: Any] = [
            "volume": channel.volume,
            "pan": channel.pan,
            "eqLow": channel.eqLowGain,
            "eqMid": channel.eqMidGain,
            "eqHigh": channel.eqHighGain
        ]
        defaults.set(settings, forKey: "channel_\(channel.identifier)")
    }
    
    func loadChannelSettings(_ channel: AudioChannel) {
        guard let settings = defaults.dictionary(forKey: "channel_\(channel.identifier)") else { return }
        channel.volume = settings["volume"] as? Float ?? 1.0
        channel.pan = settings["pan"] as? Float ?? 0.0
        channel.eqLowGain = settings["eqLow"] as? Float ?? 0.0
        channel.eqMidGain = settings["eqMid"] as? Float ?? 0.0
        channel.eqHighGain = settings["eqHigh"] as? Float ?? 0.0
    }
}
```

---

## 9. Build & Installation

### 9.1 Building the Driver

```bash
# Build driver with Xcode
xcodebuild -project ManateeDriver/ManateeDriver.xcodeproj \
           -scheme ManateeDriver \
           -configuration Release \
           ARCHS="x86_64 arm64"

# Install driver
sudo cp -r build/Release/ManateeDriver.driver /Library/Audio/Plug-Ins/HAL/
sudo killall coreaudiod
```

### 9.2 Building the App

```bash
cd Manatee
swift build -c release

# Create app bundle
mkdir -p Manatee.app/Contents/MacOS
cp .build/release/Manatee Manatee.app/Contents/MacOS/
cp Info.plist Manatee.app/Contents/
```

### 9.3 Code Signing (for distribution)

```bash
# Sign driver
codesign --sign "Developer ID Application: Your Name" \
         --deep --force \
         /Library/Audio/Plug-Ins/HAL/ManateeDriver.driver

# Sign app
codesign --sign "Developer ID Application: Your Name" \
         --deep --force \
         --entitlements Manatee.entitlements \
         Manatee.app
```

### 9.4 Required Entitlements

```xml
<!-- Manatee.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

---

## Summary

This specification covers building a complete macOS audio mixer from scratch:

| Component | Lines of Code (approx) | Complexity |
|-----------|------------------------|------------|
| HAL Driver | ~3,000 | High |
| Swift Models | ~500 | Medium |
| Audio Engine | ~800 | Medium |
| Obj-C++ Bridge | ~400 | Medium |
| SwiftUI Views | ~1,500 | Medium |
| MIDI Support | ~300 | Low |
| **Total** | **~6,500** | |

**Key challenges:**
1. Understanding CoreAudio HAL plugin architecture
2. Thread-safe audio processing in driver
3. Biquad filter implementation for EQ
4. Lock-free circular buffers for routing
5. Bridging C++ driver to Swift app

**Development time estimate:** 4-8 weeks for experienced developer.

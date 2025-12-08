# Manatee

A professional macOS audio control application with per-app volume control, MIDI controller support, and OSC network control.

![macOS 13.0+](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

### 🎚️ Per-App Volume Control
- Individual volume sliders for every running application
- Mute and solo functionality
- Pan control for stereo positioning
- Volume boost up to +3dB

### 🎹 MIDI Controller Support
- Plug-and-play USB MIDI controller support
- MIDI Learn for easy mapping
- Built-in profiles for popular controllers:
  - Behringer X-Touch Mini
  - Korg nanoKONTROL2
  - Generic MIDI controllers
- Motorized fader feedback support

### 📡 OSC Network Control
- Control from any OSC-compatible app
- Works with TouchOSC, Lemur, and others
- Wireless control from tablets and phones
- Bidirectional state synchronization

### 🖥️ Two Interface Modes
- **Menu Bar**: Quick access popover for simple adjustments
- **Mixer**: Professional mixing console window with VU meters

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac
- Audio driver installation (included)

## Installation

### From Release
1. Download the latest `.dmg` from Releases
2. Drag Manatee to Applications
3. Launch Manatee
4. Grant required permissions when prompted

### From Source
```bash
# Clone the repository
git clone https://github.com/yourusername/Manatee.git
cd Manatee

# Build with Swift Package Manager
swift build

# Or open in Xcode
open Package.swift
```

## Usage

### Menu Bar
Click the Manatee icon in the menu bar to access quick volume controls for running applications.

### Mixer View
Click "Open Mixer" to access the full mixing console with:
- Channel strips for each application
- VU meters for visual feedback
- Bank switching for many apps
- Master output control

### MIDI Learn
1. Open Preferences → MIDI
2. Click "Configure Mappings"
3. Click on a control you want to map
4. Move a fader/knob on your MIDI controller
5. The mapping is saved automatically

### OSC Control
1. Open Preferences → OSC
2. Enable OSC control
3. Note the IP address and port
4. Configure your OSC app with these addresses:
   - `/manatee/app/{bundleID}/volume` (0.0-1.5)
   - `/manatee/app/{bundleID}/mute` (0 or 1)
   - `/manatee/master/volume` (0.0-1.5)
   - `/manatee/master/mute` (0 or 1)

## Architecture

```
Manatee/
├── Sources/
│   ├── Manatee/
│   │   ├── App/           # App entry point and delegate
│   │   ├── Models/        # Data models (AudioChannel, etc.)
│   │   ├── Services/      # Audio, MIDI, OSC services
│   │   └── Views/         # SwiftUI views
│   └── ManateeBridge/     # Objective-C bridge for driver
├── Tests/                 # Unit tests
└── Package.swift          # Swift Package Manager manifest
```

## Dependencies

- [MIDIKit](https://github.com/orchetect/MIDIKit) - Modern MIDI framework
- [OSCKit](https://github.com/orchetect/OSCKit) - Open Sound Control
- [Swift Atomics](https://github.com/apple/swift-atomics) - Lock-free primitives
- [Swift Collections](https://github.com/apple/swift-collections) - Data structures

## Driver

Manatee uses a virtual audio device driver based on [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic). The driver intercepts audio from applications, allowing per-app volume control before routing to the physical output.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Create a Pull Request

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) for the audio driver foundation
- [MIDIKit](https://github.com/orchetect/MIDIKit) and [OSCKit](https://github.com/orchetect/OSCKit) by Steffan Andrews

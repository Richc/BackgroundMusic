// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Flo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Flo",
            targets: ["Flo"]
        ),
    ],
    dependencies: [
        // MIDI support with MIDI 2.0
        .package(url: "https://github.com/orchetect/MIDIKit.git", from: "0.10.0"),
        // OSC protocol support
        .package(url: "https://github.com/orchetect/OSCKit.git", from: "2.0.0"),
        // Swift atomics for lock-free audio thread communication
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        // Swift collections for advanced data structures
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        // Main application target
        .executableTarget(
            name: "Flo",
            dependencies: [
                .product(name: "MIDIKit", package: "MIDIKit"),
                .product(name: "OSCKit", package: "OSCKit"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Collections", package: "swift-collections"),
                "FloBridge"
            ],
            path: "Sources/Flo",
            exclude: ["Info.plist", "Flo.entitlements"],
            resources: [
                .process("Resources")
            ]
        ),
        
        // Objective-C/C++ bridge for BGMDriver
        .target(
            name: "FloBridge",
            dependencies: [],
            path: "Sources/FloBridge",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../SharedSource"),
                .define("FLO_BRIDGE")
            ]
        ),
    ]
)
 
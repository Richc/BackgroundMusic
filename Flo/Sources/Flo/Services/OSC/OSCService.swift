//
//  OSCService.swift
//  Flo
//
//  OSC (Open Sound Control) server for network control
//

import Foundation
import OSCKit

/// Service for handling OSC network communication
@MainActor
final class OSCService: ObservableObject {
    
    // MARK: - Published State
    
    /// Is the OSC server running
    @Published var isRunning: Bool = false
    
    /// Server port
    @Published var port: UInt16 = 9000
    
    /// Connected clients (for bidirectional communication)
    @Published var connectedClients: [String] = []
    
    /// Last received OSC message (for display/debugging)
    @Published var lastReceivedMessage: String = ""
    
    /// Error message if any
    @Published var errorMessage: String?
    
    // MARK: - Private
    
    private var server: OSCUDPServer?
    private var client: OSCUDPClient?
    
    /// Callback when a control value changes
    var onControlChange: ((ControlTarget, Float) -> Void)?
    
    // MARK: - OSC Address Patterns
    
    /*
     OSC Address Namespace:
     
     /flo/app/{bundleID}/volume      Float 0.0-1.5
     /flo/app/{bundleID}/mute        Bool (0 or 1)
     /flo/app/{bundleID}/pan         Float -1.0 to 1.0
     /flo/app/{bundleID}/solo        Bool (0 or 1)
     
     /flo/device/{uid}/volume        Float 0.0-1.0
     /flo/device/{uid}/mute          Bool (0 or 1)
     
     /flo/master/volume              Float 0.0-1.5
     /flo/master/mute                Bool (0 or 1)
     
     /flo/scene/recall               Int (scene index)
     /flo/preset/recall              String (preset name)
     
     /flo/query                      Requests current state
     */
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Lifecycle
    
    func start(port: UInt16 = 9000) async {
        self.port = port
        
        print("📡 OSCService starting on port \(port)...")
        
        do {
            server = OSCUDPServer(port: port) { [weak self] message, timeTag, host, port in
                Task { @MainActor in
                    self?.handleMessage(message)
                }
            }
            
            try server?.start()
            
            // Create client for sending feedback
            client = OSCUDPClient()
            
            isRunning = true
            errorMessage = nil
            
            print("✅ OSCService started on port \(port)")
            
        } catch {
            errorMessage = "Failed to start OSC server: \(error.localizedDescription)"
            print("❌ OSCService failed to start: \(error)")
        }
    }
    
    func stop() async {
        print("📡 OSCService stopping...")
        
        server?.stop()
        server = nil
        client = nil
        
        isRunning = false
        connectedClients.removeAll()
        
        print("✅ OSCService stopped")
    }
    
    func restart(port: UInt16) async {
        await stop()
        await start(port: port)
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: OSCMessage) {
        lastReceivedMessage = "\(message.addressPattern) \(message.values)"
        
        let components = message.addressPattern.pathComponents.map { String($0) }
        guard components.count >= 3,
              components[0] == "",
              components[1] == "flo" else {
            return
        }
        
        switch components[2] {
        case "app":
            handleAppMessage(components: Array(components.dropFirst(3)), values: message.values)
            
        case "device":
            handleDeviceMessage(components: Array(components.dropFirst(3)), values: message.values)
            
        case "master":
            handleMasterMessage(components: Array(components.dropFirst(3)), values: message.values)
            
        case "scene":
            handleSceneMessage(components: Array(components.dropFirst(3)), values: message.values)
            
        case "preset":
            handlePresetMessage(components: Array(components.dropFirst(3)), values: message.values)
            
        case "query":
            handleQueryMessage()
            
        default:
            print("⚠️ Unknown OSC address: \(message.addressPattern)")
        }
    }
    
    private func handleAppMessage(components: [String], values: [any OSCValue]) {
        guard components.count >= 2 else { return }
        
        let bundleID = components[0]
        let control = components[1]
        
        guard let value = values.first else { return }
        
        switch control {
        case "volume":
            if let floatValue = value as? Float {
                onControlChange?(.appVolume(bundleID: bundleID), floatValue)
            }
            
        case "mute":
            if let intValue = value as? Int32 {
                onControlChange?(.appMute(bundleID: bundleID), intValue > 0 ? 1 : 0)
            } else if let floatValue = value as? Float {
                onControlChange?(.appMute(bundleID: bundleID), floatValue > 0.5 ? 1 : 0)
            }
            
        case "pan":
            if let floatValue = value as? Float {
                onControlChange?(.appPan(bundleID: bundleID), floatValue)
            }
            
        case "solo":
            if let intValue = value as? Int32 {
                onControlChange?(.appSolo(bundleID: bundleID), intValue > 0 ? 1 : 0)
            }
            
        default:
            break
        }
    }
    
    private func handleDeviceMessage(components: [String], values: [any OSCValue]) {
        guard components.count >= 2 else { return }
        
        let deviceUID = components[0]
        let control = components[1]
        
        guard let value = values.first else { return }
        
        switch control {
        case "volume":
            if let floatValue = value as? Float {
                onControlChange?(.deviceVolume(deviceUID: deviceUID), floatValue)
            }
            
        case "mute":
            if let intValue = value as? Int32 {
                onControlChange?(.deviceMute(deviceUID: deviceUID), intValue > 0 ? 1 : 0)
            }
            
        default:
            break
        }
    }
    
    private func handleMasterMessage(components: [String], values: [any OSCValue]) {
        guard let control = components.first,
              let value = values.first else { return }
        
        switch control {
        case "volume":
            if let floatValue = value as? Float {
                onControlChange?(.masterVolume, floatValue)
            }
            
        case "mute":
            if let intValue = value as? Int32 {
                onControlChange?(.masterMute, intValue > 0 ? 1 : 0)
            }
            
        default:
            break
        }
    }
    
    private func handleSceneMessage(components: [String], values: [any OSCValue]) {
        guard components.first == "recall",
              let value = values.first as? Int32 else { return }
        
        onControlChange?(.sceneRecall(index: Int(value)), 1)
    }
    
    private func handlePresetMessage(components: [String], values: [any OSCValue]) {
        guard components.first == "recall",
              let value = values.first as? String else { return }
        
        onControlChange?(.presetRecall(name: value), 1)
    }
    
    private func handleQueryMessage() {
        // TODO: Send back current state to all connected clients
        print("📡 Received state query")
    }
    
    // MARK: - Sending State
    
    func sendStateUpdate(address: String, values: [any OSCValue], to host: String, port: UInt16) {
        guard let client = client else { return }
        
        let message = OSCMessage(address, values: values)
        
        do {
            try client.send(message, to: host, port: port)
        } catch {
            print("❌ Failed to send OSC message: \(error)")
        }
    }
    
    /// Broadcast current app volume to all registered clients
    func broadcastAppVolume(bundleID: String, volume: Float) {
        let address = "/flo/app/\(bundleID)/volume"
        for clientAddress in connectedClients {
            let components = clientAddress.split(separator: ":")
            if components.count == 2,
               let port = UInt16(components[1]) {
                sendStateUpdate(address: address, values: [volume], to: String(components[0]), port: port)
            }
        }
    }
    
    /// Broadcast master volume
    func broadcastMasterVolume(_ volume: Float) {
        let address = "/flo/master/volume"
        for clientAddress in connectedClients {
            let components = clientAddress.split(separator: ":")
            if components.count == 2,
               let port = UInt16(components[1]) {
                sendStateUpdate(address: address, values: [volume], to: String(components[0]), port: port)
            }
        }
    }
    
    // MARK: - Client Registration
    
    func registerClient(_ address: String) {
        if !connectedClients.contains(address) {
            connectedClients.append(address)
            print("📡 Registered OSC client: \(address)")
        }
    }
    
    func unregisterClient(_ address: String) {
        connectedClients.removeAll { $0 == address }
        print("📡 Unregistered OSC client: \(address)")
    }
}

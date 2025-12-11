//
//  MenuBarIconView.swift
//  Flo
//
//  Custom view for the menu bar icon
//

import SwiftUI
import AppKit

struct MenuBarIconView: View {
    
    private var menuBarImage: NSImage? {
        // Try multiple locations for the icon
        
        // Try 1: Load "boom box.png" from Bundle.module (SPM resources)
        if let iconURL = Bundle.module.url(forResource: "boom box", withExtension: "png"),
           let nsImage = NSImage(contentsOf: iconURL) {
            print("✅ boom box.png loaded from Bundle.module: \(iconURL)")
            return configureMenuBarImage(nsImage)
        }
        
        // Try 2: Load from main bundle Resources (installed .app)
        if let iconURL = Bundle.main.url(forResource: "boom box", withExtension: "png"),
           let nsImage = NSImage(contentsOf: iconURL) {
            print("✅ boom box.png loaded from Bundle.main: \(iconURL)")
            return configureMenuBarImage(nsImage)
        }
        
        // Try 3: Load from executable's parent directory structure (.app bundle)
        let executableURL = Bundle.main.executableURL
        if let resourcesURL = executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources") {
            let iconURL = resourcesURL.appendingPathComponent("boom box.png")
            if FileManager.default.fileExists(atPath: iconURL.path),
               let nsImage = NSImage(contentsOf: iconURL) {
                print("✅ boom box.png loaded from Resources: \(iconURL)")
                return configureMenuBarImage(nsImage)
            }
        }
        
        // Try 4: Check inside Flo_Flo.bundle
        if let resourcesURL = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Flo_Flo.bundle") {
            let iconURL = resourcesURL.appendingPathComponent("boom box.png")
            if FileManager.default.fileExists(atPath: iconURL.path),
               let nsImage = NSImage(contentsOf: iconURL) {
                print("✅ boom box.png loaded from Flo_Flo.bundle: \(iconURL)")
                return configureMenuBarImage(nsImage)
            }
        }
        
        // Try 5: Fallback to MenuBarIcon.png
        if let iconURL = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
           let nsImage = NSImage(contentsOf: iconURL) {
            print("✅ MenuBarIcon loaded from Bundle.module: \(iconURL)")
            return configureMenuBarImage(nsImage)
        }
        
        print("⚠️ Menu bar icon not found in any location")
        print("   Bundle.main.bundlePath: \(Bundle.main.bundlePath)")
        print("   Bundle.main.resourcePath: \(Bundle.main.resourcePath ?? "nil")")
        print("   Bundle.module: \(Bundle.module.bundlePath)")
        
        return nil
    }
    
    private func configureMenuBarImage(_ image: NSImage) -> NSImage {
        // Create a properly sized menu bar icon (18x18 is standard)
        let size = NSSize(width: 18, height: 18)
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        resizedImage.isTemplate = true  // Makes it adapt to menu bar light/dark mode
        return resizedImage
    }
    
    var body: some View {
        // Load the menu bar icon from bundle resources
        if let image = menuBarImage {
            Image(nsImage: image)
        } else {
            // Fallback: use a water/wave system icon as it's thematically appropriate for Flo
            Image(systemName: "water.waves")
        }
    }
}

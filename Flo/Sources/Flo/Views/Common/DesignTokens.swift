//
//  DesignTokens.swift
//  Flo
//
//  Design system tokens for consistent styling
//

import SwiftUI

// MARK: - Colors

enum FloColors {
    
    // MARK: - Brand Colors
    
    /// Primary brand color (teal/sea green - flo inspired)
    static let brand = Color(hue: 0.48, saturation: 0.45, brightness: 0.55)
    
    /// Secondary accent
    static let accent = Color.accentColor
    
    // MARK: - Channel Strip Colors
    
    /// Background of a channel strip (slightly lighter than window background)
    static let channelBackground = Color(white: 0.18)
    
    /// Elevated channel strip (selected) - blue tint
    static let channelBackgroundSelected = Color(hue: 0.58, saturation: 0.5, brightness: 0.4)
    
    /// Channel strip when inactive/grayed out - darker
    static let channelBackgroundInactive = Color(white: 0.12)
    
    /// Fader track background
    static let faderTrack = Color(white: 0.15)
    
    /// Fader cap/thumb
    static let faderCap = Color(white: 0.75)
    
    /// Fader cap when dragging
    static let faderCapActive = Color.white
    
    // MARK: - Meter Colors
    
    /// Meter green zone (-∞ to -12dB)
    static let meterGreen = Color(hue: 0.35, saturation: 0.85, brightness: 0.70)
    
    /// Meter yellow zone (-12 to -6dB)
    static let meterYellow = Color(hue: 0.15, saturation: 0.90, brightness: 0.85)
    
    /// Meter orange zone (-6 to -3dB)
    static let meterOrange = Color(hue: 0.08, saturation: 0.95, brightness: 0.90)
    
    /// Meter red zone (-3 to 0dB)
    static let meterRed = Color(hue: 0.0, saturation: 0.90, brightness: 0.85)
    
    /// Meter clip indicator
    static let meterClip = Color(hue: 0.0, saturation: 1.0, brightness: 1.0)
    
    /// Meter background
    static let meterBackground = Color(white: 0.1)
    
    // MARK: - Button States
    
    /// Mute button active
    static let muteActive = Color.green
    
    /// Mute button inactive
    static let muteInactive = Color(white: 0.3)
    
    /// Solo button active
    static let soloActive = Color.yellow
    
    /// Solo button inactive
    static let soloInactive = Color(white: 0.3)
    
    // MARK: - Semantic Colors
    
    /// Window background
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    
    /// Control background
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    
    /// Text primary
    static let textPrimary = Color(nsColor: .labelColor)
    
    /// Text secondary
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    
    /// Text tertiary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    
    /// Divider
    static let divider = Color(nsColor: .separatorColor)
    
    // MARK: - Routing Colors
    
    /// Accent green for active routes and positive indicators
    static let accentGreen = Color(hue: 0.35, saturation: 0.75, brightness: 0.65)
    
    /// Route active indicator
    static let routeActive = Color(hue: 0.35, saturation: 0.85, brightness: 0.70)
    
    // MARK: - Helper Functions
    
    /// Convert linear amplitude to decibels
    private static func linearToDecibels(_ linear: Float) -> Float {
        if linear <= 0 { return -Float.infinity }
        return 20.0 * log10(linear)
    }
    
    /// Get meter color for a given level (0.0 to 1.0+)
    static func meterColor(for level: Float) -> Color {
        let db = linearToDecibels(level)
        
        if db > 0 {
            return meterClip
        } else if db > -3 {
            return meterRed
        } else if db > -6 {
            return meterOrange
        } else if db > -12 {
            return meterYellow
        } else {
            return meterGreen
        }
    }
    
    /// Gradient for meter display
    static var meterGradient: LinearGradient {
        LinearGradient(
            colors: [meterGreen, meterYellow, meterOrange, meterRed],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Typography

enum FloTypography {
    
    /// Channel name label
    static let channelName = Font.system(size: 11, weight: .medium)
    
    /// Volume value display
    static let volumeValue = Font.system(size: 10, weight: .regular).monospacedDigit()
    
    /// Section headers
    static let sectionHeader = Font.system(size: 12, weight: .semibold)
    
    /// Button labels
    static let buttonLabel = Font.system(size: 10, weight: .bold)
    
    /// Status text
    static let status = Font.system(size: 9, weight: .regular)
}

// MARK: - Dimensions

enum FloDimensions {
    
    // MARK: - Channel Strip
    
    /// Width of a channel strip
    static let channelWidth: CGFloat = 80
    
    /// Minimum height of a channel strip
    static let channelMinHeight: CGFloat = 300
    
    /// Fader height
    static let faderHeight: CGFloat = 120
    
    /// Fader width
    static let faderWidth: CGFloat = 40
    
    /// Fader thumb size
    static let faderThumbHeight: CGFloat = 24
    static let faderThumbWidth: CGFloat = 36
    
    /// Meter width
    static let meterWidth: CGFloat = 8
    
    /// Knob diameter
    static let knobDiameter: CGFloat = 32
    
    /// Button size
    static let buttonSize: CGFloat = 24
    
    // MARK: - Spacing
    
    /// Standard padding
    static let padding: CGFloat = 8
    
    /// Compact padding
    static let paddingCompact: CGFloat = 4
    
    /// Section spacing
    static let sectionSpacing: CGFloat = 16
    
    // MARK: - Corner Radius
    
    /// Standard corner radius
    static let cornerRadius: CGFloat = 6
    
    /// Button corner radius
    static let buttonCornerRadius: CGFloat = 4
    
    /// Fader thumb corner radius
    static let faderThumbCornerRadius: CGFloat = 3
}

// MARK: - Shadows

enum FloShadows {
    
    /// Subtle shadow for elevated elements
    static let subtle = Color.black.opacity(0.1)
    
    /// Medium shadow for popovers
    static let medium = Color.black.opacity(0.2)
    
    /// Strong shadow for floating panels
    static let strong = Color.black.opacity(0.3)
}

// MARK: - View Modifiers

struct ChannelStripStyle: ViewModifier {
    var isSelected: Bool = false
    var isInactive: Bool = false
    
    func body(content: Content) -> some View {
        content
            .frame(width: FloDimensions.channelWidth)
            .background(
                RoundedRectangle(cornerRadius: FloDimensions.cornerRadius)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: FloDimensions.cornerRadius)
                            .stroke(isSelected ? FloColors.brand.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
    }
    
    private var backgroundColor: Color {
        if isInactive {
            return FloColors.channelBackgroundInactive
        } else if isSelected {
            return FloColors.channelBackgroundSelected
        } else {
            return FloColors.channelBackground
        }
    }
}

struct MuteButtonStyle: ButtonStyle {
    var isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FloTypography.buttonLabel)
            .foregroundColor(isActive ? .white : FloColors.textSecondary)
            .frame(width: FloDimensions.buttonSize, height: FloDimensions.buttonSize)
            .background(isActive ? FloColors.muteActive : FloColors.muteInactive)
            .cornerRadius(FloDimensions.buttonCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SoloButtonStyle: ButtonStyle {
    var isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FloTypography.buttonLabel)
            .foregroundColor(isActive ? .black : FloColors.textSecondary)
            .frame(width: FloDimensions.buttonSize, height: FloDimensions.buttonSize)
            .background(isActive ? FloColors.soloActive : FloColors.soloInactive)
            .cornerRadius(FloDimensions.buttonCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct RecordButtonStyle: ButtonStyle {
    var isRecording: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        Text("R")
            .font(FloTypography.buttonLabel)
            .foregroundColor(isRecording ? .white : Color.red)
            .frame(width: FloDimensions.buttonSize, height: FloDimensions.buttonSize)
            .background(isRecording ? Color.red : FloColors.muteInactive)
            .cornerRadius(FloDimensions.buttonCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Global Tooltip Window Manager

class TooltipWindowManager {
    static let shared = TooltipWindowManager()
    
    private var tooltipWindow: NSWindow?
    private var hostingView: NSHostingView<TooltipBubble>?
    
    private init() {}
    
    func show(_ text: String, at screenPoint: CGPoint) {
        // Create or update the tooltip window
        if tooltipWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.ignoresMouseEvents = true
            window.hasShadow = false
            tooltipWindow = window
        }
        
        let bubble = TooltipBubble(text: text)
        let hostingView = NSHostingView(rootView: bubble)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        
        // Size to fit content
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height)
        
        tooltipWindow?.contentView = hostingView
        tooltipWindow?.setContentSize(fittingSize)
        
        // Position above the element (screen coordinates, with Y flipped for macOS)
        let windowX = screenPoint.x - fittingSize.width / 2
        let windowY = screenPoint.y + 10  // Above the element
        tooltipWindow?.setFrameOrigin(NSPoint(x: windowX, y: windowY))
        
        tooltipWindow?.orderFront(nil)
    }
    
    func hide() {
        tooltipWindow?.orderOut(nil)
    }
}

// MARK: - Conditional Tooltip Modifier

struct ConditionalTooltip: ViewModifier {
    let tooltip: String
    @AppStorage("showTooltips") private var showTooltips = false
    
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())  // Ensure full area is hoverable
            .onHover { hovering in
                guard showTooltips else { return }
                if hovering {
                    // Delay slightly to get accurate frame
                    DispatchQueue.main.async {
                        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                            // Get mouse location in screen coordinates
                            let mouseLocation = NSEvent.mouseLocation
                            // Position tooltip above mouse
                            TooltipWindowManager.shared.show(tooltip, at: CGPoint(x: mouseLocation.x, y: mouseLocation.y + 20))
                        }
                    }
                } else {
                    TooltipWindowManager.shared.hide()
                }
            }
    }
}

// MARK: - Tooltip Bubble View

struct TooltipBubble: View {
    let text: String
    
    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 1.0, green: 0.4, blue: 0.6))  // Hot pink
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                )
            
            // Speech bubble tail
            Triangle()
                .fill(Color(red: 1.0, green: 0.4, blue: 0.6))
                .frame(width: 14, height: 8)
                .offset(y: -1)
        }
        .fixedSize()
    }
}

// MARK: - Triangle Shape for Speech Bubble

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - View Extensions

extension View {
    func channelStripStyle(isSelected: Bool = false, isInactive: Bool = false) -> some View {
        modifier(ChannelStripStyle(isSelected: isSelected, isInactive: isInactive))
    }
    
    /// Shows a tooltip only when "Show Tooltips" is enabled in settings
    func floTooltip(_ tooltip: String) -> some View {
        modifier(ConditionalTooltip(tooltip: tooltip))
    }
}

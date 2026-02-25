import SwiftUI
import UIKit

// MARK: - Color Palette

extension Color {
    /// Core palette - Deep athletic luxury
    static let drip = DripColors()
}

// MARK: - DripColors

struct DripColors {
    // Backgrounds - Matched with WordPress zine theme
    let background = Color(hex: "0A0A0A") // Base Black
    let cardBackground = Color(hex: "111111") // Card Background
    let cardBackgroundElevated = Color(hex: "1A1A1A") // Border Dark (elevated)

    // Accents - Red
    let coral = Color(hex: "FF2D2D") // Primary accent
    let coralLight = Color(hex: "FF5C5C") // Lighter variant
    let electric = Color(hex: "D42121") // Accent Dark (hover state)

    // Mood colors
    let energized = Color(hex: "4AFF6B")
    let positive = Color(hex: "6BFFA3")
    let neutral = Color(hex: "888888") // Muted Gray (matched)
    let tired = Color(hex: "FFB74A")
    let struggling = Color(hex: "FF6B4A")
    let injured = Color(hex: "FF4A6B")

    // Text - High contrast (matched with WordPress)
    let textPrimary = Color(hex: "FAFAFA") // Contrast White
    let textSecondary = Color(hex: "888888") // Muted Gray
    let textTertiary = Color(hex: "555555") // Darker muted

    // Utility
    let divider = Color(hex: "1A1A1A") // Border Dark
    let success = Color(hex: "4AFF6B") // Same as energized
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography

/// Matched with WordPress zine: Bebas Neue (display), Instrument Serif (body), JetBrains Mono (meta)
extension Font {
    /// Display fonts - Bold, condensed headlines (Bebas Neue style)
    /// Falls back to system compressed if custom font not installed
    static func dripDisplay(_ size: CGFloat) -> Font {
        if UIFont(name: "BebasNeue-Regular", size: size) != nil {
            return .custom("BebasNeue-Regular", size: size)
        }
        // Fallback: Heavy weight with tight tracking approximates condensed look
        return .system(size: size, weight: .heavy, design: .default)
    }

    /// Stats - Monospaced for numbers (JetBrains Mono style)
    static func dripStat(_ size: CGFloat) -> Font {
        if UIFont(name: "JetBrainsMono-Bold", size: size) != nil {
            return .custom("JetBrainsMono-Bold", size: size)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Body text - Clean sans-serif (DM Sans style)
    static func dripBody(_ size: CGFloat) -> Font {
        if UIFont(name: "DMSans-Regular", size: size) != nil {
            return .custom("DMSans-Regular", size: size)
        }
        // Fallback: System sans-serif
        return .system(size: size, weight: .regular, design: .default)
    }

    /// Labels - Medium weight sans-serif
    static func dripLabel(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Meta/Captions - Monospaced utility text (JetBrains Mono style)
    static func dripCaption(_ size: CGFloat) -> Font {
        if UIFont(name: "JetBrainsMono-Regular", size: size) != nil {
            return .custom("JetBrainsMono-Regular", size: size)
        }
        return .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - GlowingOrb

struct GlowingOrb: View {
    let color: Color
    let size: CGFloat
    let blur: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
    }
}

// MARK: - StatCard

struct StatCard: View {
    let value: String
    let label: String
    let icon: String?
    let accentColor: Color

    init(value: String, label: String, icon: String? = nil, accentColor: Color = Color.drip.coral) {
        self.value = value
        self.label = label
        self.icon = icon
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            Text(value)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)

            Text(label.uppercased())
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - MoodBadge

struct MoodBadge: View {
    let mood: String

    var moodColor: Color {
        switch mood.lowercased() {
        case "energized": Color.drip.energized
        case "positive": Color.drip.positive
        case "neutral": Color.drip.neutral
        case "tired": Color.drip.tired
        case "struggling": Color.drip.struggling
        case "injured": Color.drip.injured
        default: Color.drip.neutral
        }
    }

    var moodIcon: String {
        switch mood.lowercased() {
        case "energized": "bolt.fill"
        case "positive": "face.smiling.fill"
        case "neutral": "minus.circle.fill"
        case "tired": "moon.fill"
        case "struggling": "exclamationmark.triangle.fill"
        case "injured": "bandage.fill"
        default: "circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: moodIcon)
                .font(.system(size: 9, weight: .bold))
            Text(mood.capitalized)
                .font(.dripCaption(10))
                .fontWeight(.semibold)
        }
        .foregroundStyle(moodColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(moodColor.opacity(0.15))
        .fixedSize()
        .clipShape(Capsule())
    }
}

// MARK: - PulsingRecordButton

struct PulsingRecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glow rings (when recording)
                if isRecording {
                    ForEach(0 ..< 3) { i in
                        Circle()
                            .stroke(Color.drip.coral.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: 140 + CGFloat(i) * 30, height: 140 + CGFloat(i) * 30)
                            .scaleEffect(pulseScale)
                    }
                }

                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.drip.coral.opacity(isRecording ? 0.6 : 0.3),
                                Color.drip.coral.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .opacity(glowOpacity)

                // Main button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.drip.coral, Color.drip.electric],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.drip.coral.opacity(0.5), radius: isRecording ? 30 : 15, x: 0, y: 10)

                // Inner icon
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .scaleEffect(isRecording ? 1.05 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isRecording)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
                glowOpacity = 0.6
            }
        }
    }
}

// MARK: - DripButton

struct DripButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let isLoading: Bool
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case ghost
    }

    init(_ title: String, icon: String? = nil, style: ButtonStyle = .primary, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(style == .primary ? .white : Color.drip.coral)
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(title)
                    .font(.dripLabel(15))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: style == .secondary ? 1.5 : 0)
            )
        }
        .disabled(isLoading)
    }

    var backgroundColor: Color {
        switch style {
        case .primary: Color.drip.coral
        case .secondary: Color.clear
        case .ghost: Color.drip.cardBackground
        }
    }

    var foregroundColor: Color {
        switch style {
        case .primary: .white
        case .secondary: Color.drip.coral
        case .ghost: Color.drip.textPrimary
        }
    }

    var borderColor: Color {
        switch style {
        case .secondary: Color.drip.coral
        default: .clear
        }
    }
}

// MARK: - DripBackground

struct DripBackground: View {
    var body: some View {
        ZStack {
            Color.drip.background

            // Subtle gradient orbs
            VStack {
                HStack {
                    Spacer()
                    GlowingOrb(color: Color.drip.coral.opacity(0.08), size: 300, blur: 100)
                        .offset(x: 100, y: -100)
                }
                Spacer()
                HStack {
                    GlowingOrb(color: Color.drip.coral.opacity(0.05), size: 250, blur: 80)
                        .offset(x: -80, y: 50)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    let action: (() -> Void)?
    let actionIcon: String?

    init(_ title: String, action: (() -> Void)? = nil, actionIcon: String? = nil) {
        self.title = title
        self.action = action
        self.actionIcon = actionIcon
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.5)

            Spacer()

            if let action, let icon = actionIcon {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

import SwiftUI
import UIKit

// MARK: - Color Palette

extension Color {
    /// Core palette - Editorial running magazine
    static let drip = DripColors()
}

// MARK: - DripColors

struct DripColors {
    // Backgrounds - Warm paper tones
    let background = Color(hex: "F5F3F0")       // Warm paper
    let cardBackground = Color(hex: "FFFFFF")    // Clean white
    let cardBackgroundElevated = Color(hex: "FAFAF8") // Slightly warm white
    let calendarBackground = Color(hex: "E8E4DF")    // Darker warm tone for calendar

    // Accents - Burnt orange editorial pop
    let coral = Color(hex: "D4592A")             // Burnt orange (primary accent)
    let coralLight = Color(hex: "E8764A")        // Lighter variant
    let electric = Color(hex: "B84420")          // Darker hover state

    // Mood colors - Muted editorial tones
    let energized = Color(hex: "2D8A4E")         // Deep green
    let positive = Color(hex: "4A9E6B")          // Sage green
    let neutral = Color(hex: "9B9590")           // Warm gray
    let tired = Color(hex: "C4873A")             // Amber
    let struggling = Color(hex: "C45A3A")        // Terracotta
    let injured = Color(hex: "B83A4A")           // Deep rose
    let speed = Color(hex: "6B4A8A")             // Plum (fast paces)

    // Text - Rich editorial contrast
    let textPrimary = Color(hex: "1A1815")       // Rich ink black
    let textSecondary = Color(hex: "6B6560")     // Warm gray
    let textTertiary = Color(hex: "9B9590")      // Light warm gray

    // Utility
    let divider = Color(hex: "E8E4E0")           // Warm rule line
    let success = Color(hex: "2D8A4E")           // Same as energized

    /// Simplified mood → border color: green (positive), amber (neutral/tired), red (struggling)
    func moodBorderColor(for mood: String?) -> Color? {
        guard let mood = mood?.lowercased() else { return nil }
        switch mood {
        case "energized", "positive": return energized
        case "neutral", "tired": return tired
        case "struggling", "injured": return struggling
        default: return nil
        }
    }
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

/// Editorial typography: Crimson Pro (display), PT Serif (body), SF Mono (stats)
/// "The Press" font pack — tall elegant magazine feel
extension Font {
    /// Display fonts - Crimson Pro headlines (tall, elegant serif)
    static func dripDisplay(_ size: CGFloat) -> Font {
        .custom("CrimsonPro-Regular", size: size).weight(.bold)
    }

    /// Stats - Monospaced for numbers (lighter weight, refined)
    static func dripStat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Body text - PT Serif (warm, readable editorial body)
    static func dripBody(_ size: CGFloat) -> Font {
        .custom("PTSerif-Regular", size: size)
    }

    /// Labels - Crimson Pro semibold for buttons and labels
    static func dripLabel(_ size: CGFloat) -> Font {
        .custom("CrimsonPro-Regular", size: size).weight(.semibold)
    }

    /// Meta/Captions - PT Serif for small text with tracking
    static func dripCaption(_ size: CGFloat) -> Font {
        .custom("PTSerif-Regular", size: size)
    }
}

// MARK: - GlowingOrb (no-op for editorial — clean backgrounds)

struct GlowingOrb: View {
    let color: Color
    let size: CGFloat
    let blur: CGFloat

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
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
        .background(moodColor.opacity(0.12))
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

    var body: some View {
        Button(action: action) {
            ZStack {
                // Subtle ring when recording
                if isRecording {
                    Circle()
                        .stroke(Color.drip.coral.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                }

                // Main button — clean, solid
                Circle()
                    .fill(Color.drip.coral)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.drip.coral.opacity(0.3), radius: 12, x: 0, y: 4)

                // Inner icon
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                    }
                }
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .scaleEffect(isRecording ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
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
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
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
        Color.drip.background
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
        VStack(spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.dripCaption(11))
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

            // Thin editorial rule line
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }
}

import SwiftUI
import UIKit

// MARK: - Distance units (user-selectable)
//
// The app stores every distance internally in MILES. This is purely a
// display-layer choice: `DistanceUnit` is the athlete's preference (default
// `.miles`), persisted under the `"distanceUnit"` UserDefaults key so any
// view using `@AppStorage("distanceUnit")` re-renders the instant it flips.
// `DistanceFormat` is the single place that converts a stored mile value into
// what the user sees — distance, unit label, and pace. Route every distance/
// pace label through it so units can never drift screen-to-screen again.

enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    /// Uppercase column/stat label — "MI" / "KM".
    var label: String { self == .miles ? "MI" : "KM" }
    /// Lowercase inline / per-unit label — "mi" / "km".
    var short: String { self == .miles ? "mi" : "km" }
    /// Full name for the Settings picker.
    var displayName: String { self == .miles ? "Miles" : "Kilometers" }
}

enum DistanceFormat {
    static let kmPerMile = 1.609344

    /// The current preference, read straight from storage. Views that must
    /// re-render on change should hold their own `@AppStorage("distanceUnit")`
    /// and pass the resolved unit in, rather than relying on this.
    static var current: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "") ?? .miles
    }

    /// Convert a stored mile value into the target unit's numeric value.
    static func convert(miles: Double, to unit: DistanceUnit) -> Double {
        unit == .kilometers ? miles * kmPerMile : miles
    }

    /// Formatted distance value only (no unit), matching the app's convention:
    /// whole numbers at 100+, one decimal below.
    static func value(miles: Double, unit: DistanceUnit = current) -> String {
        let v = convert(miles: miles, to: unit)
        return v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    /// Value + inline unit, e.g. "12.4 mi" / "20.0 km".
    static func string(miles: Double, unit: DistanceUnit = current) -> String {
        "\(value(miles: miles, unit: unit)) \(unit.short)"
    }

    /// Convert a pace given in seconds-per-mile into "m:ss" for the target
    /// unit. km pace is *slower* per unit, so seconds ÷ 1.609344.
    static func paceMMSS(secPerMile: Double, unit: DistanceUnit = current) -> String {
        let sec = unit == .kilometers ? secPerMile / kmPerMile : secPerMile
        let t = Int(sec.rounded())
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }

    /// Re-express an already-formatted per-mile pace string ("8:24") in the
    /// target unit. Returns the input unchanged if it can't be parsed.
    static func convertPaceString(_ mmssPerMile: String, to unit: DistanceUnit) -> String {
        guard unit == .kilometers else { return mmssPerMile }
        let parts = mmssPerMile.split(separator: ":")
        guard parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) else { return mmssPerMile }
        return paceMMSS(secPerMile: Double(m * 60 + s), unit: unit)
    }
}

// MARK: - Color Palette

extension Color {
    /// Core palette - Editorial running magazine
    static let drip = DripColors()
}

// MARK: - DripColors

struct DripColors {
    /// Which palette every token below resolves to.
    ///
    /// REDESIGN-SAFELY.md §5: "a completely new palette … can be applied to
    /// the entire app by editing roughly 60 lines in one file." This is that
    /// edit. Reading it from a view body registers with `@Observable`, so
    /// flipping the skin in ☰ repaints live.
    ///
    /// NOT swapped, deliberately: `paceFast` and everything in
    /// `PaceSpectrum.swift`. Blue owns pace, the ramp is ordered dark = fast,
    /// and PALETTE.md is explicit that the ordering IS the information.
    /// Recolouring it to match a rebrand would destroy the data.
    private var wild: Bool { DripSkinStore.shared.skin == .wild }

    // Backgrounds - Warm paper tones
    var background: Color { wild ? Color(hex: "FFFFFF") : Color(hex: "FAFAF9") }       // Off-white paper (was warm cream F5F3F0)
    var cardBackground: Color { wild ? Color(hex: "FFFFFF") : Color(hex: "FFFFFF") }    // Clean white
    var cardBackgroundElevated: Color { wild ? Color(hex: "FFFFFF") : Color(hex: "FFFFFF") } // On off-white paper there is no room
                                                      // for a third surface — collapses to card.
    var calendarBackground: Color { wild ? Color(hex: "F2F2F2") : Color(hex: "F0F0EE") }    // Neutral inset well (was E8E4DF)

    // Accents - Burnt orange editorial pop
    var coral: Color { wild ? Color(hex: "EE2B24") : Color(hex: "E63946") }             // Scarlet (primary accent)
    // NOTE: the token is still *named* coral. Renaming it would touch ~5,900
    // callsites, so the rename is a separate mechanical pass — not this one.
    var coralLight: Color { wild ? Color(hex: "EE2B24") : Color(hex: "F2616C") }        // Lighter variant
    /// `--coral-deep` from `design-system/colors_and_type.css` (#B84420).
    /// The press / hover state of `coral` (e.g. the primary record button
    /// darkening). Per the design system, the one coral accent only ever
    /// deepens to this — it never shifts hue.
    var coralDeep: Color { wild ? Color(hex: "D31F19") : Color(hex: "C42A36") }         // Press/hover state
    /// Deprecated alias for `coralDeep`. The old name read like a Stripe
    /// color, not the editorial press-state coral. Retained so any stray
    /// reference keeps compiling; migrate callsites to `coralDeep`.
    @available(*, deprecated, renamed: "coralDeep")
    var electric: Color { coralDeep }
    /// `--coral-wash` from `design-system/colors_and_type.css`:
    /// `rgba(212, 89, 42, 0.12)`. Capsule fill / tint behind the active
    /// segmented chip, the "Maintaining" pill, etc. Per the design system
    /// README, this is *"the only transparency in the system."*
    var coralWash: Color { wild
        ? Color(red: 238/255, green: 43/255, blue: 36/255, opacity: 0.10)
        : Color(red: 230/255, green: 57/255, blue: 70/255, opacity: 0.12) }

    // Mood colors - Muted editorial tones
    var energized: Color { wild ? Color(hex: "12703A") : Color(hex: "2D8A4E") }         // Deep green
    var positive: Color { wild ? Color(hex: "1F7A41") : Color(hex: "4A9E6B") }          // Sage green
    var neutral: Color { wild ? Color(hex: "6B6B6B") : Color(hex: "9B9590") }           // Warm gray
    var tired: Color { wild ? Color(hex: "A8560A") : Color(hex: "C4873A") }             // Amber
    var struggling: Color { wild ? Color(hex: "B3261E") : Color(hex: "C45A3A") }        // Terracotta
    var injured: Color { wild ? Color(hex: "8E1219") : Color(hex: "B83A4A") }           // Deep rose

    // Pace — rides the brand accent hue. This is the burnt-brick (Mile)
    // end of the universal pace ramp; the full ramp is PaceSpectrum.swift.
    // (Renamed from `speed` 2026-07-03; reverted from a same-day coral rebrand 2026-08-21.)
    // It sits far enough below `coral` in lightness (L .33 vs .62) to stay
    // readable against it when both appear on one card.
    let paceFast = Color(hex: "0E1D4E")          // Navy — fast paces (Mile end of the pace ramp)

    // Text - Rich editorial contrast
    // INK — a cool near-black, and the ramp below is the same ink diluted.
    // Richness here is chroma, not darkness: #000 has zero chroma and reads
    // as a hole punched in the paper, not as ink. This ramp leans blue for
    // two reasons — it opposes the scarlet accent (so scarlet reads more
    // scarlet), and it rhymes with #0E1D4E, the Mile end of the pace ramp
    // that is already in the palette. Warm ink belonged to the cream paper;
    // on neutral paper it has nothing to sit with.
    var textPrimary: Color { wild ? Color(hex: "111111") : Color(hex: "0D1016") }       // Cool near-black — 18.2:1 on paper
    var textSecondary: Color { wild ? Color(hex: "6B6B6B") : Color(hex: "585D68") }     // Same ink, diluted — 6.3:1
    var textTertiary: Color { wild ? Color(hex: "9A9A9A") : Color(hex: "8F95A1") }      // Same ink, diluted further — 2.9:1.
                                                 // No longer shares a value with the
                                                 // `neutral` MOOD (9B9590) — that is
                                                 // deliberate: moods are unchanged.

    // Utility
    var divider: Color { wild ? Color(hex: "EBEBEB") : Color(hex: "E6E7EA") }           // The ink at its faintest — same hue
    var success: Color { wild ? Color(hex: "12703A") : Color(hex: "2D8A4E") }           // Same as energized
    /// `--paper-deep` from `design-system/colors_and_type.css` (#E8E4DF).
    /// Calendar / inset wells, histogram tracks behind a fill bar.
    /// Slightly darker than `background`.
    var paperDeep: Color { wild ? Color(hex: "F2F2F2") : Color(hex: "F0F0EE") }

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
    /// Which type system every role below resolves to. See `DripTheme.swift`.
    private static var wild: Bool { DripSkinStore.shared.skin == .wild }

    /// Display fonts - Crimson Pro headlines (tall, elegant serif)
    static func dripDisplay(_ size: CGFloat) -> Font {
        wild
            ? .custom(WildFace.display, size: size)
            : .custom("CrimsonPro-Regular", size: size).weight(.bold)
    }

    /// Stats - Monospaced for numbers (lighter weight, refined)
    static func dripStat(_ size: CGFloat) -> Font {
        // Inter, tabular. §1: "Every numeral, tabular." Inter is barred from
        // display on purpose — Inter on numerals against a tighter grotesk on
        // headlines is the contrast the system is built on.
        wild
            ? .custom(WildFace.dataSemibold, size: size).monospacedDigit()
            : .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Body text - PT Serif (warm, readable editorial body)
    static func dripBody(_ size: CGFloat) -> Font {
        // Inter. The Data role "doubles as body/UI copy" — Crimson is reserved
        // for prose the athlete actually wrote, which is a different job.
        wild
            ? .custom(WildFace.dataRegular, size: size)
            : .custom("PTSerif-Regular", size: size)
    }

    /// Labels - Crimson Pro semibold for buttons and labels
    static func dripLabel(_ size: CGFloat) -> Font {
        // Buttons and links — sentence-case, so the display face at 500, not
        // the tracked-caps label role (that is `dripEyebrow`).
        wild
            ? .custom(WildFace.displayMedium, size: size)
            : .custom("CrimsonPro-Regular", size: size).weight(.semibold)
    }

    /// Eyebrows - SF Mono medium for the editorial uppercase labels
    /// (TUESDAY, FROM YOUR COACH, ZONE SHIFTS). Apply `.tracking()` at
    /// the callsite per spec:
    ///   • caption    +0.10em (TIRED / EASY pills)        — size × 0.10
    ///   • label      +0.12em (SECTION HEADERS)           — size × 0.12
    ///   • plate meta +0.14em (top plate strip)           — size × 0.14
    /// The CSS source of truth is `Post Run Drip Design System/colors_and_type.css`.
    static func dripEyebrow(_ size: CGFloat) -> Font {
        // Schibsted Grotesk — THE label role. Mono is reserved for transcripts
        // and machine answers; the design doc lists these mono labels as the
        // era-one hangover to retype, and this is that retyping.
        wild
            ? .custom(WildFace.label, size: size)
            : .system(size: size, weight: .medium, design: .monospaced)
    }

    /// Body italic — PT Serif Italic. This is the product's *voice*:
    /// transcribed voice logs, coach notes, and the quiet instructional
    /// lines under a headline.
    ///
    /// It exists because those callsites were written as
    /// `.system(size:, design: .serif).italic()`, which renders **New York**,
    /// not PT Serif — so the journal voice had silently drifted off the
    /// design system on every surface that used it. PTSerif-Italic.ttf is
    /// already bundled and listed in Info.plist's UIAppFonts.
    static func dripBodyItalic(_ size: CGFloat) -> Font {
        // The single-line italic dek — Times, and this is its only role.
        //
        // Note this token also fronts transcribed voice logs at a few call
        // sites, and those want italic MONO (the athlete's voice), not the
        // dek. `JournalWildRow` sets its own; any other surface showing a
        // transcript needs the same treatment by hand.
        wild
            ? .custom(WildFace.serifItalic, size: size)
            : .custom("PTSerif-Italic", size: size)
    }

    /// Meta/Captions - PT Serif for small sentence-case body
    /// (error messages, inline hints). Despite the name, this is NOT the
    /// canonical caption per the design system spec — see `dripEyebrow`
    /// above for uppercase labels. Rename pending.
    static func dripCaption(_ size: CGFloat) -> Font {
        wild
            ? .custom(WildFace.dataRegular, size: size)
            : .custom("PTSerif-Regular", size: size)
    }
}

// MARK: - Dynamic Type floors

/// Sizes for the micro editorial labels, as `@ScaledMetric` bases.
///
/// **Why this exists.** Every drip font above is built with a literal point
/// size — `.system(size:)` and `.custom(_:size:)` with no `relativeTo:` — so
/// none of them respond to the reader's Dynamic Type setting. At display and
/// body sizes that is the editorial intent. At the micro end it is an
/// accessibility failure: the chart eyebrows, axis labels and legends on the
/// Trends page sit at 7.5–8pt and stay there at every accessibility size.
///
/// A surface opts in by declaring a `@ScaledMetric` against one of these
/// bases and passing the result to `dripEyebrow(_:)`:
///
///     @ScaledMetric(relativeTo: .caption2)
///     private var eyebrowMicro: CGFloat = DripTypeFloor.eyebrowMicro
///
/// The base is the *floor* — 9pt rather than the 7.5–8pt these labels used,
/// because below 9 the mono face stops being legible for readers who need
/// the setting at all. Scaling only ever goes up from there.
enum DripTypeFloor {
    /// Chart furniture: lane headers, legends, axis ticks, footnotes.
    static let eyebrowMicro: CGFloat = 9
    /// Row-level labels that already sat at 8.5–9.5pt.
    static let eyebrowSmall: CGFloat = 10
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
                .font(.dripEyebrow(10))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.0)  // 0.10em caption tracking at 10pt
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - MoodBadge

/// Tracked-uppercase capsule with a small color dot. Per the design
/// system spec: *"Mood is communicated through tracked uppercase pills
/// + dot color, not faces. No emoji."* The SF Symbol icons that used to
/// live here (`face.smiling.fill`, `bandage.fill`, etc.) were a direct
/// violation — replaced with a 5px filled dot in the mood color.
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

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(moodColor)
                .frame(width: 5, height: 5)
            Text(mood.uppercased())
                .font(.dripEyebrow(10))
                .tracking(1.0)  // 0.10em caption tracking at 10pt
        }
        .foregroundStyle(moodColor)
        // Direction I: "a mood is always type or a dot, never a large fill."
        // The tinted capsule put six saturated washes on a page whose rule is
        // one red — and at pill size `struggling` and the brand red read as
        // the same colour, so the alert stopped being an alert.
        .padding(.horizontal, DripSkinStore.shared.skin == .wild ? 0 : 10)
        .padding(.vertical, DripSkinStore.shared.skin == .wild ? 0 : 5)
        .background {
            if DripSkinStore.shared.skin != .wild {
                Capsule().fill(moodColor.opacity(0.12))
            }
        }
        .fixedSize()
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
                    .font(.dripEyebrow(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.3)  // 0.12em label tracking at 11pt

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

// MARK: - Editorial primitives (the plate chrome)
//
// These four — PlateStrip, PlateFooter, CoachQuote, Hairline — plus the
// EditorialRule below are the gestures that make a screen feel like a
// printed plate instead of an app view. They live here so every editorial
// surface (Today, Training, Workout Detail, Injuries) can compose them
// without inventing its own.
//
// Source: `Post Run Drip Design System/README.md` and `colors_and_type.css`.

/// Top-of-plate strip: surface label left, fig number right. Mono, tracked
/// `+0.14em`, on the paper background. Per README: *"the single most
/// identifiable visual gesture"* of the design system.
///
/// Usage: `PlateStrip(surface: "LOG · v1 DIARY + CHARTS", fig: TrainingDateline.string(for: goal))`
///
/// The trailing slot is the *training dateline* — a goal countdown when one
/// exists (e.g. "BERLIN −86D"), else nil → the slot renders nothing. It used
/// to be a fake figure number; pass `TrainingDateline.string(for:)`, never a
/// hardcoded "FIG. NN".
struct PlateStrip: View {
    let surface: String
    let fig: String?

    init(surface: String, fig: String? = nil) {
        self.surface = surface
        self.fig = fig
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(surface)
                .font(.dripEyebrow(10))
                .tracking(1.4)  // 0.14em meta tracking at 10pt
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 16)
            if let fig {
                Text(fig)
                    .font(.dripEyebrow(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Bottom-of-plate footer: an optional italic-serif caption above the
/// canonical signature line. The README quotes a sample footer:
/// *"Diary spine on top, cockpit's bottom half on the bottom. Strain/TSB
/// tiles dropped — data not honest yet."* — that's the register.
///
/// Pass `nil` (or use the no-arg init) to render only the signature line.
struct PlateFooter: View {
    let caption: String?

    init(_ caption: String? = nil) {
        self.caption = caption
    }

    // The standing tagline that used to print under every caption
    // ("restraint as foundation, intensity as accent") was removed 2026-08-09.
    // It appeared on five unrelated surfaces, said nothing about the data on
    // any of them, and read as generated filler rather than as the plate's
    // own voice. A footer now prints the caller's caption or nothing at all —
    // an empty `PlateFooter()` renders nothing, which is the correct amount to
    // say when there is nothing to say.
    var body: some View {
        if let caption {
            Text(caption)
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The canonical "from your coach" treatment: italic-serif body with a
/// 2px coral-at-50%-opacity left bar inset by 12px. Per README:
/// *"This is the one place a coloured left-border appears in the system.
/// Do not generalize."*
///
/// Pass `text` raw — the primitive wraps it in curly quotes itself.
struct CoachQuote: View {
    let text: String

    var body: some View {
        Text("\u{201C}\(text)\u{201D}")
            .font(.system(size: 15, design: .serif).italic())
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.drip.coral.opacity(0.5))
                    .frame(width: 2)
            }
    }
}

/// A plain 1px rule — distinct from `EditorialRule`. The JSX uses both:
/// `<Hairline>` for tight separators inside a section (e.g., between
/// stat rows), `<EditorialRule>` (line · dot · line) for section breaks.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// The canonical section break: `line · dot · line`. The README calls
/// this *"a typesetting mark, not a divider in the usual product-design
/// sense."* Use between editorial sections, not inside cards.
///
/// Replaces the private duplicates that used to live in `TodayHomeView`,
/// `TrainingTabView`, and `InjuryPlate28` (`InjuryRule28`). The fourth,
/// `WorkoutDetailPlate23`'s `WD23EditorialRule`, went with that file when the
/// workout-detail fork was deleted (Phase B, 2026-07-14).
struct EditorialRule: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
            Circle()
                .fill(Color.drip.divider)
                .frame(width: 3, height: 3)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
    }
}

// MARK: - Status bar scrim

/// The band behind the iOS status bar — the clock, the location arrow,
/// signal, wifi and battery.
///
/// WHY THIS EXISTS. A `ScrollView` draws its content *through* the top safe
/// area. That is correct iOS behaviour: in a stock app an opaque navigation
/// bar sits in that band and hides whatever slides under it. This app has no
/// opaque bar anywhere — some surfaces hide the navigation bar outright, the
/// rest carry a title-less transparent one — so the band was empty on every
/// tab and scrolled type ran straight into the system clock and battery
/// (Rio, 2026-08-18: *"the time and battery can run into fonts on the app"*,
/// *"in every page of the app it needs this"*).
///
/// WHAT IT LOOKS LIKE. Strava's treatment, which Rio asked for by example:
/// a frosted band rather than a hard cut. Type does not vanish at a line —
/// it blurs, washes toward paper, and dissolves. Three layers, top to
/// bottom of the stack:
///
///   1. `.ultraThinMaterial` — the actual blur of whatever is behind.
///   2. A paper wash over it, because bare material renders cool grey and
///      this app is warm off-white. Without it the band reads as a stripe.
///   3. A gradient MASK: fully opaque across the status bar itself, so the
///      clock is always clean, then falling to nothing over `fade` points
///      below it. The mask is what makes it a dissolve instead of an edge.
///
/// HOW THE HEIGHT IS DERIVED. From the active window's top safe-area inset,
/// read out of UIKit — the status bar on an older phone, the Dynamic Island
/// on a newer one. No hardcoded 20 / 44 / 47 / 59pt to keep in sync with the
/// next iPhone.
///
/// The first version of this asked for a ZERO-height view and let
/// `ignoresSafeArea` stretch it over the band. Cleaner to read, and it drew
/// nothing: a view with no height is free to be skipped, and this band has
/// to draw. Measure the height, then bleed.
///
/// It never takes touches, so a chip or button scrolling under it is hidden,
/// never intercepted.
///
/// APPLIED ONCE, AT THE ROOT — `MainTabView` in `RunningLogApp.swift`, on the
/// tab container. Do not also apply it per-tab: two scrims are invisible
/// today, but they are two things to keep in sync tomorrow.
struct DripStatusBarScrim: View {
    /// The surface colour washed over the blur. Defaults to the app's paper.
    var color: Color = Color.drip.background

    /// How far below the status bar the dissolve runs. Keep this short — it
    /// covers whatever sits at the top of the scroll at rest, not just what
    /// scrolls past it.
    var fade: CGFloat = 14

    /// How much paper is washed over the blur. 0 = raw material (cool grey),
    /// 1 = flat colour with the blur invisible underneath.
    var wash: Double = 0.55

    private var inset: CGFloat { Self.statusBarHeight }
    private var total: CGFloat { inset + fade }

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay { color.opacity(wash) }
            .frame(maxWidth: .infinity)
            .frame(height: total)
            .mask(alignment: .top) {
                LinearGradient(
                    stops: [
                        // Solid across the status bar — the clock never sits
                        // on a half-faded background.
                        .init(color: .black, location: 0),
                        .init(color: .black, location: max(0.001, inset / total)),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Bleed up out of the safe area so the band lands ON the status
            // bar rather than below it. Same move the offline banner in
            // `RunningLogApp` makes, and it is known to work there.
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    /// The active window's top safe-area inset.
    ///
    /// Falls back to 47pt — the Dynamic Island inset — rather than 0. If the
    /// window can't be found, painting a slightly wrong band beats painting
    /// none: the failure that brought us here was an EMPTY band.
    static var statusBarHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 47
    }
}

extension View {
    /// Paint the status bar band so scrolling content dissolves *behind* the
    /// clock and battery instead of colliding with them.
    ///
    /// Applied at the root of the tab container, so every tab inherits it.
    /// A surface presented OUTSIDE that container — a `fullScreenCover` with
    /// no navigation bar of its own — is the one case that needs its own
    /// call. Sheets do not: they present as an inset card that never reaches
    /// the status bar.
    ///
    /// Pass `color` when the surface underneath is not paper, or the wash
    /// will read as a stripe.
    func dripStatusBarScrim(
        color: Color = Color.drip.background,
        fade: CGFloat = 14
    ) -> some View {
        overlay(alignment: .top) {
            DripStatusBarScrim(color: color, fade: fade)
        }
    }
}

//
//  DripTheme.swift
//  RunningLog
//
//  The two-skin switch from REDESIGN-SAFELY.md §5.
//
//  `editorial` is the app you have today. `wild` is Direction I of the
//  design system: white stock, one red, Instrument Sans on headlines,
//  Schibsted Grotesk on labels, Inter on numerals, JetBrains Mono for
//  the athlete's transcribed words.
//
//  DELIBERATELY NOT GLOBAL (yet). `Color.drip` and every `.dripDisplay(_:)`
//  callsite are untouched, so the other five tabs render exactly as before.
//  The wild tokens live in their own namespace — `Color.wild`, `.wild*(_:)`
//  fonts — and today only `LogWildView` reads them.
//
//  To go global later, REDESIGN-SAFELY.md §5 is still the plan: make
//  `DripColors` a struct with `.editorial` / `.wild` instances and change
//  `static let drip = DripColors()` to `static var drip: DripColors`. That
//  is a separate, deliberate pass — it repaints all six tabs at once.
//
//  Token source of truth: `POSTRUNDRIPSYSTEM.md` §2 (colour) and §1 (type).
//

import SwiftUI

// MARK: - Skin

enum DripSkin: String, CaseIterable {
    case editorial
    case wild

    var label: String {
        switch self {
        case .editorial: return "Editorial"
        case .wild: return "Wild"
        }
    }
}

/// Which skin renders. Observable so a flip re-renders the tab live.
///
/// `@AppStorage` is deliberately NOT used here: it is a `DynamicProperty`
/// built for a View's storage, and as a `static var` on a type it reads and
/// writes fine but never publishes a change — the switch would only take
/// effect on relaunch. `@Observable` + an explicit `UserDefaults` write is
/// the same pattern `KeySessionStore` uses.
@Observable
final class DripSkinStore {
    static let shared = DripSkinStore()

    private static let key = "dripSkin"

    var skin: DripSkin {
        didSet {
            guard skin != oldValue else { return }
            UserDefaults.standard.set(skin.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        skin = DripSkin(rawValue: raw ?? "") ?? .editorial
    }

    func toggle() {
        skin = (skin == .wild) ? .editorial : .wild
    }
}

// MARK: - Colour · Direction I

/// Direction I tokens, verbatim from `POSTRUNDRIPSYSTEM.md` §2.
///
/// Note `ink3` — 2.8:1 — is for hairlines and disabled states only, never
/// for text. The doc is explicit about it and this comment exists so the
/// next person doesn't reach for it as a caption colour.
struct WildColors {
    // Surfaces and ink
    let paper = Color(hex: "FFFFFF")
    let paperDeep = Color(hex: "F2F2F2")     // inset wells only
    let rule = Color(hex: "EBEBEB")          // the hairline
    let ruleStrong = Color(hex: "111111")    // 2pt editorial rule
    let ink = Color(hex: "111111")
    let ink2 = Color(hex: "6B6B6B")          // 5.3:1 — safe at 10pt
    let ink3 = Color(hex: "9A9A9A")          // hairlines and disabled ONLY

    // Accents. One red: it points, it never fills a large surface —
    // the record button being the single stated exception.
    let red = Color(hex: "EE2B24")
    let redText = Color(hex: "D31F19")       // the same red as type, ≤13pt
    let redWash = Color(red: 238 / 255, green: 43 / 255, blue: 36 / 255, opacity: 0.10)
    let session = Color(hex: "1F4FA8")       // names a keyed session, and references

    // Mood ramp — green good → grey nothing → orange tired → two reds.
    // All clear 4.5:1, because a mood is always type or a rule, never a fill.
    let energized = Color(hex: "12703A")
    let positive = Color(hex: "1F7A41")
    let neutral = Color(hex: "6B6B6B")
    let tired = Color(hex: "A8560A")
    let struggling = Color(hex: "C62828")
    let injured = Color(hex: "8E1219")

    /// Mood → colour. Unknown / absent mood gets `ink3`, which is correct
    /// here because it is used as a 2pt rule, not as text.
    func mood(_ mood: String?) -> Color {
        switch (mood ?? "").lowercased() {
        case "energized": return energized
        case "positive": return positive
        case "neutral": return neutral
        case "tired": return tired
        case "struggling": return struggling
        case "injured": return injured
        default: return ink3
        }
    }

    /// Mood → colour for the mood WORD at the foot of an entry. Same ramp,
    /// except an absent mood has no word to colour, so callers skip it.
    func moodText(_ mood: String?) -> Color {
        let c = self.mood(mood)
        return c == ink3 ? ink2 : c
    }
}

extension Color {
    /// Direction I palette. Scoped to the wild skin — see the file header.
    static let wild = WildColors()
}

// MARK: - Type · Direction I

/// Five roles, one face each, plus Times italic in exactly one place.
/// `POSTRUNDRIPSYSTEM.md` §1. Never introduce a sixth family.
///
/// PostScript names, not family names — `.custom(_:size:)` wants the
/// PostScript name and silently falls back to the system font when it
/// doesn't match. If a screen renders in San Francisco, that is the bug.
enum WildFace {
    static let display = "InstrumentSans-Bold"          // 700
    static let displayMedium = "InstrumentSans-Medium"  // 500
    static let label = "SchibstedGrotesk-SemiBold"      // 600
    static let labelBold = "SchibstedGrotesk-Bold"      // 700
    static let data = "Inter-Medium"                    // 500
    static let dataSemibold = "Inter-SemiBold"          // 600
    static let dataRegular = "Inter-Regular"            // 400
    static let mono = "JetBrainsMono-Regular"           // machine
    static let monoItalic = "JetBrainsMono-Italic"      // the athlete
    static let monoMedium = "JetBrainsMono-Medium"
    /// Crimson Pro is already bundled (variable file, PostScript name
    /// `CrimsonPro-Regular`) and already used by the editorial skin.
    static let prose = "CrimsonPro-Regular"
    /// Times ships with iOS — nothing to bundle. Exactly one role: the dek.
    static let serifItalic = "TimesNewRomanPS-ItalicMT"
}

extension Font {
    /// Display — every headline. Sentence case, tracking −0.035em to
    /// −0.05em, one line where possible.
    static func wildDisplay(_ size: CGFloat) -> Font {
        .custom(WildFace.display, size: size)
    }

    /// Label — every tracked uppercase label. 9–11pt. Apply `.tracking()`
    /// at the callsite: `size * 0.12` … `size * 0.16`.
    static func wildLabel(_ size: CGFloat) -> Font {
        .custom(WildFace.label, size: size)
    }

    /// Data — every numeral, tabular. Doubles as body / UI copy.
    /// Pair with `.monospacedDigit()` at the callsite.
    static func wildData(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? WildFace.dataSemibold : WildFace.data, size: size)
    }

    static func wildDataRegular(_ size: CGFloat) -> Font {
        .custom(WildFace.dataRegular, size: size)
    }

    /// Prose — anything read as sentences that the athlete WROTE.
    static func wildProse(_ size: CGFloat) -> Font {
        .custom(WildFace.prose, size: size)
    }

    /// Italic mono is the athlete: a transcript, in their own voice.
    static func wildSaid(_ size: CGFloat) -> Font {
        .custom(WildFace.monoItalic, size: size)
    }

    /// Roman mono is the machine: a value it computed. No colour of its own.
    static func wildMachine(_ size: CGFloat) -> Font {
        .custom(WildFace.monoMedium, size: size)
    }

    /// The single-line italic dek. The only place Times appears.
    static func wildDek(_ size: CGFloat) -> Font {
        .custom(WildFace.serifItalic, size: size)
    }
}

// MARK: - Primitives

/// The hairline. Direction I replaces cards, tints and shadows with these.
struct WildRule: View {
    var strong: Bool = false
    var body: some View {
        Rectangle()
            .fill(strong ? Color.wild.ruleStrong : Color.wild.rule)
            .frame(height: strong ? 2 : 1)
    }
}

/// A tracked uppercase label — the only label role in the skin.
struct WildLabel: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 0.12
    var color: Color = Color.wild.ink2

    init(_ text: String,
         size: CGFloat = 11,
         tracking: CGFloat = 0.12,
         color: Color = Color.wild.ink2) {
        self.text = text
        self.size = size
        self.tracking = tracking
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.wildLabel(size))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

/// The record button. 132pt of the one red — the single place the skin's
/// restraint deliberately breaks (`POSTRUNDRIPSYSTEM.md` §2: "Fills:
/// record button"). Tap to record, tap to stop; the white dot becomes a
/// square, and the ring breathes while recording.
struct WildRecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color(hex: "F0C6C4"), lineWidth: 1)
                    .frame(width: 166, height: 166)
                    .scaleEffect(breathe ? 1.07 : 1.0)
                    .opacity(breathe ? 0.45 : 1.0)

                Circle()
                    .fill(isDisabled ? Color.wild.ink3 : Color.wild.red)
                    .frame(width: 132, height: 132)

                RoundedRectangle(cornerRadius: isRecording ? 3 : 23)
                    .fill(Color.white)
                    .frame(width: isRecording ? 34 : 46,
                           height: isRecording ? 34 : 46)
            }
            .frame(width: 176, height: 176)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .onChange(of: isRecording) { _, now in
            guard !reduceMotion else { breathe = false; return }
            if now {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { breathe = false }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isRecording)
    }
}

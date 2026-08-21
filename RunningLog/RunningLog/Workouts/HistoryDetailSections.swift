//
//  HistoryDetailSections.swift
//  RunningLog
//
//  Supporting section views and extensions for history detail views.
//

// `os`, `Supabase` and `Auth` were only needed by the two removed sections
// (they called the coaching-agent edge function directly). What's left is pure
// SwiftUI + Foundation.
import SwiftUI

// NOTE (log-detail redesign): `CoachInsightSection` and `WorkoutNotesSection`
// were removed from here. Both were defined and never referenced anywhere in
// the app — the live journal entry sheet builds these sections itself in
// `HistoryDetailSheet+Editorial.swift` (the coach insight now lives behind the
// "✦ READ THE INSIGHT" row; workout notes behind "＋ ADD A NOTE").
//
// What is still live in this file: EditableMoodPicker, EditableWorkoutTypeSection,
// EditableWorkoutStatsSection, and the Date/String extensions below.


// MARK: - EditableMoodPicker

/// The six moods as a rail of wash pills.
///
/// **Selection is a 1.5pt coral ring, not a fill.** Two design-system rules
/// converge here: moods render *"as a tracked uppercase pill at 12% wash,
/// never as a full fill"*, and the coral ring is the system's one documented
/// selected/active mark (*"1.5px solid #D4592A — the active mood radio, the
/// active week-strip cell ring"*). The previous solid-green selected pill
/// broke both, and put a second saturated hue on a screen allowed exactly one
/// accent. (2026-08-20)
///
/// Geometry is deliberately identical to `MoodBadge` — 10pt mono, 1.0
/// tracking, 10/5 padding, 12% wash. The pill you tap in the picker is the
/// same object as the pill printed on the entry, so choosing a mood reads as
/// setting the badge rather than operating a control that produces one.
struct EditableMoodPicker: View {
    @Binding var selectedMood: String

    private let moods = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "energized": return Color.drip.energized
        case "positive": return Color.drip.positive
        case "neutral": return Color.drip.neutral
        case "tired": return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured": return Color.drip.injured
        default: return Color.drip.neutral
        }
    }

    // Mood pills follow the design-system spec: tracked uppercase label
    // with a color dot, no SF Symbol icons. The `moodIcon` helper that
    // used to live here was a direct violation of the "no emoji, no
    // faces" rule — deleted.

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    let isSelected = selectedMood == mood
                    Button {
                        selectedMood = isSelected ? "" : mood
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(moodColor(mood))
                                .frame(width: 5, height: 5)
                            Text(mood.uppercased())
                                .font(.dripEyebrow(10))
                                .tracking(1.0)  // 0.10em caption tracking at 10pt
                        }
                        .foregroundStyle(moodColor(mood))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(moodColor(mood).opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.drip.coral, lineWidth: isSelected ? 1.5 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            // The ring is drawn on the pill's edge; without a point of slack
            // the scroll view clips it on the selected chip.
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }
}

// MARK: - EditableWorkoutTypeSection

/// The workout-label rail — mono caps chips, hairline outlines, one coral.
///
/// **Was a card of coral-wash pills.** Eleven of them, every one filled at
/// `coral.opacity(0.12)`, under a heading decorated with a coral
/// `figure.run` SF Symbol. That is coral as paint. The spec is explicit:
/// coral is *"used like punctuation… one coral element per visual cluster,
/// maximum."* So the rail is now ink-2 on hairline, and the **selected chip
/// is the cluster's single coral hit** — a 1.5pt coral ring and coral label,
/// the same selected mark the mood rail above it uses.
///
/// Also gone: the wrapping card. This section sits directly on paper between
/// two editorial rules. The old card held inset chips inside it, which is
/// card-on-card — the one composition the system names outright as forbidden.
/// (2026-08-20)
struct EditableWorkoutTypeSection: View {
    @Binding var selectedType: String

    /// The type this entry arrived with, captured once. Seeding the legacy
    /// appendix from `selectedType` instead would make the legacy chip vanish
    /// the moment you tap a canonical one — with no way back to it.
    @State private var arrivedAs: String?

    /// Was a private 6-key list of its own — the one that wrote `"interval"`
    /// while the receipt's picker wrote `"intervals"`, leaving 14 rows under
    /// one spelling and 9 under the other. Single source of truth since
    /// 2026-08-07: `WorkoutLabel.offered`, which also carries the retirement of
    /// "Tempo"/"Threshold" this list predated.
    private var workoutTypes: [(String, String)] {
        WorkoutLabel.options(including: arrivedAs ?? selectedType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mono, per spec. Was `.dripCaption(11)` — PT Serif — which set
            // the one label whose whole job is to be a tracked uppercase
            // eyebrow in the body serif. Same drift `DripStatStrip` was fixed
            // for on 2026-08-10.
            DripEyebrow(text: "WORKOUT TYPE")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workoutTypes, id: \.0) { type, label in
                        let isSelected = selectedType == type
                        Button {
                            selectedType = isSelected ? "" : type
                        } label: {
                            Text(label.uppercased())
                                .font(.dripEyebrow(10))
                                .tracking(1.0)
                                .foregroundStyle(isSelected ? Color.drip.coral : Color.drip.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            isSelected ? Color.drip.coral : Color.drip.divider,
                                            lineWidth: isSelected ? 1.5 : 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if arrivedAs == nil { arrivedAs = selectedType } }
    }
}

// MARK: - EditableWorkoutStatsSection

/// Distance and duration, edited *inside the stat strip that prints them*.
///
/// **Was a green card.** `Color.drip.energized.opacity(0.1)` fill with an
/// `energized.opacity(0.3)` border and a green `figure.run.circle.fill`
/// glyph — a straight violation of the three-palette rule (2026-07-03):
/// *blue = pace, warm = mood, coral = alert; the three palettes never share
/// hues.* Green is mood-only. A distance field is not a mood.
///
/// It also held two inset input wells (card-on-card), labelled
/// `Distance (mi)` / `Duration (m:ss)` in sentence-case parentheticals —
/// form-app voice on a surface whose labels are mono caps with a middle dot.
///
/// Now it is the hairline three-cell strip, geometry borrowed cell-for-cell
/// from `DripStatStrip`: 9pt/1.08 mono eyebrow over a 20pt mono numeral,
/// 1pt cell dividers, hairline top and bottom. Read mode prints
/// `DIST 6.22 mi`; edit mode puts a cursor in the same numeral, in the same
/// place, at the same size. Editing is writing on the record, not filling in
/// a form about it. (2026-08-20)
struct EditableWorkoutStatsSection: View {
    @Binding var distanceText: String
    @Binding var durationText: String

    private enum StatField { case distance, duration }
    @FocusState private var focusedField: StatField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DripEyebrow(text: "THE NUMBERS")

            HStack(spacing: 0) {
                // Units ride in the eyebrow (`DIST · MI`) rather than sitting
                // beside the numeral. The design system's own separator, and
                // it keeps every cell one centred column — a unit glyph next
                // to a growing text field can't stay centred as you type.
                statCell(label: "DIST · MI") {
                    TextField("0.00", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .distance)
                }
                cellDivider
                statCell(label: "TIME · M:SS") {
                    TextField("0:00", text: $durationText)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .duration)
                }
                cellDivider
                paceCell
            }
            .overlay(alignment: .top) { DripHairline() }
            .overlay(alignment: .bottom) { DripHairline() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolbar {
            // `.decimalPad` has no return key, so before this there was no
            // gesture that dismissed the keyboard from either field — you had
            // to hit Save to get the page back.
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
    }

    // ── Cells ───────────────────────────────────────────────────────────

    /// One strip cell: mono eyebrow over a 20pt mono value.
    ///
    /// The value row is height-locked to 24 so the strip doesn't jump when
    /// the pace cell swaps its empty state for a numeral mid-typing.
    @ViewBuilder
    private func statCell<Content: View>(
        label: String,
        @ViewBuilder field: () -> Content
    ) -> some View {
        VStack(spacing: 7) {
            Text(label)
                .font(.dripEyebrow(9))
                .tracking(1.08)          // 9 × 0.12em
                .foregroundStyle(Color.drip.textTertiary)
            field()
                .font(.dripStat(20))
                .monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
                .multilineTextAlignment(.center)
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 11)
    }

    /// Pace is derived, so it is printed, not typed — the third cell of the
    /// strip rather than a serif `Pace: 5:54 /mi` sentence hanging under a
    /// card.
    private var paceCell: some View {
        VStack(spacing: 7) {
            Text("PACE · MIN/MI")
                .font(.dripEyebrow(9))
                .tracking(1.08)
                .foregroundStyle(Color.drip.textTertiary)

            Group {
                if let pace = computedPace {
                    Text(pace)
                        .font(.dripStat(20))
                        .monospacedDigit()
                        .foregroundStyle(Color.drip.textPrimary)
                } else {
                    // Hard rule #8 — never an em-dash placeholder. The
                    // empty-state pattern in miniature: state the absence,
                    // say what fills it. Italic, tertiary, no illustration.
                    Text("add both")
                        .font(.dripBody(12).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 11)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(width: 1)
    }

    // ── Derivation ──────────────────────────────────────────────────────

    /// `5:54`, or nil while either input is missing or unparseable.
    private var computedPace: String? {
        guard let distance = Double(distanceText),
              let duration = parseDurationToMinutes(durationText),
              distance > 0
        else { return nil }
        let totalSecs = Int(((duration / distance) * 60).rounded())
        return String(format: "%d:%02d", totalSecs / 60, totalSecs % 60)
    }

    private func parseDurationToMinutes(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 60 + parts[1] + parts[2] / 60.0
        case 2: return parts[0] + parts[1] / 60.0
        case 1: return parts[0]
        default: return nil
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var dayOfWeekString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }

    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: self)
    }

    var dayNumberString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }

    var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    func containsAny(_ substrings: [String]) -> Bool {
        substrings.contains { self.contains($0) }
    }
}

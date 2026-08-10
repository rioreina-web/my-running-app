//
//  JournalLogRow.swift
//  RunningLog
//
//  Negative Splits — journal-style training-log entry for the Log tab.
//
//  Where `TrainingLogPreviewRow` is the compact preview used inside the
//  Training tab's dashboard, this row is the bigger journal page used in
//  the Voice Log tab's feed. Matches Plate 09:
//
//   │ TUESDAY                              ▶ VOICE · 2:34
//   │ APR 16  ·  EASY  ·  8.0 MI
//   │
//   │ "I went for an easy run today and felt pretty
//   │  good. My focus was on recovery, getting ready
//   │  for the upcoming race…"
//   │
//   │ POSITIVE
//
//  The vertical rule on the left is colored by mood and gives entries a
//  page-edge feel. Body text is italic serif, three lines visible, with
//  curly-quote framing.
//

import SwiftUI

struct JournalLogRow: View {
    let entry: TrainingLog

    /// Key sessions. Shared with the calendar and the day sheet, so the star
    /// here can no longer disagree with the one there — which it did,
    /// constantly (KEY-SESSION-APPLY.md §"Rule 2").
    @State private var keySessions = KeySessionStore.shared
    /// Body-part mentions on this entry — the athlete's own words, shown as
    /// quiet chips. Detection, never diagnosis.
    var niggles: [JournalNiggle] = []

    private var dayOfWeekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: entry.displayDate).uppercased()
    }

    /// Headline: the athlete's own title when set, else the day-of-week. The
    /// date still appears in the meta line below, so day context isn't lost
    /// when a custom title takes the headline.
    private var headlineText: String {
        entry.displayTitle ?? dayOfWeekLabel
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: entry.displayDate).uppercased()
    }

    // Pace-zone vocabulary (MP / HMP / LT / 10K / Long run …) — never the retired
    // TEMPO / THRESHOLD legacy labels. Single source of truth: WorkoutLabel.
    private var typeLabel: String {
        WorkoutLabel.display(entry.workoutType).uppercased()
    }

    /// Key (quality) session — earns a star marker.
    ///
    /// This used to be a hardcoded `Set<String>` of workout_type spellings —
    /// "Rule 2" of the four. It had no concept of how much work was actually
    /// done, so it starred a 3-mile shakeout labelled "tempo" and, because the
    /// calendar's rule had no concept of a long run, the two surfaces gave
    /// opposite answers on almost every interesting day. The set is deleted.
    ///
    /// One definition now, shared with every other surface.
    private var isKeySession: Bool { keySessions.isKey(on: entry.displayDate) }

    private var keyProvenance: KeySessionMark.Provenance {
        keySessions.provenance(on: entry.displayDate)
    }

    private var distanceLabel: String? {
        guard let s = entry.formattedWorkoutDistance else { return nil }
        return "\(s) MI"
    }

    /// Human-friendly meta line: "APR 16 · EASY · 8.0 MI"
    private var metaLine: String {
        var parts = [dateLabel, typeLabel]
        if let d = distanceLabel { parts.append(d) }
        return parts.joined(separator: "  ·  ")
    }

    /// Body text, framed with curly quotes if non-empty.
    private var bodyText: String {
        let raw = (entry.cleanedNotes?.isEmpty == false ? entry.cleanedNotes : entry.notes) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "—" }
        return "\u{201C}\(trimmed)\u{201D}"
    }

    private var moodLabel: String? {
        guard let m = entry.mood, !m.isEmpty else { return nil }
        return m.uppercased()
    }

    private var moodColor: Color {
        switch (entry.mood ?? "").lowercased() {
        case "energized": return Color.drip.energized
        case "positive":  return Color.drip.positive
        case "neutral":   return Color.drip.neutral
        case "tired":     return Color.drip.tired
        case "struggling":return Color.drip.struggling
        case "injured":   return Color.drip.injured
        default:          return Color.drip.textTertiary
        }
    }

    /// Audio/text indicator shown in the top-right of the entry.
    @ViewBuilder
    private var indicator: some View {
        if entry.source == "check_in" {
            Text("CHECK-IN")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        } else if entry.audioUrl != nil {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("VOICE")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.coral)
            }
        } else {
            Text("TEXT ONLY")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func niggleChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color.drip.textTertiary).frame(width: 4, height: 4)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Vertical mood-color rule — the page-edge accent
            Rectangle()
                .fill(moodColor)
                .frame(width: 2)
                .padding(.vertical, 4)

            // Body content
            VStack(alignment: .leading, spacing: 0) {
                // Headline row — day of week (★ marks a key session) + kind tag
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headlineText)
                        .font(.dripDisplay(20))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)
                    if isKeySession {
                        // The same star the calendar draws, styled by the same
                        // provenance. Two surfaces, one glyph, one meaning.
                        KeySessionStar(provenance: keyProvenance, isKey: true)
                            .frame(width: 10, height: 10)
                    }
                    Spacer(minLength: 12)
                    indicator
                }

                // Date · type · distance line
                Text(metaLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)

                // Body — three italic-serif lines (truncated with ellipsis)
                Text(bodyText)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)

                // Mood footer. During the two-stage reveal (`transcribed`:
                // the athlete's words are on the row, analysis still running)
                // a quiet placeholder holds the mood line's spot — mood +
                // niggle chips fill in when the status flips to completed.
                if let mood = moodLabel {
                    Text(mood)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(moodColor)
                        .padding(.top, 14)
                } else if entry.isTranscribed {
                    Text("ANALYZING…")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 14)
                }

                // Niggle chips — the athlete's own body-area words. No severity,
                // no interpretation (detection, never diagnosis).
                if !niggles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(niggles.prefix(3)) { n in
                            niggleChip(n.label)
                        }
                        if niggles.count > 3 {
                            Text("+\(niggles.count - 3)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .contentShape(Rectangle())
    }
}

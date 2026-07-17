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
    /// Body-part mentions on this entry — the athlete's own words, shown as
    /// quiet chips. Detection, never diagnosis.
    var niggles: [JournalNiggle] = []

    private var dayOfWeekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: entry.displayDate).uppercased()
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

    /// Key (quality) session — earns a star marker. Easy/recovery/rest/cross
    /// are not key; the race-pace zones + long run + intervals/progression are.
    private var isKeySession: Bool {
        let key: Set<String> = [
            "intervals", "interval", "tempo", "threshold", "fartlek", "progression",
            "race", "long_run", "long", "longrun", "long_wo",
            "mp", "hmp", "lt", "10k", "5k", "3k", "mile",
        ]
        return key.contains((entry.workoutType ?? "").lowercased())
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
                    Text(dayOfWeekLabel)
                        .font(.dripDisplay(20))
                        .foregroundStyle(Color.drip.textPrimary)
                    if isKeySession {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.textSecondary)
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

                // Mood footer
                if let mood = moodLabel {
                    Text(mood)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(moodColor)
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

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

    private var typeLabel: String {
        guard let raw = entry.workoutType else { return "RUN" }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
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
        if entry.audioUrl != nil {
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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Vertical mood-color rule — the page-edge accent
            Rectangle()
                .fill(moodColor)
                .frame(width: 2)
                .padding(.vertical, 4)

            // Body content
            VStack(alignment: .leading, spacing: 0) {
                // Headline row — day of week + audio/text indicator
                HStack(alignment: .firstTextBaseline) {
                    Text(dayOfWeekLabel)
                        .font(.dripDisplay(20))
                        .foregroundStyle(Color.drip.textPrimary)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .contentShape(Rectangle())
    }
}

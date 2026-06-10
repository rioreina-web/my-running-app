//
//  TrainingLogPreviewRow.swift
//  RunningLog
//
//  Negative Splits — compact training-log entry for the dashboard.
//
//  Replaces the verbose `JournalEntryRow` (kept for the History view)
//  with a tighter three-element layout matching Plate 06E:
//
//   APR 26  ·  LONG RUN  ·  18 MI                          ▶ 2:34
//   "Felt strong through 14, started to fade on the hills..."
//   POSITIVE
//
//  Each row is hairline-divided from the next. Tapping the row opens
//  the existing detail sheet (handled by the parent).
//

import SwiftUI

struct TrainingLogPreviewRow: View {
    let entry: TrainingLog

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

    private var snippet: String {
        let raw = (entry.cleanedNotes?.isEmpty == false ? entry.cleanedNotes : entry.notes) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "—" }
        return "“\(truncate(trimmed, to: 110))”"
    }

    private func truncate(_ s: String, to limit: Int) -> String {
        if s.count <= limit { return s }
        let cutoff = s.index(s.startIndex, offsetBy: limit)
        return s[..<cutoff].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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

    /// Audio-memo affordance shown on the right side of the eyebrow row.
    /// The TrainingLog model exposes audioUrl; we don't have audio
    /// duration on the model, so we show a play indicator only.
    ///
    /// Text-only entries render no badge — absence of the VOICE
    /// affordance is its own signal. The previous "TEXT ONLY" label
    /// added noise without communicating anything new.
    @ViewBuilder
    private var audioAffordance: some View {
        if entry.audioUrl != nil {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("VOICE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.coral)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Eyebrow row — date · type · distance · audio/text indicator
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 0) {
                    Text(dateLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("  ·  ")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(typeLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textSecondary)
                    if let dist = distanceLabel {
                        Text("  ·  ")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(dist)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                Spacer(minLength: 12)
                audioAffordance
            }

            // Italic-serif snippet of the cleaned/raw notes
            Text(snippet)
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Mood tag (if any) — small mono caps in mood color
            if let mood = moodLabel {
                Text(mood)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(moodColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 26)
        .contentShape(Rectangle())
    }
}

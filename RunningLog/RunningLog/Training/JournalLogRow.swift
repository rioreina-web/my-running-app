//
//  JournalLogRow.swift
//  RunningLog
//
//  Negative Splits — journal-style training-log entry for the Log tab.
//
//  Redesigned 2026-09-01 from a 6-layer stack (mood rule, headline+badge,
//  meta line, 3-line quote, mood word, chip row) down to 3 lines, and to
//  actually show what the entry is worth reading for:
//
//   │ Monday ★                    APR 13         ▶ VOICE
//   │ EASY · 6.2 mi · 8:45/mi · RPE 3
//   │ "Legs felt fresh right from the first mile…"      ENERGIZED
//
//  The vertical rule on the left is still colored by mood — per the
//  design system's left-rule rule, that's the one thing a leading rule
//  is allowed to mean. Distance/pace/RPE were on the model the whole
//  time (`formattedWorkoutDistance` etc.) but never rendered here; the
//  old row's three-line quote is now one line, since scanning a week is
//  this row's job — reading the full entry is the detail sheet's.
//

import SwiftUI

struct JournalLogRow: View {
    let entry: TrainingLog

    /// Key sessions. Shared with the calendar and the day sheet, so the star
    /// here can no longer disagree with the one there — which it did,
    /// constantly (KEY-SESSION-APPLY.md §"Rule 2").
    @State private var keySessions = KeySessionStore.shared
    /// Body-part mentions on this entry — the athlete's own words. The row
    /// shows only a count; the detail sheet is where they're spelled out.
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

    /// Stat-line parts: workout type, distance, pace, effort — whichever
    /// exist. A rest-day text-only entry may have none of these, in which
    /// case the line simply doesn't render.
    private var statParts: [String] {
        var parts: [String] = []
        if let type = entry.workoutType, !type.isEmpty { parts.append(typeLabel) }
        if let d = entry.formattedWorkoutDistance { parts.append("\(d) mi") }
        let pace = entry.workoutPacePerMile ?? entry.formattedWorkoutPace
        if let p = pace, !p.isEmpty { parts.append("\(p)/mi") }
        if let rpe = entry.feltRpe { parts.append("RPE \(rpe)") }
        return parts
    }

    /// One-line note preview. Full text lives in the detail sheet; this row
    /// scans a week, it doesn't read an entry.
    private var notePreview: String? {
        let raw = (entry.cleanedNotes?.isEmpty == false ? entry.cleanedNotes : entry.notes) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "\u{201C}\(trimmed)\u{201D}"
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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Vertical mood-color rule — the page-edge accent. Per the design
            // system's left-rule rule, a colored leading rule means mood and
            // nothing else.
            Rectangle()
                .fill(moodColor)
                .frame(width: 2)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                // Line 1 — identity: headline (★ marks a key session), date,
                // source, all on one baseline.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headlineText)
                        .font(.dripDisplay(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)
                    if isKeySession {
                        // The same star the calendar draws, styled by the same
                        // provenance. Two surfaces, one glyph, one meaning.
                        KeySessionStar(provenance: keyProvenance, isKey: true)
                            .frame(width: 10, height: 10)
                    }
                    Text(dateLabel)
                        .font(.dripEyebrow(10))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer(minLength: 12)
                    LogSourceBadge(
                        isCheckIn: entry.source == "check_in",
                        hasAudio: entry.audioUrl != nil
                    )
                }

                // Line 2 — the stat strip. Distance/pace/RPE were always on
                // the model; they just never rendered on this row before.
                if !statParts.isEmpty {
                    Text(statParts.joined(separator: " · "))
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // Line 3 — one-line note preview, with mood + niggle count
                // trailing on the same line instead of stacking below it.
                // During the two-stage reveal (`transcribed`: the athlete's
                // words are on the row, analysis still running) the tail
                // shows "ANALYZING…" in mood's place.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let note = notePreview {
                        Text(note)
                            .font(.dripBody(14))
                            .italic()
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    if let mood = entry.mood, !mood.isEmpty {
                        MoodBadge(mood: mood)
                    } else if entry.isTranscribed {
                        Text("ANALYZING…")
                            .font(.dripEyebrow(9))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    NiggleCountIndicator(count: niggles.count)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

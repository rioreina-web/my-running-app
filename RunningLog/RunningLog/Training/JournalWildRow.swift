//
//  JournalWildRow.swift
//  RunningLog
//
//  One journal entry, Direction I.
//
//  The layout is `Log Feed · 032c` — the canonical feed screen — retyped
//  onto the locked roles:
//
//   │ Intervals ★                          ▶ VOICE · 2:34
//   │ AUG 20 · 6 × 800M · 6.20 MI
//   │
//   │ "Legs were heavy from the first rep, honestly…"
//   │
//   │ TIRED
//
//  The 2pt rule down the leading edge is the MOOD, and nothing else —
//  `CLAUDE.md` is explicit about that and 032c is where the rule comes
//  from. The mood word at the foot repeats it in the same colour.
//
//  The one distinction that matters (`POSTRUNDRIPSYSTEM.md` §1):
//  **italic mono is the athlete, roman mono is the machine.** A transcribed
//  memo is set in italic JetBrains Mono because it is speech. A note the
//  athlete typed is set in Crimson, because they wrote it. No badge, no
//  icon, no colour does that work — the typeface says who is talking.
//

import SwiftUI

// Built once, not per row per frame. `DateFormatter()` is expensive to
// construct and these are read from inside a view body — at a dozen rows on
// screen, a per-call allocation is a measurable share of a scroll frame.
private let wildRowWeekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEEE"
    return f
}()

private let wildRowMonthDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f
}()

struct JournalWildRow: View {
    let entry: TrainingLog
    var niggles: [JournalNiggle] = []

    @State private var keySessions = KeySessionStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // The mood, as the page edge.
            Rectangle()
                .fill(Color.wild.mood(entry.mood))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                header
                Text(metaLine)
                    .font(.wildLabel(11))
                    .tracking(11 * 0.09)
                    .foregroundStyle(Color.wild.ink2)
                    .padding(.top, 8)

                words
                    .padding(.top, 13)

                if let mood = moodWord {
                    Text(mood)
                        .font(.wildLabel(11))
                        .tracking(11 * 0.12)
                        .foregroundStyle(Color.wild.moodText(entry.mood))
                        .padding(.top, 13)
                }

                if !niggles.isEmpty {
                    niggleRow
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header — headline, key-session star, provenance

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(headline)
                    .font(.wildDisplay(23))
                    .tracking(23 * -0.03)
                    .foregroundStyle(Color.wild.ink)
                    .lineLimit(1)
                if isKeySession {
                    // Blue, not red: `--session` names a keyed session, and
                    // the provenance label to the right is already the one
                    // red in this row.
                    Text("★")
                        .font(.wildData(14))
                        .foregroundStyle(Color.wild.session)
                }
            }
            Spacer(minLength: 8)
            provenance
        }
    }

    /// The athlete's own title when they set one, else the session type,
    /// else the day. The date is on the meta line either way, so nothing
    /// is lost when a custom title takes the headline.
    private var headline: String {
        if let t = entry.displayTitle { return t }
        if let t = entry.workoutTypeLabel, entry.source != "check_in" { return t }
        return dayOfWeek
    }

    private var dayOfWeek: String {
        wildRowWeekdayFormatter.string(from: entry.displayDate)
    }

    private var isKeySession: Bool { keySessions.isKey(on: entry.displayDate) }

    @ViewBuilder
    private var provenance: some View {
        if entry.source == "check_in" {
            HStack(spacing: 5) {
                playMark
                WildLabel("Check-in", size: 10, color: Color.wild.redText)
            }
        } else if entry.audioUrl != nil {
            HStack(spacing: 5) {
                playMark
                WildLabel("Voice", size: 10, color: Color.wild.redText)
            }
        } else {
            WildLabel("Note", size: 10)
        }
    }

    private var playMark: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.wild.red)
    }

    // MARK: Meta — one tracked line, everything factual

    /// "AUG 20 · 6 × 800M · 6.20 MI". 032c puts everything factual on one
    /// line under a short headline, which reads faster than labelled tiles
    /// and is what makes the feed scannable.
    private var metaLine: String {
        var parts: [String] = [dateLabel]
        if let type = entry.workoutTypeLabel { parts.append(type) }
        if let d = entry.formattedWorkoutDistance {
            parts.append("\(d) mi")
        } else if entry.source == "check_in" {
            parts.append("No run")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var dateLabel: String {
        wildRowMonthDayFormatter.string(from: entry.displayDate)
    }

    // MARK: The words

    @ViewBuilder
    private var words: some View {
        let text = bodyText
        if text.isEmpty {
            Text("—")
                .font(.wildData(14))
                .foregroundStyle(Color.wild.ink3)
        } else if entry.audioUrl != nil {
            // Spoken. Italic mono, curly-quoted, as said.
            Text("\u{201C}\(text)\u{201D}")
                .font(.wildSaid(14))
                .tracking(14 * -0.01)
                .lineSpacing(14 * 0.55)
                .foregroundStyle(Color.wild.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        } else {
            // Written. Crimson, no quotes — nobody said it out loud.
            Text(text)
                .font(.wildProse(17))
                .lineSpacing(17 * 0.5)
                .foregroundStyle(Color.wild.ink)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
    }

    private var bodyText: String {
        let raw = (entry.cleanedNotes?.isEmpty == false ? entry.cleanedNotes : entry.notes) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var moodWord: String? {
        guard let m = entry.mood?.trimmingCharacters(in: .whitespacesAndNewlines),
              !m.isEmpty else { return nil }
        return m
    }

    // MARK: Niggles — detection, never diagnosis

    private var niggleRow: some View {
        HStack(spacing: 7) {
            ForEach(niggles.prefix(3), id: \.id) { n in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.wild.red)
                        .frame(width: 4, height: 4)
                    WildLabel(n.label, size: 9, tracking: 0.16)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    Capsule().stroke(Color.wild.rule, lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Processing / failed

/// A memo still transcribing, or one that failed. A hairline row with a
/// tracked label — `ProcessingLogCard` is a card, and this skin has no
/// cards (`POSTRUNDRIPSYSTEM.md` §4).
///
/// The failure copy never implies the recording is gone, because it isn't.
struct JournalWildProcessingRow: View {
    let entry: TrainingLog
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if entry.isFailed {
                WildLabel(dateLabel, size: 10)
                WildLabel("Couldn't transcribe", size: 10, color: Color.wild.redText)
                Spacer(minLength: 8)
                Button(action: retry) {
                    WildLabel("Retry ↗", size: 10, color: Color.wild.ink)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.wild.ink2)
                WildLabel(dateLabel, size: 10)
                Spacer(minLength: 8)
                WildLabel("Transcribing", size: 10)
            }
        }
        .frame(minHeight: 44)
    }

    private var dateLabel: String {
        wildRowMonthDayFormatter.string(from: entry.displayDate)
    }
}

//
//  JournalPages.swift
//  RunningLog
//
//  The four pages of a workout in the training journal. See JournalPager.swift
//  for the pager, the spine, and the note about this rendering a session that
//  `HistoryDetailSheet` also renders.
//
//  Rules these pages keep, all of them borrowed from surfaces that learned
//  them the hard way:
//
//  • Pace is DERIVED from distance and duration. `workout_pace_per_mile` is
//    populated on ~12% of rows and is never a display source (SessionRollup).
//  • Nothing is generated here. The read page prints `coach_insight` when the
//    server has written one and says so when it has not. It does not write
//    prose from the client.
//  • The comparison ledger is arithmetic over the athlete's own rows. If no
//    comparable session exists, the block says that rather than reaching
//    further back for something that is not comparable.
//

import SwiftUI

// MARK: - Shared frame

/// Pages sit in a vertical ScrollView that does not bounce when the content
/// fits, so a page that fits reads as a sheet of paper. The workout page will
/// overflow — that one is a scroll and is meant to be.
struct JournalPageFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 26)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

/// The running head every page after the first carries: which run, which page.
struct JournalRunHead: View {
    let log: TrainingLog
    let section: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.head(log.displayDate))
                .font(.dripEyebrow(9))
                .tracking(1.6)
                .foregroundStyle(Color.drip.textTertiary)
            Spacer(minLength: 12)
            Text(section.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.6)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) { DripHairline() }
        .padding(.bottom, 22)
    }

    private static let f: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE · MMM d"; return f
    }()
    static func head(_ d: Date) -> String { f.string(from: d).uppercased() }
}

// MARK: - Formatting shared by the pages

enum JournalFormat {
    /// Seconds per mile, derived. Nil when the row cannot support it.
    static func paceSeconds(_ log: TrainingLog) -> Double? {
        guard let mi = log.workoutDistanceMiles, mi > 0.05,
              let min = log.workoutDurationMinutes, min > 0 else { return nil }
        return min * 60 / mi
    }

    static func duration(_ log: TrainingLog) -> String? {
        guard let min = log.workoutDurationMinutes, min > 0 else { return nil }
        let total = Int(min.rounded())
        return total >= 60 ? "\(total / 60):\(String(format: "%02d", total % 60))" : "\(total) min"
    }

    static func moodColor(_ mood: String?) -> Color {
        switch (mood ?? "").lowercased() {
        case "energized":  return Color.drip.energized
        case "positive":   return Color.drip.positive
        case "neutral":    return Color.drip.neutral
        case "tired":      return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured":    return Color.drip.injured
        default:           return Color.drip.textTertiary
        }
    }
}

// MARK: - 1 · The session

struct JournalSessionPage: View {
    let log: TrainingLog

    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.miles.rawValue
    private var unit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    private var headline: String { WorkoutLabel.display(log.workoutType) }

    var body: some View {
        JournalPageFrame {
            VStack(alignment: .leading, spacing: 0) {
                // Kicker
                HStack(spacing: 8) {
                    Circle().fill(Color.drip.coral).frame(width: 4, height: 4)
                    Text(JournalRunHead.head(log.displayDate))
                        .font(.dripEyebrow(11))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.coral)
                }
                .padding(.bottom, 12)

                // Headline — the period is the spec's rule for standalone
                // headlines, and the coral full stop is the one accent here.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(headline)
                        .font(.dripDisplay(52))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(".")
                        .font(.dripDisplay(52))
                        .foregroundStyle(Color.drip.coral)
                }
                .lineLimit(2)
                .minimumScaleFactor(0.6)

                if let title = log.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    Text(title)
                        .font(.dripBody(16.5).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 14)
                }

                // Byline
                HStack(spacing: 9) {
                    if let mood = log.mood, !mood.isEmpty {
                        let c = JournalFormat.moodColor(mood)
                        HStack(spacing: 6) {
                            Circle().fill(c).frame(width: 5, height: 5)
                            Text(mood.uppercased())
                                .font(.dripEyebrow(10))
                                .tracking(1.0)
                                .foregroundStyle(c)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(c.opacity(0.12)))
                    }
                    if let source = log.source, !source.isEmpty {
                        Text("·").foregroundStyle(Color.drip.textTertiary)
                        Text("From \(source)".uppercased())
                            .font(.dripEyebrow(10))
                            .tracking(1.0)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .padding(.top, 8)
                .overlay(alignment: .top) { DripHairline() }
                .overlay(alignment: .bottom) { DripHairline() }

                // The three measures, on one ruled line
                HStack(spacing: 0) {
                    measure(
                        value: log.workoutDistanceMiles.map {
                            DistanceFormat.value(miles: $0, unit: unit)
                        } ?? "—",
                        unit: log.workoutDistanceMiles == nil ? nil : unit.short,
                        key: "Distance"
                    )
                    divider
                    measure(value: JournalFormat.duration(log) ?? "—", unit: nil, key: "Moving")
                    divider
                    measure(
                        value: JournalFormat.paceSeconds(log).map {
                            DistanceFormat.paceMMSS(secPerMile: $0, unit: unit)
                        } ?? "—",
                        unit: JournalFormat.paceSeconds(log) == nil ? nil : "/\(unit.short)",
                        key: "Avg pace"
                    )
                }
                .padding(.top, 24)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1).padding(.vertical, 2)
    }

    private func measure(value: String, unit: String?, key: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.dripStat(26))
                    .foregroundStyle(Color.drip.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.dripStat(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Text(key.uppercased())
                .font(.dripEyebrow(10))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }
}

// MARK: - 2 · In your words

struct JournalWordsPage: View {
    let log: TrainingLog

    private var words: String? {
        let raw = (log.cleanedNotes ?? log.notes)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    var body: some View {
        JournalPageFrame {
            VStack(alignment: .leading, spacing: 0) {
                JournalRunHead(log: log, section: "In your words")

                if let words {
                    Text("\u{201C}\(words)\u{201D}")
                        .font(.dripBody(16))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(5)
                } else {
                    Text("No words on this one — just the memo.")
                        .font(.dripBody(14).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                }

                if log.audioUrl != nil {
                    Text("▶ MEMO")
                        .font(.dripEyebrow(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 20)
                    // PLAYBACK IS NOT WIRED HERE. The player is private to
                    // HistoryDetailSheet. This says the memo exists; the sheet
                    // still owns playing it. Wire or remove before shipping —
                    // a control that does nothing is worse than no control, so
                    // this is a label, not a button.
                }
            }
        }
    }
}

// MARK: - 3 · The workout

/// Conditions, SIGNALS, splits, telemetry, route — all of it
/// `WorkoutRepReceiptView`, which loads itself from the workout id.
///
/// `.embedded` because this page carries the date in its running head. The
/// receipt is taller than a page, so this is the one page that scrolls, and
/// that is deliberate: the alternative is cutting the receipt into pieces,
/// which means refactoring it.
struct JournalWorkoutPage: View {
    let log: TrainingLog

    var body: some View {
        JournalPageFrame {
            VStack(alignment: .leading, spacing: 0) {
                JournalRunHead(log: log, section: "The workout")
                WorkoutRepReceiptView(workoutId: log.id, placement: .embedded)
                    .padding(.horizontal, -24)   // the receipt brings its own 24pt gutter
            }
        }
    }
}

// MARK: - 4 · The read

struct JournalReadPage: View {
    let log: TrainingLog

    @State private var showInsight = true
    @State private var comparison: JournalComparison?

    private var insight: String? {
        let t = log.coachInsight?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let t, !t.isEmpty else { return nil }
        return t
    }

    var body: some View {
        JournalPageFrame {
            VStack(alignment: .leading, spacing: 0) {
                JournalRunHead(log: log, section: "The read")

                // ── The read itself ────────────────────────────────────
                if let insight, showInsight {
                    Text(insight)
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(4)
                } else {
                    // No stored insight. The honest empty state — and NOT a
                    // "generate" button, because generation is owned by
                    // HistoryDetailViewModel and calling the edge function
                    // from here would be a second, divergent path to the
                    // same row. Ask still works below.
                    Text("No read written for this session yet. Ask below, or open it from the log to generate one.")
                        .font(.dripBody(14).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                }

                // ── Against your own work ──────────────────────────────
                if let comparison {
                    VStack(alignment: .leading, spacing: 0) {
                        DripEyebrow(text: "AGAINST YOUR OWN WORK")
                            .padding(.bottom, 10)

                        ledgerRow("This session", comparison.thisPace)
                        if let prior = comparison.priorPace, let when = comparison.priorLabel {
                            ledgerRow(when, prior)
                            if let delta = comparison.deltaLabel {
                                ledgerRow("Difference", delta, tone: comparison.slower ? Color.drip.tired : Color.drip.energized)
                            }
                        } else {
                            Text("No comparable \(comparison.typeLabel.lowercased()) in the last 90 days.")
                                .font(.dripBody(13).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.top, 22)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.drip.textPrimary).frame(height: 1)
                    }
                }

                // ── Ask ────────────────────────────────────────────────
                // The existing block, unchanged. It owns SessionAskService and
                // its own state; the only thing passed in is what this page
                // knows about the insight.
                //
                // `canGenerateInsight: false` on purpose — see the empty state
                // above. The read chip therefore reveals a stored read and
                // nothing else on this surface.
                SessionAskBlock(
                    workoutId: log.id,
                    dateLabel: log.displayDate.editorialDateString,
                    hasInsight: insight != nil,
                    canGenerateInsight: false,
                    isGenerating: false,
                    hasInsightError: false,
                    onReadTapped: {
                        withAnimation(.easeInOut(duration: 0.2)) { showInsight = true }
                    }
                )
                .padding(.horizontal, -24)   // the block brings its own gutter
                .padding(.top, 26)

                Text("The read is written from this session's own rows. It can be wrong — the numbers above it are not.")
                    .font(.dripBody(11.5).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(2)
                    .padding(.top, 18)
            }
        }
        .task(id: log.id) {
            comparison = JournalComparison.make(for: log)
        }
    }

    private func ledgerRow(_ key: String, _ value: String, tone: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key.uppercased())
                .font(.dripEyebrow(10))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.dripStat(13))
                .foregroundStyle(tone ?? Color.drip.textPrimary)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { DripHairline() }
    }
}

// MARK: - The comparison

/// This session against the most recent comparable one, computed from the
/// rows already in `TrainingLogStore` — no fetch, no model, no invention.
///
/// "Comparable" is deliberately strict: same normalised workout type, within
/// 25% of the distance, before this session, inside the store's window. A
/// looser rule finds a number to print, and a number that is not comparable
/// is worse than no number.
struct JournalComparison {
    let typeLabel: String
    let thisPace: String
    let priorPace: String?
    let priorLabel: String?
    let deltaLabel: String?
    let slower: Bool

    @MainActor
    static func make(for log: TrainingLog) -> JournalComparison? {
        let unit = DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "")
            ?? .miles
        guard let thisPaceSec = JournalFormat.paceSeconds(log),
              let miles = log.workoutDistanceMiles, miles > 0.05 else { return nil }

        let type = WorkoutLabel.normalize(log.workoutType)
        let label = WorkoutLabel.display(log.workoutType)
        let thisDate = log.displayDate

        let candidate = TrainingLogStore.shared.rows
            .filter { row in
                guard row.date < thisDate,
                      let m = row.miles, m > 0.05,
                      let dur = row.durationMinutes, dur > 0,
                      WorkoutLabel.normalize(row.typeKey) == type
                else { return false }
                return abs(m - miles) / miles <= 0.25
            }
            .max(by: { $0.date < $1.date })

        let fmt = { (s: Double) in
            "\(DistanceFormat.paceMMSS(secPerMile: s, unit: unit)) /\(unit.short)"
        }

        guard let candidate,
              let m = candidate.miles, let dur = candidate.durationMinutes else {
            return JournalComparison(typeLabel: label, thisPace: fmt(thisPaceSec),
                                     priorPace: nil, priorLabel: nil,
                                     deltaLabel: nil, slower: false)
        }

        let priorSec = dur * 60 / m
        let delta = thisPaceSec - priorSec           // + = slower now
        let sign = delta >= 0 ? "+" : "−"
        let secs = Int(abs(delta).rounded())

        let df = DateFormatter(); df.dateFormat = "MMM d"
        return JournalComparison(
            typeLabel: label,
            thisPace: fmt(thisPaceSec),
            priorPace: fmt(priorSec),
            priorLabel: "\(label) · \(df.string(from: candidate.date))",
            deltaLabel: "\(sign)\(secs) s/\(unit.short)",
            slower: delta >= 0
        )
    }
}

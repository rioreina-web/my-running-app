//
//  SignalDayDetail.swift
//  RunningLog · Trends
//
//  THE WORKOUT and THE LOG — the half of the day sheet that was missing.
//
//  Why this file exists (2026-08-18)
//  ─────────────────────────────────
//  Tapping a bar in Trends › OVER TIME opened a sheet that showed the day's
//  miles split by pace zone and then stopped: half a screen of white space
//  where the day itself should be. The two questions a runner has when they
//  tap a day are "what was the session?" and "what did I say about it?" —
//  and both answers already existed in the app. The sheet just never asked.
//
//  Nothing here is a new renderer. Every block is the one the rest of the
//  app already uses, so an edit made here shows up everywhere else:
//
//    • the athlete's own description → `TheWorkoutBlock`
//      (Workouts/TheWorkoutBlock.swift — one block, one editor, all surfaces)
//    • the parsed workout           → `WorkoutRepReceiptView(placement:
//      .embedded)` — the same receipt the journal entry embeds
//    • the voice memo               → `MemoPlayerRow`
//
//  The only genuinely new code is the day query and the stacking order.
//
//  Two deliberate choices:
//
//  1. THE PARSER GETS ITS OWN EYEBROW. `parsed_structure.pattern` is the
//     parser's read of the GPS trace, not the athlete's words, so it never
//     renders under "THE WORKOUT" (see the note on `TheWorkoutBlock.text`).
//     It sits under "WHAT THE PARSER READ", with its confidence visible.
//
//  2. RECEIPTS LOAD LAZILY ON A MULTI-RUN DAY. A receipt pulls per-second
//     streams (up to ~2 MB per run — PERF-AUDIT-2026-08-10 finding #1). A
//     one-run day opens its receipt immediately; an AM/PM day starts them
//     collapsed and builds each one only when it's opened.
//

import Observation
import os
import Supabase
import SwiftUI

// MARK: - Day loader

/// Everything the day sheet needs beyond the numbers the chart already holds:
/// the day's `training_logs` rows, runs and memos alike.
///
/// The day boundary is `Calendar.current.startOfDay` on `workout_date`, which
/// is exactly how `SignalService.build` buckets a run into a bar — so the rows
/// listed here are the rows that made the bar. Rows with no `workout_date`
/// (a memo recorded with no run attached) fall back to `created_at`, again
/// matching the chart.
@Observable
final class SignalDayDetailModel {

    private(set) var rows: [TrainingLog] = []
    private(set) var isLoading = false
    private(set) var failed = false
    private var loadedDay: Date?

    /// Rows carrying a run — distance on the clock. These get a workout block.
    var runs: [TrainingLog] {
        rows.filter { ($0.workoutDistanceMiles ?? 0) > 0 }
    }

    /// Rows carrying words or a recording. A row can be BOTH a run and a memo
    /// (since the 2026-08-05 picker fix a memo attaches to the run's own row),
    /// so these two lists deliberately overlap rather than partition.
    var memos: [TrainingLog] {
        rows.filter { SignalDayDetailModel.words($0) != nil || $0.audioUrl != nil }
    }

    var isEmpty: Bool { rows.isEmpty }

    /// The athlete's words: the cleaned transcript when the processor has run,
    /// the raw one until then. Never a placeholder.
    static func words(_ r: TrainingLog) -> String? {
        let t = (r.cleanedNotes ?? r.notes)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let t, !t.isEmpty else { return nil }
        return t
    }

    @MainActor
    func load(day: Date) async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        if loadedDay == start { return }          // one fetch per day, per sheet
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        loadedDay = start
        isLoading = true
        failed = false
        defer { isLoading = false }

        let iso = ISO8601DateFormatter()
        let lo = iso.string(from: start)
        let hi = iso.string(from: end)

        do {
            // Awaited in sequence, NOT with `async let`. `TrainingLog`'s
            // Decodable conformance is main-actor isolated, and an `async let`
            // body runs in a nonisolated child task — decoding there is a Swift
            // 6 concurrency error, not a style choice. Two small queries on one
            // day cost a round trip; correctness wins.
            //
            // Two plain queries rather than one nested `or(...)`: a timestamp
            // inside an `or` filter needs quoting the client doesn't do, and a
            // silently-empty day is exactly the failure this sheet is fixing.
            //
            // `Failable` per row (Models/TrainingLog.swift): decoding a page as
            // `[TrainingLog]` is all-or-nothing, and one malformed row would
            // blank the whole day.
            let dated: [Failable<TrainingLog>] = try await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .gte("workout_date", value: lo)
                .lt("workout_date", value: hi)
                .order("workout_date", ascending: true)
                .limit(20)
                .execute()
                .value

            let undated: [Failable<TrainingLog>] = try await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .is("workout_date", value: nil)
                .gte("created_at", value: lo)
                .lt("created_at", value: hi)
                .order("created_at", ascending: true)
                .limit(20)
                .execute()
                .value

            var seen = Set<UUID>()
            let merged = (dated + undated)
                .compactMap(\.value)
                .filter { seen.insert($0.id).inserted }
                .sorted { ($0.workoutDate ?? $0.createdAt) < ($1.workoutDate ?? $1.createdAt) }

            rows = merged
        } catch {
            Log.coach.error("SignalDayDetailModel.load failed: \(error)")
            failed = true
            loadedDay = nil                        // let the next open retry
        }
    }
}

// MARK: - The sections

/// THE WORKOUT + THE LOG, stacked under the day sheet's pace breakdown.
struct SignalDayDetailSections: View {
    let date: Date
    let model: SignalDayDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isLoading && model.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if model.failed {
                Text("Couldn't load this day. Pull the sheet closed and open it again.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 18)
            } else {
                if !model.runs.isEmpty {
                    EditorialRule().padding(.vertical, 20)
                    sectionEyebrow("THE WORKOUT")
                    ForEach(Array(model.runs.enumerated()), id: \.element.id) { idx, run in
                        SignalDayRunBlock(
                            run: run,
                            // Same label the editor shows from every other
                            // surface — `Date.workoutBlockDateLabel`, not a
                            // second formatter that could drift from it.
                            dateLabel: date.workoutBlockDateLabel,
                            startsOpen: model.runs.count == 1
                        )
                        .padding(.top, idx == 0 ? 14 : 22)
                    }
                }

                if !model.memos.isEmpty {
                    EditorialRule().padding(.vertical, 20)
                    sectionEyebrow("THE LOG")
                    ForEach(Array(model.memos.enumerated()), id: \.element.id) { idx, memo in
                        SignalDayMemoBlock(memo: memo)
                            .padding(.top, idx == 0 ? 14 : 20)
                    }
                }

                if model.runs.isEmpty && model.memos.isEmpty && !model.isLoading {
                    EditorialRule().padding(.vertical, 20)
                    Text("Nothing logged on this day.")
                        .font(.dripBody(13).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
    }

    private func sectionEyebrow(_ s: String) -> some View {
        Text(s)
            .font(.dripEyebrow(11)).tracking(1.3)
            .foregroundStyle(Color.drip.textSecondary)
    }
}

// MARK: - One run

/// A run, in the order a runner reads it: what it was → what you said it was →
/// what the parser made of it → the splits themselves.
private struct SignalDayRunBlock: View {
    let run: TrainingLog
    let dateLabel: String
    /// One-run days open the receipt straight away; multi-run days wait for a
    /// tap, so an AM/PM day doesn't pull two stream blobs on open.
    let startsOpen: Bool

    @State private var expanded: Bool = false
    @State private var didInit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // The athlete's own description. Same block, same editor, same
            // `workout_notes` column as the journal entry and the receipt —
            // edit it here and it changes there.
            TheWorkoutBlock(
                workoutId: run.id,
                dateLabel: dateLabel,
                notes: run.workoutNotes,
                loadsOwnNotes: (run.workoutNotes?.isEmpty ?? true)
            )

            parsedRead

            // The parsed workout itself — reps, splits, HR — as the rest of
            // the app draws it. `.embedded` because this card already carries
            // the date and THE WORKOUT above it.
            DisclosureGroup(isExpanded: $expanded) {
                if expanded {
                    WorkoutRepReceiptView(workoutId: run.id, placement: .embedded)
                        .padding(.top, 10)
                }
            } label: {
                Text(expanded ? "HIDE THE SPLITS" : "SHOW THE SPLITS")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.coral)
            }
            .tint(Color.drip.coral)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            expanded = startsOpen
        }
    }

    // MARK: Header — type · distance · pace · time

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let type = run.workoutTypeLabel {
                    Text(type.uppercased())
                        .font(.dripStat(10)).tracking(1.2)
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.drip.coralWash)
                        .clipShape(Capsule())
                }
                if let src = sourceLabel {
                    Text(src)
                        .font(.dripEyebrow(9.5)).tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Spacer(minLength: 0)
                if let t = timeOfDay {
                    Text(t)
                        .font(.dripEyebrow(9.5)).tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let mi = run.workoutDistanceMiles {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", mi))
                            .font(.dripDisplay(22)).foregroundStyle(Color.drip.textPrimary)
                        Text("mi").font(.dripBody(12)).foregroundStyle(Color.drip.textTertiary)
                    }
                }
                if let pace = run.workoutPacePerMile, !pace.isEmpty {
                    Text("\(pace) /mi")
                        .font(.dripStat(12)).foregroundStyle(Color.drip.textSecondary)
                }
                if let dur = durationLabel {
                    Text(dur)
                        .font(.dripStat(12)).foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    // MARK: What the parser read

    /// `parsed_structure` — the observer's read of the trace. Labelled as the
    /// parser's, never as the athlete's, and always carrying its confidence:
    /// a low-confidence parse should look like a guess, because it is one.
    @ViewBuilder
    private var parsedRead: some View {
        if let p = run.parsedStructure,
           (p.pattern?.isEmpty == false) || p.workSummary != nil {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("WHAT THE PARSER READ")
                        .font(.dripEyebrow(9.5)).tracking(1.1)
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer(minLength: 0)
                    Text("\(Int((p.confidence * 100).rounded()))% CONFIDENT")
                        .font(.dripStat(9)).tracking(0.8)
                        .foregroundStyle(p.confidence >= 0.6 ? Color.drip.textTertiary : Color.drip.coral)
                }
                if let pattern = p.pattern, !pattern.isEmpty {
                    Text(pattern)
                        .font(.dripBody(14.5))
                        .foregroundStyle(Color.drip.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let w = p.workSummary {
                    HStack(spacing: 16) {
                        if let mi = w.totalDistanceMi, mi > 0 {
                            parsedStat("WORK", String(format: "%.1f mi", mi))
                        }
                        if let pace = w.avgWorkPacePerMile, !pace.isEmpty {
                            parsedStat("AVG WORK", "\(pace)/mi")
                        }
                        if let peak = w.peakSustainedPacePerMile, !peak.isEmpty {
                            parsedStat("PEAK", "\(peak)/mi")
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
        }
    }

    private func parsedStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.dripEyebrow(8.5)).tracking(0.9)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value).font(.dripStat(12)).foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: Labels

    private var sourceLabel: String? {
        switch run.source?.lowercased() {
        case "strava", "strava_backfill": return "STRAVA"
        case "auto_sync":                 return "WATCH"
        case "manual":                    return "ENTERED BY HAND"
        case "voice_log", "check_in":     return "FROM A MEMO"
        default:                          return nil
        }
    }

    private var timeOfDay: String? {
        guard let d = run.workoutDate else { return nil }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: d).uppercased()
    }

    private var durationLabel: String? {
        guard let m = run.workoutDurationMinutes, m > 0 else { return nil }
        let total = Int((m * 60).rounded())
        let h = total / 3600, mm = (total % 3600) / 60, ss = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, mm, ss)
            : String(format: "%d:%02d", mm, ss)
    }
}

// MARK: - One memo

/// The log entry as a record: play it, or read it. No AI annotation — the Log
/// is pure record (CLAUDE.md, "Information architecture").
private struct SignalDayMemoBlock: View {
    let memo: TrainingLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(memo.audioUrl != nil ? "VOICE" : "TYPED")
                    .font(.dripEyebrow(9.5)).tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                if let mood = memo.mood, !mood.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(TrendsMoodColor.color(mood)).frame(width: 7, height: 7)
                        Text(mood.uppercased())
                            .font(.dripEyebrow(9.5)).tracking(1.0)
                            .foregroundStyle(TrendsMoodColor.color(mood))
                    }
                }
                Spacer(minLength: 0)
                if let t = memo.displayTitle {
                    Text(t)
                        .font(.dripEyebrow(9.5)).tracking(0.6)
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                }
            }

            if let url = memo.audioUrl, !url.isEmpty {
                MemoPlayerRow(url: url)
            }

            if let words = SignalDayDetailModel.words(memo) {
                Text(words)
                    .font(.dripBody(13.5).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if memo.audioUrl != nil {
                Text(memo.processingStatus == "pending"
                     ? "Still transcribing."
                     : "No transcript on this one.")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }
}

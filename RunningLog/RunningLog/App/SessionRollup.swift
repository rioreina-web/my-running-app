//
//  SessionRollup.swift
//  RunningLog
//
//  Turns `TodayLogRow` uploads into SESSIONS — the unit The Sheet renders.
//
//  A session is not a day and it is not an upload. Aug 4 2026 is five Strava
//  activities, which are two sessions: a 6:08am track workout (warm-up +
//  threshold + cooldown) and a 5:52pm double. Rolling to the day reports one
//  15.7 mi threshold day that never happened; rolling to the upload reports
//  five runs that never happened either.
//
//  WHY THIS IS NOT IN LogDedup.swift (yet)
//  `LogDedup.dedupedByPhysicalWorkout()` has six call sites across four files,
//  including `KeySessionStore` ingestion, and the repo has no test coverage
//  that would catch a regression there. This file sits ON TOP of that helper
//  rather than modifying it: it consumes the deduped output and adds the
//  session layer. Promote it into `LogDedup.swift` once The Sheet has proven
//  out on device — at which point the six call sites need a before/after
//  totals check, not a hope.
//
//  Pipeline, in this order. Collapsing the steps loses information:
//    1. `dedupedByPhysicalWorkout()`  — existing rule, untouched
//    2. group by LOCAL calendar day
//    3. split each day into sessions by clock gap
//
//  Step 1 must stay at DAY level, not session level: on Jul 18 2026 the Strava
//  row is stamped 01:38 and the voice memo 06:38, five hours apart, so a
//  session-gap test would never pair them.
//

import Foundation

// MARK: - TrainingSession

/// One physical run, assembled from one or more uploads.
struct TrainingSession: Identifiable {
    /// Stable across reloads: the first piece's row id. Used for the
    /// expand/collapse set, so a refresh doesn't collapse an open row.
    let id: UUID
    /// Start of the session's local calendar day. Grouping and week maths key
    /// off this, never off the raw `Date` — see `Self.localDay`.
    let day: Date
    /// Clock time the session started, local. Drives ordering within a day and
    /// the `6:05p` marker a day's later sessions show instead of a numeral.
    let start: Date
    /// Uploads that count toward the totals.
    let pieces: [TodayLogRow]
    /// `pieces` plus any row folded out of the totals by step 1. Notes and mood
    /// are read from here, so a folded voice memo still speaks.
    let allPieces: [TodayLogRow]
    /// How many rows step 1 folded out. Surfaces as the "duplicate row folded
    /// in" chip on expand.
    let foldedCount: Int

    let miles: Double
    let minutes: Double
    /// Normalized `workout_type` of the session's hardest piece — what the row
    /// is NAMED for.
    let typeKey: String?
    let mood: String?
    /// The session's words. Prefers `cleanedNotes`, falls back to `notes`, and
    /// is nil for junk-tier Strava defaults ("Morning Run").
    let note: String?
    let isQuality: Bool
    /// True when this is a day's second or later session. Only expressible
    /// because rows are sessions — a day-grouped sheet cannot say it.
    let isSecond: Bool

    /// Seconds per mile, DERIVED. `workout_pace_per_mile` is populated on 12%
    /// of rows and must never be a display source.
    var paceSeconds: Double? {
        guard miles > 0.05, minutes > 0 else { return nil }
        return minutes * 60 / miles
    }
}

// MARK: - Rollup

enum SessionRollup {

    /// A new upload joins the current session when it starts within this many
    /// minutes of the previous upload's END.
    ///
    /// 90 rather than 60 because Jul 21 2026's warm-up-to-cooldown gap is 65
    /// minutes and is plainly one session. Raising it much past 90 starts
    /// merging a morning shakeout into a midday workout.
    static let sessionGapMinutes: Double = 90

    /// Junk titles Strava writes when the athlete never named the activity.
    /// A row whose only note is one of these has no words, and showing it as a
    /// diary quote is worse than showing nothing.
    private static let junkTitles: Set<String> = [
        "morning run", "afternoon run", "evening run", "lunch run",
        "night run", "morning jog", "run", "treadmill", "workout"
    ]

    /// Intent ladder. A session is named for its hardest piece, so a track day
    /// reads "Threshold", not "Recovery run" because the warm-up sorted first.
    ///
    /// Ranked on `WorkoutLabel.normalize(_:)`, NEVER the raw key — `tempo` and
    /// `interval` are both live in stored rows, and `firstIndex(of:)` returns
    /// nil for a key absent from the ladder, which would name a day for its
    /// warm-up.
    private static let ladder: [String] = [
        "recovery", "easy", "moderate", "steady", "long_run",
        "progression", "fartlek", "threshold", "intervals", "long_wo", "race"
    ]

    static let qualityKeys: Set<String> = [
        "threshold", "intervals", "fartlek", "progression", "long_wo", "race"
    ]

    static func rank(_ typeKey: String?) -> Int {
        guard let n = WorkoutLabel.normalize(typeKey),
              let i = ladder.firstIndex(of: n) else { return -1 }
        return i
    }

    static func isQuality(_ typeKey: String?) -> Bool {
        guard let n = WorkoutLabel.normalize(typeKey) else { return false }
        return qualityKeys.contains(n)
    }

    /// Start of `date`'s calendar day in the athlete's CURRENT timezone.
    ///
    /// `workout_date` is a `timestamptz`. Grouping the decoded `Date` by a UTC
    /// day — which `date(workout_date)` in SQL and several edge functions do —
    /// misplaces 8 rows / 39.2 mi of this athlete's history onto the wrong
    /// date: an Aug 5 7:01pm run is stored `2026-08-06 00:01Z`. `Calendar
    /// .current` is already local, so this is correct on device; the note is
    /// here so nobody "fixes" it to a UTC calendar later.
    static func localDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    // MARK: Build

    /// Rows → sessions, newest day first, chronological within a day.
    static func sessions(from rows: [TodayLogRow]) -> [TrainingSession] {
        // Step 1 — existing dedup rule, untouched.
        let kept = rows.dedupedByPhysicalWorkout()
        let keptIDs = Set(kept.map(\.id))

        // Step 2 — group by LOCAL calendar day. Both the kept rows and the
        // rows step 1 folded out, so a folded memo can be re-attached below.
        let keptByDay = Dictionary(grouping: kept.filter { ($0.miles ?? 0) > 0 }) {
            localDay($0.date)
        }
        let foldedByDay = Dictionary(grouping: rows.filter { !keptIDs.contains($0.id) }) {
            localDay($0.date)
        }

        var out: [TrainingSession] = []

        for (day, dayRows) in keptByDay {
            // Step 3 — split into sessions by clock gap.
            let ordered = dayRows.sorted { $0.date < $1.date }
            var groups: [[TodayLogRow]] = []
            for row in ordered {
                if let last = groups.last, let prev = last.last {
                    let prevEnd = prev.date.addingTimeInterval((prev.durationMinutes ?? 0) * 60)
                    let gap = row.date.timeIntervalSince(prevEnd) / 60
                    if gap <= sessionGapMinutes {
                        groups[groups.count - 1].append(row)
                        continue
                    }
                }
                groups.append([row])
            }

            let folded = foldedByDay[day] ?? []

            for (index, pieces) in groups.enumerated() {
                // A folded row attaches to the session nearest in time. With one
                // session it all lands there, which is the Jul 18 case.
                let mine = folded.filter { f in
                    guard groups.count > 1 else { return true }
                    let nearest = groups.enumerated().min { a, b in
                        let da = abs((a.element.first?.date ?? day).timeIntervalSince(f.date))
                        let db = abs((b.element.first?.date ?? day).timeIntervalSince(f.date))
                        return da < db
                    }
                    return nearest?.offset == index
                }

                let all = pieces + mine
                let miles = pieces.reduce(0) { $0 + ($1.miles ?? 0) }
                let minutes = pieces.reduce(0) { $0 + ($1.durationMinutes ?? 0) }
                let hardest = pieces.max { rank($0.typeKey) < rank($1.typeKey) }

                // Mood and words belong to the session's NAMED piece, not to
                // whichever cooldown happened to get a memo — Aug 4 carries a
                // memo on the cooldown (RPE 3) and one on the threshold session
                // (RPE 7). Walk ALL pieces, including folded ones: on Jul 18 the
                // folded voice_log row is the only carrier of the words.
                let byIntent = all.sorted { rank($0.typeKey) > rank($1.typeKey) }
                let spoken = ([hardest].compactMap { $0 } + byIntent).first { row in
                    row.mood != nil || row.audioUrl != nil
                        || (row.source ?? "").lowercased() == "voice_log"
                }

                out.append(
                    TrainingSession(
                        id: pieces.first?.id ?? all.first?.id ?? UUID(),
                        day: day,
                        start: pieces.first?.date ?? day,
                        pieces: pieces,
                        allPieces: all,
                        foldedCount: mine.count,
                        miles: miles,
                        minutes: minutes,
                        typeKey: hardest?.typeKey,
                        mood: spoken?.mood,
                        note: words(from: spoken) ?? byIntent.compactMap { words(from: $0) }.first,
                        isQuality: all.contains { isQuality($0.typeKey) },
                        isSecond: index > 0
                    )
                )
            }
        }

        // Days newest-first; sessions WITHIN a day chronological, so the date
        // numeral leads the day block and the evening double sits under it.
        return out.sorted { a, b in
            a.day == b.day ? a.start < b.start : a.day > b.day
        }
    }

    /// A row's words, or nil when it has none worth quoting.
    private static func words(from row: TodayLogRow?) -> String? {
        guard let row else { return nil }
        let raw = (row.cleanedNotes?.isEmpty == false ? row.cleanedNotes : row.notes)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, raw.count > 26,
              !junkTitles.contains(raw.lowercased()) else { return nil }
        return raw
    }
}

// MARK: - Tags

/// Filter chips. OR'd with each other, AND'd with the search box — which is
/// how a chip row reads.
enum SessionTag: String, CaseIterable, Identifiable {
    case key, long, threshold, intervals, doubles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .key:        "Key"
        case .long:       "Long"
        case .threshold:  "Threshold"
        case .intervals:  "Intervals"
        case .doubles:    "Doubles"
        }
    }

    /// Matches on `WorkoutLabel.normalize(_:)`, never the raw key, so a stored
    /// `tempo` lands under Threshold and a stored `interval` under Intervals.
    ///
    /// `key` deliberately overlaps `threshold` and `intervals`: it is the
    /// coach's word for the same rows, and selecting both is harmless under OR.
    /// Do not try to make the set disjoint.
    func matches(_ s: TrainingSession) -> Bool {
        let n = WorkoutLabel.normalize(s.typeKey)
        switch self {
        case .key:       return s.isQuality
        case .long:      return n == "long_run" || n == "long_wo"
        case .threshold: return n == "threshold"
        case .intervals: return n == "intervals"
        case .doubles:   return s.isSecond
        }
    }
}

extension TrainingSession {
    /// Everything a search should reach: the session's name, its words, and the
    /// words and labels of every piece folded inside it.
    var searchHaystack: String {
        var parts = [WorkoutLabel.display(typeKey), note ?? ""]
        for p in allPieces {
            parts.append(WorkoutLabel.display(p.typeKey))
            parts.append(p.cleanedNotes ?? "")
            parts.append(p.notes ?? "")
        }
        return parts.joined(separator: " ").lowercased()
    }

    func matches(query: String) -> Bool {
        query.isEmpty || searchHaystack.contains(query)
    }

    /// The matched sentence, trimmed to one line, plus the range of the hit so
    /// the view can mark it.
    ///
    /// The window opens ~14 characters BEFORE the match, snapped to a word
    /// boundary: the column fits roughly 40 characters, so a centred window
    /// ellipses the search term itself away and the snippet explains nothing.
    func snippet(for query: String) -> (text: String, match: Range<String.Index>)? {
        guard !query.isEmpty else { return nil }
        let sources = ([note] + allPieces.map { $0.cleanedNotes ?? $0.notes })
            .compactMap { $0 }
        guard let src = sources.first(where: { $0.lowercased().contains(query) }),
              let hit = src.range(of: query, options: .caseInsensitive)
        else { return nil }

        var from = src.index(hit.lowerBound, offsetBy: -14, limitedBy: src.startIndex)
            ?? src.startIndex
        if from != src.startIndex,
           let space = src[from..<hit.lowerBound].firstIndex(of: " ") {
            from = src.index(after: space)
        }
        let to = src.index(hit.upperBound, offsetBy: 90, limitedBy: src.endIndex) ?? src.endIndex

        var text = String(src[from..<to])
        if from != src.startIndex { text = "…" + text }
        if to != src.endIndex { text += "…" }

        guard let match = text.range(of: query, options: .caseInsensitive) else { return nil }
        return (text, match)
    }
}

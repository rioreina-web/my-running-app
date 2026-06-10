//
//  TodayHomeView.swift
//  RunningLog
//
//  Plate 18 redesign — a "diary + charts" Today tab. Top half is the
//  athlete's narrative (today's check-in, yesterday's journal entry,
//  tomorrow's prescribed workout). Bottom half is the cockpit (12-week
//  fitness trend, this-week-vs-4-week-avg zone shifts, race predictions
//  across 5 distances).
//
//  Section order top → bottom:
//    1. Date heading + race countdown               (header)
//    2. Today · how are you feeling?                (TodayMoodPrompt)
//    3. Yesterday's journal entry                   (TodayJournalEntry)
//    4. Tomorrow's prescription                     (TodayTomorrowSection)
//    5. ── editorial rule ──
//    6. Fitness · 12-week trend chart               (TodayFitnessTrendChart)
//    7. Zone shifts · this week vs 4-week avg       (TodayZoneShiftsRow)
//    8. Race predictions · 5 distances              (TodayRacePredictionsStrip)
//
//  Data sources are documented in design/PLATE_18_DATA.md. Two known
//  holes (daily_check_ins table, coach_intent column) use degraded
//  v1 substitutes — see TodayPlate18.swift.
//
//  The components themselves live in TodayPlate18.swift; this file is
//  just orchestration: state, loadAll() fanout, and section glue.
//

import os
import Supabase
import SwiftUI

struct TodayHomeView: View {
    // Diary side — yesterday's log only; the rest of the window is fetched
    // but not retained (we only need the most-recent row right now).
    @State private var lastLog: TodayLastLog?
    @State private var goal: TodayGoal?
    @State private var coachNote: CoachMemo?

    // Plate 18 additions — tomorrow + cockpit charts.
    @State private var tomorrowWorkout: TodayTomorrowWorkout?
    @State private var fitnessTrend: TodayFitnessTrend = TodayFitnessTrend(weeklySamples: [])
    @State private var zoneShifts: TodayZoneShifts = TodayZoneShifts(zones: [])
    @State private var racePredictions: TodayRacePredictions = TodayRacePredictions(
        mile: nil, fiveK: nil, tenK: nil, half: nil, marathon: nil, confidence: nil
    )

    @State private var loaded = false

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlateStrip(surface: "LOG  ·  v1 DIARY + CHARTS", fig: "FIG. 18")
                header
                if let note = coachNote {
                    EditorialRule()
                    coachNoteSection(note: note)
                }
                TodayMoodPrompt()
                EditorialRule()
                yesterdaySection
                if let workout = tomorrowWorkout {
                    TodayTomorrowSection(workout: workout)
                }
                EditorialRule()
                TodayFitnessTrendChart(trend: fitnessTrend)
                TodayZoneShiftsRow(shifts: zoneShifts)
                TodayRacePredictionsStrip(predictions: racePredictions)
                EditorialRule()
                PlateFooter("Diary spine on top, cockpit's bottom half on the bottom.")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
    }

    // MARK: - Sections

    /// Top of the screen — coral day-of-week eyebrow, Crimson Pro date
    /// headline ("May 4th."), italic-serif countdown aside. Matches the
    /// plate-18 reference in `TodayScreen.jsx` line-for-line.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayOfWeekLabel)
                .font(.dripEyebrow(11))
                .tracking(1.3)  // 0.12em label tracking at 11pt
                .foregroundStyle(Color.drip.coral)

            Text(dateHeadline)
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)

            if let aside = countdownAside {
                Text(aside)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    /// Yesterday block — the journal entry component when a recent log
    /// exists, otherwise a quiet placeholder.
    private var yesterdaySection: some View {
        Group {
            if !loaded {
                Text("Loading…")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textTertiary)
            } else if let log = lastLog {
                TodayJournalEntry(log: log)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YESTERDAY")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                    Text("No runs logged yet. When you do, your last entry lands here.")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    /// Just the day-of-week ("TUESDAY") — date proper goes in the
    /// display headline below. Day appears in coral as the active-day
    /// signal.
    private var dayOfWeekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date()).uppercased()
    }

    /// "May 4th." — month + ordinal day + period. Period is intentional
    /// per the spec's "period after standalone headlines" rule.
    private var dateHeadline: String {
        let cal = Calendar.current
        let day = cal.component(.day, from: Date())
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let month = monthFormatter.string(from: Date())
        let ordinalFormatter = NumberFormatter()
        ordinalFormatter.numberStyle = .ordinal
        let ordinal = ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        return "\(month) \(ordinal)."
    }

    /// "— eleven weeks to the marathon. —" — italic-serif race countdown.
    /// Returns nil when no goal / no race date is set; the aside hides
    /// in that case so the empty state is just day + date.
    private var countdownAside: String? {
        guard let goal, let raceDate = goal.raceDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                       to: cal.startOfDay(for: raceDate)).day ?? 0
        guard days > 0 else { return nil }
        let weeks = max(1, Int((Double(days) / 7.0).rounded()))
        let spelled = NumberFormatter()
        spelled.numberStyle = .spellOut
        let weeksWord = spelled.string(from: NSNumber(value: weeks)) ?? "\(weeks)"
        let raceWord = raceDistancePhrase(goal.distanceLabel)
        let plural = weeks == 1 ? "week" : "weeks"
        return "— \(weeksWord) \(plural) to the \(raceWord). —"
    }

    private func raceDistancePhrase(_ label: String) -> String {
        switch label.lowercased() {
        case "marathon": return "marathon"
        case "half":     return "half"
        case "10k":      return "10K"
        case "5k":       return "5K"
        default:         return label.lowercased()
        }
    }

    // MARK: - Data loading

    /// Fan out all five Plate 18 fetches concurrently. Each returns a
    /// safe default on failure (empty arrays / zero zones), so a single
    /// fetch error doesn't blank the whole screen — the failed section
    /// just renders its empty-state copy.
    private func loadAll() async {
        async let logsTask = TodayLogRow.fetchRecent(days: 90)
        async let goalTask = TodayGoal.fetchActive()
        async let tomorrowTask = TodayTomorrowWorkout.fetchTomorrow()
        async let trendTask = TodayFitnessTrend.fetch()
        async let zonesTask = TodayZoneShifts.fetch()
        async let racesTask = TodayRacePredictions.fetch()
        async let noteTask = CoachMemo.fetchLatestUnread()

        let (logs, fetchedGoal, tomorrow, trend, zones, races, note) = await (
            logsTask, goalTask, tomorrowTask, trendTask, zonesTask, racesTask, noteTask
        )
        let mostRecent = logs.first.map { TodayLastLog(from: $0) }

        await MainActor.run {
            self.lastLog = mostRecent
            self.goal = fetchedGoal
            self.tomorrowWorkout = tomorrow
            self.fitnessTrend = trend
            self.zoneShifts = zones
            self.racePredictions = races
            self.coachNote = note
            self.loaded = true
        }
    }

    // MARK: - Coach note section

    /// Renders the most-recent unread coach note as an editorial
    /// blockquote. Tapping marks read — the note disappears on next
    /// app open, which is the right level of "saw it, move on."
    @ViewBuilder
    private func coachNoteSection(note: CoachMemo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FROM YOUR COACH")
                .font(.dripEyebrow(11))
                .tracking(1.3)  // 0.12em label tracking at 11pt
                .foregroundStyle(Color.drip.coral)

            // The canonical coach-voice gesture — italic-serif body with
            // a 2px coral-50% left bar. The README's "one place a
            // coloured left-border appears in the system" rule.
            CoachQuote(text: note.body)

            HStack(spacing: 8) {
                Text(note.relativeDate.uppercased())
                    .font(.dripEyebrow(10))
                    .tracking(1.0)  // 0.10em caption tracking at 10pt
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Button {
                    Task {
                        await note.markRead()
                        await MainActor.run { coachNote = nil }
                    }
                } label: {
                    Text("Mark read  ↗")
                        .font(.dripEyebrow(11))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Coach note

/// One unread note from the athlete's coach. Renders on the home; the
/// athlete clears it by tapping "Mark read." Coach side writes via the
/// `CoachMemoComposer` on the web roster's athlete deep-dive page.
struct CoachMemo: Decodable {
    let id: UUID
    let body: String
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "created_at"
    }

    var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Pulls the most-recent unread note for the current athlete.
    /// Returns nil when nothing's pending — the home then skips the
    /// section entirely.
    static func fetchLatestUnread() async -> CoachMemo? {
        do {
            let rows: [CoachMemo] = try await supabase
                .from("coach_notes")
                .select("id, body, created_at")
                .is("read_at", value: nil)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.coach.error("CoachMemo fetch failed: \(error)")
            return nil
        }
    }

    /// Stamps `read_at = now()` on this row. Fire-and-forget — failure
    /// is non-fatal because the next sync will catch it.
    func markRead() async {
        struct ReadUpdate: Encodable {
            let read_at: String
        }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        do {
            try await supabase
                .from("coach_notes")
                .update(ReadUpdate(read_at: nowIso))
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            Log.coach.error("CoachMemo markRead failed: \(error)")
        }
    }
}

// MARK: - Goal

struct TodayGoal {
    let timeSeconds: Int
    let distanceKey: String
    let raceDate: Date?

    var timeDisplay: String {
        let h = timeSeconds / 3600
        let m = (timeSeconds % 3600) / 60
        let s = timeSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var distanceLabel: String {
        switch distanceKey.lowercased() {
        case "marathon": return "Marathon"
        case "half_marathon", "half": return "Half"
        case "10k": return "10K"
        case "5k": return "5K"
        case "mile": return "Mile"
        default: return distanceKey.capitalized
        }
    }

    var contextLine: String? {
        guard let raceDate else { return nil }
        let weeks = max(0, Int(raceDate.timeIntervalSinceNow / (7 * 86400)))
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        if weeks == 0 {
            return "Race day this week — \(f.string(from: raceDate))."
        }
        return "\(weeks) weeks out · \(f.string(from: raceDate))"
    }

    static func fetchActive() async -> TodayGoal? {
        struct Row: Decodable {
            let target_time_seconds: Int?
            let target_race_distance: String?
            let end_date: String?
        }
        do {
            let rows: [Row] = try await supabase
                .from("training_plans")
                .select("target_time_seconds, target_race_distance, end_date")
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let r = rows.first,
                  let secs = r.target_time_seconds,
                  let dist = r.target_race_distance
            else { return nil }
            let raceDate: Date? = {
                guard let s = r.end_date else { return nil }
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone.current
                return f.date(from: s)
            }()
            return TodayGoal(timeSeconds: secs, distanceKey: dist, raceDate: raceDate)
        } catch {
            Log.coach.error("TodayGoal fetch failed: \(error)")
            return nil
        }
    }
}

// MARK: - Light log row

/// Trim of training_logs used by the home view's analytics. Bigger than
/// `TodayLastLog` because we need the whole window for mileage + mood.
struct TodayLogRow: Decodable {
    let id: UUID
    let date: Date
    let miles: Double?
    let pace: String?
    let typeKey: String?
    let mood: String?
    /// Server-generated coaching insight. Populated by
    /// `process-training-memo` for voice logs; populated on-demand by
    /// `generate-workout-insight` (Sprint 2) for HealthKit-imported logs.
    /// Empty string treated as nil so blank rows fall through to the
    /// iOS heuristic.
    let coachInsight: String?
    /// Raw transcript / journaled text. Plate 18's diary entry prefers
    /// `cleanedNotes` (LLM-cleaned punctuation + spelling) but falls
    /// back to `notes` so an entry never goes silent.
    let notes: String?
    let cleanedNotes: String?
    /// Used to fill the meta line ("8.4 mi · 7:42 / mi · 64 min · TIRED").
    let durationMinutes: Double?
    /// Which writer produced this row: `voice_log`, `auto_sync`, `strava`.
    /// The training-tab cell sum treats voice_log rows as annotations on a
    /// GPS-source row when one exists for the same day — otherwise the same
    /// physical workout gets counted twice (once as GPS, once as voice).
    let source: String?
    /// Per-mile (or per-segment) breakdown from Strava/Vital. Powers the
    /// pace-spectrum + splits visualization in `TrainingDayExpanded`.
    let paceSegments: [PaceSegment]?

    private enum CodingKeys: String, CodingKey {
        case id
        case date = "workout_date"
        case miles = "workout_distance_miles"
        case pace = "workout_pace_per_mile"
        case typeKey = "workout_type"
        case mood
        case coachInsight = "coach_insight"
        case notes
        case cleanedNotes = "cleaned_notes"
        case durationMinutes = "workout_duration_minutes"
        case source
        case paceSegments = "pace_segments"
    }

    static func fetchRecent(days: Int) async -> [TodayLogRow] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        do {
            let rows: [TodayLogRow] = try await supabase
                .from("training_logs")
                .select("id, workout_date, workout_distance_miles, workout_pace_per_mile, workout_type, mood, coach_insight, notes, cleaned_notes, workout_duration_minutes, source, pace_segments")
                .gte("workout_date", value: ISO8601DateFormatter().string(from: cutoff))
                .order("workout_date", ascending: false)
                .limit(1500)
                .execute()
                .value
            return rows
        } catch {
            Log.coach.error("TodayLogRow fetch failed: \(error)")
            return []
        }
    }
}

// MARK: - Convenience adapter

struct TodayLastLog {
    let id: UUID
    let workoutDate: Date
    let distanceMiles: Double?
    let pacePerMile: String?
    let typeKey: String?
    let typeLabel: String
    let mood: String?
    /// Trimmed to one sentence for the home (model output sometimes
    /// runs longer). Nil when no insight has been generated for this
    /// log yet — the home falls back to the heuristic in that case.
    let coachInsight: String?
    /// Raw + cleaned journal text. `TodayJournalEntry` prefers cleaned
    /// (LLM-cleaned punctuation + spelling) and falls back to raw so the
    /// quote never goes silent.
    let rawNotes: String?
    let cleanedNotes: String?
    /// Wall-clock minutes of the workout (used in the meta line).
    let durationMinutes: Double?

    init(from row: TodayLogRow) {
        self.id = row.id
        self.workoutDate = row.date
        self.distanceMiles = row.miles
        self.pacePerMile = row.pace
        self.typeKey = row.typeKey
        self.typeLabel = Self.humanType(row.typeKey)
        self.mood = row.mood
        self.coachInsight = Self.firstSentence(row.coachInsight)
        self.rawNotes = row.notes
        self.cleanedNotes = row.cleanedNotes
        self.durationMinutes = row.durationMinutes
    }

    /// Pull the first sentence from a longer insight. Looks for `.`,
    /// `?`, or `!` — falls back to the whole string when no terminator
    /// is present. Trims whitespace.
    private static func firstSentence(_ text: String?) -> String? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        for terminator in [". ", "? ", "! "] {
            if let r = raw.range(of: terminator) {
                let s = String(raw[..<r.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }
        }
        return raw
    }

    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: workoutDate)
    }

    private static func humanType(_ key: String?) -> String {
        switch (key ?? "").lowercased() {
        case "easy": return "Easy run"
        case "recovery": return "Recovery"
        case "tempo": return "Tempo"
        case "intervals": return "Intervals"
        case "long_run": return "Long run"
        case "race": return "Race"
        case "progression": return "Progression"
        case "strides": return "Strides"
        default: return "Run"
        }
    }
}

// MARK: - EditorialRule
//
// Now lives in DesignSystem.swift as a shared primitive. Removed from
// here to keep one source of truth.

// MARK: - MoodLabel

/// SwiftUI mirror of the web `MoodBadge`: a small pill carrying the
/// mood word in the mood's accent color. Used inline next to a workout
/// headline and as the legend below the 14-day mood strip.
///
/// Color comes from the existing Drip palette (positive / tired /
/// struggling / injured / energized), all already defined in the iOS
/// theme.
struct MoodLabel: View {
    let mood: String

    var body: some View {
        Text(displayName)
            .font(.dripCaption(11))
            .tracking(0.4)
            .foregroundStyle(Self.color(for: mood))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Self.color(for: mood).opacity(0.12))
            .clipShape(Capsule())
    }

    private var displayName: String {
        let m = mood.lowercased()
        // Title-case the canonical key.
        switch m {
        case "energized": return "Energized"
        case "positive", "good", "great": return "Positive"
        case "neutral", "okay": return "Neutral"
        case "tired": return "Tired"
        case "struggling", "rough": return "Struggling"
        case "injured": return "Injured"
        default:
            // Fall back to the raw string with a capital first letter.
            return mood.prefix(1).uppercased() + mood.dropFirst()
        }
    }

    /// Maps any mood key (or nil) to a Drip color. Used by both the
    /// pill background and the 14-day strip cells so the visualization
    /// reads consistently. Days without a mood return the divider tone.
    static func color(for mood: String?) -> Color {
        guard let mood = mood?.lowercased(), !mood.isEmpty else {
            return Color.drip.divider
        }
        switch mood {
        case "energized": return Color.drip.energized
        case "positive", "good", "great": return Color.drip.positive
        case "tired": return Color.drip.tired
        case "struggling", "rough": return Color.drip.struggling
        case "injured": return Color.drip.injured
        case "neutral", "okay": return Color.drip.textSecondary
        default: return Color.drip.textSecondary
        }
    }
}

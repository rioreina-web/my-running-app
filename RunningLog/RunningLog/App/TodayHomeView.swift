//
//  TodayHomeView.swift
//  RunningLog
//
//  Plate 18 redesign — the training journal, paged.
//
//  This used to be one vertical ScrollView holding every section at once. It
//  is now a paper you turn. There are TWO paged journals in the repo and
//  `journalMode` below picks which one runs; both compile either way.
//
//  .workoutPages (current, 2026-08-21) — the pages are ONE RUN's detail:
//    1. The session   — headline, mood, source, the three measures
//    2. In your words — the athlete's entry (skipped when there are none)
//    3. The workout   — WorkoutRepReceiptView: conditions, signals, splits,
//                       telemetry, route (skipped when there is no stream)
//    4. The read      — the stored coach_insight, a comparison against the
//                       athlete's own comparable session, and SessionAskBlock
//  The spine at the foot lists recent runs; tapping one loads its pages.
//  Lives in JournalPager.swift / JournalPages.swift.
//
//  .dayPages (2026-08-21, superseded) — the pages are calendar days: today
//  (check-ins, coach note, the day's sessions, tomorrow), then the numbers,
//  then one page per past day with gaps collapsed. Lives in HomePage.swift /
//  HomeDayPager.swift, and everything below `// MARK: - The pager` serves it.
//
//  The check-ins are the casualty of .workoutPages: the mood prompt, the
//  sleep prompt and the coach note have no page in a journal made of runs.
//  They are still fetched and still built here — they are simply not on
//  screen in this mode. THAT IS UNRESOLVED, and it matters: the mood and
//  sleep prompts feed the recovery ledger.
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
import UIKit

struct TodayHomeView: View {
    // Journal side. The window used to be fetched and thrown away — only the
    // most-recent row was kept. The paged surface needs the whole window, so
    // the rows are now rolled into sessions and grouped by local day; see
    // HomePage.swift.
    @State private var lastLog: TodayLastLog?
    @State private var goal: TodayGoal?
    @State private var coachNote: CoachMemo?

    // Paging state. `pages` and `sessionsByDay` are derived once per load
    // rather than per render — SessionRollup walks every row, and a LazyHStack
    // asks its content for a body more often than you would like.
    @State private var pages: [HomePage] = [.day(SessionRollup.localDay(Date())), .cockpit]
    @State private var sessionsByDay: [Date: [TrainingSession]] = [:]
    /// Seeded with today so the first frame — before `loadAll()`
    /// returns — opens on the front page rather than nowhere.
    @State private var currentPageID: HomePage.ID? = HomePage.day(SessionRollup.localDay(Date())).id

    // Plate 18 additions — tomorrow + cockpit charts.
    @State private var tomorrowWorkout: TodayTomorrowWorkout?
    @State private var fitnessTrend: TodayFitnessTrend = TodayFitnessTrend(weeklySamples: [])
    @State private var zoneShifts: TodayZoneShifts = TodayZoneShifts(zones: [])
    @State private var racePredictions: TodayRacePredictions = TodayRacePredictions(
        mile: nil, fiveK: nil, tenK: nil, half: nil, marathon: nil, confidence: nil
    )

    @State private var loaded = false
    @State private var loadFailed = false

    /// The workout detail, opened by tapping a session on any page. Nil when
    /// closed. `DayWorkouts` is the same payload the Trends day drill-down
    /// hands to `HistoryDetailPager`. Used by `.dayPages` mode only.
    @State private var dayWorkouts: DayWorkouts?

    /// The runs the workout-paged journal turns through.
    @State private var journalEntries: [TrainingLog] = []

    /// WHICH JOURNAL THIS IS. `.workoutPages` — the pages are one run's
    /// detail (session · words · workout · read) and the spine at the foot
    /// switches runs. `.dayPages` — the pages are calendar days, which is
    /// what this surface was between the paged rewrite and 2026-08-21.
    ///
    /// Both are built and both work. This line is the whole switch, and
    /// reversing the decision is changing this one word. The day-page code
    /// (HomePage.swift, HomeDayPager.swift) stays compiled either way.
    private let journalMode: JournalMode = .workoutPages

    enum JournalMode { case workoutPages, dayPages }

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            // The masthead. Fixed above the pages — it belongs to the
            // surface, not to any one day.
            PlateStrip(surface: "TRAINING JOURNAL", fig: "FIG. 18")
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if loaded && loadFailed {
                EmptyStateView(
                    variant: .error,
                    eyebrow: "Couldn't load",
                    title: "Today didn't load. Check your connection and try again.",
                    cta: .init(label: "Retry") {
                        Task { await loadAll() }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.top, 20)
                Spacer()
            } else if journalMode == .workoutPages {
                JournalPagerView(entries: journalEntries)
            } else {
                pager
            }
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
    }

    // MARK: - The pager

    /// One local day per page, today first, turning back through the log.
    ///
    /// Same mechanic as `HistoryDetailPager` — see the note in
    /// HomeDayPager.swift about the one place the two deliberately differ
    /// (direction), which is still unresolved.
    private var pager: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { page in
                        pageView(for: page)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(page.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentPageID)
            .scrollIndicators(.hidden)

            HomeFolioRail(pages: pages, currentID: $currentPageID, index: currentIndex)
        }
        .onChange(of: currentPageID) { old, new in
            guard old != nil, new != nil, old != new else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        // Custom actions are only surfaced by VoiceOver when the container is
        // itself an accessibility element.
        .accessibilityElement(children: .contain)
        // Named for time, not for screen direction — matching
        // HistoryDetailPager's wording.
        .accessibilityAction(named: "Older day") { step(1) }
        .accessibilityAction(named: "Newer day") { step(-1) }
        .sheet(item: $dayWorkouts) { dw in
            HistoryDetailPager(entries: dw.entries, initial: dw.initial) {
                // An edit or a delete in the sheet changes the rows the pages
                // are built from. Rebuild rather than leave a stale page
                // behind; `loadAll` keeps the reader where they were.
                Task { await loadAll() }
            }
        }
    }

    /// Fetch the tapped session's real `TrainingLog` rows and open the detail.
    /// Nothing opens if the fetch fails — see `HomeSessionOpener`.
    private func open(_ session: TrainingSession, on day: Date) {
        let onDay = sessionsByDay[day] ?? [session]
        Task {
            if let dw = await HomeSessionOpener.resolve(sessionsOnDay: onDay, focus: session) {
                dayWorkouts = dw
            }
        }
    }

    private var currentIndex: Int {
        pages.firstIndex { $0.id == currentPageID } ?? 0
    }

    private func step(_ delta: Int) {
        let target = currentIndex + delta
        guard pages.indices.contains(target) else { return }
        withAnimation(.snappy(duration: 0.28)) {
            currentPageID = pages[target].id
        }
    }

    @ViewBuilder
    private func pageView(for page: HomePage) -> some View {
        switch page {
        case .day(let date):
            if SessionRollup.localDay(Date()) == date {
                todayPage
            } else {
                HomeDayPageView(
                    day: date,
                    sessions: sessionsByDay[date] ?? [],
                    onOpen: { open($0, on: date) }
                )
            }
        case .cockpit:
            cockpitPage
        case .gap(let from, let through, let days):
            HomeGapPageView(from: from, through: through, days: days)
        }
    }

    // MARK: - The pages

    /// Today. The only page carrying the check-ins, the coach note and
    /// tomorrow's prescription — all four are today-relative, and putting
    /// them on a past page would either invent data or lie about the date.
    private var todayPage: some View {
        HomePageFrame {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let note = coachNote {
                    EditorialRule()
                    coachNoteSection(note: note)
                }

                TodayMoodPrompt()
                // The one-tap sleep check-in rides with the mood prompt —
                // one daily ritual, two words. Tier-1 recovery signal;
                // writes `daily_checkins`, feeds the ledger's Sleep factor.
                SleepCheckInPrompt()

                EditorialRule()

                todaySessions

                if let workout = tomorrowWorkout {
                    TodayTomorrowSection(workout: workout)
                }
            }
        }
    }

    /// Today's own runs — which on this account is regularly two or three.
    ///
    /// This replaces the old "yesterday's journal entry" block. Yesterday is
    /// not gone; it is one turn to the right, on its own page, where it can
    /// say its own date.
    @ViewBuilder
    private var todaySessions: some View {
        let today = SessionRollup.localDay(Date())
        let sessions = sessionsByDay[today] ?? []

        if !loaded {
            Text("Loading…")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textTertiary)
        } else if sessions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S SESSION")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Text("Nothing logged yet today. When you run, it lands here.")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    HomeSessionEntry(
                        session: session,
                        showClockTime: sessions.count > 1,
                        ordinal: index + 1,
                        of: sessions.count,
                        onOpen: { open(session, on: today) }
                    )
                }
            }
        }
    }

    /// The numbers. Account-level, belonging to no day, which is why it is
    /// page two rather than the bottom half of today.
    ///
    /// OPEN: this duplicates the Trends tab. If it leaves Today, the page
    /// model becomes purely days and this whole property goes with it.
    private var cockpitPage: some View {
        HomePageFrame {
            VStack(alignment: .leading, spacing: 24) {
                Text("THE NUMBERS")
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
                TodayFitnessTrendChart(trend: fitnessTrend)
                TodayZoneShiftsRow(shifts: zoneShifts)
                TodayRacePredictionsStrip(predictions: racePredictions)
                EditorialRule()
                PlateFooter("Training journal on the day pages, cockpit on its own.")
            }
        }
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

    // The "yesterday" block was removed when this surface became a pager.
    // Yesterday is not gone — it is one turn to the right, on a page that can
    // say its own date instead of borrowing today's. `TodayJournalEntry` is
    // still in TodayPlate18.swift and still used elsewhere; `lastLog` is still
    // loaded, and is what a "jump to the last run" affordance would use if one
    // is ever added to the rail.

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
        // The logs fetch doubles as a connectivity canary. If it throws,
        // the network is down — every other section would render empty —
        // so we surface one Retry instead of a silently blank screen.
        // Secondary fetches already fall back to safe defaults on error.
        // Via the shared store: if Log or Train is refreshing at the same
        // moment (e.g. at launch), this coalesces onto that request instead
        // of firing its own 90-day fetch.
        async let logsTask = TrainingLogStore.shared.refresh(days: 90)
        async let goalTask = TodayGoal.fetchActive()
        async let tomorrowTask = TodayTomorrowWorkout.fetchTomorrow()
        async let trendTask = TodayFitnessTrend.fetch()
        async let zonesTask = TodayZoneShifts.fetch()
        async let racesTask = TodayRacePredictions.fetch()
        async let noteTask = CoachMemo.fetchLatestUnread()
        async let journalTask = JournalEntries.recent()

        let logs: [TodayLogRow]
        do {
            logs = try await logsTask
        } catch {
            Log.coach.error("Today loadAll failed: \(error.localizedDescription)")
            await MainActor.run {
                self.loadFailed = true
                self.loaded = true
            }
            return
        }

        let (fetchedGoal, tomorrow, trend, zones, races, note) = await (
            goalTask, tomorrowTask, trendTask, zonesTask, racesTask, noteTask
        )
        let entries = await journalTask
        let mostRecent = logs.first.map { TodayLastLog(from: $0) }

        // Rows → sessions → pages. Done here, off the main actor, because
        // SessionRollup walks every row in the window and the page run is
        // stable until the next load.
        let rolled = SessionRollup.sessions(from: logs)
        let builtPages = HomePageBuilder.pages(from: rolled)
        let grouped = Dictionary(grouping: rolled, by: { $0.day })
            .mapValues { $0.sorted { $0.start < $1.start } }

        await MainActor.run {
            self.loadFailed = false
            self.journalEntries = entries
            self.pages = builtPages
            self.sessionsByDay = grouped
            // Only land on today's page on the first load. A refresh that
            // rebuilt the run must not yank the athlete back to the front
            // page from wherever they were reading.
            if self.currentPageID == nil || !builtPages.contains(where: { $0.id == self.currentPageID }) {
                self.currentPageID = builtPages.first?.id
            }
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
// Codable (not just Decodable): TrainingLogStore snapshots these rows to
// disk for the instant-render fast path, so they must encode too.
struct TodayLogRow: Codable {
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
    /// Raw transcript / journaled text. Plate 18's journal entry prefers
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
    /// Storage path of the recording, when this row carries one. A voice memo
    /// about a GPS run gets its audio reattached onto the run row (see
    /// migration `20260702150000_reattach_voice_memos_to_runs`), so `source`
    /// stays `strava` while `audio_url` is non-nil — the only reliable "this
    /// is a voice memo" signal for such rows. Mirrors the backend's own
    /// qualitative/audio-bearing definition in `20260702200000`.
    let audioUrl: String?
    /// Per-mile (or per-segment) breakdown from Strava/Vital. Powers the
    /// pace-spectrum + splits visualization in `TrainingDayExpanded`.
    let paceSegments: [PaceSegment]?
    /// Rep-level structure (warmup / work_rep / recovery / cooldown, each with
    /// its own distance + pace). This is the ONLY source that carries true rep
    /// pace — `pace_segments` are per-mile splits that average reps with their
    /// recoveries. The Volume × Pace histogram bins by these when present so a
    /// 4:40 rep counts as 4:40, not as the 6:30 mile it lived inside.
    let parsed: ParsedLite?
    var structureBlocks: [StructureBlockLite]? { parsed?.blocks }
    /// Effort as the athlete conveyed it, 1-10, extracted from the memo by
    /// `extract-rpe`. Nil is the honest majority case: the extractor is
    /// instructed to return null rather than guess when the transcript
    /// doesn't say how hard it felt, and non-voice rows never get one.
    var feltRPE: Int? = nil
    /// Typed workout description — the athlete's own statement of intent, and
    /// the parser's TOP structure source. Distinct from `notes` (transcript)
    /// and `cleanedNotes` (LLM-tidied transcript).
    var workoutNotes: String? = nil
    /// Server-computed conditions from `fetch-workout-weather`, including the
    /// heat `adjustment_pct`. Nil on indoor/manual rows with no GPS to
    /// attribute weather to. Never recompute the penalty on-device.
    var weather: RunWeather? = nil

    struct ParsedLite: Codable { let blocks: [StructureBlockLite]? }
    struct StructureBlockLite: Codable {
        let role: String?
        let distanceMiles: Double?
        let avgPace: String?   // "M:SS"
        private enum CodingKeys: String, CodingKey {
            case role
            case distanceMiles = "distance_miles"
            case avgPace = "avg_pace_per_mile"
        }
    }

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
        case audioUrl = "audio_url"
        case paceSegments = "pace_segments"
        case parsed = "parsed_structure"
        case feltRPE = "felt_rpe"
        case workoutNotes = "workout_notes"
        case weather = "weather_actual"
    }

    static func fetchRecent(days: Int) async -> [TodayLogRow] {
        do {
            return try await fetchRecentThrowing(days: days)
        } catch {
            Log.coach.error("TodayLogRow fetch failed: \(error)")
            return []
        }
    }

    /// Throwing variant. Surfaces that need to tell a real fetch failure
    /// apart from a genuinely empty result (so they can show a Retry state
    /// instead of a misleading "no runs yet" empty state) call this and
    /// handle the error themselves.
    static func fetchRecentThrowing(days: Int) async throws -> [TodayLogRow] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let rows: [TodayLogRow] = try await supabase
            .from("training_logs")
            .select("id, workout_date, workout_distance_miles, workout_pace_per_mile, workout_type, mood, coach_insight, notes, cleaned_notes, workout_duration_minutes, source, audio_url, pace_segments, parsed_structure, felt_rpe, workout_notes, weather_actual")
            .gte("workout_date", value: ISO8601DateFormatter().string(from: cutoff))
            .order("workout_date", ascending: false)
            .limit(1500)
            .execute()
            .value
        return rows
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
        WorkoutLabel.display(key)
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

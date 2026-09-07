//
//  WorkoutsAndRepsSection.swift
//  RunningLog
//
//  Session receipts: recent quality workouts as ledger entries. Each row
//  carries the parsed structure as its title ("8×1K · 5.3 mi" — workout
//  labels are pace-zone labels; Intervals/Tempo/Threshold are retired),
//  a zone chip, the work-bout REP PACE (rest excluded, ○ when
//  heat-adjusted), and a RepDensityStrip — width = rep distance, color =
//  the zone-anchored PaceSpectrum ramp — so a column of rows reads as a
//  flip-book of the block. Tapping opens the full Rep Receipt.
//
//  Self-contained (own fetch, own sheet) so it drops into TrainingTabView
//  or the Key Sessions detail with a single line.
//
//  TWO DRESSES, ONE LEDGER (2026-08-17). `style: .card` is the original —
//  a bordered card among other cards on Train. `style: .editorial` is what
//  Trends §03 wears now that the key-session dot grid is gone: no border, no
//  label, month rules between runs, structure set in Crimson. Rows, fetch and
//  tap target are identical; only the dressing branches. `initialCount` goes
//  with it — four rows is right for a card, a teaser for a whole section.
//
//  SHOWS FOUR, GOES DEEPER ON REQUEST (2026-08-11). The card opens at four
//  receipts — enough to read the recent shape without turning a section into a
//  scroll — and a footer button walks back through the block a page at a time.
//  Paging is two-stage on purpose: the first taps reveal rows already fetched
//  (instant, one enrichment round trip for the newly shown ids), and only when
//  those run out does it go back to the server for older sessions. Enrichment
//  stays lazy either way — laps are one query PER ROW, so eagerly fetching a
//  year of sessions to show four of them is the thing this avoids.
//
//  LONG RUNS ARE KEY SESSIONS (2026-08-19, Rio). This ledger used to fetch
//  rep workouts only, so the Saturday long run — the biggest aerobic stimulus
//  of the week, averaging 14.0 mi across 21 sessions in the last 180 days —
//  appeared nowhere on a section titled "Key sessions". The backend has said
//  otherwise since `keySessions.ts` was written: it admits a long run on the
//  classifier's label and tags it `kind: "long_run"`. This surface now agrees.
//
//  A long run is NOT dressed like a workout, because its numbers are not the
//  same numbers:
//    • Pace is the WHOLE RUN's mean, not a work-bout pace. It is labelled
//      `/mi avg` and set in secondary weight, so it can never be read as the
//      rep pace on the row above it. `KeySessionOut.kind` exists on the
//      backend for exactly this reason — the two never share a scale.
//    • The chip reads LONG rather than a pace zone: a long run's stored
//      structure ("17.1 mi long") carries no `(zone)` to parse, and inventing
//      one would be a guess.
//    • The title is "Long run · 17.1 mi". The stored structure is deliberately
//      ignored — appending the distance to it printed the miles twice.
//    • The chart is `LongRunPaceStrip`, not `RepDensityStrip`: one continuous
//      bar split at the run's own miles, no gaps, on the same PaceSpectrum
//      ramp. `RepDensityStrip` merges consecutive non-rest laps into work
//      bouts before drawing — right for reps, and it flattened the 25 recorded
//      mile splits of the 2026-08-01 long run into three slabs, one per water
//      stop. A long run with no recorded splits (a single summary lap, as on
//      2026-08-16 and 2026-08-08) draws no bar at all rather than a flat one:
//      even pacing the app never measured is not a thing to picture.
//  `long_wo` ("Long run workout") is a workout that happens to be long: it has
//  reps, so it takes the normal quality dress.
//
//  Data: training_logs (key-session types — detection only, never displayed as
//  labels) + workout_features.workout_structure + running_workout_laps for
//  the visible rows. All RLS user-scoped. Degrades row by row: no structure
//  → plain distance title; no laps → no strip, no rep pace; a long run with
//  neither laps nor duration gets no pace at all rather than a fabricated one.
//
//  Design: outputs/key-sessions-low-data-editorial-mockup-2026-07-02.html +
//  outputs/pace-volume-studies-2026-07-02.html (Study D).
//

import SwiftUI
import Supabase
import os

struct WorkoutsAndRepsSection: View {

    /// How the section dresses itself.
    ///
    /// `.card` is the original: a bordered card with a "KEY SESSIONS" label
    /// (it read "WORKOUTS & REPS" until long runs joined the list on
    /// 2026-08-19), one of several cards stacked on the Train tab.
    ///
    /// `.editorial` is what the Trends tab asked for when the key-session dot
    /// grid came out (2026-08-17): no card, no label, month rules between
    /// runs, and the structure set in Crimson rather than PT Serif — because
    /// here the ledger IS the section, not a card inside one. Same rows, same
    /// fetch, same tap target.
    enum Style { case card, editorial }

    var style: Style = .card
    /// How many receipts the section opens at, and how many each "Show more"
    /// adds. Four on the Train tab, where this is one card among many; more on
    /// Trends, where it is the whole section and four rows reads as a teaser.
    var initialCount: Int = 4

    private struct QualityWorkout: Decodable, Identifiable {
        let id: UUID
        var workout_date: String?
        var workout_type: String?
        var workout_distance_miles: Double?
        /// Only read for a long run with no laps — the last honest route to an
        /// average pace. 23 of 24 long runs in the last year carry it.
        var workout_duration_minutes: Double?
    }
    private struct FeatureRow: Decodable {
        let training_log_id: UUID
        let workout_structure: String?
    }
    private struct SheetID: Identifiable { let id: UUID }

    /// Detection filter only — these tokens select which logs are key
    /// sessions; they are never rendered as labels (the taxonomy dropped them).
    ///
    /// `long_run` and `long_wo` joined the list on 2026-08-19. Both were absent
    /// even though `SessionRollup.qualityKeys` already counts `long_wo` as
    /// quality and `keySessions.ts` already admits `long_run` — this list was
    /// the only place in the app that disagreed.
    private static let keySessionTypes = [
        "intervals", "interval", "threshold", "tempo", "fartlek",
        "progression", "race", "long_run", "long_wo",
    ]

    /// Fallback opening count, used only as the initial `shown` value before
    /// `load()` raises it to `initialCount`. `initialCount` is the number that
    /// matters — see it for why the two exist.
    private static let pageSize = 4
    /// How many rows one server page holds. Deliberately a multiple of
    /// `pageSize` so a fetch never leaves a partial page dangling.
    private static let fetchPage = 12

    /// Does this row take the long-run dress? Routed through
    /// `WorkoutLabel.normalize(_:)` rather than compared raw, because `"long"`
    /// and `"longrun"` are both live in stored rows and a raw comparison would
    /// dress them as workouts.
    ///
    /// `long_wo` deliberately returns false: a long run workout has reps, so it
    /// has a real rep pace and a real zone chip.
    private func isLongRun(_ w: QualityWorkout) -> Bool {
        WorkoutLabel.normalize(w.workout_type) == "long_run"
    }

    /// A long run workout (`long_wo`) is one continuous run with structure
    /// embedded in it — 4×3mi at steady inside a 21-miler. Its reps usually
    /// run SLOWER than the athlete's race anchors, so `RepDensityStrip`'s
    /// merge-the-work view collapses the whole run into one block and draws
    /// nothing; the honest mark is the long-run one — every split, on the
    /// pace ramp. The zone chip and rep pace still come from the server
    /// structure (the run-relative pass in `workoutSegmentation.ts`).
    private func isLongWorkout(_ w: QualityWorkout) -> Bool {
        WorkoutLabel.normalize(w.workout_type) == "long_wo"
    }

    @State private var items: [QualityWorkout] = []
    /// The athlete's own key-session marks, via the ONE shared store (so this
    /// ledger can never disagree with the star on the journal/calendar/day
    /// sheet). The ledger honors them in BOTH directions: a day marked key
    /// surfaces its session here even when its type is outside
    /// `keySessionTypes` — a moderate long run, a steady day, a progression;
    /// key sessions are whatever the athlete says they are — and a day marked
    /// not-key drops out even when the type matches. Same precedence as the
    /// star: the athlete's word beats the type heuristic.
    @State private var keySessions = KeySessionStore.shared
    /// Rows present ONLY because the athlete marked their day key — they
    /// leave the list if the mark is withdrawn, unlike type-qualified rows.
    @State private var markedInIds: Set<UUID> = []
    @State private var structures: [UUID: String] = [:]
    @State private var lapsById: [UUID: [WorkoutLapRow]] = [:]
    @State private var loaded = false
    @State private var sheet: SheetID?
    @State private var errorText: String?
    /// How many receipts are on screen. Grows by `pageSize` per tap.
    @State private var shown = Self.pageSize
    /// True once the server has returned a short page — there are no older
    /// quality sessions, so the footer stops offering to look for them.
    @State private var reachedEnd = false
    /// Rows consumed from the type-driven server query. Distinct from
    /// `items.count` now that marks can insert rows (which would make offsets
    /// skip server rows) and exclude them (which would refetch the same page
    /// forever).
    @State private var serverOffset = 0
    @State private var isLoadingMore = false
    /// Rows whose structure + laps have been asked for. Tracked explicitly
    /// rather than inferred from `lapsById`/`structures`, because a session
    /// with neither — no features computed, no laps uploaded — is a real
    /// answer, and inferring would re-query it on every reveal.
    @State private var enriched: Set<UUID> = []

    var body: some View {
        Group {
            switch style {
            case .card:
                stack
                    .padding(16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
            case .editorial:
                // Bare on paper. The section head above it is the label, and a
                // card border inside a section that is already ruled top and
                // bottom draws a box around a box.
                stack
            }
        }
        .task { await load() }
        // A mark set or cleared while this ledger is on screen re-applies
        // immediately — the day sheet's star and this list are one answer.
        .onChange(of: keySessions.overrideByDay) {
            guard loaded else { return }
            Task {
                await applyOverrides()
                await enrich(Array(items.prefix(shown)))
            }
        }
        // Was a hand-rolled copy of WorkoutRepDetailSheet's chrome — the same
        // NavigationStack + ScrollView + "WORKOUT" toolbar, duplicated. Three
        // surfaces each had one, so the missing Done button and the missing
        // opaque nav bar had to be fixed in four places. One place now. (S2)
        .sheet(item: $sheet) { s in
            WorkoutRepDetailSheet(workoutId: s.id)
        }
    }

    /// Everything inside the chrome, so both styles share one definition.
    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            if style == .card { sectionLabel }
            if !items.isEmpty {
                rows
                footer
            } else if !loaded {
                Text("Loading workouts…")
                    .font(.dripStat(11)).foregroundStyle(Color.drip.textTertiary)
                    .padding(.vertical, 12)
            } else {
                Text(errorText ?? "No key sessions logged yet. The first interval day, MP miles, LT session or long run lands here.")
                    .font(.dripBody(13).italic()).foregroundStyle(Color.drip.textSecondary)
                    .padding(.vertical, 12)
            }
        }
    }

    /// The visible receipts. Editorial breaks them into month runs; card keeps
    /// the flat list it always had.
    @ViewBuilder
    private var rows: some View {
        switch style {
        case .card:
            ForEach(Array(items.prefix(shown))) { w in
                Button { sheet = SheetID(id: w.id) } label: { receipt(w) }
                    .buttonStyle(.plain)
            }
        case .editorial:
            ForEach(monthRuns) { run in
                monthRule(run.label)
                ForEach(run.rows) { w in
                    Button { sheet = SheetID(id: w.id) } label: { editorialReceipt(w) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var sectionLabel: some View {
        HStack(spacing: 10) {
            // Renamed from "WORKOUTS & REPS" (2026-08-19). Once long runs are
            // in the list the old label describes only part of it, and Trends
            // §03 already calls this same ledger "Key sessions". One name.
            Text("KEY SESSIONS")
                .font(.dripStat(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.bottom, 6)
    }

    // MARK: more

    /// The card's one control. "Show more" while there is more — whether it's
    /// already in memory or still on the server — and "Show fewer" once the
    /// whole history is on screen, so an expanded card is never a one-way door.
    ///
    /// Reports what it's doing rather than guessing: it never claims there are
    /// older sessions it hasn't checked for, and once the server comes back
    /// short it stops offering.
    @ViewBuilder
    private var footer: some View {
        let hasMore = shown < items.count || !reachedEnd
        if hasMore || shown > initialCount {
            Button {
                if hasMore { Task { await showMore() } } else { collapse() }
            } label: {
                HStack(spacing: 8) {
                    Text(hasMore ? "SHOW MORE" : "SHOW FEWER")
                        .font(.dripStat(10)).tracking(1.2)
                        .foregroundStyle(Color.drip.textSecondary)
                    if isLoadingMore {
                        ProgressView().controlSize(.mini).tint(Color.drip.textTertiary)
                    } else {
                        Image(systemName: hasMore ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer()
                    // The count, so the athlete knows what "more" is worth
                    // before spending a tap on it.
                    Text("\(min(shown, items.count)) of \(items.count)\(reachedEnd ? "" : "+")")
                        .font(.dripStat(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoadingMore)
        }
    }

    /// Reveal the next page. Rows already fetched appear immediately and are
    /// enriched behind them; only when the fetched list runs dry does this go
    /// back to the server for older sessions.
    private func showMore() async {
        guard !isLoadingMore else { return }
        if shown >= items.count, !reachedEnd {
            isLoadingMore = true
            await fetchOlder()
            isLoadingMore = false
        }
        let next = min(shown + initialCount, items.count)
        guard next > shown else { return }
        let revealed = Array(items[shown..<next])
        shown = next
        await enrich(revealed)
    }

    /// Back to the opening four. Fetched rows and their enrichments stay in
    /// memory, so re-expanding is instant and costs no network.
    private func collapse() {
        shown = initialCount
    }

    // MARK: receipt row

    private func receipt(_ w: QualityWorkout) -> some View {
        let long = isLongRun(w)
        let longWo = isLongWorkout(w)
        let parts = structureParts(structures[w.id])
        let chip: String? = long ? "LONG" : parts.zone
        // long_wo: rep pace from the server structure — see editorialReceipt.
        let pace = long
            ? avgPace(w)
            : longWo ? (parts.pace.map { RepPace(label: $0) } ?? avgPace(w))
            : repPace(w.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateLine(w.workout_date))
                    .font(.dripStat(10)).tracking(0.6)
                    .foregroundStyle(Color.drip.coral)
                Spacer()
                if let chip {
                    Text(chip)
                        .font(.dripStat(9)).tracking(1.0)
                        .foregroundStyle(long ? Color.drip.textTertiary : Color.drip.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title(parts.title, w))
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                if let pace {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(pace.label).font(.dripStat(13))
                            .foregroundStyle(pace.isAvg ? Color.drip.textSecondary : Color.drip.textPrimary)
                        // "AVG PACE", never "REP PACE": a long run has no reps,
                        // and the two numbers do not belong on one scale.
                        Text(pace.isAvg ? "AVG PACE" : "REP PACE").font(.dripStat(8)).tracking(0.8)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                } else {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(.top, 3)
            if let laps = lapsById[w.id] {
                // Two marks, one language. A rep workout gets blocks with
                // gaps (the gaps ARE the rest); a long run gets one unbroken
                // bar split at its own miles. A long run WORKOUT sits with
                // the rep workouts now that enrichment carries the parser's
                // lap roles — a 4×3mi with floats reads as four blocks, same
                // as any interval day, and only falls back to the continuous
                // bar when no rest structure was parsed. Same PaceSpectrum
                // ramp everywhere, so a 5:19 rep and a 6:38 mile are the
                // blues they always are.
                if long || (longWo && !hasRepStructure(laps)) {
                    LongRunPaceStrip(laps: laps).padding(.top, 9)
                } else {
                    RepDensityStrip(laps: laps).padding(.top, 9)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    // MARK: editorial receipt row

    /// The same receipt, set for the Trends tab: the structure in Crimson at
    /// reading size, the measured rep pace as the one number on the right, and
    /// the density strip underneath. The date drops from coral to tertiary —
    /// twenty coral date lines down a page is not punctuation, and the month
    /// rules now carry the dating.
    private func editorialReceipt(_ w: QualityWorkout) -> some View {
        let long = isLongRun(w)
        let longWo = isLongWorkout(w)
        let parts = structureParts(structures[w.id])
        // Always LONG for a long run, even on the rare row whose stored
        // structure does parse a zone: "Long run" under an LT chip is a
        // contradiction on one line. A long run typed with rep structure is a
        // classifier problem and gets fixed there, not papered over here.
        let chip: String? = long ? "LONG" : parts.zone
        // A long_wo's rep pace comes from the server structure — the reps sit
        // slower than the work gate, so the client-side lap merge would
        // return the whole-run mean and print it in rep-pace weight.
        let pace = long
            ? avgPace(w)
            : longWo ? (parts.pace.map { RepPace(label: $0) } ?? avgPace(w))
            : repPace(w.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateLine(w.workout_date))
                    .font(.dripEyebrow(9)).tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer(minLength: 8)
                if let chip {
                    Text(chip)
                        .font(.dripEyebrow(9)).tracking(1.0)
                        .foregroundStyle(long ? Color.drip.textTertiary : Color.drip.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title(parts.title, w))
                    .font(.dripDisplay(18))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if let pace {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(pace.label)
                            .font(.dripStat(16))
                            // A long run's mean sits a step back from a rep
                            // pace. Same column, visibly not the same claim.
                            .foregroundStyle(pace.isAvg ? Color.drip.textSecondary : Color.drip.textPrimary)
                        Text(pace.isAvg ? "/mi avg" : "/mi")
                            .font(.dripBody(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                } else {
                    // Nothing measured to state — no laps on a workout, or a
                    // long run carrying neither laps nor a logged duration.
                    // The chevron says "there is more inside" rather than
                    // inventing a number this row does not have.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(.top, 2)
            if let laps = lapsById[w.id] {
                // See `receipt(_:)` — a long run's shape is its splits
                // (RepDensityStrip's bout merge collapsed 25 recorded miles
                // into three slabs, one per water stop). A long run WORKOUT
                // is different now that enrichment retags rest from the
                // parser's lap roles: its reps segment honestly, so it takes
                // the rep blocks like every other quality day — the
                // continuous mile ribbon here is only the fallback for a
                // long_wo the parser never segmented. (The ribbon dressing a
                // 4×3mi was exactly the "rep strip drew nothing" era: no
                // rest tags meant one 21-mile bout, which renders empty.)
                if long || (longWo && !hasRepStructure(laps)) {
                    LongRunPaceStrip(laps: laps, height: 10).padding(.top, 8)
                } else {
                    RepDensityStrip(laps: laps, height: 10).padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
        // One row, one announcement — otherwise VoiceOver reads the date, the
        // zone, the title and the pace as four separate unlabelled fragments.
        .accessibilityElement(children: .combine)
    }

    // MARK: editorial — month runs

    private struct MonthRun: Identifiable {
        let id: String       // "2026-07"
        let label: String    // "JULY" (or "JULY 2025" across a year boundary)
        let rows: [QualityWorkout]
    }

    /// Visible rows split into consecutive same-month runs. Built off the
    /// already-sorted list, so a month never appears twice and no row is
    /// dropped for having an unparseable date — those fall into a run keyed
    /// on whatever prefix they have, labelled blank, and still render.
    private var monthRuns: [MonthRun] {
        var runs: [MonthRun] = []
        let topYear = String((items.first?.workout_date ?? "").prefix(4))
        for w in items.prefix(shown) {
            let key = String((w.workout_date ?? "").prefix(7))
            if let last = runs.last, last.id == key {
                runs[runs.count - 1] = MonthRun(id: key, label: last.label, rows: last.rows + [w])
            } else {
                runs.append(MonthRun(id: key, label: monthLabel(key, topYear: topYear), rows: [w]))
            }
        }
        return runs
    }

    private static let monthNames = [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
    ]

    /// "2026-07" → "JULY". The year is appended only when the run has walked
    /// back past the newest row's year, so a normal block isn't stamped with a
    /// year on every rule.
    private func monthLabel(_ key: String, topYear: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return "" }
        let name = Self.monthNames[m - 1]
        return String(parts[0]) == topYear ? name : "\(name) \(parts[0])"
    }

    private func monthRule(_ label: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.dripEyebrow(9)).tracking(1.5)
                .foregroundStyle(Color.drip.textSecondary)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    // MARK: data

    private func load() async {
        guard items.isEmpty else { return }   // re-entrant `.task`; keep the page state
        // `shown` can't be initialised from `initialCount` at declaration —
        // a @State initial value can't read another property of the same
        // struct — so it's raised here, before the first enrichment decides
        // how many rows to fetch laps for.
        shown = max(shown, initialCount)
        // The store loads at launch; this is only the cold-path fallback (a
        // surface reached before RunningLogApp's kickoff finished).
        if !keySessions.hasLoaded { await keySessions.loadOverrides() }
        do {
            items = try await fetchPage(offset: 0)
        } catch {
            errorText = "Couldn't load workouts: \(error.localizedDescription)"
            Log.coach.error("WorkoutsAndRepsSection load failed: \(error)")
            loaded = true
            return
        }
        serverOffset = items.count
        if items.count < Self.fetchPage { reachedEnd = true }
        await applyOverrides()
        await enrich(Array(items.prefix(shown)))
        loaded = true
    }

    /// "yyyy-MM-dd" for a fetched row. `workout_date` stores the local wall
    /// clock, matching `day_overrides.date` — the same convention every other
    /// key-session surface leans on.
    private func dayKey(_ w: QualityWorkout) -> String? {
        guard let d = w.workout_date, d.count >= 10 else { return nil }
        return String(d.prefix(10))
    }

    /// Apply the athlete's marks to the fetched list, both directions.
    /// Exclusion is a filter; inclusion fetches each marked day's main run
    /// (the day's longest logged session) when the type gate missed it. Runs
    /// after every page append, and again whenever a mark changes while the
    /// ledger is on screen, so a tap in the day sheet moves this list the
    /// same moment it moves the star.
    private func applyOverrides() async {
        let keyOverrides = keySessions.overrideByDay

        // A row that is only here because of a mark leaves with the mark —
        // withdrawing the override (back to auto) must not strand a moderate
        // run in a list its type never qualified for.
        items.removeAll { w in
            guard markedInIds.contains(w.id), let day = dayKey(w) else { return false }
            return keyOverrides[day] != true
        }
        markedInIds = markedInIds.filter { id in items.contains { $0.id == id } }

        guard !keyOverrides.isEmpty else { return }

        // OUT: the athlete said this day was not a key session.
        items.removeAll { w in
            guard let day = dayKey(w) else { return false }
            return keyOverrides[day] == false
        }

        // IN: days the athlete marked key with no row in the list yet. Only
        // days inside the span already fetched — older marked days join as
        // paging reaches them, so the list stays in date order with no holes.
        let presentDays = Set(items.compactMap(dayKey))
        let oldestFetched = items.compactMap(dayKey).min()
        let missingDays = keyOverrides
            .filter { $0.value && !presentDays.contains($0.key) }
            .keys
            .filter { day in
                guard let oldest = oldestFetched else { return true }
                return reachedEnd || day >= oldest
            }
            .sorted(by: >)

        guard !missingDays.isEmpty else { return }
        var added = false
        for day in missingDays.prefix(24) {   // marks are sparse; cap defensively
            do {
                let dayRows: [QualityWorkout] = try await supabase
                    .from("training_logs")
                    .select("id,workout_date,workout_type,workout_distance_miles,workout_duration_minutes")
                    .gte("workout_date", value: "\(day)T00:00:00")
                    .lte("workout_date", value: "\(day)T23:59:59")
                    .order("workout_distance_miles", ascending: false, nullsFirst: false)
                    .limit(1)
                    .execute().value
                if let row = dayRows.first, !items.contains(where: { $0.id == row.id }) {
                    items.append(row)
                    markedInIds.insert(row.id)
                    added = true
                }
            } catch {
                Log.coach.error("WorkoutsAndRepsSection marked-day fetch failed for \(day): \(error)")
            }
        }
        if added {
            items.sort { ($0.workout_date ?? "") > ($1.workout_date ?? "") }
        }
    }

    /// One server page of quality sessions, newest first.
    private func fetchPage(offset: Int) async throws -> [QualityWorkout] {
        try await supabase
            .from("training_logs")
            .select("id,workout_date,workout_type,workout_distance_miles,workout_duration_minutes")
            .in("workout_type", values: Self.keySessionTypes)
            .order("workout_date", ascending: false)
            // `range` is inclusive at both ends, so a page of n spans n-1.
            .range(from: offset, to: offset + Self.fetchPage - 1)
            .execute().value
    }

    /// Append the next server page. A short page — or a failure — sets
    /// `reachedEnd`, so the footer stops offering to look again rather than
    /// retrying silently on every tap.
    private func fetchOlder() async {
        do {
            let older = try await fetchPage(offset: serverOffset)
            serverOffset += older.count
            // Guard against a duplicate row arriving across page boundaries
            // (two sessions sharing a date can reorder between requests).
            let known = Set(items.map(\.id))
            items.append(contentsOf: older.filter { !known.contains($0.id) })
            if older.count < Self.fetchPage { reachedEnd = true }
            await applyOverrides()
        } catch {
            Log.coach.error("WorkoutsAndRepsSection page fetch failed: \(error)")
            reachedEnd = true
        }
    }

    /// Structures + laps for a set of rows. Enrichments — every row renders
    /// without them, so this never gates the list appearing, and it is called
    /// per revealed page rather than over the whole fetched list.
    private func enrich(_ rows: [QualityWorkout]) async {
        let pending = rows.filter { !enriched.contains($0.id) }
        guard !pending.isEmpty else { return }
        pending.forEach { enriched.insert($0.id) }
        let ids = pending.map(\.id.uuidString)
        if let feats: [FeatureRow] = try? await supabase
            .from("workout_features")
            .select("training_log_id,workout_structure")
            .in("training_log_id", values: ids)
            .execute().value {
            for f in feats {
                if let structure = f.workout_structure, structures[f.training_log_id] == nil {
                    structures[f.training_log_id] = structure
                }
            }
        }
        await withTaskGroup(of: (UUID, [WorkoutLapRow]).self) { group in
            for id in pending.map(\.id) {
                group.addTask {
                    async let l = WorkoutLapsService.fetchLaps(workoutId: id)
                    async let roles = WorkoutLapsService.fetchLapRoles(workoutId: id)
                    // Retag work/rest from the parser's lap_roles, exactly as
                    // the Rep Receipt does (its header note applies here too:
                    // the DB's generated `is_rest` only flags sub-200m laps,
                    // so a half-mile float reads as WORK and mergeWorkBouts
                    // glues a 4×3mi into one 21-mile bout — which is why
                    // long workouts used to fall back to the continuous mile
                    // ribbon instead of rep blocks). Roles absent → laps
                    // unchanged, list behaves exactly as before.
                    let (rawLaps, roleByIndex) = await (l, roles)
                    let tagged: [WorkoutLapRow] = roleByIndex.isEmpty ? rawLaps : rawLaps.map { row in
                        guard let idx = row.lap_index, let role = roleByIndex[idx] else { return row }
                        var r = row
                        // Keep the watch's own rest flag alongside the label —
                        // `mergeWorkBouts` reads it (`restForHeat`) to decide
                        // whether a bout earns the short-rep heat discount, and
                        // a label must not be able to invent a rest she never
                        // took. Same preservation as the Rep Receipt's rewrite.
                        r.db_is_rest = row.is_rest
                        r.is_rest = role != "rep"
                        return r
                    }
                    return (id, tagged)
                }
            }
            for await (id, laps) in group where !laps.isEmpty {
                lapsById[id] = laps
            }
        }
    }

    /// Does this row's lap set segment into reps? True when the parser (or
    /// the watch) marked genuine rest inside the run — the precondition for
    /// the rep-block strip to say anything honest.
    private func hasRepStructure(_ laps: [WorkoutLapRow]) -> Bool {
        laps.contains { $0.is_rest == true } && laps.contains { $0.is_rest != true }
    }

    // MARK: derived — rep pace (mirrors the strip's work-rep definition)

    /// The one number in the right-hand column. `isAvg` marks it as a whole-run
    /// mean rather than a work-bout pace — the row renders it differently, and
    /// nothing downstream may treat the two as comparable.
    private struct RepPace { let label: String; var isAvg: Bool = false }

    /// Distance-weighted mean work-bout pace, rest excluded; prefixed ○ and
    /// shown heat-adjusted when the laps carry an adjustment that moves the
    /// number ≥ 1 s/mi (the raw pace remains one tap away on the receipt).
    private func repPace(_ id: UUID) -> RepPace? {
        guard let raw = lapsById[id] else { return nil }
        let work = WorkoutLapsService.mergeWorkBouts(raw).filter { lap in
            lap.is_rest != true
                && (lap.avg_pace_sec_per_mile ?? 0) > 0
                && (lap.distance_meters ?? 0) >= 150
                && (lap.moving_time_seconds ?? 0) >= 20
        }
        let meters = work.reduce(0.0) { $0 + ($1.distance_meters ?? 0) }
        let seconds = work.reduce(0.0) { $0 + Double($1.moving_time_seconds ?? 0) }
        guard meters > 0, seconds > 0 else { return nil }
        let miles = meters / 1609.344
        let paceSec = seconds / miles
        // Each bout's OWN adjustment, distance-weighted — not one lap's ratio
        // stretched across the session. The old uniform-ratio shortcut read
        // `heat_adjusted / raw` off the first lap that carried both and applied
        // it to every rep, which threw away the per-lap intensity factor the
        // backend had already computed (it scales credit by how hard the bout
        // was, so the fast reps and the float legs do NOT share a ratio). On a
        // 6×1K alternation that landed 0.2 s/mi off the receipt's number for
        // the same session — small here, but it is a different quantity, and
        // two surfaces disagreeing about one workout is how the 8-vs-16 s/mi
        // heat bug stayed invisible.
        let adjustedSeconds = work.reduce(0.0) { acc, lap in
            let mi = (lap.distance_meters ?? 0) / 1609.344
            let rawPace = lap.avg_pace_sec_per_mile ?? 0
            let adj = lap.heat_adjusted_pace_sec_per_mile ?? 0
            return acc + (adj > 0 ? adj : rawPace) * mi
        }
        let adjustedPace = adjustedSeconds / miles
        if adjustedPace > 0, abs(adjustedPace - paceSec) >= 1 {
            return RepPace(label: "○ \(fmt(adjustedPace))")
        }
        return RepPace(label: fmt(paceSec))
    }

    // MARK: derived — average pace (long runs only)

    /// A long run's whole-run mean pace.
    ///
    /// Deliberately NOT `repPace(_:)`. That function excludes rest by
    /// construction — and a long run has no rest laps, so it would return the
    /// whole-run mean anyway and print it in the same weight as a 5:19 rep
    /// pace. Same arithmetic, entirely different claim; this function exists so
    /// the claim is labelled.
    ///
    /// Laps first (every lap counts — the whole run is the stimulus), falling
    /// back to the logged duration ÷ distance for the several long runs that
    /// carry no lap data at all. No heat adjustment: the backend emits a null
    /// adjusted pace for `kind: "long_run"` and this matches it. Returns nil
    /// when neither route has the numbers — an unpaced row is the honest
    /// answer, and the chevron already says "there is more inside".
    private func avgPace(_ w: QualityWorkout) -> RepPace? {
        if let laps = lapsById[w.id] {
            let meters = laps.reduce(0.0) { $0 + ($1.distance_meters ?? 0) }
            let seconds = laps.reduce(0.0) { $0 + Double($1.moving_time_seconds ?? 0) }
            if meters > 0, seconds > 0 {
                return RepPace(label: fmt(seconds / (meters / 1609.344)), isAvg: true)
            }
        }
        guard let minutes = w.workout_duration_minutes, minutes > 0,
              let miles = w.workout_distance_miles, miles > 0
        else { return nil }
        return RepPace(label: fmt(minutes * 60 / miles), isAvg: true)
    }

    private func fmt(_ paceSec: Double) -> String {
        let total = Int(paceSec.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: format — structure → title + zone chip

    /// "8×1K @ 5:14 (10K)" → (title: "8×1K", zone: "10K", pace: "5:14").
    /// Legacy zone tokens map forward ("threshold" → LT); "tempo" is
    /// ambiguous by decision and gets no chip. The @-pace is dropped from
    /// the title — the right column carries the measured rep pace instead,
    /// except on a `long_wo` row, where the captured pace IS the rep pace
    /// (the client-side lap merge has no rep boundary to work from there).
    private func structureParts(_ raw: String?) -> (title: String?, zone: String?, pace: String?) {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else {
            return (nil, nil, nil)
        }
        var zone: String?
        if s.hasSuffix(")"), let open = s.lastIndex(of: "(") {
            let token = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
                .trimmingCharacters(in: .whitespaces).lowercased()
            zone = Self.zoneChip[token]
            s = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        }
        var pace: String?
        if let r = s.range(of: #"\s*@\s*\d{1,2}:\d{2}"#, options: .regularExpression) {
            pace = String(s[r])
                .replacingOccurrences(of: "@", with: "")
                .trimmingCharacters(in: .whitespaces)
            s.removeSubrange(r)
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return (s.isEmpty ? nil : s, zone, pace)
    }

    private static let zoneChip: [String: String] = [
        "mile": "MILE", "3k": "3K", "5k": "5K", "10k": "10K",
        "hmp": "HMP", "mp": "MP", "lt": "LT", "threshold": "LT",
        // The run-relative structure pass labels long-run-workout reps by
        // their own zone; steady is the usual one and earns a chip. Moderate
        // stays chipless — those rows are long runs and wear LONG instead.
        "steady": "STEADY",
    ]

    private func title(_ structure: String?, _ w: QualityWorkout) -> String {
        let dist = w.workout_distance_miles
        // A long run's stored structure reads "17.1 mi long", so the shared
        // path below would print the distance twice — "17.1 mi long · 17.1 mi".
        // Name the session and let `distSuffix` carry the miles, exactly as it
        // does for every other row.
        if isLongRun(w) { return "Long run" + distSuffix(dist) }
        if let structure {
            return structure + distSuffix(dist)
        }
        if let dist, dist > 0 {
            return String(format: "%.1f mi", dist)
        }
        return "Workout"
    }

    private func distSuffix(_ mi: Double?) -> String {
        guard let mi, mi > 0 else { return "" }
        return String(format: " · %.1f mi", mi)
    }

    private func dateLine(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let day = String(iso.prefix(10))
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: day) else { return day }
        let outF = DateFormatter(); outF.locale = Locale(identifier: "en_US_POSIX"); outF.dateFormat = "EEE · MMM d"
        return outF.string(from: d).uppercased()
    }
}

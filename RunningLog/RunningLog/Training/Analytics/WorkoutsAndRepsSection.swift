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
//  SHOWS FOUR, GOES DEEPER ON REQUEST (2026-08-11). The card opens at four
//  receipts — enough to read the recent shape without turning a section into a
//  scroll — and a footer button walks back through the block a page at a time.
//  Paging is two-stage on purpose: the first taps reveal rows already fetched
//  (instant, one enrichment round trip for the newly shown ids), and only when
//  those run out does it go back to the server for older sessions. Enrichment
//  stays lazy either way — laps are one query PER ROW, so eagerly fetching a
//  year of sessions to show four of them is the thing this avoids.
//
//  Data: training_logs (quality types — detection only, never displayed as
//  labels) + workout_features.workout_structure + running_workout_laps for
//  the visible rows. All RLS user-scoped. Degrades row by row: no structure
//  → plain distance title; no laps → no strip, no rep pace.
//
//  Design: outputs/key-sessions-low-data-editorial-mockup-2026-07-02.html +
//  outputs/pace-volume-studies-2026-07-02.html (Study D).
//

import SwiftUI
import Supabase
import os

struct WorkoutsAndRepsSection: View {
    private struct QualityWorkout: Decodable, Identifiable {
        let id: UUID
        var workout_date: String?
        var workout_type: String?
        var workout_distance_miles: Double?
    }
    private struct FeatureRow: Decodable {
        let training_log_id: UUID
        let workout_structure: String?
    }
    private struct SheetID: Identifiable { let id: UUID }

    /// Detection filter only — these tokens select which logs are quality;
    /// they are never rendered as labels (the taxonomy dropped them).
    private static let qualityTypes = ["intervals", "interval", "threshold", "tempo", "fartlek", "progression", "race"]
    /// How many receipts the card opens at, and how many each "Show more"
    /// adds. One number for both so the rhythm of the reveal is even.
    private static let pageSize = 4
    /// How many rows one server page holds. Deliberately a multiple of
    /// `pageSize` so a fetch never leaves a partial page dangling.
    private static let fetchPage = 12

    @State private var items: [QualityWorkout] = []
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
    @State private var isLoadingMore = false
    /// Rows whose structure + laps have been asked for. Tracked explicitly
    /// rather than inferred from `lapsById`/`structures`, because a session
    /// with neither — no features computed, no laps uploaded — is a real
    /// answer, and inferring would re-query it on every reveal.
    @State private var enriched: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel
            if !items.isEmpty {
                ForEach(Array(items.prefix(shown))) { w in
                    Button { sheet = SheetID(id: w.id) } label: { receipt(w) }
                        .buttonStyle(.plain)
                }
                footer
            } else if !loaded {
                Text("Loading workouts…")
                    .font(.dripStat(11)).foregroundStyle(Color.drip.textTertiary)
                    .padding(.vertical, 12)
            } else {
                Text(errorText ?? "No quality sessions logged yet. The first interval day, MP miles, or LT session lands here.")
                    .font(.dripBody(13).italic()).foregroundStyle(Color.drip.textSecondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
        .task { await load() }
        // Was a hand-rolled copy of WorkoutRepDetailSheet's chrome — the same
        // NavigationStack + ScrollView + "WORKOUT" toolbar, duplicated. Three
        // surfaces each had one, so the missing Done button and the missing
        // opaque nav bar had to be fixed in four places. One place now. (S2)
        .sheet(item: $sheet) { s in
            WorkoutRepDetailSheet(workoutId: s.id)
        }
    }

    private var sectionLabel: some View {
        HStack(spacing: 10) {
            Text("WORKOUTS & REPS")
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
        if hasMore || shown > Self.pageSize {
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
        let next = min(shown + Self.pageSize, items.count)
        guard next > shown else { return }
        let revealed = Array(items[shown..<next])
        shown = next
        await enrich(revealed)
    }

    /// Back to the opening four. Fetched rows and their enrichments stay in
    /// memory, so re-expanding is instant and costs no network.
    private func collapse() {
        shown = Self.pageSize
    }

    // MARK: receipt row

    private func receipt(_ w: QualityWorkout) -> some View {
        let parts = structureParts(structures[w.id])
        let pace = repPace(w.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateLine(w.workout_date))
                    .font(.dripStat(10)).tracking(0.6)
                    .foregroundStyle(Color.drip.coral)
                Spacer()
                if let zone = parts.zone {
                    Text(zone)
                        .font(.dripStat(9)).tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
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
                        Text(pace.label).font(.dripStat(13)).foregroundStyle(Color.drip.textPrimary)
                        Text("REP PACE").font(.dripStat(8)).tracking(0.8)
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
                RepDensityStrip(laps: laps).padding(.top, 9)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    // MARK: data

    private func load() async {
        guard items.isEmpty else { return }   // re-entrant `.task`; keep the page state
        do {
            items = try await fetchPage(offset: 0)
        } catch {
            errorText = "Couldn't load workouts: \(error.localizedDescription)"
            Log.coach.error("WorkoutsAndRepsSection load failed: \(error)")
            loaded = true
            return
        }
        if items.count < Self.fetchPage { reachedEnd = true }
        await enrich(Array(items.prefix(shown)))
        loaded = true
    }

    /// One server page of quality sessions, newest first.
    private func fetchPage(offset: Int) async throws -> [QualityWorkout] {
        try await supabase
            .from("training_logs")
            .select("id,workout_date,workout_type,workout_distance_miles")
            .in("workout_type", values: Self.qualityTypes)
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
            let older = try await fetchPage(offset: items.count)
            // Guard against a duplicate row arriving across page boundaries
            // (two sessions sharing a date can reorder between requests).
            let known = Set(items.map(\.id))
            items.append(contentsOf: older.filter { !known.contains($0.id) })
            if older.count < Self.fetchPage { reachedEnd = true }
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
                group.addTask { (id, await WorkoutLapsService.fetchLaps(workoutId: id)) }
            }
            for await (id, laps) in group where !laps.isEmpty {
                lapsById[id] = laps
            }
        }
    }

    // MARK: derived — rep pace (mirrors the strip's work-rep definition)

    private struct RepPace { let label: String }

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
        let paceSec = seconds / (meters / 1609.344)
        // Uniform per-session adjustment ratio, read off the first raw lap
        // that carries both numbers (workout-level weather snapshot).
        var ratio: Double?
        for lap in raw {
            if let r = lap.avg_pace_sec_per_mile, r > 0,
               let a = lap.heat_adjusted_pace_sec_per_mile, a > 0 {
                ratio = a / r
                break
            }
        }
        if let ratio, abs(paceSec * ratio - paceSec) >= 1 {
            return RepPace(label: "○ \(fmt(paceSec * ratio))")
        }
        return RepPace(label: fmt(paceSec))
    }

    private func fmt(_ paceSec: Double) -> String {
        let total = Int(paceSec.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: format — structure → title + zone chip

    /// "8×1K @ 5:14 (10K)" → (title: "8×1K", zone: "10K").
    /// Legacy zone tokens map forward ("threshold" → LT); "tempo" is
    /// ambiguous by decision and gets no chip. The @-pace is dropped from
    /// the title — the right column carries the measured rep pace instead.
    private func structureParts(_ raw: String?) -> (title: String?, zone: String?) {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else {
            return (nil, nil)
        }
        var zone: String?
        if s.hasSuffix(")"), let open = s.lastIndex(of: "(") {
            let token = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
                .trimmingCharacters(in: .whitespaces).lowercased()
            zone = Self.zoneChip[token]
            s = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        }
        if let r = s.range(of: #"\s*@\s*\d{1,2}:\d{2}"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return (s.isEmpty ? nil : s, zone)
    }

    private static let zoneChip: [String: String] = [
        "mile": "MILE", "3k": "3K", "5k": "5K", "10k": "10K",
        "hmp": "HMP", "mp": "MP", "lt": "LT", "threshold": "LT",
    ]

    private func title(_ structure: String?, _ w: QualityWorkout) -> String {
        let dist = w.workout_distance_miles
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

//
//  TrendsService.swift
//  RunningLog
//
//  Loads the unified Trends timeline from the `trends-timeline` edge
//  function and exposes it as `[TrendsWeek]` for the Trends tab. Mirrors
//  the `DailyReadService` shape: an @Observable singleton with a cached
//  result + a `refresh()` the view calls on entry.
//
//  The endpoint is read-only and LLM-free; it returns the same 26-week
//  window every call and the view slices it by `TrendsRange`. See
//  `docs/specs/trends-tab-data-wiring.md` and
//  `supabase/functions/trends-timeline/`.
//

import Foundation
import os
import Supabase

@Observable
final class TrendsService {
    static let shared = TrendsService()

    /// Full window (up to 26 weeks), oldest → newest. The view slices this.
    private(set) var weeks: [TrendsWeek] = []
    /// Implausible runs the timeline set aside (watch-not-paused etc.),
    /// undecided — surfaced to Trim or Keep. Never deleted.
    private(set) var flagged: [TrendsFlaggedRun] = []
    /// Runs the athlete explicitly trimmed — surfaced so they can Restore.
    private(set) var trimmed: [TrendsFlaggedRun] = []
    private(set) var isLoading = false
    private(set) var lastError: Error?

    /// True once a successful (or seeded) load has populated `weeks`.
    private var loaded = false

    private init() {}

    /// Preview / test seam — inject a fixed window without hitting the network.
    init(preview weeks: [TrendsWeek]) {
        self.weeks = weeks
        self.loaded = true
    }

    /// Fetch the timeline. No-op if already loaded (unless `force`), so it's
    /// cheap to call on every tab entry.
    @MainActor
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await callEdgeFunction(name: "trends-timeline", body: ["weeks": 26])
            let payload = try JSONDecoder().decode(TrendsTimelinePayload.self, from: data)
            weeks = payload.weeks.map { $0.toModel() }
            flagged = (payload.flagged ?? []).map { $0.toModel() }
            trimmed = (payload.trimmed ?? []).map { $0.toModel() }
            loaded = true
            lastError = nil
            Log.coach.info("Trends timeline loaded (\(self.weeks.count) weeks)")
        } catch {
            lastError = error
            Log.coach.error("Trends timeline load failed: \(error.localizedDescription)")
        }
    }

    /// Trim (excluded = true), Keep/Restore (excluded = false) a run. Writes
    /// `training_logs.stats_excluded` (owner UPDATE is RLS-allowed), then
    /// reloads so the chart + lists recompute.
    @MainActor
    func setExcluded(_ trainingLogId: String, excluded: Bool) async {
        do {
            try await supabase
                .from("training_logs")
                .update(["stats_excluded": excluded])
                .eq("id", value: trainingLogId)
                .execute()
            await refresh(force: true)
        } catch {
            lastError = error
            Log.coach.error("setExcluded failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Wire format

/// Matches the `trends-timeline` response. Snake-case keys mapped to the
/// `TrendsWeek` view model. `mood`/`key_pace_sec`/`voice_quote` are
/// nullable — an empty week carries no fabricated values.
private struct TrendsTimelinePayload: Decodable {
    let weeks: [TrendsWeekDTO]
    let flagged: [FlaggedRunDTO]?
    let trimmed: [FlaggedRunDTO]?
}

/// A run the timeline set aside as implausible (e.g. watch left running).
/// Surfaced for review/trim — never auto-deleted.
struct TrendsFlaggedRun: Identifiable {
    let id: String          // training_log_id
    let date: String        // "2026-04-10"
    let miles: Double
    let pace: String?
    let reason: String
}

private struct FlaggedRunDTO: Decodable {
    let date: String
    let miles: Double
    let pace: String?
    let reason: String
    let trainingLogId: String

    enum CodingKeys: String, CodingKey {
        case date, miles, pace, reason
        case trainingLogId = "training_log_id"
    }

    func toModel() -> TrendsFlaggedRun {
        TrendsFlaggedRun(id: trainingLogId, date: date, miles: miles, pace: pace, reason: reason)
    }
}

private struct TrendsWeekDTO: Decodable {
    let weekStart: String
    let month: String
    let dateLabel: String
    let miles: Double
    let qualityMiles: Double
    let keyPaceSec: Int?
    let mood: String?
    let niggles: [String]
    let voiceQuote: String?

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case month
        case dateLabel = "date_label"
        case miles
        case qualityMiles = "quality_miles"
        case keyPaceSec = "key_pace_sec"
        case mood
        case niggles
        case voiceQuote = "voice_quote"
    }

    func toModel() -> TrendsWeek {
        TrendsWeek(
            month: month,
            dateLabel: dateLabel,
            miles: miles,
            qualityMiles: qualityMiles,
            keyPaceSec: keyPaceSec,
            mood: mood ?? "",          // "" = no mood; the chart skips the dot
            niggles: niggles,
            voiceQuote: voiceQuote
        )
    }
}

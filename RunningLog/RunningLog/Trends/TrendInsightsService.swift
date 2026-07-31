//
//  TrendInsightsService.swift
//  RunningLog
//
//  Loads the narrative trend cards ("What the chart shows") from the
//  `trends-insights` edge function and exposes them as `[TrendInsightCard]`
//  for the **Trends 2** tab. Mirrors `TrendsService`: an @Observable
//  singleton with a cached result + a `refresh()` the view calls on entry.
//
//  The endpoint is read-only and LLM-free. It fuses the same weekly
//  substrate the chart renders with the athlete's own words, and returns
//  one card per fired (or honestly-quiet) trend. `hidden` cards never
//  cross the wire — an unmet data gate is simply absent, never a stub.
//
//  See `supabase/functions/trends-insights/` and
//  `docs/specs/trends-insights-plan-2026-07-23.md`.
//

import Foundation
import os

// MARK: - Card model (dumb-renderer contract)

/// One narrative trend card. Matches the `trends-insights` response
/// contract: `{ id, group, status, headline, body, evidence, confidence }`.
struct TrendInsightCard: Identifiable, Decodable {
    let id: String            // "A1", "A3", "C0" …
    let group: String         // "A" | "B" | "C"
    let status: String        // "active" | "quiet"  (hidden filtered server-side)
    let headline: String
    let body: String
    let evidence: [TrendEvidence]
    let confidence: String    // "low" | "medium" | "high"
    /// Full series behind the card for the in-card mini-chart. Optional — a
    /// card without one (all `quiet` cards) renders prose-only. Defaulted so
    /// callers/previews can omit it; decoded when the payload includes it.
    var series: TrendSeries? = nil

    var isActive: Bool { status == "active" }
}

/// A chart-pluckable evidence point behind a card.
struct TrendEvidence: Decodable, Identifiable {
    let week: String
    let value: Double
    let label: String?

    var id: String { "\(week)-\(value)-\(label ?? "")" }
}

/// The full ordered series behind a card — the whole 12-week line, not two
/// endpoints. `polarity` orients the chart so improvement reads upward.
/// Keys match the `trends-insights` payload verbatim (camelCase `markerIdx`);
/// the default `JSONDecoder` (no snake-case conversion) maps them directly.
struct TrendSeries: Decodable {
    let points: [Double]
    let labels: [String]?
    let unit: String?
    let polarity: String?          // "up_good" | "down_good" | "neutral"
    let markerIdx: [Int]?
    let band: Band?

    struct Band: Decodable { let lo: Double; let hi: Double }
}

// MARK: - Service

@Observable
final class TrendInsightsService {
    static let shared = TrendInsightsService()

    /// The cards to render, server-ordered (group A → B → C, active before
    /// quiet, higher confidence first). Empty until a load populates it.
    private(set) var cards: [TrendInsightCard] = []
    private(set) var isLoading = false
    private(set) var lastError: Error?

    /// True once a successful (or seeded) load has run.
    private var loaded = false

    private init() {}

    /// Preview / test seam — inject fixed cards without hitting the network.
    init(preview cards: [TrendInsightCard]) {
        self.cards = cards
        self.loaded = true
    }

    /// Fetch the cards. No-op if already loaded (unless `force`), so it's
    /// cheap to call on every tab entry.
    @MainActor
    func refresh(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await callEdgeFunction(name: "trends-insights", body: ["weeks": 26])
            let payload = try JSONDecoder().decode(TrendInsightsPayload.self, from: data)
            cards = payload.cards
            loaded = true
            lastError = nil
            Log.coach.info("Trends insights loaded (\(self.cards.count) cards)")
        } catch is CancellationError {
            // Switching tabs mid-fetch cancels the request — not a real failure.
            // Leave `loaded` false (so the next tab entry retries) and DON'T set
            // lastError, so the view never flashes its error state on a transient
            // cancellation. Mirrors how the error reporter suppresses -999s.
            Log.coach.info("Trends insights load cancelled (tab switch) — will retry")
        } catch let urlError as URLError where urlError.code == .cancelled {
            Log.coach.info("Trends insights load cancelled (tab switch) — will retry")
        } catch {
            lastError = error
            Log.coach.error("Trends insights load failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Wire format

private struct TrendInsightsPayload: Decodable {
    let cards: [TrendInsightCard]
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case cards
        case generatedAt = "generated_at"
    }
}

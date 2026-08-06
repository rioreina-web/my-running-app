//
//  AskModels.swift
//  RunningLog · Analysis
//
//  Wire types for the `ask` edge function — the analysis surface.
//
//  The contract these mirror lives in
//  `supabase/functions/_shared/analyzers/types.ts`. Two naming conventions
//  meet here and both are deliberate: the envelope is snake_case (matching
//  every other edge-function response in the app) while the analyzer payload
//  is camelCase (it is the TypeScript interface serialized as-is). The
//  `CodingKeys` below are explicit rather than relying on a global
//  `.convertFromSnakeCase` strategy, which would mangle `sessionsUsed` into
//  `sessionsUsed` → `sessions_used` and silently drop coverage.
//
//  The invariant worth preserving on this side: **the facts are the answer.**
//  `narration` is advisory and may be nil on any given response — a missing
//  API key, a rejected number, an exhausted quota. The view must render
//  `facts` with or without it, and must never compute a number of its own to
//  fill a gap.
//

import Foundation

// MARK: - Fact lines

/// One computed fact. `tone` has no "bad" case on purpose — hard rule #2.
/// Observation, not judgement; `watch` is the ceiling.
struct AskFact: Decodable, Identifiable, Equatable {
    let key: String
    let label: String
    let value: String
    let unit: String?
    let delta: String?
    let tone: Tone?

    var id: String { key }

    enum Tone: String, Decodable {
        case neutral, good, watch
    }
}

// MARK: - Coverage

/// What the answer is built on. Rendered under EVERY answer, not just weak
/// ones — the difference between a surface that feels analytical and one that
/// feels like it is guessing.
struct AskCoverage: Decodable, Equatable {
    let sessionsUsed: Int
    let windowDays: Int
    let missing: [String]
    let confidence: Confidence

    enum Confidence: String, Decodable {
        case high, moderate, low
    }
}

// MARK: - Series

struct AskSeriesPoint: Decodable, Equatable {
    let x: String
    let y: Double
    /// The conditions-adjusted twin, typically. Nil when the series is single.
    let y2: Double?
    let label: String?
}

struct AskSeries: Decodable, Equatable {
    let kind: Kind
    let unit: String
    /// Lower is better (pace) — the chart inverts the axis.
    let invertY: Bool?
    /// Reference band drawn behind the marks.
    let band: [Double]?
    let y2Label: String?
    let points: [AskSeriesPoint]

    enum Kind: String, Decodable {
        case line, bar
    }

    var isInverted: Bool { invertY == true }
}

// MARK: - Empty state

/// Hard rule #8: never an em-dash placeholder. An analyzer that cannot answer
/// says what would make the answer possible.
struct AskEmptyState: Decodable, Equatable {
    let eyebrow: String
    let nudge: String
}

// MARK: - Narration

struct AskNarration: Decodable, Equatable {
    let text: String
    let caveat: String?
}

// MARK: - Catalog

/// A registered analyzer, as the endpoint advertises it. The chip rail is
/// built from this rather than a hardcoded list, so adding an analyzer
/// server-side surfaces in the app without a client release.
struct AskAnalyzer: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    let group: String

    /// Display name for the group header. Falls back to the raw key so a
    /// group added server-side still renders legibly.
    var groupTitle: String {
        switch group {
        case "load": return "Load"
        case "mix": return "Mix"
        case "adaptation": return "Adaptation"
        case "durability": return "Durability"
        case "specificity": return "Specificity"
        case "recovery": return "Recovery"
        case "consistency": return "Consistency"
        case "block": return "Block"
        case "conditions": return "Conditions"
        case "body": return "Body"
        case "comparison": return "Comparison"
        default: return group.capitalized
        }
    }
}

// MARK: - Follow-ups

struct AskFollowup: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
}

// MARK: - Response

/// The `ask` envelope.
///
/// `mode` distinguishes three outcomes the surface renders differently:
///   • `analyzed`  — an analyzer ran; facts are present.
///   • `prose`     — nothing in the registry fit; the question belongs to the
///                   existing coaching-agent path. No facts, no chart.
///   • `ambiguous` — the router offered disambiguation instead of guessing.
///   • `catalog`   — the chip-rail bootstrap response.
struct AskResponse: Decodable {
    let success: Bool
    let mode: Mode
    let annotated: Bool?
    let analyzerId: String?
    let analyzerLabel: String?
    let facts: [AskFact]
    let series: AskSeries?
    let coverage: AskCoverage?
    let empty: AskEmptyState?
    let narration: AskNarration?
    let followups: [AskFollowup]
    let disambiguation: [AskAnalyzer]?
    let catalog: [AskAnalyzer]?

    enum Mode: String, Decodable {
        case analyzed, prose, ambiguous, catalog
    }

    enum CodingKeys: String, CodingKey {
        case success, mode, annotated
        case analyzerId = "analyzer_id"
        case analyzerLabel = "analyzer_label"
        case facts, series, coverage, empty, narration, followups
        case disambiguation, catalog
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? true
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .analyzed
        annotated = try c.decodeIfPresent(Bool.self, forKey: .annotated)
        analyzerId = try c.decodeIfPresent(String.self, forKey: .analyzerId)
        analyzerLabel = try c.decodeIfPresent(String.self, forKey: .analyzerLabel)
        // Absent arrays decode as empty, never nil — the view never has to
        // distinguish "no facts" from "facts key missing".
        facts = try c.decodeIfPresent([AskFact].self, forKey: .facts) ?? []
        series = try c.decodeIfPresent(AskSeries.self, forKey: .series)
        coverage = try c.decodeIfPresent(AskCoverage.self, forKey: .coverage)
        empty = try c.decodeIfPresent(AskEmptyState.self, forKey: .empty)
        narration = try c.decodeIfPresent(AskNarration.self, forKey: .narration)
        followups = try c.decodeIfPresent([AskFollowup].self, forKey: .followups) ?? []
        disambiguation = try c.decodeIfPresent([AskAnalyzer].self, forKey: .disambiguation)
        catalog = try c.decodeIfPresent([AskAnalyzer].self, forKey: .catalog)
    }
}

// MARK: - Equatable

/// `CoachAskSheet.Phase` is Equatable, so the response it carries must be
/// too. Compared on identity + content rather than synthesized, because
/// `series` and `coverage` are incidental to "is this the same answer".
extension AskResponse: Equatable {
    static func == (lhs: AskResponse, rhs: AskResponse) -> Bool {
        lhs.analyzerId == rhs.analyzerId &&
            lhs.mode == rhs.mode &&
            lhs.facts == rhs.facts &&
            lhs.narration == rhs.narration
    }
}

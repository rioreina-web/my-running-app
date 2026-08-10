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
///
/// `conversational` cuts across `mode` and is the one to branch on for typed
/// questions (2026-08-10). True means this envelope is not the whole answer:
/// ask `coaching-agent` too, lead with that reply, and render whatever card
/// arrived here beneath it. It is always false for chips, and false for every
/// mode when the server has re-bound `UNBOUND_ANSWERS`.
struct AskResponse: Decodable {
    let success: Bool
    let mode: Mode
    let annotated: Bool?
    let analyzerId: String?
    let analyzerLabel: String?
    /// What the analyzer actually answered, when narrower than its standing
    /// label — "Is my 10K pace improving?" for a chip that reads LT. Nil means
    /// the chip's wording was accurate and the card keeps the asked question.
    let resolvedTitle: String?
    let facts: [AskFact]
    let series: AskSeries?
    let coverage: AskCoverage?
    let empty: AskEmptyState?
    /// Other parameterizations of the same analyzer, for the on-card switcher.
    /// Empty when the answer has nothing to switch between.
    let variants: [AskVariant]
    let narration: AskNarration?
    let followups: [AskFollowup]
    let disambiguation: [AskAnalyzer]?
    let catalog: [AskAnalyzer]?
    /// Fetch a conversational reply and lead with it. See the type comment.
    /// Defaults false so an older server (or a re-bound one) keeps the
    /// pre-2026-08-10 behaviour without a client release.
    let conversational: Bool

    enum Mode: String, Decodable {
        case analyzed, prose, ambiguous, catalog
    }

    enum CodingKeys: String, CodingKey {
        case success, mode, annotated
        case analyzerId = "analyzer_id"
        case analyzerLabel = "analyzer_label"
        case resolvedTitle = "resolved_title"
        case facts, series, coverage, empty, variants, narration, followups
        case disambiguation, catalog, conversational
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? true
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .analyzed
        annotated = try c.decodeIfPresent(Bool.self, forKey: .annotated)
        analyzerId = try c.decodeIfPresent(String.self, forKey: .analyzerId)
        analyzerLabel = try c.decodeIfPresent(String.self, forKey: .analyzerLabel)
        resolvedTitle = try c.decodeIfPresent(String.self, forKey: .resolvedTitle)
        // Absent arrays decode as empty, never nil — the view never has to
        // distinguish "no facts" from "facts key missing".
        facts = try c.decodeIfPresent([AskFact].self, forKey: .facts) ?? []
        series = try c.decodeIfPresent(AskSeries.self, forKey: .series)
        coverage = try c.decodeIfPresent(AskCoverage.self, forKey: .coverage)
        empty = try c.decodeIfPresent(AskEmptyState.self, forKey: .empty)
        variants = try c.decodeIfPresent([AskVariant].self, forKey: .variants) ?? []
        narration = try c.decodeIfPresent(AskNarration.self, forKey: .narration)
        followups = try c.decodeIfPresent([AskFollowup].self, forKey: .followups) ?? []
        disambiguation = try c.decodeIfPresent([AskAnalyzer].self, forKey: .disambiguation)
        catalog = try c.decodeIfPresent([AskAnalyzer].self, forKey: .catalog)
        conversational = try c.decodeIfPresent(Bool.self, forKey: .conversational) ?? false
    }
}

// MARK: - Variants

/// A JSON scalar, so `params` can round-trip back to the server untouched.
///
/// The server owns the param schema; the client's only job is to hand the same
/// values back on tap. Decoding into concrete types here would mean teaching
/// the app every analyzer's schema — and getting it wrong the first time a
/// numeric param ships.
enum AskParamValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported param value"
        )
    }

    /// The value as `callEdgeFunction` wants it — `[String: Any]` JSON.
    var jsonValue: Any {
        switch self {
        case let .string(v): return v
        case let .number(v): return v == v.rounded() ? Int(v) : v
        case let .bool(v): return v
        }
    }
}

/// Another way to ask the same question — the on-card zone switcher.
///
/// `zone_trend` auto-picks the band the athlete ran most, which is a guess at
/// intent and is often not the one they meant. Rather than widen the chip rail,
/// the card offers the alternatives the server says have data behind them.
struct AskVariant: Decodable, Equatable, Identifiable {
    let label: String
    let params: [String: AskParamValue]
    let active: Bool
    /// Sessions behind this variant — thin options can be de-emphasised.
    let sessions: Int

    var id: String { label }

    /// Params shaped for re-posting.
    var jsonParams: [String: Any] {
        params.mapValues(\.jsonValue)
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

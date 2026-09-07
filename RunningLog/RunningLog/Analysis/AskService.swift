//
//  AskService.swift
//  RunningLog · Analysis
//
//  Client for the `ask` edge function.
//
//  Two calls, and a deliberate asymmetry between them:
//
//    • `loadCatalog()` — the chip rail. Costs nothing server-side (no
//      analyzer runs, no model call), so it is safe on view appear and is
//      cached for the session.
//    • `resolve(...)` — one analyzer. Layer 1 is free; only a Layer-2
//      narration call is metered. `narrate: false` therefore makes a chip tap
//      genuinely free, which is why the rail can feel free to touch.
//
//  This service holds no transcript. `CoachAskSheet` owns the one answer it
//  is showing, so the service stays a stateless caller plus a catalog cache —
//  which keeps the sheet's existing `Phase` state machine the single source
//  of truth for what's on screen.
//

import Foundation
import os

@Observable
final class AskService {
    static let shared = AskService()

    /// The registered analyzers, as the server advertises them. Empty until
    /// the first successful `loadCatalog()`.
    private(set) var catalog: [AskAnalyzer] = []

    private var catalogLoaded = false
    private let logger = Logger(subsystem: "com.postrundrip.app", category: "Ask")

    private init() {}

    // MARK: - Catalog

    /// Analyzers grouped for the chip rail, in the registry's own order.
    /// Grouping is derived, not hardcoded — a group added server-side appears
    /// here without a client change.
    var groupedCatalog: [(title: String, analyzers: [AskAnalyzer])] {
        var order: [String] = []
        var buckets: [String: [AskAnalyzer]] = [:]
        for analyzer in catalog {
            if buckets[analyzer.group] == nil {
                buckets[analyzer.group] = []
                order.append(analyzer.group)
            }
            buckets[analyzer.group]?.append(analyzer)
        }
        return order.map { key in
            (title: buckets[key]?.first?.groupTitle ?? key, analyzers: buckets[key] ?? [])
        }
    }

    @MainActor
    func loadCatalog(force: Bool = false) async {
        guard force || !catalogLoaded else { return }
        do {
            let data = try await callEdgeFunction(
                name: "ask",
                body: ["analyzer_id": "__catalog__"]
            )
            let decoded = try JSONDecoder().decode(AskResponse.self, from: data)
            catalog = decoded.catalog ?? []
            catalogLoaded = true
            logger.info("ask catalog loaded — \(self.catalog.count) analyzers")
        } catch {
            // A missing catalog is not fatal: the athlete can still type, and
            // the rail simply doesn't render. Nothing they did failed, so
            // this stays in the log rather than on screen.
            logger.error("ask catalog failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Running an analyzer

    /// Run a named analyzer — the chip path. No router, no ambiguity, and
    /// with `narrate: false` no model call at all.
    ///
    /// `params` is how the card's variant switcher re-asks the same question of
    /// a different band. Passing nothing keeps the previous behaviour, which is
    /// the analyzer's own auto-pick.
    @MainActor
    func resolve(
        analyzerId: String,
        params: [String: Any]? = nil,
        narrate: Bool = true
    ) async throws -> AskResponse {
        var body: [String: Any] = ["analyzer_id": analyzerId, "narrate": narrate]
        if let params, !params.isEmpty { body["params"] = params }
        return try await post(body: body)
    }

    /// Re-run the analyzer that produced `response` against one of its variants.
    @MainActor
    func resolve(variant: AskVariant, of response: AskResponse) async throws -> AskResponse {
        guard let analyzerId = response.analyzerId else {
            throw AskServiceError.noAnalyzerToSwitch
        }
        return try await resolve(analyzerId: analyzerId, params: variant.jsonParams)
    }

    /// Free text — routed server-side against the registry's closed enum.
    /// A `mode: .prose` response means no analyzer fit; the caller decides
    /// whether to hand the question on to the coaching agent.
    @MainActor
    func resolve(question: String) async throws -> AskResponse {
        try await post(body: ["question": question, "narrate": true])
    }

    @MainActor
    private func post(body: [String: Any]) async throws -> AskResponse {
        let data = try await callEdgeFunction(name: "ask", body: body)
        let decoded = try JSONDecoder().decode(AskResponse.self, from: data)
        logger.info(
            "ask ran — analyzer=\(decoded.analyzerId ?? "none") mode=\(decoded.mode.rawValue) annotated=\(decoded.annotated == true)"
        )
        return decoded
    }

    // MARK: - Errors

    enum AskServiceError: Error {
        /// A variant was tapped on a response that names no analyzer — only
        /// reachable if the server sends variants on a prose/ambiguous answer,
        /// which it does not. Explicit rather than a silent no-op.
        case noAnalyzerToSwitch
    }

    /// Athlete-facing message for a failed run. Kept here so the sheet and
    /// any future caller phrase the same failure the same way.
    static func message(for error: Error) -> String {
        if error is AskServiceError {
            return "That answer can't be switched to another band."
        }
        if let edge = error as? EdgeFunctionError {
            switch edge {
            case let .httpError(statusCode, _, message):
                if statusCode == 429 {
                    return "You've used today's analysis budget. The numbers are still there tomorrow."
                }
                if statusCode == 401 || statusCode == 403 {
                    return "Sign in again to run this."
                }
                return message.isEmpty ? "The analysis didn't complete." : message
            }
        }
        if error is DecodingError {
            // A shape change between client and server should read as a
            // product problem, not as "your training data is broken".
            return "That answer came back in a shape this version doesn't understand."
        }
        return "Couldn't reach the analysis service. Try again in a moment."
    }
}

// MARK: - Feature gate

/// Phase A ships the chip rail only. Free text needs the Layer-0 router
/// exercised against real questions, and `ask-narration` to have recorded
/// eval cassettes (hard rule #3), before it faces athletes.
enum AskFeature {
    static let isEnabled = true

    /// Typed questions. **On in all builds as of 2026-08-10** — this is the
    /// flag that had been keeping chat out of release builds entirely, and
    /// turning it on is what "add chat to the app" means in practice.
    ///
    /// SHIPPED DELIBERATELY AHEAD OF ITS EVAL COVERAGE. This is the "unbound
    /// at first" call, not an oversight. What is still open, re-audited
    /// 2026-08-10 — close these before the surface is considered launched:
    ///
    ///   1. `ask-narration` now HAS a cassette directory
    ///      (`_evals/cassettes/ask-narration.v1/`, 8 files) but all 8 are
    ///      stubs with an empty `recorded_response`, and it is still missing
    ///      from `GOLDEN_FAMILIES` in `.github/scripts/check_eval_coverage.py`
    ///      even though its own prompt declares itself golden. CI would not
    ///      block a regression in it today. One `record.ts` run closes this.
    ///   2. The Layer-0 router (`ask/index.ts:routeWithModel`) uses an inline
    ///      prompt and has no test file.
    ///   3. Under `UNBOUND_ANSWERS` every typed question now reaches
    ///      `coaching-agent` — no longer just the ones the router declines.
    ///      That family is golden and its cassettes are stubs too, so the
    ///      conversational path is unguarded on the way in AND is not
    ///      number-guarded on the way out (only Layer-2 narration over
    ///      analyzer facts is). This is the widest exposure of the three.
    static let freeTextEnabled = true
}

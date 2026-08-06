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
    @MainActor
    func resolve(analyzerId: String, narrate: Bool = true) async throws -> AskResponse {
        try await post(body: ["analyzer_id": analyzerId, "narrate": narrate])
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

    /// Athlete-facing message for a failed run. Kept here so the sheet and
    /// any future caller phrase the same failure the same way.
    static func message(for error: Error) -> String {
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

    /// Free text routes through Layer 0 (question -> analyzer id) and can fall
    /// through to `ask-narration`, which has no recorded eval cassettes yet
    /// (hard rule #3). Keep this OFF for anything athletes touch. It is on in
    /// DEBUG only so the composer can be exercised in the simulator.
    ///
    /// Three specifics to close before this becomes an unconditional `true`
    /// (audited 2026-08-05):
    ///
    ///   1. `ask-narration` has no cassette DIRECTORY at all, and is missing
    ///      from `GOLDEN_FAMILIES` in `.github/scripts/check_eval_coverage.py`
    ///      even though its own prompt file declares itself golden — so CI
    ///      would not block a regression in it today.
    ///   2. The Layer-0 router (`ask/index.ts:routeWithModel`) uses an inline
    ///      prompt and has no test file. Exercising it is exactly what this
    ///      DEBUG flag is for.
    ///   3. A question the router matches to NOTHING falls through to
    ///      `coaching-agent` (`ask/index.ts` prose branch). That family is
    ///      golden, but all three of its cassettes are stubs with an empty
    ///      `recorded_response`, so the fallthrough is unguarded too.
    #if DEBUG
    static let freeTextEnabled = true
    #else
    static let freeTextEnabled = false
    #endif
}

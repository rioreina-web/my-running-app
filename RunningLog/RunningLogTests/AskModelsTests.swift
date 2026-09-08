//
//  AskModelsTests.swift
//  RunningLogTests
//
//  Decoding tests for the `ask` wire contract.
//
//  These exist because the envelope mixes two naming conventions —
//  snake_case at the top level, camelCase inside the analyzer payload — and a
//  silent decode failure there would surface as a blank card rather than an
//  error. Each fixture below is a verbatim response shape from
//  `supabase/functions/ask/index.ts`.
//
//  The contract these pin: **facts and coverage survive independently of
//  narration.** Every degradation path the endpoint has — no API key, a
//  rejected number, an exhausted quota — produces `narration: null` with the
//  analysis intact, and the client must render that.
//

import XCTest
@testable import RunningLog

final class AskModelsTests: XCTestCase {
    private func decode(_ json: String) throws -> AskResponse {
        try JSONDecoder().decode(AskResponse.self, from: Data(json.utf8))
    }

    // MARK: - The happy path

    func testDecodesAnalyzedResponse() throws {
        let response = try decode("""
        {
          "success": true,
          "mode": "analyzed",
          "annotated": true,
          "analyzer_id": "zone_trend",
          "analyzer_label": "Is my LT pace improving?",
          "facts": [
            {"key":"recent_pace","label":"LT pace · last 3 sessions","value":"7:03","unit":"/mi","delta":"−9s","tone":"good"},
            {"key":"early_pace","label":"LT pace · first 3 sessions","value":"7:12","unit":"/mi"}
          ],
          "series": {
            "kind":"line","unit":"sec_per_mile","invertY":true,"band":null,
            "y2Label":"conditions-neutral",
            "points":[{"x":"2026-06-03","y":432,"y2":431,"label":null},
                      {"x":"2026-08-04","y":423,"y2":414,"label":"LT 5×1600m"}]
          },
          "coverage": {"sessionsUsed":8,"windowDays":120,"missing":["no HR on 2 of 8 sessions"],"confidence":"high"},
          "empty": null,
          "narration": {"text":"Your LT band has come down 9 seconds.","caveat":null},
          "followups": [{"id":"compare_session","label":"Compare the two fastest"}]
        }
        """)

        XCTAssertEqual(response.mode, .analyzed)
        XCTAssertEqual(response.analyzerId, "zone_trend")
        XCTAssertEqual(response.facts.count, 2)
        XCTAssertEqual(response.facts.first?.value, "7:03")
        XCTAssertEqual(response.facts.first?.tone, .good)
        // A fact without a tone must decode, not fail — tone is optional.
        XCTAssertNil(response.facts.last?.tone)
        XCTAssertEqual(response.coverage?.sessionsUsed, 8)
        XCTAssertEqual(response.coverage?.confidence, .high)
        XCTAssertEqual(response.coverage?.missing.first, "no HR on 2 of 8 sessions")
        XCTAssertEqual(response.series?.kind, .line)
        XCTAssertTrue(response.series?.isInverted == true)
        XCTAssertEqual(response.series?.points.count, 2)
        XCTAssertEqual(response.series?.points.last?.y2, 414)
        XCTAssertEqual(response.narration?.text, "Your LT band has come down 9 seconds.")
        XCTAssertEqual(response.followups.first?.id, "compare_session")
    }

    // MARK: - Degradation

    func testFactsSurviveWithoutNarration() throws {
        // The endpoint's guard rejected the narration, or there was no API
        // key. The analysis must still render in full.
        let response = try decode("""
        {
          "success": true, "mode": "analyzed", "annotated": false,
          "analyzer_id": "load_balance",
          "facts": [{"key":"acwr","label":"Acute : chronic ratio","value":"1.06","delta":"in band","tone":"good"}],
          "series": null,
          "coverage": {"sessionsUsed":42,"windowDays":49,"missing":[],"confidence":"high"},
          "narration": null,
          "followups": []
        }
        """)

        XCTAssertEqual(response.annotated, false)
        XCTAssertNil(response.narration)
        XCTAssertEqual(response.facts.count, 1, "facts must survive a dropped narration")
        XCTAssertEqual(response.coverage?.confidence, .high)
        XCTAssertNil(response.facts.first?.unit, "a unit-less fact is valid")
    }

    func testDecodesEmptyState() throws {
        let response = try decode("""
        {
          "success": true, "mode": "analyzed", "annotated": false,
          "analyzer_id": "zone_trend",
          "facts": [],
          "coverage": {"sessionsUsed":2,"windowDays":120,"missing":[],"confidence":"low"},
          "empty": {"eyebrow":"2 LT sessions on file","nudge":"The trend gets honest at 4."},
          "narration": null,
          "followups": []
        }
        """)

        XCTAssertTrue(response.facts.isEmpty)
        XCTAssertEqual(response.empty?.eyebrow, "2 LT sessions on file")
        XCTAssertFalse(
            response.empty?.nudge.contains("—") ?? true,
            "hard rule #8 — empty-state copy must not use an em-dash placeholder"
        )
        XCTAssertEqual(response.coverage?.confidence, .low)
    }

    func testDecodesProseFallthrough() throws {
        let response = try decode("""
        {
          "success": true, "mode": "prose", "annotated": false,
          "analyzer_id": null, "facts": [], "series": null,
          "coverage": null, "narration": null, "followups": []
        }
        """)

        XCTAssertEqual(response.mode, .prose)
        XCTAssertNil(response.analyzerId)
        XCTAssertTrue(response.facts.isEmpty)
        XCTAssertNil(response.coverage)
    }

    func testDecodesAmbiguousWithDisambiguation() throws {
        let response = try decode("""
        {
          "success": true, "mode": "ambiguous", "annotated": false,
          "analyzer_id": null, "facts": [], "followups": [],
          "disambiguation": [
            {"id":"zone_trend","label":"The LT pace trend","group":"adaptation"},
            {"id":"compare_session","label":"Tuesday's session","group":"comparison"}
          ]
        }
        """)

        XCTAssertEqual(response.mode, .ambiguous)
        XCTAssertEqual(response.disambiguation?.count, 2)
        XCTAssertEqual(response.disambiguation?.first?.groupTitle, "Adaptation")
    }

    func testDecodesCatalog() throws {
        let response = try decode("""
        {
          "success": true, "mode": "catalog",
          "catalog": [
            {"id":"compare_session","label":"Compare this session to similar ones","group":"comparison"},
            {"id":"load_balance","label":"Am I ramping too fast?","group":"load"},
            {"id":"zone_trend","label":"Is my LT pace improving?","group":"adaptation"}
          ]
        }
        """)

        XCTAssertEqual(response.mode, .catalog)
        XCTAssertEqual(response.catalog?.count, 3)
        XCTAssertEqual(response.catalog?[1].groupTitle, "Load")
        // Absent arrays decode as empty, never nil — the view never has to
        // distinguish "no facts" from "facts key missing".
        XCTAssertTrue(response.facts.isEmpty)
        XCTAssertTrue(response.followups.isEmpty)
    }

    // MARK: - Forward compatibility

    func testUnknownGroupStillRenders() throws {
        let response = try decode("""
        {"success":true,"mode":"catalog",
         "catalog":[{"id":"velocity_duration","label":"Critical speed","group":"physiology"}]}
        """)
        XCTAssertEqual(response.catalog?.first?.groupTitle, "Physiology",
                       "a group added server-side must still render legibly")
    }

    func testExtraServerFieldsAreIgnored() throws {
        // A future field must not break an older build.
        let response = try decode("""
        {"success":true,"mode":"analyzed","analyzer_id":"load_balance",
         "facts":[],"followups":[],
         "cache_hit":true,"latency_ms":412,"experimental_block":{"a":1}}
        """)
        XCTAssertEqual(response.analyzerId, "load_balance")
    }
}

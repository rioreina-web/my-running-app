//
//  SessionStoryTests.swift
//  RunningLogTests
//
//  Pure-logic tests for the Session Story surface: ghost selection,
//  drift tiers, the templated read (numbers cited, coach voice honored),
//  and the wire-format decode.
//

import Foundation
import Testing
@testable import RunningLog

// MARK: - Fixtures

private func keySession(
    id: String,
    date: String,
    zone: String = "5k",
    kind: String = "quality"
) -> KeySession {
    KeySession(
        id: id,
        date: date,
        dateLabel: date,
        zone: zone,
        workPaceSec: 320,
        workPaceAdjSec: nil,
        heatCategory: nil,
        workHrAvg: nil,
        structure: nil,
        distanceMi: nil,
        qualityLoad: 60,
        kind: kind
    )
}

private func story(
    kind: String = "reps",
    avgPace: Int? = 328,
    conditionsPace: Int? = 309,
    heatCost: Int? = 16,
    hillCost: Int? = 3,
    fade: Double? = -3.0,
    mood: String? = nil,
    niggles: [StoryNiggle] = []
) -> SessionStory {
    SessionStory(
        logId: "log-a",
        date: "2026-07-21",
        name: "6×1mi",
        kind: kind,
        totalMiles: 7.5,
        durationMin: 43,
        segments: [],
        avgPaceSec: avgPace,
        neutralPaceSec: conditionsPace.map { $0 + 2 },
        conditionsPaceSec: conditionsPace,
        heat: heatCost.map { StoryHeat(tempF: 78, dewF: 72, costSecPerMi: $0) },
        grade: StoryGrade(avgGradePct: 0.4, elevGainM: 48, costSecPerMi: hillCost),
        hr: StoryHR(avg: 166, max: 173, metersPerBeat: 1.77),
        drift: nil,
        fadeSecPerMi: fade,
        memo: mood.map { StoryMemo(text: "Felt harder than the pace suggests.", mood: $0) },
        niggles: niggles
    )
}

// MARK: - Ghost selection

@Suite struct PreviousComparableTests {
    @Test func picksNearestEarlierOfSameKind() {
        let all = [
            keySession(id: "a", date: "2026-07-01"),
            keySession(id: "b", date: "2026-07-10"),
            keySession(id: "long", date: "2026-07-12", zone: "easy", kind: "long_run"),
            keySession(id: "c", date: "2026-07-21"),
        ]
        let ghost = SessionStoryLogic.previousComparable(to: all[3], in: all)
        #expect(ghost?.id == "b") // nearest quality; the long run never qualifies
    }

    @Test func prefersSameZoneOverNearer() {
        let all = [
            keySession(id: "tenk", date: "2026-07-05", zone: "10k"),
            keySession(id: "fivek", date: "2026-07-01", zone: "5k"),
            keySession(id: "now", date: "2026-07-21", zone: "5k"),
        ]
        let ghost = SessionStoryLogic.previousComparable(to: all[2], in: all)
        #expect(ghost?.id == "fivek") // same zone beats nearer different zone
    }

    @Test func fallsBackToAnyQualityWhenZoneNeverSeen() {
        let all = [
            keySession(id: "tenk", date: "2026-07-05", zone: "10k"),
            keySession(id: "now", date: "2026-07-21", zone: "mile"),
        ]
        let ghost = SessionStoryLogic.previousComparable(to: all[1], in: all)
        #expect(ghost?.id == "tenk")
    }

    @Test func longRunsCompareOnlyToLongRuns() {
        let all = [
            keySession(id: "q", date: "2026-07-18"),
            keySession(id: "lr1", date: "2026-07-11", zone: "easy", kind: "long_run"),
            keySession(id: "lr2", date: "2026-07-19", zone: "steady", kind: "long_run"),
        ]
        let ghost = SessionStoryLogic.previousComparable(to: all[2], in: all)
        #expect(ghost?.id == "lr1")
    }

    @Test func firstOfItsKindHasNoGhost() {
        let all = [keySession(id: "only", date: "2026-07-21")]
        #expect(SessionStoryLogic.previousComparable(to: all[0], in: all) == nil)
    }
}

// MARK: - Drift tiers

@Suite struct DriftTierTests {
    private func drift(_ kind: String, _ value: Double) -> StoryDrift {
        StoryDrift(kind: kind, value: value, meaningful: true, note: "")
    }

    @Test func decouplingBands() {
        #expect(DriftTier.tier(for: drift("decoupling", 2.5)) == .durable)
        #expect(DriftTier.tier(for: drift("decoupling", 4.9)) == .durable)
        #expect(DriftTier.tier(for: drift("decoupling", 5.0)) == .creeping)
        #expect(DriftTier.tier(for: drift("decoupling", 7.9)) == .creeping)
        #expect(DriftTier.tier(for: drift("decoupling", 8.0)) == .high)
    }

    @Test func repDriftBands() {
        #expect(DriftTier.tier(for: drift("reps", 5)) == .durable)
        #expect(DriftTier.tier(for: drift("reps", 9)) == .creeping)
        #expect(DriftTier.tier(for: drift("reps", 15)) == .high)
    }
}

// MARK: - The Read

@Suite struct SessionStoryReadTests {
    @Test func citesTheGhostAndTheCosts() {
        let now = story(conditionsPace: 309)
        let then = story(conditionsPace: 320)
        let read = SessionStoryRead.build(session: now, compare: then)
        #expect(read.body.contains("11s/mi faster"))
        #expect(read.body.contains("6×1mi"))
        #expect(read.body.contains("16s/mi to heat"))
        #expect(read.body.contains("3s/mi to hills"))
        #expect(!read.question.isEmpty)
    }

    @Test func negativeFadeReadsAsHeldToTheEnd() {
        let read = SessionStoryRead.build(session: story(fade: -5.0), compare: nil)
        #expect(read.body.contains("faster"))
        #expect(read.body.contains("held to the end"))
    }

    @Test func firstSessionSaysSoInsteadOfInventingAComparison() {
        let read = SessionStoryRead.build(session: story(), compare: nil)
        #expect(read.body.contains("nothing to set it against"))
    }

    @Test func nigglesSurfaceAsWatchedNeverDiagnosed() {
        let n = StoryNiggle(bodyArea: "knee", side: "left", severityHint: "sore", quote: "sore left knee")
        let read = SessionStoryRead.build(session: story(niggles: [n]), compare: nil)
        #expect(read.body.contains("left knee"))
        #expect(read.body.contains("your own words"))
        // Hard rule #2: never a prescription, never a diagnosis.
        #expect(!read.body.lowercased().contains("rest"))
        #expect(!read.body.lowercased().contains("ice"))
    }

    @Test func strugglingMoodShapesTheQuestion() {
        let read = SessionStoryRead.build(session: story(mood: "struggling"), compare: nil)
        #expect(read.question.contains("conditions"))
    }
}

// MARK: - Wire format

@Suite struct SessionStoryDecodeTests {
    @Test func decodesAFullPayload() throws {
        let json = """
        {
          "session": {
            "log_id": "abc", "date": "2026-07-21", "name": "6×1mi", "kind": "reps",
            "total_miles": 7.5, "duration_min": 43,
            "segments": [
              {"label": "R1", "pace_sec": 328, "hr": 160, "distance_m": 1609},
              {"label": "R2", "pace_sec": 325, "hr": 165, "distance_m": 1609}
            ],
            "avg_pace_sec": 328, "neutral_pace_sec": 312, "conditions_pace_sec": 309,
            "heat": {"temp_f": 78, "dew_f": 72, "cost_sec_per_mi": 16},
            "grade": {"avg_grade_pct": 0.4, "elev_gain_m": 48, "cost_sec_per_mi": 3},
            "hr": {"avg": 166, "max": 173, "meters_per_beat": 1.77},
            "drift": {"kind": "reps", "value": 9, "meaningful": true, "note": ""},
            "fade_sec_per_mi": -3.0,
            "memo": {"text": "Humidity and hills made it harder than the splits say.", "mood": "positive"},
            "niggles": [{"body_area": "knee", "side": "left", "severity_hint": "sore", "quote": "sore left knee"}]
          },
          "compare": null,
          "generated_at": "2026-07-27T12:00:00Z"
        }
        """
        let payload = try JSONDecoder()
            .decode(SessionStoryPayloadDTO.self, from: Data(json.utf8))
            .toModel()
        #expect(payload.session.segments.count == 2)
        #expect(payload.session.segments[0].label == "R1")
        #expect(payload.session.heat?.costSecPerMi == 16)
        #expect(payload.session.drift?.meaningful == true)
        #expect(payload.session.memo?.mood == "positive")
        #expect(payload.session.niggles.first?.bodyArea == "knee")
        #expect(payload.compare == nil)
    }

    @Test func toleratesMissingOptionalBlocks() throws {
        let json = """
        {
          "session": {
            "log_id": "abc", "date": "2026-07-21", "name": "Long 13 mi", "kind": "sustained",
            "total_miles": null, "duration_min": null,
            "segments": [], "avg_pace_sec": null, "neutral_pace_sec": null,
            "conditions_pace_sec": null, "heat": null, "grade": null, "hr": null,
            "drift": null, "fade_sec_per_mi": null, "memo": null, "niggles": []
          },
          "compare": null
        }
        """
        let payload = try JSONDecoder()
            .decode(SessionStoryPayloadDTO.self, from: Data(json.utf8))
            .toModel()
        #expect(payload.session.kind == "sustained")
        #expect(payload.session.avgPaceSec == nil)
        #expect(payload.session.memo == nil)
    }
}

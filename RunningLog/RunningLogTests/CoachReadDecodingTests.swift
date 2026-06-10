//
//  CoachReadDecodingTests.swift
//  RunningLogTests
//
//  Locks the JSON ↔ `CoachRead` contract. The trickiest piece is the
//  paragraph segment union — the JSON mixes raw strings with
//  `{workout_id}` / `{doc_id}` objects, and the decoder discriminates
//  by trying each variant in turn. These tests would fail if anyone
//  accidentally collapses segments to a single shape, drops the
//  date-only `read_date` formatter, or breaks the snake_case CodingKeys.
//

import Foundation
import Testing
@testable import RunningLog

@Suite("CoachRead decoding")
struct CoachReadDecodingTests {

    // MARK: - Mixed-segment paragraph

    @Test("Decodes a Read with workout chip + doc chip + plain string segments")
    func mixedSegmentParagraph() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "read_date": "2026-05-19",
          "headline": "The base is taking.",
          "paragraph": [
            "Three good weeks in a row. ",
            { "workout_id": "aaaaaaaa-1111-1111-1111-111111111111" },
            " came in 6s under target — third tempo this block to land where it should. The ",
            { "doc_id": "bbbbbbbb-1111-1111-1111-111111111111" },
            " on aerobic support says this is the phase to hold steady, not push."
          ],
          "cant_see": {
            "eyebrow": "NO SLEEP DATA",
            "body": "Watch isn't syncing sleep this week — I'm guessing on recovery."
          },
          "sources": {
            "workouts": ["aaaaaaaa-1111-1111-1111-111111111111"],
            "docs": ["bbbbbbbb-1111-1111-1111-111111111111"],
            "memos": [
              {
                "label": "TUE AM",
                "excerpt": "legs feeling smooth",
                "log_id": "cccccccc-1111-1111-1111-111111111111"
              }
            ]
          },
          "confidence": { "level": "HIGH", "sub": "5 workouts and a recent half" },
          "ai_model": "gemini-2.5-flash",
          "generated_at": "2026-05-19T13:41:02.000Z"
        }
        """.data(using: .utf8)!

        let read = try JSONDecoder.coachRead().decode(CoachRead.self, from: json)

        // Structural assertions.
        #expect(read.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(read.headline == "The base is taking.")
        #expect(read.paragraph.count == 5)

        // Segments in order.
        guard case .text(let s0) = read.paragraph[0] else {
            Issue.record("paragraph[0] expected .text, got \(read.paragraph[0])")
            return
        }
        #expect(s0.hasPrefix("Three good weeks"))

        guard case .workout(let w1) = read.paragraph[1] else {
            Issue.record("paragraph[1] expected .workout, got \(read.paragraph[1])")
            return
        }
        #expect(w1 == UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111"))

        guard case .text(let s2) = read.paragraph[2] else {
            Issue.record("paragraph[2] expected .text, got \(read.paragraph[2])")
            return
        }
        #expect(s2.contains("came in 6s under target"))

        guard case .doc(let d3) = read.paragraph[3] else {
            Issue.record("paragraph[3] expected .doc, got \(read.paragraph[3])")
            return
        }
        #expect(d3 == UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111"))

        guard case .text = read.paragraph[4] else {
            Issue.record("paragraph[4] expected .text, got \(read.paragraph[4])")
            return
        }

        // cantSee block.
        #expect(read.cantSee?.eyebrow == "NO SLEEP DATA")
        #expect(read.cantSee?.body.contains("guessing on recovery") == true)

        // Sources.
        #expect(read.sources.workouts == [UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!])
        #expect(read.sources.docs == [UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!])
        #expect(read.sources.memos.count == 1)
        #expect(read.sources.memos[0].label == "TUE AM")
        #expect(read.sources.memos[0].logId == UUID(uuidString: "cccccccc-1111-1111-1111-111111111111"))

        // Confidence.
        #expect(read.confidence.level == .high)
        #expect(read.confidence.sub == "5 workouts and a recent half")

        // Metadata.
        #expect(read.aiModel == "gemini-2.5-flash")

        // Dates — `read_date` is date-only, `generated_at` is ISO-8601.
        // Both must decode without throwing.
        let cal = Calendar(identifier: .iso8601)
        let day = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: read.readDate)
        #expect(day.year == 2026 && day.month == 5 && day.day == 19)
    }

    // MARK: - cant_see optional

    @Test("cant_see: null decodes as nil")
    func cantSeeNullable() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "read_date": "2026-05-19",
          "headline": "Quiet week — by design.",
          "paragraph": ["Recovery week. Nothing to read into the volume drop."],
          "cant_see": null,
          "sources": { "workouts": [], "docs": [], "memos": [] },
          "confidence": { "level": "MEDIUM", "sub": "3 workouts, recent" },
          "ai_model": null,
          "generated_at": "2026-05-19T13:00:00Z"
        }
        """.data(using: .utf8)!

        let read = try JSONDecoder.coachRead().decode(CoachRead.self, from: json)
        #expect(read.cantSee == nil)
        #expect(read.aiModel == nil)
        #expect(read.confidence.level == .medium)
    }

    // MARK: - Empty-state (new account)

    @Test("Empty-state paragraph with a single string segment decodes")
    func emptyStateRead() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "read_date": "2026-05-19",
          "headline": "Nothing to read yet.",
          "paragraph": ["I need a workout to read. Log one and I'll have something to say."],
          "cant_see": { "eyebrow": "NEW ACCOUNT", "body": "Haven't seen you run yet." },
          "sources": { "workouts": [], "docs": [], "memos": [] },
          "confidence": { "level": "LOW", "sub": "first read — light evidence" },
          "ai_model": "gemini-2.5-flash",
          "generated_at": "2026-05-19T06:00:00Z"
        }
        """.data(using: .utf8)!

        let read = try JSONDecoder.coachRead().decode(CoachRead.self, from: json)
        #expect(read.paragraph.count == 1)
        #expect(read.sources.workouts.isEmpty)
        #expect(read.confidence.level == .low)
    }

    // MARK: - Round-trip encode → decode

    @Test("CoachRead round-trips through JSONEncoder/JSONDecoder")
    func encodeDecodeRoundTrip() throws {
        let original = CoachRead(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            readDate: ISO8601DateFormatter().date(from: "2026-05-19T00:00:00Z")!,
            headline: "Test headline",
            paragraph: [
                .text("Plain start. "),
                .workout(workoutId: UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!),
                .text(" and a doc: "),
                .doc(docId: UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!),
            ],
            cantSee: .init(eyebrow: "X", body: "y"),
            sources: .init(
                workouts: [UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!],
                docs: [UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!],
                memos: []
            ),
            confidence: .init(level: .high, sub: "sub"),
            aiModel: "gemini-2.5-flash",
            generatedAt: Date(timeIntervalSince1970: 1_747_656_000)
        )

        // Encode → decode pairing must use a strategy that handles dates
        // symmetrically; the default JSONEncoder writes Double-seconds,
        // which JSONDecoder.coachRead() does NOT understand. Use ISO-8601
        // on the encoder so the strings round-trip cleanly.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder.coachRead().decode(CoachRead.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.headline == original.headline)
        #expect(decoded.paragraph.count == 4)
        #expect(decoded.sources.workouts == original.sources.workouts)
        #expect(decoded.confidence.level == .high)

        // Spot-check segment shape preservation.
        if case .workout(let id) = decoded.paragraph[1] {
            #expect(id == UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111"))
        } else {
            Issue.record("paragraph[1] expected .workout, got \(decoded.paragraph[1])")
        }
        if case .doc(let id) = decoded.paragraph[3] {
            #expect(id == UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111"))
        } else {
            Issue.record("paragraph[3] expected .doc, got \(decoded.paragraph[3])")
        }
    }

    // MARK: - Decoder rejects bogus segment shape

    @Test("A segment that's neither string nor recognized object fails decoding")
    func unrecognizedSegmentShapeRejected() {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "read_date": "2026-05-19",
          "headline": "x",
          "paragraph": [{ "mystery_field": "nope" }],
          "sources": { "workouts": [], "docs": [], "memos": [] },
          "confidence": { "level": "LOW", "sub": "x" },
          "generated_at": "2026-05-19T06:00:00Z"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder.coachRead().decode(CoachRead.self, from: json)
        }
    }
}

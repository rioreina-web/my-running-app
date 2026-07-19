//
//  CoachRead.swift
//  RunningLog
//
//  Swift mirror of the `daily_coaching_reads` row produced by the
//  `coaching-daily-read` edge function. Drives the Coach tab's morning
//  Read surface (see Coach iOS direction A · The Read).
//
//  Phase 2.1 of coach-the-read-prompts.md.
//
//  Shape highlights:
//    - `paragraph` is an ordered array of segments, each of which is one
//      of {plain text, workout citation, doc citation}. The JSON shape
//      mixes raw strings with `{workout_id}` / `{doc_id}` objects; the
//      decoder discriminates by trying each variant in turn.
//    - `cantSee` is the honest "what I can't see" block. Optional —
//      omitted when the picture is clean.
//    - `sources` collects every cited workout/doc id plus voice memos
//      that informed the read (memos never appear inline in paragraph;
//      they surface only in the Sources panel).
//    - `confidence` is a HIGH / MEDIUM / LOW assessment with a short
//      sub-line.
//

import Foundation

/// One published morning Coach Read, as rendered on the iOS Coach tab.
struct CoachRead: Codable, Identifiable, Equatable {
    let id: UUID
    let readDate: Date
    let headline: String
    // v5 sectioned narrative. Optional + backward-compatible: pre-v5 rows have
    // null columns and decode fine, falling back to `paragraph`. When
    // `sections` is present, the narrative screen renders these instead.
    let eyebrow: String?
    let sections: [Section]?
    let question: String?
    let paragraph: [Segment]
    let cantSee: CantSee?
    let sources: Sources
    let confidence: Confidence
    let aiModel: String?
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case readDate = "read_date"
        case headline
        case eyebrow
        case sections
        case question
        case paragraph
        case cantSee = "cant_see"
        case sources
        case confidence
        case aiModel = "ai_model"
        case generatedAt = "generated_at"
    }

    /// True when the row carries a v5 sectioned narrative worth rendering.
    var hasSections: Bool { (sections?.isEmpty == false) }

    // MARK: - Section (v5)

    /// One labeled editorial section: "The week", "The hard days",
    /// "The long run", "How you felt", "One thing". `body` is an ordered
    /// mix of prose and inline tap-through refs.
    struct Section: Codable, Equatable {
        let label: String
        let body: [SectionSegment]
    }

    /// One segment of a v5 section body. JSON variants:
    ///   - raw string                                  → `.text`
    ///   - `{"text": "...", "workout_id": "<uuid>"}`   → `.workout` (tappable)
    ///   - `{"text": "...", "niggle": "right achilles"}` → `.niggle` (tappable)
    /// Unlike the legacy `Segment`, refs carry their own display `text`.
    enum SectionSegment: Codable, Equatable {
        case text(String)
        case workout(text: String, workoutId: UUID)
        case niggle(text: String, bodyPart: String)

        private enum Key: String, CodingKey {
            case text
            case workoutId = "workout_id"
            case niggle
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let raw = try? single.decode(String.self) {
                self = .text(raw)
                return
            }
            let k = try decoder.container(keyedBy: Key.self)
            let text = (try? k.decode(String.self, forKey: .text)) ?? ""
            if k.contains(.workoutId),
               let id = try? k.decode(UUID.self, forKey: .workoutId) {
                self = .workout(text: text, workoutId: id)
                return
            }
            if k.contains(.niggle),
               let part = try? k.decode(String.self, forKey: .niggle) {
                self = .niggle(text: text, bodyPart: part)
                return
            }
            // Unknown ref shape — degrade to its text so the prose still reads.
            self = .text(text)
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let raw):
                var s = encoder.singleValueContainer()
                try s.encode(raw)
            case .workout(let text, let id):
                var k = encoder.container(keyedBy: Key.self)
                try k.encode(text, forKey: .text)
                try k.encode(id, forKey: .workoutId)
            case .niggle(let text, let part):
                var k = encoder.container(keyedBy: Key.self)
                try k.encode(text, forKey: .text)
                try k.encode(part, forKey: .niggle)
            }
        }
    }

    // MARK: - Segment

    /// One element of the Read's paragraph. The JSON variants are:
    ///   - raw string                   → `.text(String)`
    ///   - `{"workout_id": "<uuid>"}`   → `.workout(workoutId: UUID)`
    ///   - `{"doc_id": "<uuid>"}`       → `.doc(docId: UUID)`
    ///
    /// The frontend renders strings inline and citation cases as kerned
    /// chips. Any segment that doesn't match one of the three variants
    /// fails decoding — by contract, the edge-function validator has
    /// already stripped malformed segments before they reach the row.
    enum Segment: Codable, Equatable {
        case text(String)
        case workout(workoutId: UUID)
        case doc(docId: UUID)

        private enum CitationKey: String, CodingKey {
            case workoutId = "workout_id"
            case docId = "doc_id"
        }

        init(from decoder: Decoder) throws {
            // 1) Plain string? singleValueContainer().decode(String.self)
            //    throws cleanly when the underlying JSON is an object, so
            //    `try?` here is the right discriminator — not a swallow.
            if let single = try? decoder.singleValueContainer(),
               let raw = try? single.decode(String.self) {
                self = .text(raw)
                return
            }
            // 2) Object with workout_id or doc_id. Use `contains()` to
            //    discriminate so that a key whose value is malformed
            //    (e.g. non-UUID) surfaces a real DecodingError instead
            //    of being silently demoted to "not a citation."
            let keyed = try decoder.container(keyedBy: CitationKey.self)
            if keyed.contains(.workoutId) {
                let id = try keyed.decode(UUID.self, forKey: .workoutId)
                self = .workout(workoutId: id)
                return
            }
            if keyed.contains(.docId) {
                let id = try keyed.decode(UUID.self, forKey: .docId)
                self = .doc(docId: id)
                return
            }
            throw DecodingError.dataCorruptedError(
                forKey: .workoutId,
                in: keyed,
                debugDescription:
                    "CoachRead.Segment: expected a string, "
                    + "{\"workout_id\": <uuid>}, or {\"doc_id\": <uuid>}"
            )
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let raw):
                var single = encoder.singleValueContainer()
                try single.encode(raw)
            case .workout(let id):
                var keyed = encoder.container(keyedBy: CitationKey.self)
                try keyed.encode(id, forKey: .workoutId)
            case .doc(let id):
                var keyed = encoder.container(keyedBy: CitationKey.self)
                try keyed.encode(id, forKey: .docId)
            }
        }
    }

    // MARK: - Cant-see block

    /// Honest-uncertainty block. Rendered as a mono eyebrow + italic
    /// body when present; suppressed entirely when nil.
    struct CantSee: Codable, Equatable {
        let eyebrow: String
        let body: String
    }

    /// Build a CoachRead from a plain answer string — the client-side mirror
    /// of the edge function's `toEditorialRead`. Used as a fallback when the
    /// ask endpoint returns its chat envelope ({ response: "..." }) rather than
    /// the editorial { read } shape, so the ask surface still renders.
    static func fromPlainText(_ text: String) -> CoachRead {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var headline = "Here's what I see"
        var body = clean
        // Peel the first sentence off as a headline when it's short enough.
        var earliest: Range<String.Index>?
        for terminator in [". ", "! ", "? "] {
            if let r = clean.range(of: terminator),
               earliest == nil || r.lowerBound < earliest!.lowerBound {
                earliest = r
            }
        }
        if let r = earliest,
           clean.distance(from: clean.startIndex, to: r.lowerBound) <= 90 {
            headline = String(clean[..<r.lowerBound])
            body = String(clean[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if body.isEmpty {
            body = clean.isEmpty
                ? "I don't have enough to say yet — log a few runs and ask again."
                : clean
        }
        return CoachRead(
            id: UUID(),
            readDate: Date(),
            headline: headline,
            eyebrow: nil,
            sections: nil,
            question: nil,
            paragraph: [.text(body)],
            cantSee: nil,
            sources: Sources(workouts: [], docs: [], memos: []),
            confidence: Confidence(level: .medium, sub: "Based on your recent training"),
            aiModel: nil,
            generatedAt: Date()
        )
    }

    // MARK: - Sources

    struct Sources: Codable, Equatable {
        let workouts: [UUID]
        let docs: [UUID]
        let memos: [Memo]

        struct Memo: Codable, Equatable {
            let label: String
            let excerpt: String
            let logId: UUID

            enum CodingKeys: String, CodingKey {
                case label
                case excerpt
                case logId = "log_id"
            }
        }
    }

    // MARK: - Confidence

    struct Confidence: Codable, Equatable {
        let level: Level
        let sub: String

        enum Level: String, Codable {
            case high = "HIGH"
            case medium = "MEDIUM"
            case low = "LOW"
        }
    }
}

// MARK: - Decoder configuration

extension JSONDecoder {
    /// JSONDecoder pre-configured to decode `CoachRead` (and the
    /// hydration response shapes that wrap it). Handles both the
    /// `read_date` date-only string ("2026-05-19") and the `generated_at`
    /// ISO-8601 timestamp by trying the date-only formatter first and
    /// falling back to ISO-8601.
    static func coachRead() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            if let day = Self.dateOnlyFormatter.date(from: raw) {
                return day
            }
            if let ts = Self.iso8601WithFractional.date(from: raw) {
                return ts
            }
            if let ts = Self.iso8601Basic.date(from: raw) {
                return ts
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription:
                    "Unrecognized date format: \(raw). "
                    + "Expected yyyy-MM-dd or ISO-8601."
            )
        }
        return decoder
    }

    // The three formatters used by `coachRead()`.
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

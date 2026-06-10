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
        case paragraph
        case cantSee = "cant_see"
        case sources
        case confidence
        case aiModel = "ai_model"
        case generatedAt = "generated_at"
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

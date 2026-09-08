//
//  SessionAskService.swift
//  RunningLog
//
//  Client for the `session-ask` edge function: one question about one session.
//
//  NOT an extension of `DailyReadService.ask(_:)`. That is the Coach's client
//  and it posts to `coaching-agent` — a chat agent whose ask-vs-answer design
//  answered a workout question with "I need more info, what's your weekly
//  mileage?" (HistoryDetailViewModel.swift:795). `session-ask` is the
//  purpose-built sibling of `generate-workout-insight`, called by
//  training_log_id, and this is its own small client.
//
//  SESSION-ASK-APPLY.md §5.2.
//

import Foundation
import Supabase

@Observable
final class SessionAskService {
    static let shared = SessionAskService()

    private init() {}

    struct Answer: Decodable {
        let answer: String
        /// "Read from this session's splits, your pace zones and …" (§3).
        /// Assembled server-side from what the context builder actually
        /// loaded, so it can't claim a source that wasn't read.
        let readFrom: String?
        /// The rail for the NEXT question, gated to what this session can
        /// actually answer. Ships on the response rather than in the binary
        /// so changing it is a deploy, not an App Store release (§8).
        let suggested: [Suggestion]

        struct Suggestion: Decodable, Identifiable, Equatable {
            let id: String
            let text: String
        }

        // The envelope is snake_case; `suggested` is the TS interface
        // serialized as-is. Declared explicitly rather than reaching for a
        // decoder-wide `.convertFromSnakeCase`, which is the same deliberate
        // split `AskResponse` makes for the Ask surface.
        enum CodingKeys: String, CodingKey {
            case answer
            case readFrom = "read_from"
            case suggested
        }
    }

    enum SessionAskError: LocalizedError {
        case empty
        case upstream(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "No answer came back."
            case .upstream(let message):
                return message
            }
        }
    }

    /// Ask one question about one session.
    ///
    /// Mirrors the request shape `generateCoachInsight()` already uses for
    /// `generate-workout-insight`, so decoding and error handling follow a
    /// path that exists.
    func ask(_ question: String, workoutId: UUID) async throws -> Answer {
        struct Req: Encodable {
            let question: String
            let training_log_id: String
        }
        // The function returns either an answer envelope or `{ error }`;
        // decode both so a 4xx/5xx body surfaces its message instead of a
        // generic decoding failure.
        struct Resp: Decodable {
            let answer: String?
            let read_from: String?
            let suggested: [Answer.Suggestion]?
            let error: String?
        }

        let resp: Resp = try await supabase.functions.invoke(
            "session-ask",
            options: .init(
                body: Req(question: question, training_log_id: workoutId.uuidString)
            )
        )

        if let error = resp.error, !error.isEmpty {
            throw SessionAskError.upstream(error)
        }

        let text = resp.answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw SessionAskError.empty }

        return Answer(
            answer: text,
            readFrom: resp.read_from?.trimmingCharacters(in: .whitespacesAndNewlines),
            suggested: resp.suggested ?? []
        )
    }
}

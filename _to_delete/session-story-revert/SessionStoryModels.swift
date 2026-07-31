//
//  SessionStoryModels.swift
//  RunningLog
//
//  Wire format + view models + pure logic for the Session Story sheet
//  (Trends ▸ Key sessions ▸ tap a session). Decodes the `session-story`
//  edge-function payload with the same snake_case DTO pattern as
//  `KeySessionDTO` / `FastSegmentsDTO`, and carries the two pure pieces the
//  view (and the tests) share:
//
//    • `SessionStoryLogic.previousComparable` — which earlier key session is
//      the honest ghost for this one (same kind; quality prefers same zone).
//    • `SessionStoryRead` — the templated observation block. Coach voice:
//      observation with specific numbers, soft question at the end, never a
//      prescription, never a diagnosis (CLAUDE.md hard rule #2).
//
//  Adjusted paces are models, not measurements: raw pace is always present
//  and heat-neutral / conditions paces ride alongside, never replace.
//

import Foundation

// MARK: - View models

struct SessionStory {
    let logId: String
    let date: String            // "2026-07-21"
    let name: String            // "5K 5×1km · 6.0 mi" or a fallback
    let kind: String            // "reps" | "sustained"
    let totalMiles: Double?
    let durationMin: Int?
    let segments: [StorySegment]
    let avgPaceSec: Int?        // raw — work pace (reps) / whole-run (sustained)
    let neutralPaceSec: Int?    // heat removed
    let conditionsPaceSec: Int? // heat + hills removed
    let heat: StoryHeat?
    let grade: StoryGrade?
    let hr: StoryHR?
    let drift: StoryDrift?
    let fadeSecPerMi: Double?   // positive = the back half slowed
    let memo: StoryMemo?
    let niggles: [StoryNiggle]

    var isReps: Bool { kind == "reps" }
}

struct StorySegment: Identifiable {
    let label: String           // "R1" … / "1st half" / "Last 2 mi"
    let paceSec: Int
    let hr: Int?
    let distanceM: Int?
    var id: String { label }
}

struct StoryHeat {
    let tempF: Int
    let dewF: Int
    let costSecPerMi: Int
}

struct StoryGrade {
    let avgGradePct: Double?
    let elevGainM: Int
    let costSecPerMi: Int?
}

struct StoryHR {
    let avg: Int
    let max: Int?
    let metersPerBeat: Double?
}

struct StoryDrift {
    let kind: String            // "reps" (bpm) | "decoupling" (%)
    let value: Double
    let meaningful: Bool
    let note: String
}

struct StoryMemo {
    let text: String
    let mood: String?
}

struct StoryNiggle: Identifiable {
    let bodyArea: String
    let side: String?
    let severityHint: String?
    let quote: String?
    var id: String { bodyArea + (side ?? "") + (quote ?? "") }
}

struct SessionStoryPayload {
    let session: SessionStory
    let compare: SessionStory?
}

// MARK: - Drift tier (view + tests share the thresholds)

enum DriftTier: String {
    case durable = "DURABLE ZONE"
    case creeping = "CREEPING"
    case high = "HIGH"

    /// Decoupling (%): < 5 durable, < 8 creeping, else high — the same band
    /// the Fitness Signal prototype drew. Rep drift (bpm across the set):
    /// ≤ 6 durable, ≤ 14 creeping, else high.
    static func tier(for drift: StoryDrift) -> DriftTier {
        if drift.kind == "decoupling" {
            if drift.value < 5 { return .durable }
            if drift.value < 8 { return .creeping }
            return .high
        }
        if drift.value <= 6 { return .durable }
        if drift.value <= 14 { return .creeping }
        return .high
    }
}

// MARK: - Ghost selection

enum SessionStoryLogic {
    /// The previous comparable key session — the ghost. Same `kind` always
    /// (a long run's whole-run pace and a rep session's work pace are not
    /// comparable; see `KeySession.kind`). Among quality sessions, a same-zone
    /// predecessor wins over a nearer different-zone one; when no same-zone
    /// session exists, the nearest earlier quality session is still an honest
    /// "last hard day". Returns nil for the first session of its kind.
    static func previousComparable(
        to session: KeySession,
        in all: [KeySession]
    ) -> KeySession? {
        let earlier = all
            .filter { $0.id != session.id && $0.date < session.date && $0.kind == session.kind }
            .sorted { $0.date > $1.date } // nearest first
        guard !earlier.isEmpty else { return nil }
        if session.kind == "quality",
           let sameZone = earlier.first(where: { $0.zone == session.zone }) {
            return sameZone
        }
        return earlier.first
    }
}

// MARK: - The Read (templated observation, coach voice)

enum SessionStoryRead {
    /// Observation + soft question. Numbers always cited (data-depth rule);
    /// never a prescription, never a diagnosis. The memo's mood shapes the
    /// question the way a coach would let it.
    static func build(session s: SessionStory, compare g: SessionStory?) -> (body: String, question: String) {
        var body = ""

        if let g, let now = s.conditionsPaceSec ?? s.neutralPaceSec ?? s.avgPaceSec,
           let then = g.conditionsPaceSec ?? g.neutralPaceSec ?? g.avgPaceSec {
            let d = now - then
            let kindLabel = s.isReps ? "interval day" : "sustained effort"
            if d <= -2 {
                body = "Conditions-adjusted, this was \(paceDelta(-d)) faster than your last \(kindLabel) (\(g.name), \(dateLabel(g.date)))"
            } else if d >= 2 {
                body = "Conditions-adjusted, this was \(paceDelta(d)) slower than your last \(kindLabel) (\(g.name), \(dateLabel(g.date)))"
            } else {
                body = "Conditions-adjusted, this sat level with your last \(kindLabel) (\(g.name), \(dateLabel(g.date)))"
            }
        } else {
            body = s.isReps
                ? "First interval day of its kind in the window — nothing to set it against yet"
                : "First sustained effort of its kind in the window — nothing to set it against yet"
        }

        var costs: [String] = []
        if let heat = s.heat, heat.costSecPerMi > 0 { costs.append("\(heat.costSecPerMi)s/mi to heat") }
        if let grade = s.grade, let c = grade.costSecPerMi, c > 0 { costs.append("\(c)s/mi to hills") }
        if costs.isEmpty {
            body += "."
        } else {
            body += " — the day itself cost about \(costs.joined(separator: " and "))."
        }

        if let fade = s.fadeSecPerMi {
            if fade <= -3 {
                body += " The back half came in \(Int(abs(fade.rounded())))s/mi faster — it held to the end."
            } else if fade >= 3 {
                body += " The back half gave up \(Int(fade.rounded()))s/mi."
            } else {
                body += " The back half held level."
            }
        }

        if let n = s.niggles.first {
            let area = [n.side, n.bodyArea].compactMap { $0 }.joined(separator: " ")
            body += " Your memo mentioned the \(area) — surfaced from your own words, worth watching."
        }

        return (body, question(for: s, compare: g))
    }

    private static func question(for s: SessionStory, compare _: SessionStory?) -> String {
        switch s.memo?.mood {
        case "struggling":
            return "The clock and the memo disagree less than you think — the conditions explain most of it. What would this have been on a cool morning?"
        case "tired":
            return "Tired going in and still this close to last time — what does that say about where fitness actually is?"
        case "energized", "positive":
            return "That's the shape you want. What made this one work — and can the next hard day borrow it?"
        default:
            if let fade = s.fadeSecPerMi, fade <= -3 {
                return "Finishing faster than you started — was that the plan, or did the day open up?"
            }
            return "Same session in a few weeks — what's the one thing you'd change?"
        }
    }

    private static func paceDelta(_ sec: Int) -> String {
        sec >= 60 ? "\(sec / 60):\(String(format: "%02d", sec % 60))/mi" : "\(sec)s/mi"
    }

    private static let monthAbbr = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    static func dateLabel(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let m = Int(parts[1]), (1...12).contains(m),
              let d = Int(parts[2]) else { return iso }
        return "\(monthAbbr[m - 1]) \(d)"
    }
}

// MARK: - Wire format (snake_case → models)

struct SessionStoryPayloadDTO: Decodable {
    let session: SessionStoryDTO
    let compare: SessionStoryDTO?

    func toModel() -> SessionStoryPayload {
        SessionStoryPayload(session: session.toModel(), compare: compare?.toModel())
    }
}

struct SessionStoryDTO: Decodable {
    let logId: String
    let date: String
    let name: String
    let kind: String
    let totalMiles: Double?
    let durationMin: Int?
    let segments: [SegmentDTO]
    let avgPaceSec: Int?
    let neutralPaceSec: Int?
    let conditionsPaceSec: Int?
    let heat: HeatDTO?
    let grade: GradeDTO?
    let hr: HRDTO?
    let drift: DriftDTO?
    let fadeSecPerMi: Double?
    let memo: MemoDTO?
    let niggles: [NiggleDTO]

    enum CodingKeys: String, CodingKey {
        case logId = "log_id"
        case date, name, kind
        case totalMiles = "total_miles"
        case durationMin = "duration_min"
        case segments
        case avgPaceSec = "avg_pace_sec"
        case neutralPaceSec = "neutral_pace_sec"
        case conditionsPaceSec = "conditions_pace_sec"
        case heat, grade, hr, drift
        case fadeSecPerMi = "fade_sec_per_mi"
        case memo, niggles
    }

    struct SegmentDTO: Decodable {
        let label: String
        let paceSec: Int
        let hr: Int?
        let distanceM: Int?
        enum CodingKeys: String, CodingKey {
            case label
            case paceSec = "pace_sec"
            case hr
            case distanceM = "distance_m"
        }
    }

    struct HeatDTO: Decodable {
        let tempF: Int
        let dewF: Int
        let costSecPerMi: Int
        enum CodingKeys: String, CodingKey {
            case tempF = "temp_f"
            case dewF = "dew_f"
            case costSecPerMi = "cost_sec_per_mi"
        }
    }

    struct GradeDTO: Decodable {
        let avgGradePct: Double?
        let elevGainM: Int
        let costSecPerMi: Int?
        enum CodingKeys: String, CodingKey {
            case avgGradePct = "avg_grade_pct"
            case elevGainM = "elev_gain_m"
            case costSecPerMi = "cost_sec_per_mi"
        }
    }

    struct HRDTO: Decodable {
        let avg: Int
        let max: Int?
        let metersPerBeat: Double?
        enum CodingKeys: String, CodingKey {
            case avg, max
            case metersPerBeat = "meters_per_beat"
        }
    }

    struct DriftDTO: Decodable {
        let kind: String
        let value: Double
        let meaningful: Bool
        let note: String
    }

    struct MemoDTO: Decodable {
        let text: String
        let mood: String?
    }

    struct NiggleDTO: Decodable {
        let bodyArea: String
        let side: String?
        let severityHint: String?
        let quote: String?
        enum CodingKeys: String, CodingKey {
            case bodyArea = "body_area"
            case side
            case severityHint = "severity_hint"
            case quote
        }
    }

    func toModel() -> SessionStory {
        SessionStory(
            logId: logId,
            date: date,
            name: name,
            kind: kind,
            totalMiles: totalMiles,
            durationMin: durationMin,
            segments: segments.map {
                StorySegment(label: $0.label, paceSec: $0.paceSec, hr: $0.hr, distanceM: $0.distanceM)
            },
            avgPaceSec: avgPaceSec,
            neutralPaceSec: neutralPaceSec,
            conditionsPaceSec: conditionsPaceSec,
            heat: heat.map { StoryHeat(tempF: $0.tempF, dewF: $0.dewF, costSecPerMi: $0.costSecPerMi) },
            grade: grade.map { StoryGrade(avgGradePct: $0.avgGradePct, elevGainM: $0.elevGainM, costSecPerMi: $0.costSecPerMi) },
            hr: hr.map { StoryHR(avg: $0.avg, max: $0.max, metersPerBeat: $0.metersPerBeat) },
            drift: drift.map { StoryDrift(kind: $0.kind, value: $0.value, meaningful: $0.meaningful, note: $0.note) },
            fadeSecPerMi: fadeSecPerMi,
            memo: memo.map { StoryMemo(text: $0.text, mood: $0.mood) },
            niggles: niggles.map {
                StoryNiggle(bodyArea: $0.bodyArea, side: $0.side, severityHint: $0.severityHint, quote: $0.quote)
            }
        )
    }
}

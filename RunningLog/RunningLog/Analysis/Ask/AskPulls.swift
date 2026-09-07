//
//  AskPulls.swift
//  RunningLog · Analysis · Ask
//
//  A "pull" is one live query the athlete has chosen to keep on the Ask tab:
//  a metric, a window, something to compare against, and how to draw it. It
//  recomputes on every appear — nothing here is a stored snapshot.
//
//  WHY ONLY NINE METRICS. Every one of these is either stored or divides two
//  stored columns. Two obvious candidates were left out on purpose:
//
//    • Threshold PACE. There is no stored series for it anywhere. A prototype
//      of this screen invented one, which is exactly the failure the coverage
//      line at the foot of each block exists to prevent.
//    • Rep pace. `training_logs.parsed_structure` stores each block's
//      distance with `pace_sec_per_mile` null on every one, so rep pace has
//      to be derived from `pace_segments` per session. That is a workout
//      surface, not a weekly trend, so it does not belong in a pull.
//
//  Windows are counted in COMPLETE weeks. The current week is excluded rather
//  than drawn as a collapse — a Monday reading three miles into the week is
//  not a downward trend, and drawing it as one is the chart lying.
//

import Foundation
import SwiftUI

// MARK: - Metric

enum AskMetric: String, CaseIterable, Codable, Identifiable {
    case weeklyMiles
    case acwr
    case longRunShare
    case easyShare
    case thresholdMinutes
    case qualityLoad
    case sleepHours
    case restingHR
    case bodyMentions

    var id: String { rawValue }

    /// Short name — the pull's default title, and the label in the editor.
    var short: String {
        switch self {
        case .weeklyMiles:      return "Weekly volume"
        case .acwr:             return "Acute : chronic"
        case .longRunShare:     return "Long-run share"
        case .easyShare:        return "Easy-day share"
        case .thresholdMinutes: return "Threshold minutes"
        case .qualityLoad:      return "Quality load"
        case .sleepHours:       return "Sleep"
        case .restingHR:        return "Resting HR"
        case .bodyMentions:     return "Niggle mentions"
        }
    }

    var unit: String {
        switch self {
        case .weeklyMiles:      return "mi"
        case .acwr:             return ""
        case .longRunShare:     return "%"
        case .easyShare:        return "%"
        case .thresholdMinutes: return "min"
        case .qualityLoad:      return ""
        case .sleepHours:       return "h"
        case .restingHR:        return "bpm"
        case .bodyMentions:     return ""
        }
    }

    /// Which direction reads as improvement. `.none` means the metric is a
    /// description rather than a score — volume is not "better" when it rises.
    /// Hard rule #2: observation, not judgement. `watch` is the ceiling.
    enum Direction { case up, down, none }
    var better: Direction {
        switch self {
        case .easyShare, .sleepHours:            return .up
        case .longRunShare, .restingHR, .bodyMentions: return .down
        case .weeklyMiles, .acwr, .thresholdMinutes, .qualityLoad: return .none
        }
    }

    /// How many decimals the figure carries. Paces would need mm:ss; none of
    /// the nine is a pace, which is itself the point.
    var decimals: Int {
        switch self {
        case .acwr, .sleepHours: return 2
        case .weeklyMiles, .restingHR, .qualityLoad: return 1
        default: return 0
        }
    }

    /// The provenance line under every block. Filled with real counts by
    /// `AskPullService`; this is the shape when nothing has loaded yet.
    var sourceTable: String {
        switch self {
        case .weeklyMiles, .longRunShare: return "training_logs"
        case .acwr, .easyShare, .thresholdMinutes, .qualityLoad: return "workout_features"
        case .sleepHours, .restingHR: return "daily_biometrics"
        case .bodyMentions: return "body_mentions"
        }
    }

    /// Seeded when the athlete first opens the tab. ONE, not three and not
    /// nine. Ask is a place to ask; a screen that opens with six questions we
    /// picked is a menu wearing a composer, and the athlete reads it as work
    /// to get through before they can type. The rest arrive two ways, both
    /// pulled rather than pushed: "New pull", or pinning an answer to a
    /// question they actually asked.
    static let defaults: [AskMetric] = [.weeklyMiles]
}

// MARK: - Pull knobs

enum AskWindow: String, CaseIterable, Codable, Identifiable {
    case four, twelve, block
    var id: String { rawValue }
    var label: String {
        switch self {
        case .four:   return "4 weeks"
        case .twelve: return "12 weeks"
        case .block:  return "Whole block"
        }
    }
    var weeks: Int {
        switch self {
        case .four: return 4
        case .twelve: return 12
        case .block: return AskPullService.blockWeeks
        }
    }
}

/// What the delta is measured against. Both live options are computable from
/// the series itself. A "vs last build" option was cut: the app has no stored
/// notion of a previous build, so it could only ever have been invented.
enum AskCompare: String, CaseIterable, Codable, Identifiable {
    case none, start, mean
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:  return "nothing"
        case .start: return "window start"
        case .mean:  return "block mean"
        }
    }
}

enum AskPullChart: String, CaseIterable, Codable, Identifiable {
    case line, bars, dots, figure
    var id: String { rawValue }
    var label: String {
        switch self {
        case .line: return "Line"
        case .bars: return "Bars"
        case .dots: return "Dots"
        case .figure: return "Figure only"
        }
    }
}

struct AskPull: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var metric: AskMetric
    var name: String
    var window: AskWindow = .twelve
    var compare: AskCompare = .mean
    var chart: AskPullChart = .line

    init(metric: AskMetric,
         name: String? = nil,
         window: AskWindow = .twelve,
         compare: AskCompare = .mean,
         chart: AskPullChart = .line) {
        self.metric = metric
        self.name = name ?? metric.short
        self.window = window
        self.compare = compare
        self.chart = chart
    }
}

// MARK: - Store

/// Pulls live in `UserDefaults`, not Postgres. They are a view preference —
/// which questions this athlete keeps on screen — and nothing server-side
/// reads them. A table plus a migration plus RLS buys nothing until they sync
/// across devices, and that is a decision to take on its own.
@Observable
final class AskPullStore {
    static let shared = AskPullStore()

    // v2 (2026-09-01): the seed dropped from three pulls to one. Bumping the
    // key rather than migrating, because the only thing lost is a default
    // nobody chose.
    private static let key = "askPulls.v2"

    var pulls: [AskPull] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([AskPull].self, from: data) {
            pulls = decoded
        } else {
            pulls = AskMetric.defaults.map { metric in
                AskPull(metric: metric,
                        window: .twelve,
                        compare: .mean,
                        chart: metric == .weeklyMiles || metric == .qualityLoad ? .bars : .line)
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pulls) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// Metrics not already on screen — what "New pull" and the suggestions
    /// can still offer.
    var unusedMetrics: [AskMetric] {
        let used = Set(pulls.map(\.metric))
        return AskMetric.allCases.filter { !used.contains($0) }
    }

    func add(_ metric: AskMetric) {
        guard !pulls.contains(where: { $0.metric == metric }) else { return }
        pulls.append(AskPull(metric: metric,
                             chart: metric == .bodyMentions ? .bars : .line))
    }

    func remove(_ id: UUID) { pulls.removeAll { $0.id == id } }

    func move(_ id: UUID, up: Bool) {
        guard let i = pulls.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard pulls.indices.contains(j) else { return }
        pulls.swapAt(i, j)
    }
}

// MARK: - Series

/// One computed metric over complete weeks. `points` is oldest-first.
struct AskMetricSeries {
    struct Point: Identifiable {
        let id = UUID()
        let label: String   // "Aug 24"
        let value: Double
    }
    var points: [Point]
    /// Provenance, rendered under every block. Real counts, not a table name.
    var source: String
    /// What the series cannot see. Rendered when the block is expanded, and
    /// the reason a thin metric still reads honestly.
    var caveat: String?

    static let empty = AskMetricSeries(points: [], source: "nothing on file", caveat: nil)
}

/// A pull resolved against its series — what the block actually draws.
struct AskPullReading {
    let pull: AskPull
    let points: [AskMetricSeries.Point]
    let latest: Double?
    let mean: Double
    /// The dashed reference line, when the comparison draws one.
    let ghost: Double?
    let deltaText: String
    enum Tone { case good, watch, flat }
    let tone: Tone
    let source: String
    let caveat: String?

    var figure: String {
        guard let latest else { return "—" }
        return AskPullReading.format(latest, decimals: pull.metric.decimals)
    }

    static func format(_ v: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", v)
    }
}

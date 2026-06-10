//
//  LogDedup.swift
//  RunningLog
//
//  Single source of truth for "how do you turn N rows for the same
//  physical workout into 1 row?" The training_logs table accumulates
//  rows from three writers (voice_log, auto_sync, strava) and the
//  unique-index dedup only catches re-imports of the same vital ID.
//  Every consumer that aggregates miles needs to defend itself; this
//  helper makes the rule consistent and reviewable in one place.
//
//  Rule:
//    1. Group rows by calendar day.
//    2. If any GPS-source row (strava | auto_sync) exists on the day,
//       drop voice_log rows from the day. They mirror the GPS row with
//       user-stated distance and would double-count.
//    3. Cluster the remaining rows by distance (±0.1 mi — tight, since
//       cross-source dupes are GPS imports of the same activity and
//       agree to two decimals). Multiple clusters per day = a real
//       doubles day (WU + main + CD as separate uploads).
//    4. Within a cluster, dedup ONLY across sources. If the cluster
//       holds rows from one source, those are distinct same-source
//       uploads (e.g. May 5: WU + CD both 2.01 mi from Strava) — keep
//       them all. If the cluster holds rows from multiple sources,
//       pick the highest priority: strava > auto_sync > voice_log.
//
//  Used by:
//    • TrainingTabView.summedMiles → calendar cell + weekly totals
//    • TrainingPaceAnalysisSection.computePeriods → pace-volume chart
//
//  NOT a substitute for backend dedup. WorkoutSyncService still needs to
//  stop creating the duplicates in the first place; this just keeps the
//  display honest while that lands.
//

import Foundation

extension Array where Element == TodayLogRow {
    /// Returns one row per physical workout — see file header for the rule.
    func dedupedByPhysicalWorkout() -> [TodayLogRow] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: self) { cal.startOfDay(for: $0.date) }
        var result: [TodayLogRow] = []

        for (_, dayLogs) in byDay {
            let hasGps = dayLogs.contains { LogDedupHelpers.isGpsSource($0.source) }
            let candidates = hasGps
                ? dayLogs.filter { LogDedupHelpers.isGpsSource($0.source) }
                : dayLogs

            // Cluster by distance — longer workouts first so the cluster
            // anchor is the largest run on that day. Tight 0.1 mi
            // tolerance: cross-source dupes are GPS imports of the same
            // activity and agree to two decimals; anything looser starts
            // merging genuine 1.7 mi runs into a 2.0 mi cluster.
            let sorted = candidates.sorted { ($0.miles ?? 0) > ($1.miles ?? 0) }
            var clusters: [[TodayLogRow]] = []
            for log in sorted {
                let m = log.miles ?? 0
                guard m > 0 else { continue }
                if let i = clusters.firstIndex(where: { cluster in
                    let cm = cluster.first?.miles ?? 0
                    return abs(cm - m) < 0.1
                }) {
                    clusters[i].append(log)
                } else {
                    clusters.append([log])
                }
            }

            for cluster in clusters {
                let distinctSources = Set(
                    cluster.compactMap { $0.source?.lowercased() }
                )
                if distinctSources.count > 1 {
                    // Cross-source dupes: pick highest priority, drop the rest.
                    if let best = cluster.max(by: {
                        LogDedupHelpers.sourcePriority($0.source)
                            < LogDedupHelpers.sourcePriority($1.source)
                    }) {
                        result.append(best)
                    }
                } else {
                    // Same-source uploads on the same day at the same
                    // distance = real distinct activities (WU + CD pattern,
                    // doubles days, etc.). Keep them all.
                    result.append(contentsOf: cluster)
                }
            }
        }

        return result.sorted { $0.date > $1.date }
    }
}

enum LogDedupHelpers {
    static func isGpsSource(_ s: String?) -> Bool {
        let v = (s ?? "").lowercased()
        return v == "strava" || v == "auto_sync"
    }

    static func sourcePriority(_ source: String?) -> Int {
        switch (source ?? "").lowercased() {
        case "strava":    return 3   // most reliable distance + segments
        case "auto_sync": return 2   // HealthKit/Vital fallback
        case "voice_log": return 1   // annotation only
        default:          return 0
        }
    }
}

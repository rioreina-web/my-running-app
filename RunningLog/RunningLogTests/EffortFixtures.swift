//
//  EffortFixtures.swift
//  RunningLogTests
//
//  Synthetic data for the Effort chart engine tests. Mirrors the handoff's
//  fabricated 5 × 2 mi @ MP session (14.4 mi / 98:50, 5,920 s, 4 s sampling).
//

import Foundation
@testable import RunningLog

enum EffortFixtures {

    /// The handoff's session: WU 840 s, then 5 × (rep 728 s, float 180 s — no
    /// float after R5), then CD 720 s. Sample interval 4 s. Distance is
    /// integrated from pace so mile marks are testable.
    static func session() -> (samples: [EffortSample], segments: [EffortSegment]) {
        struct Block { let kind: EffortSegmentKind; let label: String; let dur: Double; let pace: Double; let hr: Double }
        let repPaces = [366.0, 364, 361, 367, 357]     // ≈ 6:06 … 5:57
        let repHRs   = [158.0, 159, 160, 158, 161]
        var blocks: [Block] = [Block(kind: .warmup, label: "WU", dur: 840, pace: 520, hr: 130)]
        for i in 0..<5 {
            blocks.append(Block(kind: .rep, label: "R\(i + 1)", dur: 728, pace: repPaces[i], hr: repHRs[i]))
            if i < 4 { blocks.append(Block(kind: .float, label: "FLOAT", dur: 180, pace: 520, hr: 140)) }
        }
        blocks.append(Block(kind: .cooldown, label: "CD", dur: 720, pace: 540, hr: 125))

        var samples: [EffortSample] = []
        var segments: [EffortSegment] = []
        var t = 0.0
        var dist = 0.0
        let dt = 4.0
        for b in blocks {
            let t0 = t
            let end = t + b.dur
            while t < end {
                dist += dt / b.pace                 // miles gained this 4 s at this pace
                samples.append(EffortSample(
                    t: t, distanceMiles: dist, hr: b.hr,
                    paceSecPerMile: b.pace, cadenceSPM: 178, elevationFt: 40))
                t += dt
            }
            segments.append(EffortSegment(kind: b.kind, label: b.label, t0: t0, t1: end))
        }
        return (samples, segments)
    }

    /// Build resampled points directly, choosing which fall inside a rep. Lets a
    /// test drive `resolve` to a precise WORK / SPLIT outcome. Rep window is
    /// [0, repCount); jog points follow.
    static func points(rep repValue: Double, repCount: Int, jog: [Double]) -> (points: [EffortPoint], segments: [EffortSegment]) {
        var pts: [EffortPoint] = []
        for i in 0..<repCount { pts.append(EffortPoint(t: Double(i), value: repValue)) }
        for (i, v) in jog.enumerated() { pts.append(EffortPoint(t: Double(repCount + i), value: v)) }
        let seg = [EffortSegment(kind: .rep, label: "R1", t0: 0, t1: Double(repCount))]
        return (pts, seg)
    }
}

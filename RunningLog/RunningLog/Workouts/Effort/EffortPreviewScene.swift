//
//  EffortPreviewScene.swift
//  RunningLog
//
//  DEBUG-only visual-iteration harness for "The Effort" portrait 3a, seeded with
//  the design handoff's synthetic 5 × 2 mi @ MP session. Reached via the
//  `-effortPreview` launch argument (see RunningLogApp). Not compiled in release.
//

#if DEBUG
import SwiftUI

struct EffortPreviewScene: View {
    private let data = EffortPreviewFixture.session()

    var body: some View {
        ScrollView {
            EffortDetailCharts(
                samples: data.samples,
                segments: [],                     // no lap data → WINDOW path (the reported case)
                targetPaceSecPerMile: 365,
                distanceLabel: "6.0 MI",
                durationLabel: "38:10",
                figure: "FIG. 31",
                paceZones: EffortPreviewFixture.demoZones,
                hrZones: rr_zones(maxHR: 185),
                lapMarks: Array(data.segments.map(\.t1).dropLast()),
                elevationGainFt: 255)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
    }
}

struct EffortLandscapePreviewScene: View {
    private let data = EffortPreviewFixture.session()
    var body: some View {
        EffortLandscapeView(
            samples: data.samples,
            segments: [],
            targetPaceSecPerMile: 365,
            distanceLabel: "6.0 MI",
            durationLabel: "38:10",
            paceZones: EffortPreviewFixture.demoZones,
            hrZones: rr_zones(maxHR: 185),
            lapMarks: Array(data.segments.map(\.t1).dropLast()),
            elevationGainFt: 255)
    }
}

/// Mirrors the handoff session (also mirrored in RunningLogTests/EffortFixtures).
enum EffortPreviewFixture {
    /// Demo pace zones so the preview exercises the zone-anchored axis.
    static let demoZones = PaceZonesEngine(
        easy: PaceZoneRange(paceFast: 480, paceSlow: 540, label: "Easy",
                            effortPercent: "", openEndedSlow: false, source: "preview", confidence: "high"),
        moderate: nil, steady: nil,
        marathon: nil, halfMarathon: nil, tenMile: nil,
        tenK: PaceZoneAnchor(pace: 360, source: "preview", confidence: "high"),
        fiveK: PaceZoneAnchor(pace: 345, source: "preview", confidence: "high"),
        threeK: nil,
        mile: PaceZoneAnchor(pace: 300, source: "preview", confidence: "high"),
        fifteenHundred: nil,
        observedEasy: nil,
        athleteUserId: "preview", computedAt: "", primarySource: "preview")

    static func session() -> (samples: [EffortSample], segments: [EffortSegment]) {
        // Mimics the reported workout: fast reps ~5:30 with WALK recoveries that
        // plunge to ~15:00 (900 s clamp) — the case that blew out the old scale.
        struct Block { let kind: EffortSegmentKind; let label: String; let dur: Double; let pace: Double; let hr: Double }
        let repPaces = [330.0, 335, 328]          // ≈ 5:30, 5:35, 5:28
        let repHRs   = [168.0, 171, 170]
        let floatPaces = [540.0, 900.0]           // R1→R2 a 9:00 JOG, R2→R3 a walk
        var blocks: [Block] = [Block(kind: .warmup, label: "WU", dur: 300, pace: 450, hr: 140)]  // 7:30 jog
        for i in 0..<3 {
            blocks.append(Block(kind: .rep, label: "R\(i + 1)", dur: 480, pace: repPaces[i], hr: repHRs[i]))
            if i < 2 { blocks.append(Block(kind: .float, label: "FLOAT", dur: 150, pace: floatPaces[i], hr: 128)) }
        }
        blocks.append(Block(kind: .cooldown, label: "CD", dur: 240, pace: 470, hr: 135))         // 7:50 jog

        var samples: [EffortSample] = []
        var segments: [EffortSegment] = []
        var t = 0.0, dist = 0.0
        let dt = 4.0
        for b in blocks {
            let t0 = t
            let end = t + b.dur
            while t < end {
                dist += dt / b.pace
                // a little noise so the trace isn't a ruler
                let jitter = (sin(t / 17) + cos(t / 9)) * (b.kind == .rep ? 2.5 : 6)
                samples.append(EffortSample(
                    t: t, distanceMiles: dist, hr: b.hr + jitter * 0.4,
                    paceSecPerMile: b.pace + jitter, cadenceSPM: 178, elevationFt: 40 + jitter))
                t += dt
            }
            segments.append(EffortSegment(kind: b.kind, label: b.label, t0: t0, t1: end))
        }
        return (samples, segments)
    }
}
#endif

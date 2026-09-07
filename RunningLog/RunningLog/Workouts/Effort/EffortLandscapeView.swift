//
//  EffortLandscapeView.swift
//  RunningLog
//
//  "The Effort" — landscape takeover. Every available metric (pace, HR, cadence,
//  elevation) stacked on one shared, wide time axis so they can be read against
//  each other, with a single synchronized scrub across all panels. Reached by
//  the EXPAND affordance on the portrait section (and honors device rotation via
//  EffortOrientation). Full-screen instrument, not a card.
//

import SwiftUI
import UIKit

struct EffortLandscapeView: View {
    let samples: [EffortSample]
    let segments: [EffortSegment]
    let targetPaceSecPerMile: Double
    let distanceLabel: String
    let durationLabel: String
    var paceZones: PaceZonesEngine? = nil
    var hrZones: [RRZone] = []
    var lapMarks: [TimeInterval] = []
    var elevationGainFt: Int? = nil
    /// The watch's recorded splits (raw laps, pre-merge) for the SPLITS overlay.
    var watchSplits: [EffortWatchSplit] = []
    /// Non-nil ⇒ FIX REPS is available right here: the same structure editor
    /// the receipt offers, presented over the takeover, so a wrong band count
    /// can be corrected while it's on screen. Its save reloads the receipt and
    /// the corrected bands re-render behind the dismissed sheet.
    var fixReps: EffortFixRepsContext? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var scrubT: TimeInterval?
    @State private var showLaps = false
    @State private var showWatchSplits = false
    @State private var showFixReps = false
    @State private var selected: EffortMetric = .pace

    private var metrics: [EffortMetric] {
        var out: [EffortMetric] = [.pace]
        if samples.contains(where: { $0.hr > 0 }) { out.append(.hr) }
        if samples.contains(where: { $0.cadenceSPM > 0 }) { out.append(.cad) }
        let elev = samples.map(\.elevationFt)
        if (elev.max() ?? 0) - (elev.min() ?? 0) > 1 { out.append(.elev) }
        return out
    }

    // One chart per screen — swipe (or tap a metric) to move between them; each
    // fills the whole landscape.
    var body: some View {
        GeometryReader { geo in
            let header: CGFloat = 42
            let plotH = max(140, geo.size.height - header - 88)   // fill the screen

            VStack(spacing: 0) {
                headerBar
                    .frame(height: header)
                TabView(selection: $selected) {
                    ForEach(metrics, id: \.self) { m in
                        EffortPortraitChart(
                            samples: samples, segments: segments,
                            targetPaceSecPerMile: targetPaceSecPerMile,
                            distanceLabel: distanceLabel, durationLabel: durationLabel,
                            metric: m, plotHeight: plotH,
                            paceZones: paceZones, hrZones: hrZones,
                            lapMarks: lapMarks, showLaps: showLaps,
                            watchSplits: watchSplits, showWatchSplits: showWatchSplits,
                            elevationGainFt: elevationGainFt,
                            showChrome: false, sharedScrubT: $scrubT, showXAxis: true,
                            holdToScrub: false)
                            .padding(.top, 6)
                            .tag(m)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .padding(.horizontal, 16)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .onAppear { EffortOrientation.set(.landscape) }
        .onDisappear { EffortOrientation.set(.portrait) }
        .sheet(isPresented: $showFixReps) {
            if let fr = fixReps {
                EditWorkoutStructureSheet(
                    workoutId: fr.workoutId, initialLaps: fr.laps,
                    initialIntent: fr.intent, onSaved: fr.onSaved)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("THE EFFORT")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)
            Text("\(distanceLabel) · \(durationLabel)")
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            // Metric selector — active metric highlighted; also swipeable.
            ForEach(metrics, id: \.self) { m in
                chip(shortLabel(m), on: selected == m) { selected = m }
            }
            if !watchSplits.isEmpty {
                chip("SPLITS", on: showWatchSplits) { showWatchSplits.toggle() }
            }
            if !lapMarks.isEmpty { chip("LAPS", on: showLaps) { showLaps.toggle() } }
            if fixReps != nil { chip("FIX REPS", on: false) { showFixReps = true } }
            chip("CLOSE", on: false) { dismiss() }
        }
    }

    private func shortLabel(_ m: EffortMetric) -> String {
        switch m {
        case .pace: return "PACE"
        case .hr:   return "HR"
        case .cad:  return "CAD"
        case .elev: return "ELEV"
        }
    }

    private func chip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dripEyebrow(9))
                .tracking(1.1)
                .foregroundStyle(on ? Color.drip.coral : Color.drip.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(on ? Color.drip.coral : Color.drip.divider,
                                          lineWidth: on ? 1.3 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Requests a landscape (or portrait) geometry for the presenting scene, even
/// under rotation lock. Mirrors the pattern proven in WeekStressClockSheet —
/// retried because the first attempt lands while the cover is still presenting.
///
/// The geometry request alone is not enough: the system re-evaluates it
/// against the cover's hosting controller, which supports portrait, so the
/// takeover could open (or be rotated back to) portrait. Narrowing
/// `AppDelegate.orientationMask` for the cover's lifetime is what makes
/// landscape the ONLY orientation while it is up.
enum EffortOrientation {
    @MainActor
    static func set(_ mask: UIInterfaceOrientationMask, retries: Int = 3) {
        AppDelegate.orientationMask = (mask == .landscape) ? .landscape : .all

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                        ?? scenes.first
        else { return }

        var top = scene.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }

        guard retries > 0 else { return }
        let wanted = mask == .landscape
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            let isLandscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
            if isLandscape != wanted { set(mask, retries: retries - 1) }
        }
    }
}

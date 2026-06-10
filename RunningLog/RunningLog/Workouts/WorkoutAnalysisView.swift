//
//  WorkoutAnalysisView.swift
//  RunningLog
//
//  Source-agnostic workout analysis view. Takes a RunningWorkout (from any
//  source — Strava, HealthKit, voice log, manual) and renders its stream data,
//  parsed structure, splits, charts, and route with pace-zone overlay.
//
//  If a parsed_structure exists, the hero shows the Observer's interpretation
//  ("5×1mi @ 5:19 • 10K @ 5:15"). Otherwise falls back to distance + avg pace.
//

import Charts
import CoreLocation
import MapKit
import os
import PostgREST
import Supabase
import SwiftUI

struct WorkoutAnalysisView: View {
    let workout: RunningWorkout

    @State private var bundle: ExternalStreamBundle?
    @State private var parsed: ParsedStructure?
    @State private var paceSegments: [PaceSegment] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // Workout type — user override of the AI-parsed type. nil = use parsed.type.
    @State private var workoutTypeRaw: String?
    @State private var isSavingType = false

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            // Always render header + stats. Rich cards below gated on data.
            ScrollView {
                VStack(spacing: 20) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    if isLoading {
                        HStack { Spacer(); ProgressView().tint(Color.drip.coral); Spacer() }
                            .padding(.vertical, 40)
                    }

                    // Stats — hero number (distance) + time + 5-stat shelf
                    HeroStatsCard(workout: workout, meta: bundle?.meta, stream: bundle?.stream)
                        .padding(.horizontal, 20)

                    // Session — user-editable workout type with AI fallback
                    WorkoutTypeSection(
                        userType: workoutTypeRaw,
                        parsedType: parsed?.type,
                        isSaving: isSavingType,
                        onSelect: { newType in
                            Task { await saveWorkoutType(newType) }
                        }
                    )
                    .padding(.horizontal, 20)

                    // Parsed structure hero (only when AI parse exists)
                    if let p = parsed {
                        ParsedStructureHero(parsed: p)
                            .padding(.horizontal, 20)
                    }

                    if !isLoading, bundle?.stream == nil, parsed == nil {
                        Text("No detailed sensor data for this workout yet.\nStream pull or AI parse hasn't run.")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }

                    // Splits — visual table with pace bars + HR
                    if !paceSegments.isEmpty {
                        SplitsTable(segments: paceSegments)
                            .expandable("Splits")
                            .padding(.horizontal, 20)
                    }

                    // PACE + ELEVATION overlay (two lines, shared axis)
                    if let s = bundle?.stream,
                       let vel = s.velocitySmooth, let alt = s.altitude,
                       vel.count == alt.count, vel.count >= 10 {
                        PaceElevationOverlay(velocities: vel, altitudes: alt, times: s.time)
                            .expandable("Pace + Elevation")
                            .padding(.horizontal, 20)
                    } else if let s = bundle?.stream, let vel = s.velocitySmooth, !vel.isEmpty {
                        PaceStreamCard(velocities: vel, times: s.time)
                            .expandable("Pace")
                            .padding(.horizontal, 20)
                    }

                    // HR
                    if let s = bundle?.stream, let hr = s.heartrate, !hr.isEmpty {
                        HRStreamCard(heartrates: hr, times: s.time)
                            .expandable("Heart Rate")
                            .padding(.horizontal, 20)
                    }

                    // CADENCE
                    if let s = bundle?.stream, let cad = s.cadence, cad.contains(where: { $0 > 0 }) {
                        CadenceStreamCard(cadences: cad, times: s.time)
                            .expandable("Cadence")
                            .padding(.horizontal, 20)
                    }

                    // GAP (grade-adjusted pace)
                    if let s = bundle?.stream,
                       let vel = s.velocitySmooth, let alt = s.altitude, let dist = s.distance,
                       vel.count == alt.count, alt.count == dist.count, vel.count >= 10 {
                        GAPStreamCard(velocities: vel, altitudes: alt, distances: dist, times: s.time)
                            .expandable("Grade-Adjusted Pace")
                            .padding(.horizontal, 20)
                    }

                    // PACE ZONES (stacked bar breakdown)
                    if let s = bundle?.stream, let vel = s.velocitySmooth, !vel.isEmpty {
                        PaceZonesCard(velocities: vel, times: s.time)
                            .expandable("Pace Zones")
                            .padding(.horizontal, 20)
                    }

                    // PACE ZONE ROUTE MAP — GPS route colored by pace zone
                    if let route = bundle?.route, !route.isEmpty,
                       let vel = bundle?.stream?.velocitySmooth, vel.count >= route.count {
                        PaceZoneRouteMap(route: route, velocities: vel)
                            .expandable("Route by Pace Zone")
                            .padding(.horizontal, 20)
                    } else if let route = bundle?.route, !route.isEmpty {
                        RouteMapCard(route: route)
                            .expandable("Route")
                            .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .task(id: workout.id) { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text(workout.startDate.formatted(.dateTime.weekday(.wide)))
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)

            Text(workout.startDate.formatted(.dateTime.month(.wide).day().year()))
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            SourceBadge(source: workout.sourceApp)
                .padding(.top, 4)
        }
    }

    // MARK: - Data Loading

    private func load() async {
        isLoading = true
        loadError = nil

        let loaded = await ExternalStreamAdapter.load(forTrainingLogId: workout.id)
        let parsedLoaded = await ParsedStructureLoader.load(forTrainingLogId: workout.id)
        let segments = await PaceSegmentsLoader.load(forTrainingLogId: workout.id)
        let wt = await loadWorkoutType()

        await MainActor.run {
            self.bundle = loaded
            self.parsed = parsedLoaded
            self.paceSegments = segments
            self.workoutTypeRaw = wt
            self.isLoading = false
            if loaded == nil && parsedLoaded == nil && segments.isEmpty {
                self.loadError = "No stream or parsed data available for this workout."
            }
        }
    }

    /// Read training_logs.workout_type for this workout.
    private func loadWorkoutType() async -> String? {
        struct Row: Decodable { let workout_type: String? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("workout_type")
                .eq("id", value: workout.id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first?.workout_type ?? nil
        } catch {
            Log.app.error("loadWorkoutType failed: \(error)")
            return nil
        }
    }

    /// Persist a user-chosen workout_type. Overrides any AI-parsed value.
    private func saveWorkoutType(_ type: String) async {
        await MainActor.run { isSavingType = true }
        do {
            let payload: [String: AnyJSON] = ["workout_type": .string(type)]
            try await supabase
                .from("training_logs")
                .update(payload)
                .eq("id", value: workout.id.uuidString)
                .execute()
            await MainActor.run {
                workoutTypeRaw = type
                isSavingType = false
            }
        } catch {
            Log.app.error("saveWorkoutType failed: \(error)")
            await MainActor.run { isSavingType = false }
        }
    }
}

// MARK: - Workout Type Section

/// Session type card with chip-strip picker. User selection overrides the
/// AI-parsed type; while no user selection exists, the parsed type is shown
/// with an "AI" badge.
private struct WorkoutTypeSection: View {
    let userType: String?
    let parsedType: String?
    let isSaving: Bool
    let onSelect: (String) -> Void

    /// Canonical type vocabulary. Slugs match `parsed_structure.type` values
    /// where possible (`long_run`, `easy`, `tempo`, `interval`, `progression`,
    /// `race`, `recovery`) plus `steady` (not produced by the parser yet but
    /// part of the user-facing vocabulary).
    private static let allTypes: [(slug: String, label: String, icon: String)] = [
        ("long_run", "Long Run", "figure.walk.motion"),
        ("easy", "Easy", "leaf.fill"),
        ("steady", "Steady", "figure.run"),
        ("tempo", "Tempo", "speedometer"),
        ("interval", "Intervals", "repeat.circle.fill"),
        ("progression", "Progression", "chart.line.uptrend.xyaxis"),
        ("race", "Race", "trophy.fill"),
        ("recovery", "Recovery", "moon.stars.fill"),
    ]

    /// Effective type used to drive the icon + label. User override wins.
    private var effectiveSlug: String? {
        userType ?? parsedType
    }

    private var effective: (slug: String, label: String, icon: String)? {
        guard let s = effectiveSlug else { return nil }
        return Self.allTypes.first(where: { $0.slug == s })
    }

    private var isFromAI: Bool {
        userType == nil && parsedType != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — small caps + thin warm rule (matches SectionHeader pattern)
            HStack {
                Text("SESSION")
                    .font(.dripCaption(11))
                    .tracking(1.5)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text(effective == nil ? "TAP TO SET" : "TAP TO CHANGE")
                    .font(.dripCaption(10))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
                .padding(.horizontal, 4)
                .padding(.bottom, 12)

            // Card — current selection
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: effective?.icon ?? "questionmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(effective?.label ?? "Choose a session type")
                            .font(.dripLabel(17))
                            .foregroundStyle(Color.drip.textPrimary)
                        if isFromAI {
                            Text("AI")
                                .font(.dripCaption(9))
                                .tracking(0.5)
                                .foregroundStyle(Color.drip.coral)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.drip.coral.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                    Text(isFromAI
                        ? "Detected from your run · tap a tag to override"
                        : (effective == nil ? "No session type yet" : "Tap a tag below to change"))
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                Spacer()
                if isSaving {
                    ProgressView().tint(Color.drip.coral).scaleEffect(0.75)
                }
            }
            .padding(14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Chip strip — horizontal scroll to fit 8 chips on narrow screens
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.allTypes, id: \.slug) { type in
                        let isSelected = effectiveSlug == type.slug
                        Button {
                            onSelect(type.slug)
                        } label: {
                            Text(type.label)
                                .font(.dripCaption(12))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isSelected ? Color.drip.electric : Color.drip.textSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected
                                        ? Color.drip.coral.opacity(0.10)
                                        : Color.drip.textTertiary.opacity(0.08)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.drip.coral.opacity(0.30) : Color.clear, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }
        }
    }
}

// MARK: - Hero Stats Card

/// Editorial stats card: distance as the hero number, time prominent,
/// then a 5-column shelf — Avg Pace · GAP · Avg HR · Cadence · Elev.
private struct HeroStatsCard: View {
    let workout: RunningWorkout
    let meta: StreamMeta?
    let stream: VitalWorkoutStream?

    private var distanceText: String {
        String(format: "%.2f", workout.distanceMiles)
    }

    /// Avg pace without trailing unit ("6:49"). The shelf adds context via label.
    private var avgPaceText: String {
        workout.formattedPace.replacingOccurrences(of: " /mi", with: "")
    }

    /// Grade-adjusted pace — same polynomial Strava uses, averaged over the run.
    private var avgGapText: String? {
        guard let stream,
              let vel = stream.velocitySmooth,
              let alt = stream.altitude,
              let dist = stream.distance,
              vel.count == alt.count, alt.count == dist.count, vel.count >= 10
        else { return nil }
        let window = 5
        var paces: [Double] = []
        for i in window..<vel.count {
            let v = vel[i]
            guard v > 0.3 else { continue }
            let dAlt = alt[i] - alt[i - window]
            let dDist = max(dist[i] - dist[i - window], 1)
            let grade = dAlt / dDist
            let mult = 1 + grade * 3.3 + grade * grade * 15
            let pace = 1609.34 / v
            paces.append(pace / max(mult, 0.7))
        }
        guard !paces.isEmpty else { return nil }
        let avg = paces.reduce(0, +) / Double(paces.count)
        return paceString(secPerMile: Int(avg))
    }

    /// Cadence — Strava reports single-leg, double for spm. Filter junk (<30).
    private var cadenceText: String? {
        guard let cads = stream?.cadence else { return nil }
        let valid = cads.filter { $0 > 30 }
        guard !valid.isEmpty else { return nil }
        let avg = (valid.reduce(0, +) / Double(valid.count)) * 2
        return "\(Int(avg.rounded()))"
    }

    private var avgHrText: String? {
        meta?.averageHr.map { "\($0)" }
    }

    private var elevText: String? {
        meta?.totalElevationGain.map { "\(Int(($0 * 3.28084).rounded()))" }
    }

    /// Build the shelf from only the stats we actually have. Empty cells were
    /// crowding the row with "—" placeholders; the shelf now collapses to
    /// however many real stats exist and breathes accordingly.
    private struct ShelfItem: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        let unit: String?
        let accent: Color
    }

    private var shelfItems: [ShelfItem] {
        var items: [ShelfItem] = [
            ShelfItem(value: avgPaceText, label: "AVG PACE", unit: nil, accent: Color.drip.textPrimary)
        ]
        if let gap = avgGapText {
            items.append(ShelfItem(value: gap, label: "GAP", unit: nil, accent: Color.drip.textPrimary))
        }
        if let hr = avgHrText {
            items.append(ShelfItem(value: hr, label: "AVG HR", unit: nil, accent: Color.drip.struggling))
        }
        if let cad = cadenceText {
            items.append(ShelfItem(value: cad, label: "CADENCE", unit: nil, accent: Color.drip.textPrimary))
        }
        if let elev = elevText {
            items.append(ShelfItem(value: elev, label: "ELEV", unit: "ft", accent: Color.drip.energized))
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero row — distance on the left (large), time on the right
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DISTANCE")
                        .font(.dripCaption(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(distanceText)
                            .font(.system(size: 38, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("mi")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("TIME")
                        .font(.dripCaption(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(workout.formattedDuration)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.drip.textPrimary)
                }
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)

            // Shelf — only the stats we actually have. No "—" placeholders.
            let items = shelfItems
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    ShelfStat(value: item.value, label: item.label, unit: item.unit, accent: item.accent)
                    if idx < items.count - 1 {
                        ShelfDivider()
                    }
                }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ShelfStat: View {
    let value: String
    let label: String
    let unit: String?
    let accent: Color

    init(value: String, label: String, unit: String? = nil, accent: Color = Color.drip.textPrimary) {
        self.value = value
        self.label = label
        self.unit = unit
        self.accent = accent
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                if let unit {
                    Text(unit)
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            Text(label)
                .font(.dripCaption(9))
                .tracking(1)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShelfDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(width: 1, height: 24)
    }
}

// MARK: - Splits Table

private struct SplitsTable: View {
    let segments: [PaceSegment]

    private var paceRange: (fastest: Int, slowest: Int) {
        let secs = segments.compactMap { Self.paceToSec($0.pacePerMile) }.filter { $0 > 0 }
        guard !secs.isEmpty else { return (300, 600) }
        return (secs.min()!, secs.max()!)
    }

    private var hrRange: (min: Int, max: Int)? {
        let hrs = segments.compactMap(\.avgHeartRate)
        guard !hrs.isEmpty else { return nil }
        return (hrs.min()!, hrs.max()!)
    }

    var body: some View {
        let pace = paceRange
        let fastestSec = pace.fastest
        let slowestSec = pace.slowest

        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("SPLITS")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("fastest \(fmt(fastestSec))  •  slowest \(fmt(slowestSec))")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Column headers
            HStack(spacing: 0) {
                Text("MI").frame(width: 26, alignment: .leading)
                Text("DIST").frame(width: 56, alignment: .leading)
                Spacer()
                Text("PACE")
                    .frame(width: 86, alignment: .trailing)
                    .padding(.trailing, 14)
                Text("HR").frame(width: 40, alignment: .trailing)
            }
            .font(.dripCaption(10))
            .tracking(0.8)
            .foregroundStyle(Color.drip.textTertiary)

            // Rows
            VStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                    PaceSegmentSplitRow(
                        index: idx + 1,
                        segment: seg,
                        fastestSec: fastestSec,
                        slowestSec: slowestSec,
                        isFastest: Self.paceToSec(seg.pacePerMile) == fastestSec
                    )
                    if idx < segments.count - 1 {
                        Divider().padding(.leading, 4)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static func paceToSec(_ p: String) -> Int {
        let parts = p.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    private func fmt(_ sec: Int) -> String {
        guard sec > 0 else { return "—" }
        return "\(sec / 60):\(String(format: "%02d", sec % 60))/mi"
    }
}

private struct PaceSegmentSplitRow: View {
    let index: Int
    let segment: PaceSegment
    let fastestSec: Int
    let slowestSec: Int
    let isFastest: Bool

    var body: some View {
        let paceSec = paceToSec(segment.pacePerMile)
        let widthFraction = barFraction(paceSec: paceSec)
        let barColor = color(forPace: paceSec)

        VStack(spacing: 6) {
            HStack(spacing: 0) {
                // Mile badge
                ZStack {
                    Circle()
                        .fill(isFastest ? Color.drip.coral : Color.drip.textTertiary.opacity(0.15))
                        .frame(width: 22, height: 22)
                    Text("\(index)")
                        .font(.dripLabel(11))
                        .foregroundStyle(isFastest ? .white : Color.drip.textSecondary)
                }
                .frame(width: 26, alignment: .leading)

                Text(String(format: "%.2fmi", segment.distanceMiles))
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 56, alignment: .leading)

                Spacer()

                Text(segment.pacePerMile + "/mi")
                    .font(.dripLabel(14))
                    .foregroundStyle(isFastest ? Color.drip.coral : Color.drip.textPrimary)
                    .frame(width: 86, alignment: .trailing)
                    .padding(.trailing, 14)

                if let hr = segment.avgHeartRate {
                    Text("\(hr)")
                        .font(.dripStat(12))
                        .foregroundStyle(Color.drip.struggling)
                        .frame(width: 40, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            // Visual pace bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.drip.textTertiary.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(8, geo.size.width * widthFraction), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.leading, 26)
        }
        .padding(.vertical, 8)
    }

    private func paceToSec(_ p: String) -> Int {
        let parts = p.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// Fraction of the bar to fill — fastest mile = full, slowest = ~25%.
    private func barFraction(paceSec: Int) -> CGFloat {
        guard paceSec > 0, slowestSec > fastestSec else { return 1 }
        let span = CGFloat(slowestSec - fastestSec)
        let from = CGFloat(paceSec - fastestSec)
        // Inverted: fast pace (low number) → high fraction
        return max(0.25, 1.0 - (from / span) * 0.75)
    }

    private func color(forPace paceSec: Int) -> Color {
        guard paceSec > 0, slowestSec > fastestSec else { return Color.drip.coral }
        let t = Double(paceSec - fastestSec) / Double(slowestSec - fastestSec)
        if t < 0.33 { return Color.drip.coral }
        if t < 0.66 { return .orange }
        return Color.green.opacity(0.7)
    }
}

// MARK: - Expand + zoom wrapper

/// Generic tap-to-expand modifier. Any view it's applied to becomes tappable;
/// tapping opens a fullscreen sheet with pinch-to-zoom + drag-to-pan over the
/// same content rendered larger.
private struct ExpandToZoom: ViewModifier {
    let title: String
    @State private var showExpanded = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(20)
            }
            .contentShape(Rectangle())
            .onTapGesture { showExpanded = true }
            .sheet(isPresented: $showExpanded) {
                ZoomableChartSheet(title: title) { content }
            }
    }
}

extension View {
    fileprivate func expandable(_ title: String) -> some View {
        modifier(ExpandToZoom(title: title))
    }
}

/// Fullscreen sheet that renders any chart content with pinch-zoom + drag-pan.
/// Double-tap to reset.
private struct ZoomableChartSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    content()
                        .frame(minWidth: (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390 - 32)
                        .padding(16)
                        .scaleEffect(scale, anchor: .center)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(0.5, min(4.0, lastScale * value))
                                    }
                                    .onEnded { _ in lastScale = scale },
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Pinch to zoom · Double-tap to reset")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Chart Cards

private struct ChartCardHeader: View {
    let title: String
    let icon: String
    let iconColor: Color
    let trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.dripCaption(11))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.dripLabel(12))
                    .foregroundStyle(Color.drip.textPrimary)
            }
        }
    }
}

private func paceString(secPerMile: Int) -> String {
    let m = secPerMile / 60
    let s = secPerMile % 60
    return String(format: "%d:%02d", m, s)
}

private func paceSecFromMps(_ mps: Double) -> Int {
    guard mps > 0.2 else { return 0 }
    return Int((1609.34 / mps).rounded())
}

// PACE STREAM ── line chart of pace over time
private struct PaceStreamCard: View {
    let velocities: [Double]
    let times: [Int]?

    var body: some View {
        let points: [(t: Double, pace: Double)] = velocities.enumerated().compactMap { i, v in
            guard v > 0.3 else { return nil }
            let t = (times?[safe: i]).map(Double.init) ?? Double(i)
            return (t, 1609.34 / v) // sec/mile
        }
        let yRange: ClosedRange<Double>? = {
            guard !points.isEmpty else { return nil }
            let ps = points.map(\.pace)
            return (ps.min()! * 0.92)...(ps.max()! * 1.05)
        }()
        let avgPace = points.isEmpty ? 0 : points.map(\.pace).reduce(0,+) / Double(points.count)

        VStack(alignment: .leading, spacing: 12) {
            ChartCardHeader(
                title: "PACE",
                icon: "speedometer",
                iconColor: Color.drip.coral,
                trailing: avgPace > 0 ? "avg \(paceString(secPerMile: Int(avgPace)))" : nil
            )
            Chart(points, id: \.t) { p in
                LineMark(x: .value("t", p.t), y: .value("pace", p.pace))
                    .foregroundStyle(Color.drip.coral)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: (yRange ?? 300...600), type: .linear)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisValueLabel {
                        if let s = v.as(Double.self) { Text(paceString(secPerMile: Int(s))) }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// HR STREAM — line chart + zone bands + stats row
private struct HRStreamCard: View {
    let heartrates: [Int]
    let times: [Int]?

    private var stats: (avg: Int, max: Int, min: Int) {
        let nonzero = heartrates.filter { $0 > 0 }
        guard !nonzero.isEmpty else { return (0, 0, 0) }
        let avg = nonzero.reduce(0, +) / nonzero.count
        return (avg, nonzero.max()!, nonzero.min()!)
    }

    var body: some View {
        let s = stats
        // User max HR for zones (default 190; use AppStorage in real read)
        let maxHR = max(190, s.max + 5)
        let z1 = Double(maxHR) * 0.60   // recovery
        let z2 = Double(maxHR) * 0.70   // endurance
        let z3 = Double(maxHR) * 0.80   // tempo
        let z4 = Double(maxHR) * 0.90   // threshold
        let z5 = Double(maxHR)          // VO2

        let points: [(t: Double, hr: Double)] = heartrates.enumerated().compactMap { i, h in
            guard h > 0 else { return nil }
            let t = (times?[safe: i]).map(Double.init) ?? Double(i)
            return (t, Double(h))
        }
        let yMin = max(80, Double(s.min) - 10)
        let yMax = max(z5, Double(s.max) + 5)

        VStack(alignment: .leading, spacing: 14) {
            ChartCardHeader(
                title: "HEART RATE",
                icon: "heart.fill",
                iconColor: .red,
                trailing: nil
            )

            // Stats row — clean, scannable
            HStack(spacing: 0) {
                HRStatBlock(label: "AVG", value: "\(s.avg)", color: .red)
                Divider().frame(height: 32)
                HRStatBlock(label: "MAX", value: "\(s.max)", color: .red.opacity(0.85))
                Divider().frame(height: 32)
                HRStatBlock(label: "MIN", value: "\(s.min)", color: .red.opacity(0.55))
            }

            // Chart with zone bands
            Chart {
                // Zone bands as background rectangles
                RectangleMark(yStart: .value("Z1 lo", yMin), yEnd: .value("Z1 hi", z1))
                    .foregroundStyle(Color.gray.opacity(0.08))
                RectangleMark(yStart: .value("Z2 lo", z1), yEnd: .value("Z2 hi", z2))
                    .foregroundStyle(Color.green.opacity(0.10))
                RectangleMark(yStart: .value("Z3 lo", z2), yEnd: .value("Z3 hi", z3))
                    .foregroundStyle(Color.yellow.opacity(0.10))
                RectangleMark(yStart: .value("Z4 lo", z3), yEnd: .value("Z4 hi", z4))
                    .foregroundStyle(Color.orange.opacity(0.12))
                RectangleMark(yStart: .value("Z5 lo", z4), yEnd: .value("Z5 hi", z5))
                    .foregroundStyle(Color.red.opacity(0.12))

                // HR line (gradient)
                ForEach(points, id: \.t) { p in
                    LineMark(x: .value("t", p.t), y: .value("hr", p.hr))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.red, Color.red.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }

                // Avg line
                RuleMark(y: .value("avg", Double(s.avg)))
                    .foregroundStyle(Color.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .leading, alignment: .leading) {
                        Text("avg \(s.avg)")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.red.opacity(0.6))
                            .padding(.trailing, 4)
                    }
            }
            .chartYScale(domain: yMin...yMax)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 20)) { v in
                    AxisGridLine().foregroundStyle(Color.drip.textTertiary.opacity(0.15))
                    AxisValueLabel().font(.dripCaption(9))
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 160)

            // Zone legend
            HStack(spacing: 8) {
                ZoneChip(label: "Z1", color: .gray)
                ZoneChip(label: "Z2", color: .green)
                ZoneChip(label: "Z3", color: .yellow)
                ZoneChip(label: "Z4", color: .orange)
                ZoneChip(label: "Z5", color: .red)
            }
            .font(.dripCaption(10))
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct HRStatBlock: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dripDisplay(20))
                .foregroundStyle(color)
            Text(label)
                .font(.dripCaption(10))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ZoneChip: View {
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(color.opacity(0.4)).frame(width: 10, height: 10).cornerRadius(2)
            Text(label).foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// GAP ── Grade Adjusted Pace using Strava's polynomial approximation
// GAP multiplier ≈ 1 + grade*3.3 + grade^2*15 (grade as fraction)
private struct GAPStreamCard: View {
    let velocities: [Double]
    let altitudes: [Double]
    let distances: [Double]
    let times: [Int]?

    private var points: [(t: Double, gap: Double)] {
        let n = min(velocities.count, altitudes.count, distances.count)
        var out: [(t: Double, gap: Double)] = []
        let window = 5
        for i in window..<n {
            let v = velocities[i]
            guard v > 0.3 else { continue }
            let dAlt = altitudes[i] - altitudes[i - window]
            let dDist = max(distances[i] - distances[i - window], 1)
            let grade = dAlt / dDist
            let flatMultiplier = 1 + grade * 3.3 + grade * grade * 15
            let pace = 1609.34 / v
            let gap = pace / max(flatMultiplier, 0.7)
            let t = (times?[safe: i]).map(Double.init) ?? Double(i)
            out.append((t, gap))
        }
        return out
    }

    var body: some View {
        let points = self.points
        let avgGap = points.isEmpty ? 0 : points.map(\.gap).reduce(0,+) / Double(points.count)
        let yMin = (points.map(\.gap).min() ?? 300) * 0.92
        let yMax = (points.map(\.gap).max() ?? 600) * 1.05

        VStack(alignment: .leading, spacing: 12) {
            ChartCardHeader(
                title: "GRADE-ADJUSTED PACE",
                icon: "arrow.up.and.down.righttriangle.up.righttriangle.down.fill",
                iconColor: .purple,
                trailing: avgGap > 0 ? "avg \(paceString(secPerMile: Int(avgGap)))" : nil
            )
            Chart(points, id: \.t) { p in
                LineMark(x: .value("t", p.t), y: .value("gap", p.gap))
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: yMin...yMax)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisValueLabel {
                        if let s = v.as(Double.self) { Text(paceString(secPerMile: Int(s))) }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// PACE ZONES ── horizontal stacked bar: % time in each app-defined zone
private struct PaceZonesCard: View {
    let velocities: [Double]
    let times: [Int]?

    private var rows: [(name: String, fraction: Double, color: Color)] {
        let zoneList = PaceZoneDefaults.current().bands
        var bins: [String: Double] = [:]
        var total = 0.0
        for (i, v) in velocities.enumerated() {
            guard v > 0.3 else { continue }
            let paceSec = 1609.34 / v
            let dt: Double
            if let times, times.count > i + 1 {
                dt = Double(times[i + 1] - times[i])
            } else {
                dt = 1
            }
            total += dt
            var assigned = "Recovery"
            var bestThresh = Double.infinity
            for (name, threshold, _) in zoneList {
                if paceSec <= threshold && threshold < bestThresh {
                    assigned = name
                    bestThresh = threshold
                }
            }
            bins[assigned, default: 0] += dt
        }
        return zoneList.map { (name, _, color) in
            let v = bins[name] ?? 0
            return (name, total > 0 ? v / total : 0, color)
        }.filter { $0.1 > 0.002 }
    }

    var body: some View {
        let rows = self.rows
        return VStack(alignment: .leading, spacing: 12) {
            ChartCardHeader(
                title: "PACE ZONES",
                icon: "chart.bar.fill",
                iconColor: Color.drip.coral,
                trailing: nil
            )
            // Horizontal stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(rows, id: \.0) { r in
                        Rectangle()
                            .fill(r.2)
                            .frame(width: max(geo.size.width * r.1, 1))
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)

            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Circle().fill(r.2).frame(width: 8, height: 8)
                        Text(r.0).font(.dripCaption(12)).foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        Text(String(format: "%.0f%%", r.1 * 100))
                            .font(.dripLabel(12))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Full pace ladder anchored to the user's 10K pace (in sec/mi). Uses Riegel-ish
/// ratios to derive every distance from a single anchor. All bands ordered
/// slowest → fastest for stacked display.
private struct PaceZoneDefaults {
    let easy: Double      // ~10K * 1.40
    let moderate: Double  // ~10K * 1.30
    let steady: Double    // ~10K * 1.20
    let mp: Double        // marathon
    let hmp: Double       // half marathon
    let tenK: Double
    let fiveK: Double
    let threeK: Double
    let mile: Double

    /// Ordered slowest → fastest. Each entry: (label, threshold pace sec/mi, color)
    var bands: [(String, Double, Color)] {
        [
            ("Recovery", easy + 60, Color.gray.opacity(0.6)),
            ("Easy", easy, Color.green.opacity(0.55)),
            ("Moderate", moderate, Color(red: 0.5, green: 0.75, blue: 0.4)),
            ("Steady", steady, Color.yellow.opacity(0.7)),
            ("MP", mp, Color.orange.opacity(0.7)),
            ("HMP", hmp, Color.orange),
            ("10K", tenK, Color(red: 0.95, green: 0.45, blue: 0.30)),
            ("5K", fiveK, Color.red.opacity(0.85)),
            ("3K", threeK, Color.red),
            ("Mile", mile, Color(red: 0.7, green: 0.1, blue: 0.5)),
        ]
    }

    static func current() -> PaceZoneDefaults {
        // Anchor: user's 10K pace (sec/mi). TODO: read from athlete_state instead
        // of hardcoding when we wire this to the live predictor.
        let tenK: Double = 319

        // Distance paces from Riegel-style equivalence (consistent with PaceCalculator's ratios)
        let mp = tenK * 1.12       // marathon
        let hmp = tenK * 1.06      // half
        let fiveK = tenK * 0.97
        let threeK = tenK * 0.95
        let mile = tenK * 0.94

        // Easy / Moderate / Steady — derived from MP using PaceCalculator's effort
        // ratios (Easy = MP/0.75, Moderate top = MP/0.85, Steady top = MP/0.95).
        // Threshold values define the FAST edge of each band — slower paces fall
        // into the slower band.
        let easy = mp / 0.75       // ~slowest aerobic
        let moderate = mp / 0.85   // moderate effort cap
        let steady = mp / 0.95     // steady effort cap (just below MP)

        return PaceZoneDefaults(
            easy: easy,
            moderate: moderate,
            steady: steady,
            mp: mp,
            hmp: hmp,
            tenK: tenK,
            fiveK: fiveK,
            threeK: threeK,
            mile: mile
        )
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}

// MARK: - Splits Bar Chart

private struct SplitsBarChart: View {
    let segments: [PaceSegment]

    private var paceRange: (min: Double, max: Double) {
        let paces = segments.compactMap { Self.paceStringToSeconds($0.pacePerMile) }
        guard !paces.isEmpty else { return (300, 600) }
        return (paces.min()! * 0.92, paces.max()! * 1.05)
    }

    var body: some View {
        let range = paceRange
        VStack(alignment: .leading, spacing: 12) {
            ChartCardHeader(
                title: "SPLITS",
                icon: "chart.bar.fill",
                iconColor: Color.drip.coral,
                trailing: "\(segments.count) mile\(segments.count == 1 ? "" : "s")"
            )
            Chart(Array(segments.enumerated()), id: \.offset) { idx, seg in
                let paceSec = Self.paceStringToSeconds(seg.pacePerMile)
                BarMark(
                    x: .value("Split", idx + 1),
                    y: .value("Pace", paceSec)
                )
                .foregroundStyle(Self.color(forPace: paceSec, range: range))
                .annotation(position: .top) {
                    Text(seg.pacePerMile)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            // Swift Charts requires lowerBound <= upperBound, so domain stays
            // min...max. Bars naturally read "taller = slower mile" which is the
            // conventional split-chart semantic.
            .chartYScale(domain: range.min...range.max)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisValueLabel {
                        if let s = v.as(Double.self) { Text(paceString(secPerMile: Int(s))) }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .stride(by: 1)) { v in
                    AxisValueLabel { if let i = v.as(Int.self) { Text("\(i)") } }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static func paceStringToSeconds(_ p: String) -> Double {
        let parts = p.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return Double(parts[0] * 60 + parts[1])
    }

    private static func color(forPace pace: Double, range: (min: Double, max: Double)) -> Color {
        // Fastest mile = coral/red, slowest = muted
        guard range.max > range.min else { return Color.drip.coral }
        let t = (pace - range.min) / (range.max - range.min)
        if t < 0.33 { return Color.drip.coral }
        if t < 0.66 { return Color.orange }
        return Color.green.opacity(0.7)
    }
}

// MARK: - Pace + Elevation Overlay

private struct PaceElevationOverlay: View {
    let velocities: [Double]
    let altitudes: [Double]
    let times: [Int]?

    private var points: [(t: Double, pace: Double, alt: Double)] {
        let n = min(velocities.count, altitudes.count)
        var out: [(t: Double, pace: Double, alt: Double)] = []
        for i in 0..<n {
            let v = velocities[i]
            guard v > 0.3 else { continue }
            let t = (times?[safe: i]).map(Double.init) ?? Double(i)
            out.append((t, 1609.34 / v, altitudes[i]))
        }
        return out
    }

    var body: some View {
        let pts = points
        let paces = pts.map(\.pace)
        let alts = pts.map(\.alt)
        let avgPace = paces.isEmpty ? 0 : Int(paces.reduce(0, +) / Double(paces.count))
        let fastestPace = paces.isEmpty ? 0 : Int(paces.min()!)
        let elevGainFt = computeElevGainFt(alts)
        let paceMin = (paces.min() ?? 300) * 0.92
        let paceMax = (paces.max() ?? 600) * 1.05
        let altMin = (alts.min() ?? 0) - 5
        let _ = (alts.max() ?? 100) + 5

        VStack(alignment: .leading, spacing: 14) {
            ChartCardHeader(
                title: "PACE + ELEVATION",
                icon: "chart.xyaxis.line",
                iconColor: Color.drip.coral,
                trailing: nil
            )

            // Stats row
            HStack(spacing: 0) {
                StatBlock(label: "AVG PACE", value: paceString(secPerMile: avgPace) + "/mi", color: Color.drip.coral)
                Divider().frame(height: 32)
                StatBlock(label: "FASTEST", value: paceString(secPerMile: fastestPace) + "/mi", color: Color.drip.coral.opacity(0.7))
                Divider().frame(height: 32)
                StatBlock(label: "ELEV GAIN", value: "\(elevGainFt) ft", color: .green)
            }

            // Chart — gradient elevation under, gradient pace line over
            Chart {
                ForEach(pts, id: \.t) { p in
                    AreaMark(
                        x: .value("t", p.t),
                        yStart: .value("base", altMin),
                        yEnd: .value("alt", p.alt)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.30), Color.green.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }
                ForEach(pts, id: \.t) { p in
                    LineMark(x: .value("t", p.t), y: .value("pace", p.pace))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.drip.coral, Color.drip.coral.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                RuleMark(y: .value("avg", Double(avgPace)))
                    .foregroundStyle(Color.drip.coral.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: paceMin...paceMax)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Color.drip.textTertiary.opacity(0.15))
                    AxisValueLabel {
                        if let s = v.as(Double.self) { Text(paceString(secPerMile: Int(s))) }
                    }
                    .font(.dripCaption(9))
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 160)

            HStack(spacing: 16) {
                LegendItem(color: Color.drip.coral, label: "Pace")
                LegendItem(color: .green.opacity(0.5), label: "Elevation")
            }
            .font(.dripCaption(10))
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Sum of positive altitude gains, converted to feet.
    private func computeElevGainFt(_ alts: [Double]) -> Int {
        var gain: Double = 0
        for i in 1..<alts.count {
            let d = alts[i] - alts[i - 1]
            if d > 0 { gain += d }
        }
        return Int(gain * 3.28084)
    }
}

private struct StatBlock: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(color)
            Text(label)
                .font(.dripCaption(10))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - Cadence Stream Card

private struct CadenceStreamCard: View {
    let cadences: [Double]
    let times: [Int]?

    var body: some View {
        let points: [(t: Double, cad: Double)] = cadences.enumerated().compactMap { i, c in
            guard c > 30 else { return nil } // cadence < 30 spm is invalid
            let t = (times?[safe: i]).map(Double.init) ?? Double(i)
            // Strava reports single-leg cadence; double for spm (steps per minute)
            return (t, c * 2)
        }
        let avg = points.isEmpty ? 0 : points.map(\.cad).reduce(0, +) / Double(points.count)
        let yMin = (points.map(\.cad).min() ?? 140) - 5
        let yMax = (points.map(\.cad).max() ?? 190) + 5

        VStack(alignment: .leading, spacing: 12) {
            ChartCardHeader(
                title: "CADENCE",
                icon: "figure.run",
                iconColor: .blue,
                trailing: avg > 0 ? "avg \(Int(avg)) spm" : nil
            )
            Chart(points, id: \.t) { p in
                LineMark(x: .value("t", p.t), y: .value("cad", p.cad))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: yMin...yMax)
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Pace Zone Route Map (GPS route colored by pace zone)

private struct PaceZoneRouteMap: View {
    let route: [CLLocation]
    let velocities: [Double]

    var body: some View {
        let zones = PaceZoneDefaults.current()
        VStack(alignment: .leading, spacing: 12) {
            ChartCardHeader(
                title: "ROUTE BY PACE ZONE",
                icon: "map.fill",
                iconColor: Color.drip.coral,
                trailing: nil
            )
            PaceZoneMapRepresentable(route: route, velocities: velocities, zones: zones)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Legend
            HStack(spacing: 12) {
                LegendDot(color: .gray, label: "Recovery")
                LegendDot(color: .green, label: "Easy")
                LegendDot(color: .yellow, label: "Moderate")
                LegendDot(color: .orange, label: "Steady")
                LegendDot(color: .red, label: "MP+")
            }
            .font(.dripCaption(10))
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Color.drip.textSecondary)
        }
    }
}

private struct PaceZoneMapRepresentable: UIViewRepresentable {
    let route: [CLLocation]
    let velocities: [Double]
    let zones: PaceZoneDefaults

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.showsUserLocation = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard route.count >= 2 else { return }

        // Build colored segments — each 2 consecutive points = one segment, colored by pace
        let n = min(route.count, velocities.count)
        var currentColor: UIColor = .systemGray
        var currentCoords: [CLLocationCoordinate2D] = [route[0].coordinate]

        for i in 1..<n {
            let v = velocities[i]
            let paceSec = v > 0.3 ? 1609.34 / v : 0
            let color = colorForPace(paceSec, zones: zones)
            if color == currentColor {
                currentCoords.append(route[i].coordinate)
            } else {
                // flush current segment
                if currentCoords.count >= 2 {
                    let line = ColoredPolyline(coordinates: currentCoords, count: currentCoords.count)
                    line.color = currentColor
                    map.addOverlay(line)
                }
                currentCoords = [route[i - 1].coordinate, route[i].coordinate]
                currentColor = color
            }
        }
        if currentCoords.count >= 2 {
            let line = ColoredPolyline(coordinates: currentCoords, count: currentCoords.count)
            line.color = currentColor
            map.addOverlay(line)
        }

        // Fit to route
        let coords = route.map(\.coordinate)
        let rect = coords.reduce(MKMapRect.null) { acc, c in
            let point = MKMapPoint(c)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            return acc.union(pointRect)
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? ColoredPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = line.color
                r.lineWidth = 4
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    private func colorForPace(_ paceSec: Double, zones: PaceZoneDefaults) -> UIColor {
        if paceSec <= 0 { return .systemGray }
        if paceSec <= zones.mp - 30 { return .systemRed }         // HMP+ (very fast)
        if paceSec <= zones.mp { return .systemRed }              // MP
        if paceSec <= zones.steady { return .systemOrange }       // Steady
        if paceSec <= zones.moderate { return .systemYellow }     // Moderate
        if paceSec <= zones.easy { return .systemGreen }          // Easy
        return .systemGray                                        // Recovery
    }
}

class ColoredPolyline: MKPolyline {
    var color: UIColor = .systemGray
}

// MARK: - Pace Segments Loader

enum PaceSegmentsLoader {
    static func load(forTrainingLogId id: UUID) async -> [PaceSegment] {
        struct Row: Decodable {
            let pace_segments: [PaceSegment]?
        }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("pace_segments")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first?.pace_segments ?? []
        } catch {
            Log.app.error("PaceSegmentsLoader: \(error)")
            return []
        }
    }
}

// MARK: - Parsed Structure Hero

private struct ParsedStructureHero: View {
    let parsed: ParsedStructure

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text(parsed.type.uppercased())
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                ConfidenceBadge(value: parsed.confidence)
            }

            if let pattern = parsed.pattern {
                Text(pattern)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            if let eq = parsed.equivalentRacePace {
                Divider()
                HStack {
                    Text("Equivalent")
                        .font(.dripCaption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Text("\(eq.distanceKey.uppercased()) @ \(eq.pacePerMile)/mi")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                if let reason = eq.reasoning, !reason.isEmpty {
                    Text(reason)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(3)
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var iconName: String {
        switch parsed.type.lowercased() {
        case "interval": return "repeat.circle.fill"
        case "tempo": return "speedometer"
        case "long_run": return "figure.walk.motion"
        case "progression": return "chart.line.uptrend.xyaxis"
        case "race": return "trophy.fill"
        case "easy", "recovery": return "leaf.fill"
        default: return "figure.run"
        }
    }
}

private struct ConfidenceBadge: View {
    let value: Double
    var body: some View {
        let pct = Int((value * 100).rounded())
        let color: Color = value >= 0.8 ? .green : value >= 0.6 ? .orange : .gray
        return Text("\(pct)%")
            .font(.dripCaption(11))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Parsed Structure Loader

enum ParsedStructureLoader {
    static func load(forTrainingLogId id: UUID) async -> ParsedStructure? {
        struct Row: Decodable {
            let parsed_structure: ParsedStructure?
        }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("parsed_structure")
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first?.parsed_structure ?? nil
        } catch {
            Log.app.error("ParsedStructureLoader: \(error)")
            return nil
        }
    }
}

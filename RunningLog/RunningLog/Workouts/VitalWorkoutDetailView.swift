//
//  VitalWorkoutDetailView.swift
//  RunningLog
//
//  Rich workout detail view powered by Vital API data.
//  Shows GPS map, heart rate chart, mile splits, elevation profile, and more.
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - VitalWorkoutDetailView

struct VitalWorkoutDetailView: View {
    @Environment(VitalManager.self) private var vitalManager
    let workout: RunningWorkout
    let vitalWorkoutId: String

    @State private var stream: VitalWorkoutStream?
    @State private var splits: [MileSplit] = []
    @State private var paceSplits: [PaceSplit] = []
    @State private var route: [CLLocation] = []
    @State private var heartRateSamples: [HeartRateSample] = []
    @State private var isLoading = true
    @State private var streamFailed = false
    @State private var vitalSummary: VitalWorkoutSummary?
    /// For non-Vital sources (Strava etc.). Populated from
    /// training_logs.external_streams meta block.
    @State private var externalMeta: StreamMeta?
    @State private var showMileSplits = true

    /// Average HR for secondary stats — Vital first, external fallback.
    private var displayAvgHr: Int? {
        vitalSummary?.averageHr ?? externalMeta?.averageHr
    }

    /// Elevation gain in feet — Vital first, external fallback. Both stores
    /// meters; convert at the boundary.
    private var displayElevationFeet: Int? {
        let metersOpt = vitalSummary?.totalElevationGain ?? externalMeta?.totalElevationGain
        return metersOpt.map { Int($0 * 3.28084) }
    }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Color.drip.coral)
                    Text("Loading workout data...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        PlateStrip(surface: "WORKOUT DETAIL  ·  SHARPENED", fig: "FIG. 23")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        // Header — Plate 23 editorial replacement.
                        // Old: centered weekday + date + source-badge stack
                        // New: left-aligned editorial set with mono eyebrow,
                        // Crimson Pro display date, italic-serif tagline.
                        WD23Header(workout: workout)
                            .padding(.horizontal, 20)

                        // Main Stats — Plate 23: two-slot stat strip
                        // (DISTANCE · DURATION) replaces the 2×2 StatCard
                        // grid. Pace, calories, elevation, HR fold into the
                        // secondary stats row below.
                        WD23TwoStatStrip(workout: workout, avgHr: displayAvgHr, elevationFeet: displayElevationFeet)
                            .padding(.horizontal, 20)

                        // Secondary row now carries only the stats the
                        // top strip can't fit: ELEV + CALORIES. Pace and
                        // HR moved up to the editorial 4-stat strip.
                        WD23SecondaryStats(
                            workout: workout,
                            elevationFeet: displayElevationFeet
                        )
                        .padding(.horizontal, 20)

                        EditorialRule()
                            .padding(.horizontal, 20)

                        // Pace Chart — existing component, now sitting on
                        // the bone background instead of inside a card.
                        if let s = stream, let vel = s.velocitySmooth, let dist = s.distance,
                           vel.count == dist.count, vel.count >= 10 {
                            VStack(alignment: .leading, spacing: 8) {
                                WD23SectionEyebrow(label: "PACE × HR  ·  OVER DISTANCE")
                                PaceChartCard(
                                    velocities: vel,
                                    distances: dist,
                                    times: s.time ?? [],
                                    heartrates: s.heartrate,
                                    altitudes: s.altitude,
                                    cadences: s.cadence
                                )
                            }
                            .padding(.horizontal, 20)

                            EditorialRule()
                                .padding(.horizontal, 20)
                        }

                        // Heart Rate (show summary stats even without stream)
                        if !heartRateSamples.isEmpty || vitalSummary?.averageHr != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                WD23SectionEyebrow(
                                    label: "HEART RATE",
                                    trailing: heartRateSummaryString()
                                )
                                heartRateSection
                            }
                            .padding(.horizontal, 20)

                            EditorialRule()
                                .padding(.horizontal, 20)
                        }

                        // Splits (Pace segments + Mile splits) — existing
                        // splits section still handles its own internal
                        // toggle. Editorial eyebrow above keeps the visual
                        // language consistent.
                        if !paceSplits.isEmpty || !splits.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                WD23SectionEyebrow(label: "SPLITS")
                                splitsSection
                            }
                            .padding(.horizontal, 20)

                            EditorialRule()
                                .padding(.horizontal, 20)
                        }

                        // GPS Map — moved to AFTER splits so the editorial
                        // narrative arc reads: header → strip → pace × HR
                        // → HR detail → splits → map → context. Existing
                        // RouteMapCard kept intact (real MapKit map, not a
                        // mockup illustration).
                        if !route.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                WD23SectionEyebrow(label: "ROUTE")
                                RouteMapCard(route: route)
                            }
                            .padding(.horizontal, 20)

                            EditorialRule()
                                .padding(.horizontal, 20)
                        }

                        // Elevation Profile
                        if let altitudes = stream?.altitude, !altitudes.isEmpty {
                            ElevationProfileCard(
                                altitudes: altitudes,
                                distances: stream?.distance ?? [],
                                totalElevationGain: vitalSummary?.totalElevationGain
                            )
                            .padding(.horizontal, 20)
                        }

                        // Cadence & Power
                        if stream?.cadence != nil || stream?.power != nil {
                            additionalMetrics
                                .padding(.horizontal, 20)
                        }

                        // Stream failed — offer retry
                        if streamFailed {
                            VStack(spacing: 12) {
                                Text("Detailed data couldn't be loaded")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textTertiary)

                                Button {
                                    streamFailed = false
                                    isLoading = true
                                    Task { await loadData() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Retry")
                                            .font(.dripLabel(13))
                                    }
                                    .foregroundStyle(Color.drip.coral)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.drip.coral.opacity(0.1))
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        EditorialRule()
                            .padding(.horizontal, 20)

                        PlateFooter("Pace, narrated. The story this run tells about your fitness.")
                            .padding(.horizontal, 20)

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .task(id: vitalWorkoutId) { await loadData() }
    }

    // MARK: - Plate 23 helpers

    /// Compact summary string for the HR section eyebrow's trailing
    /// position. e.g. "AVG 143  ·  MAX 162". Returns nil when no HR
    /// summary is available.
    private func heartRateSummaryString() -> String? {
        guard let summary = vitalSummary,
              let avg = summary.averageHr else { return nil }
        var parts = ["AVG \(avg)"]
        if let mx = summary.maxHr {
            parts.append("MAX \(mx)")
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Header

    private var workoutHeader: some View {
        VStack(spacing: 8) {
            Text(workout.dayOfWeek)
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)

            Text(workout.formattedDate)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            SourceBadge(source: workout.sourceApp)
                .padding(.top, 4)
        }
    }

    // MARK: - Main Stats

    private var mainStatsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(value: workout.formattedDistance, label: "Distance", icon: "point.topleft.down.to.point.bottomright.curvepath.fill")
                StatCard(value: workout.formattedDuration, label: "Duration", icon: "clock.fill")
            }
            HStack(spacing: 12) {
                StatCard(value: workout.formattedPace, label: "Avg Pace", icon: "speedometer")
                StatCard(value: "\(Int(workout.calories))", label: "Calories", icon: "flame.fill", accentColor: Color.drip.tired)
            }
            if let summary = vitalSummary {
                HStack(spacing: 12) {
                    if let movingTime = summary.movingTime {
                        StatCard(
                            value: formatDuration(Double(movingTime)),
                            label: "Moving Time",
                            icon: "timer"
                        )
                    }
                    if let elevGain = summary.totalElevationGain {
                        StatCard(
                            value: "\(Int(elevGain * 3.28084)) ft",
                            label: "Elevation Gain",
                            icon: "mountain.2.fill",
                            accentColor: .green
                        )
                    }
                }
            }
        }
    }

    // MARK: - Heart Rate

    private var heartRateSection: some View {
        VStack(spacing: 12) {
            if let avgHR = vitalSummary?.averageHr, let maxHR = vitalSummary?.maxHr {
                HeartRateCard(average: Double(avgHR), max: Double(maxHR))
            }
            if !heartRateSamples.isEmpty {
                HeartRateGraphCard(samples: heartRateSamples, duration: workout.durationMinutes)
            }
        }
    }

    // MARK: - Splits

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with toggle
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)

                // Toggle between mile splits and pace segments
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showMileSplits = true }
                    } label: {
                        Text("MILE SPLITS")
                            .font(.dripCaption(11))
                            .tracking(1.2)
                            .foregroundStyle(showMileSplits ? Color.drip.coral : Color.drip.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(showMileSplits ? Color.drip.coral.opacity(0.15) : Color.clear)
                            .clipShape(Capsule())
                    }

                    if !paceSplits.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showMileSplits = false }
                        } label: {
                            Text("PACE SEGMENTS")
                                .font(.dripCaption(11))
                                .tracking(1.2)
                                .foregroundStyle(!showMileSplits ? Color.drip.coral : Color.drip.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(!showMileSplits ? Color.drip.coral.opacity(0.15) : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()
            }

            if showMileSplits {
                // Mile splits
                VStack(spacing: 0) {
                    ForEach(splits) { split in
                        SplitRow(split: split, fastestPace: fastestMilePace, slowestPace: slowestMilePace)
                    }
                }
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
            } else {
                // Pace splits (Garmin-style)
                VStack(spacing: 0) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("#")
                            .frame(width: 24, alignment: .trailing)
                        Text("TIME")
                            .frame(width: 60, alignment: .center)
                        Text("DIST")
                            .frame(width: 58, alignment: .center)
                        Spacer()
                        Text("PACE")
                            .frame(width: 52, alignment: .center)
                        Text("HR")
                            .frame(width: 38, alignment: .trailing)
                    }
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(0.8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    ForEach(paceSplits) { split in
                        PaceSplitRow(
                            split: split,
                            fastestPace: fastestPaceSplit,
                            slowestPace: slowestPaceSplit
                        )
                    }
                }
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
            }
        }
    }

    private var fastestMilePace: Double {
        splits.filter { !$0.isPartial }.map(\.paceMinutes).min() ?? 0
    }

    private var slowestMilePace: Double {
        splits.filter { !$0.isPartial }.map(\.paceMinutes).max() ?? 10
    }

    private var fastestPaceSplit: Double {
        paceSplits.map(\.paceMinutes).min() ?? 0
    }

    private var slowestPaceSplit: Double {
        paceSplits.map(\.paceMinutes).max() ?? 10
    }

    // MARK: - Additional Metrics

    private var additionalMetrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let cadence = stream?.cadence, !cadence.isEmpty {
                    let avgCadence = cadence.reduce(0, +) / Double(cadence.count)
                    StatCard(
                        value: "\(Int(avgCadence * 2))",
                        label: "Avg Cadence (spm)",
                        icon: "metronome.fill"
                    )
                }
                if let power = stream?.power, !power.isEmpty {
                    let avgPower = power.reduce(0, +) / Double(power.count)
                    StatCard(
                        value: "\(Int(avgPower)) W",
                        label: "Avg Power",
                        icon: "bolt.fill",
                        accentColor: .yellow
                    )
                }
            }
            if let steps = vitalSummary?.steps {
                HStack(spacing: 12) {
                    StatCard(
                        value: "\(steps)",
                        label: "Steps",
                        icon: "shoeprints.fill"
                    )
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        // Strava-pulled workouts have their stream stored as JSONB on
        // training_logs.external_streams (written by the strava-test-pull
        // edge function). Vital's API doesn't know about those workout IDs,
        // so for any non-Vital source we go straight to ExternalStreamAdapter.
        if isExternalSource {
            await loadFromExternalStreams()
            return
        }

        // Fetch summary and stream in parallel — don't let one block the other
        let cachedSummary = vitalManager.getSummary(for: vitalWorkoutId)
        async let summaryTask: VitalWorkoutSummary? = {
            if let cached = cachedSummary {
                return cached
            }
            _ = await vitalManager.fetchRunningWorkouts(for: workout.startDate)
            return await vitalManager.getSummary(for: vitalWorkoutId)
        }()
        async let streamTask = vitalManager.fetchWorkoutStream(workoutId: vitalWorkoutId)

        let summary = await summaryTask
        let fetchedStream = await streamTask

        // Guard against task cancellation
        guard !Task.isCancelled else { return }

        if let fetchedStream {
            let calculatedSplits = vitalManager.calculateSplits(from: fetchedStream)
            let calculatedPaceSplits = vitalManager.calculatePaceSplits(from: fetchedStream)
            let fetchedRoute = vitalManager.extractRoute(from: fetchedStream)
            let hrSamples = extractHRSamples(from: fetchedStream)

            await MainActor.run {
                stream = fetchedStream
                splits = calculatedSplits
                paceSplits = calculatedPaceSplits
                route = fetchedRoute
                heartRateSamples = hrSamples
                vitalSummary = summary
                streamFailed = false
                isLoading = false
            }
        } else {
            await MainActor.run {
                vitalSummary = summary
                streamFailed = true
                isLoading = false
            }
        }
    }

    /// True when the workout came from a non-Vital pipeline (Strava import,
    /// HealthKit + external_streams, etc.). The stream lives in
    /// training_logs.external_streams, not on the Vital API.
    private var isExternalSource: Bool {
        if vitalWorkoutId.hasPrefix("strava_") { return true }
        let s = workout.sourceApp.lowercased()
        return s.contains("strava")
    }

    /// Load stream + route + meta from training_logs.external_streams (the
    /// path used for Strava-pulled workouts). Mirrors the Vital path's
    /// state mutations so the rest of the view doesn't care about source.
    private func loadFromExternalStreams() async {
        let bundle = await ExternalStreamAdapter.load(forTrainingLogId: workout.id)

        guard !Task.isCancelled else { return }

        guard let bundle else {
            await MainActor.run {
                streamFailed = true
                isLoading = false
            }
            return
        }

        let fetchedStream = bundle.stream
        let fetchedRoute = bundle.route

        let calculatedSplits = fetchedStream.map { vitalManager.calculateSplits(from: $0) } ?? []
        let calculatedPaceSplits = fetchedStream.map { vitalManager.calculatePaceSplits(from: $0) } ?? []
        let hrSamples = fetchedStream.map { extractHRSamples(from: $0) } ?? []

        await MainActor.run {
            stream = fetchedStream
            splits = calculatedSplits
            paceSplits = calculatedPaceSplits
            route = fetchedRoute
            heartRateSamples = hrSamples
            externalMeta = bundle.meta
            streamFailed = fetchedStream == nil && fetchedRoute.isEmpty
            isLoading = false
        }
    }

    private func extractHRSamples(from stream: VitalWorkoutStream) -> [HeartRateSample] {
        guard let heartrates = stream.heartrate, let times = stream.time,
              heartrates.count == times.count, !heartrates.isEmpty
        else { return [] }

        let startTime = times[0]
        // Sample every 5th point for smooth chart
        return stride(from: 0, to: heartrates.count, by: 5).map { i in
            HeartRateSample(
                timestamp: Double(times[i] - startTime),
                bpm: Double(heartrates[i])
            )
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSecs = Int(seconds)
        let hours = totalSecs / 3600
        let mins = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

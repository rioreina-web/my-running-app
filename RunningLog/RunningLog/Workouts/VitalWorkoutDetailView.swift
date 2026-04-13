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
    @State private var showMileSplits = true

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
                        // Header
                        workoutHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        // Main Stats
                        mainStatsGrid
                            .padding(.horizontal, 20)

                        // Pace Chart
                        if let s = stream, let vel = s.velocitySmooth, let dist = s.distance,
                           vel.count == dist.count, vel.count >= 10 {
                            PaceChartCard(
                                velocities: vel,
                                distances: dist,
                                times: s.time ?? [],
                                heartrates: s.heartrate,
                                altitudes: s.altitude,
                                cadences: s.cadence
                            )
                            .padding(.horizontal, 20)
                        }

                        // GPS Map
                        if !route.isEmpty {
                            RouteMapCard(route: route)
                                .padding(.horizontal, 20)
                        }

                        // Heart Rate (show summary stats even without stream)
                        if !heartRateSamples.isEmpty || vitalSummary?.averageHr != nil {
                            heartRateSection
                                .padding(.horizontal, 20)
                        }

                        // Splits (Pace segments + Mile splits)
                        if !paceSplits.isEmpty || !splits.isEmpty {
                            splitsSection
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

                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .task(id: vitalWorkoutId) { await loadData() }
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
        // Fetch summary and stream in parallel — don't let one block the other
        async let summaryTask: VitalWorkoutSummary? = {
            if let cached = vitalManager.getSummary(for: vitalWorkoutId) {
                return cached
            }
            _ = await vitalManager.fetchRunningWorkouts(for: workout.startDate)
            return vitalManager.getSummary(for: vitalWorkoutId)
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

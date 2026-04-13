//
//  AthleteProfileView.swift
//  RunningLog
//
//  Displays the comprehensive athlete profile built from training history.
//

import SwiftUI

struct AthleteProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AthleteProfileService.self) private var profileService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if profileService.isLoading && profileService.profile == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.drip.coral)
                        Text("Building your profile...")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                } else if let profile = profileService.profile {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection(profile)
                            volumeSection(profile)
                            paceSection(profile)
                            performanceSection(profile)
                            injurySection(profile)
                            recoverySection(profile)
                            preferencesSection(profile)
                            if let bio = profile.biomechanics {
                                biomechanicsSection(bio)
                            }
                            goalSection(profile)
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("No profile data yet")
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textSecondary)
                        Text("Log some training to build your profile")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textTertiary)
                        DripButton("Build Profile", icon: "arrow.clockwise") {
                            Task { await profileService.fetchProfile(forceRebuild: true) }
                        }
                        .frame(width: 200)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ATHLETE PROFILE")
                        .font(.dripCaption(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.coral)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if profileService.profile != nil {
                        Button {
                            Task { await profileService.fetchProfile(forceRebuild: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.drip.coral)
                        }
                        .disabled(profileService.isLoading)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Header

    private func headerSection(_ profile: AthleteProfileData) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.drip.coral)

            Text("\(profile.dataSpanMonths) months of training data")
                .font(.dripLabel(16))
                .foregroundStyle(Color.drip.textPrimary)

            Text("\(profile.totalLogs) logged runs")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)

            if profileService.isLoading {
                ProgressView()
                    .tint(Color.drip.coral)
                    .scaleEffect(0.7)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Volume

    private func volumeSection(_ profile: AthleteProfileData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Volume")

            // Summary stats
            let vs = profile.volumeSummary
            HStack(spacing: 0) {
                statCell(value: String(format: "%.0f", vs.currentWeeklyAvg), label: "mi/wk", highlight: true)
                statCell(value: String(format: "%.0f", vs.peakWeeklyEver), label: "peak mi/wk")
                statCell(value: String(format: "%.1f", vs.longestRunEver), label: "longest")
                statCell(value: "\(Int(vs.consistencyScore * 100))%", label: "consistent")
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Volume by tier
            if profile.volume.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(profile.volume.enumerated()), id: \.offset) { index, tier in
                        HStack {
                            Text(tierLabel(tier.tier))
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Text(String(format: "%.0f mi/wk", tier.avgWeeklyMiles))
                                .font(.dripStat(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("(\(tier.totalRuns) runs)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if index < profile.volume.count - 1 {
                            Divider().background(Color.drip.divider)
                        }
                    }
                }
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Pace

    private func paceSection(_ profile: AthleteProfileData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Pace Evolution")

            VStack(spacing: 0) {
                ForEach(Array(profile.pace.enumerated()), id: \.offset) { index, tier in
                    HStack {
                        Text(tierLabel(tier.tier))
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatPace(tier.avgPaceSecondsPerMile))
                                .font(.dripStat(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            HStack(spacing: 8) {
                                Text("easy \(formatPace(tier.easyPace))")
                                Text("fast \(formatPace(tier.fastestPace))")
                            }
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < profile.pace.count - 1 {
                        Divider().background(Color.drip.divider)
                    }
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Performance Trajectory

    private func performanceSection(_ profile: AthleteProfileData) -> some View {
        Group {
            if profile.performanceTrajectory.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Performance Trajectory")

                    let first = profile.performanceTrajectory.first!
                    let last = profile.performanceTrajectory.last!

                    VStack(spacing: 0) {
                        trajectoryRow(label: "5K", old: first.predicted5k, new: last.predicted5k)
                        Divider().background(Color.drip.divider)
                        trajectoryRow(label: "10K", old: first.predicted10k, new: last.predicted10k)
                        Divider().background(Color.drip.divider)
                        trajectoryRow(label: "Half", old: first.predictedHalf, new: last.predictedHalf)
                        Divider().background(Color.drip.divider)
                        trajectoryRow(label: "Marathon", old: first.predictedMarathon, new: last.predictedMarathon)
                    }
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack {
                        Text(first.date)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                        Spacer()
                        Text(last.date)
                    }
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func trajectoryRow(label: String, old: String, new: String) -> some View {
        HStack {
            Text(label)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 70, alignment: .leading)
            Spacer()
            Text(old)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(Color.drip.textTertiary)
            Text(new)
                .font(.dripStat(14))
                .foregroundStyle(Color.drip.coral)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Injuries

    private func injurySection(_ profile: AthleteProfileData) -> some View {
        Group {
            if !profile.injuryHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Injury History")

                    VStack(spacing: 0) {
                        ForEach(Array(profile.injuryHistory.prefix(5).enumerated()), id: \.offset) { index, injury in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(injury.side != "unknown" ? "\(injury.side.capitalized) \(injury.bodyArea)" : injury.bodyArea)
                                            .font(.dripBody(14))
                                            .foregroundStyle(Color.drip.textPrimary)
                                        if injury.isRecurring {
                                            Text("RECURRING")
                                                .font(.dripCaption(9))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.drip.injured)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text("Last: \(injury.mostRecent)")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(injury.occurrences)x")
                                        .font(.dripStat(14))
                                        .foregroundStyle(Color.drip.textPrimary)
                                    Text("sev \(String(format: "%.0f", injury.avgSeverity))/10")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if index < min(profile.injuryHistory.count, 5) - 1 {
                                Divider().background(Color.drip.divider)
                            }
                        }
                    }
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Recovery

    private func recoverySection(_ profile: AthleteProfileData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Recovery")

            HStack(spacing: 0) {
                statCell(
                    value: "\(Int(profile.recovery.avgMoodPositivePct * 100))%",
                    label: "positive mood"
                )
                statCell(
                    value: String(format: "%.1f", profile.recovery.typicalEasyDayFrequency),
                    label: "easy days/wk"
                )
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Preferences

    private func preferencesSection(_ profile: AthleteProfileData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Training Preferences")

            VStack(spacing: 0) {
                if !profile.preferences.mostCommonWorkoutTypes.isEmpty {
                    prefRow(icon: "figure.run", label: "Workout types", value: profile.preferences.mostCommonWorkoutTypes.joined(separator: ", "))
                    Divider().background(Color.drip.divider)
                }
                if profile.preferences.avgLongRunDistance > 0 {
                    prefRow(icon: "road.lanes", label: "Avg long run", value: String(format: "%.1f mi", profile.preferences.avgLongRunDistance))
                    Divider().background(Color.drip.divider)
                }
                if !profile.preferences.preferredRunDays.isEmpty {
                    prefRow(icon: "calendar", label: "Preferred days", value: profile.preferences.preferredRunDays.joined(separator: ", "))
                    Divider().background(Color.drip.divider)
                }
                prefRow(icon: "arrow.right.arrow.left", label: "Back-to-back days", value: profile.preferences.trainsConsecutively ? "Common" : "Rare")
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func prefRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.drip.coral)
                .frame(width: 22)
            Text(label)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text(value)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Biomechanics

    private func biomechanicsSection(_ bio: BiomechanicsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Biomechanics")

            VStack(spacing: 0) {
                HStack {
                    Text("Form Score")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f/10", bio.latestScore))
                        .font(.dripStat(16))
                        .foregroundStyle(Color.drip.coral)
                    Text(bio.trend)
                        .font(.dripCaption(11))
                        .foregroundStyle(trendColor(bio.trend))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if !bio.keyFindings.isEmpty {
                    Divider().background(Color.drip.divider)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(bio.keyFindings.prefix(2).enumerated()), id: \.offset) { _, finding in
                            Text(finding)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Goals

    private func goalSection(_ profile: AthleteProfileData) -> some View {
        Group {
            if profile.goalHistory.completed > 0 || profile.goalHistory.active > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Goals")

                    HStack(spacing: 0) {
                        statCell(value: "\(profile.goalHistory.completed)", label: "completed")
                        statCell(value: "\(profile.goalHistory.active)", label: "active")
                    }
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if !profile.goalHistory.raceDistancesTargeted.isEmpty {
                        Text("Race distances: \(profile.goalHistory.raceDistancesTargeted.joined(separator: ", "))")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statCell(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripStat(18))
                .foregroundStyle(highlight ? Color.drip.coral : Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func tierLabel(_ tier: String) -> String {
        switch tier {
        case "last_6_months": return "Last 6mo"
        case "6_to_12_months": return "6-12mo"
        case "1_to_2_years": return "1-2yr"
        case "2_plus_years": return "2+ yr"
        default: return tier
        }
    }

    private func formatPace(_ seconds: Int) -> String {
        PaceCalculator.formatPaceWithUnit(Double(seconds))
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "improving": return Color.drip.positive
        case "declining": return Color.drip.injured
        default: return Color.drip.textTertiary
        }
    }
}

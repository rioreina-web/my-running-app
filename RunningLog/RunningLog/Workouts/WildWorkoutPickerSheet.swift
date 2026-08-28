//
//  WildWorkoutPickerSheet.swift
//  RunningLog
//
//  "Link a run" — the run picker, Direction I.
//
//  The editorial `WorkoutPickerSheet` stays exactly as it is and still serves
//  the editorial skin. This is the same sheet with the same data and the same
//  merge, re-laid on the locked system:
//
//    • no cards, no rounded rectangles, no fills — hairlines between rows
//    • the distance is the figure, the way it is on the Log screen's linked
//      block, so the two surfaces read as one thing
//    • `Color.drip.energized` is gone. That token is a MOOD — deep green,
//      "how the athlete felt" — and the old sheet used it as an accent for
//      the checkmarks, the Done button and the spinner. Under this system
//      accents are the one red, and moods are never borrowed for chrome.
//    • selection is the same ink badge the front door uses for LATEST, so
//      there is no new marker to learn
//
//  THE FETCH IS NOT DUPLICATED. Every source, and the merge across them,
//  lives in `HealthKitManager.refreshRecentRuns` — the same call the Log tab's
//  linked-run block reads, so the two can never disagree about which run is
//  latest. A warning worth repeating from there: that method's Strava source
//  list is the only way a synced run reaches this picker, and this picker is
//  the only way the view model learns a run's `vital_workout_id` — which is
//  what its attach-to-existing-row branch keys on. Omit a source there and
//  every memo for that source silently becomes a NEW duplicate
//  `training_logs` row.
//

import SwiftUI

struct WildWorkoutPickerSheet: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var selectedWorkout: RunningWorkout?
    @Binding var isPresented: Bool

    @State private var workouts: [RunningWorkout] = []
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.wild.paper.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        lede
                        if workouts.isEmpty && !isRefreshing {
                            emptyState
                        } else {
                            noRunRow
                            ForEach(workouts) { workout in
                                row(workout)
                            }
                            if isRefreshing { syncingRow }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        WildLabel("Refresh ↗", size: 10, tracking: 0.14,
                                  color: isRefreshing ? Color.wild.ink2 : Color.wild.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = false } label: {
                        WildLabel("Done", size: 11, tracking: 0.14, color: Color.wild.redText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(Color.wild.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await refresh() }
        }
    }

    // MARK: Lede

    private var lede: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Link a run.")
                .font(.wildDisplay(32))
                .tracking(32 * -0.045)
                .foregroundStyle(Color.wild.ink)
            Text("Attach this memo to a run you already logged.")
                .font(.wildDek(16))
                .foregroundStyle(Color.wild.ink2)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) { WildRule(strong: true) }
    }

    // MARK: Rows

    private var noRunRow: some View {
        Button {
            selectedWorkout = nil
            isPresented = false
        } label: {
            HStack(spacing: 12) {
                Text("No run")
                    .font(.wildDisplay(19))
                    .tracking(19 * -0.03)
                    .foregroundStyle(Color.wild.ink)
                Text("Keep the memo on its own.")
                    .font(.custom(WildFace.mono, size: 11))
                    .foregroundStyle(Color.wild.ink2)
                Spacer(minLength: 8)
                if selectedWorkout == nil { linkedBadge }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { WildRule() }
        }
        .buttonStyle(.plain)
    }

    private func row(_ w: RunningWorkout) -> some View {
        Button {
            selectedWorkout = w
            isPresented = false
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // The distance is the figure — same treatment as the Log
                // screen's linked block, so the two surfaces rhyme.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.2f", w.distanceMiles))
                        .font(.wildData(26, semibold: true))
                        .tracking(26 * -0.035)
                        .monospacedDigit()
                        .foregroundStyle(Color.wild.ink)
                    WildLabel("mi", size: 10, tracking: 0.14)
                }
                .frame(width: 96, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dayLine(w.startDate))
                        .font(.wildDisplay(13))
                        .tracking(13 * -0.02)
                        .foregroundStyle(Color.wild.ink)
                    Text(metaLine(w))
                        .font(.custom(WildFace.mono, size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color.wild.ink2)
                }

                Spacer(minLength: 8)

                if selectedWorkout?.id == w.id { linkedBadge }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { WildRule() }
        }
        .buttonStyle(.plain)
    }

    /// The same ink badge the front door uses for LATEST — one selection idea
    /// across both surfaces rather than a checkmark here and a badge there.
    private var linkedBadge: some View {
        WildLabel("Linked", size: 9, tracking: 0.14, color: Color.wild.paper)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.wild.ink)
    }

    private var syncingRow: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.mini).tint(Color.wild.ink2)
            WildLabel("Syncing", size: 10, tracking: 0.16)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { WildRule() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No recent runs found. Runs appear here once your watch or running app has synced them.")
                .font(.wildProse(18))
                .foregroundStyle(Color.wild.ink2)
            Button {
                Task { await refresh() }
            } label: {
                WildLabel("Refresh ↗", size: 10, tracking: 0.14, color: Color.wild.redText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
    }

    // MARK: Copy

    private func dayLine(_ d: Date) -> String {
        let cal = Calendar.current
        let time = wildPickerTimeFormatter.string(from: d).lowercased()
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday, \(time)" }
        return "\(wildPickerDayFormatter.string(from: d)), \(time)"
    }

    private func metaLine(_ w: RunningWorkout) -> String {
        let pace = w.pacePerMile > 0
            ? PaceCalculator.formatPaceFromMinutes(w.pacePerMile) + "/mi"
            : "—"
        return "\(w.formattedDuration) · \(pace) · \(w.sourceApp)"
    }

    // MARK: Data

    /// Fetch every source, merge, dedup — all of it in
    /// `HealthKitManager.refreshRecentRuns`, which is also what the Log tab's
    /// linked-run block reads. This sheet used to carry its own copy of that
    /// merge and publish only the HealthKit half back, which is why the Log
    /// screen could not see a Strava-only run (2026-08-24).
    private func refresh() async {
        isRefreshing = true
        let merged = await healthKitManager.refreshRecentRuns()
        await MainActor.run {
            workouts = merged
            isRefreshing = false
        }
    }
}

// MARK: - Formatters

// File-level: built once, not per row per frame.
private let wildPickerTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "h:mm a"
    return f
}()

private let wildPickerDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE MMM d"
    return f
}()

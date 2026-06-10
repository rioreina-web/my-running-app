//
//  EditGoalSheet.swift
//  RunningLog
//
//  Athlete-facing goal editor — race distance, finish time, race date.
//  Calls update-plan-goal edge function. Two modes:
//
//    plan != nil → updates the plan's goal AND mirrors to athlete_pace_profiles.
//    plan == nil → no plan yet; just upserts athlete_pace_profiles. The
//                  race-date picker is hidden because there's no plan to
//                  anchor it to.
//
//  The AI never invokes this path; see feedback_ai_advises_never_acts.md.
//

import SwiftUI
import os

struct EditGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel

    @State private var distance: String
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var raceDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let plan: TrainingPlan?
    /// Fires after the goal is successfully saved. Caller uses this to
    /// chain the RecomputePacesSheet soft-ask. No-op when there's no plan.
    private let onSaved: () -> Void

    init(viewModel: TrainingPlanViewModel, plan: TrainingPlan?, onSaved: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.plan = plan
        self.onSaved = onSaved
        // If the stored distance isn't one of the four supported options
        // (legacy "ultra" or "general" plans), fall through to "marathon"
        // so the picker has a valid selection to render.
        let supported: Set<String> = ["5k", "10k", "half_marathon", "marathon"]
        let initialDistance = plan.flatMap {
            supported.contains($0.targetRaceDistance) ? $0.targetRaceDistance : nil
        } ?? "marathon"
        _distance = State(initialValue: initialDistance)
        let totalSec = plan?.targetTimeSeconds ?? 0
        _hours = State(initialValue: totalSec / 3600)
        _minutes = State(initialValue: (totalSec % 3600) / 60)
        _seconds = State(initialValue: totalSec % 60)
        _raceDate = State(initialValue: plan?.endDate ?? Date())
    }

    // Four supported race distances. Ultra and "No specific race" were removed
    // from the picker — kept the segmented control with only these four labels
    // so they fit without truncation.
    private static let allowedDistances: [(value: String, label: String)] = [
        ("5k", "5K"),
        ("10k", "10K"),
        ("half_marathon", "HM"),
        ("marathon", "Marathon"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        intro
                        distanceSection
                        timeSection
                        if plan != nil {
                            dateSection
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(plan == nil ? "Set Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || !hasChanges)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan == nil ? "Set your race goal" : "Update your race goal")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)
            Text(plan == nil
                 ? "Your goal anchors every training pace. You can subscribe to a coach plan later — paces will already be tuned."
                 : "Changing the goal updates the plan's anchor. Workout paces will not silently re-resolve — you'll be asked.")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Race distance")
            Picker("Race distance", selection: $distance) {
                ForEach(Self.allowedDistances, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Goal finish time")
            HStack(spacing: 12) {
                timePicker("hr", selection: $hours, range: 0..<25)
                Text(":").font(.dripStat(20)).foregroundStyle(Color.drip.textTertiary)
                timePicker("min", selection: $minutes, range: 0..<60)
                Text(":").font(.dripStat(20)).foregroundStyle(Color.drip.textTertiary)
                timePicker("sec", selection: $seconds, range: 0..<60)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Race date")
            DatePicker(
                "Race date",
                selection: $raceDate,
                in: Date()...Date.distantFuture,
                displayedComponents: .date
            )
            .labelsHidden()
        }
    }

    private func timePicker(_ label: String, selection: Binding<Int>, range: Range<Int>) -> some View {
        VStack(spacing: 4) {
            Picker(label, selection: selection) {
                ForEach(Array(range), id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(width: 64, height: 100)
            .clipped()
            Text(label).font(.dripCaption(10)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.dripCaption(10))
            .tracking(0.6)
            .foregroundStyle(Color.drip.textTertiary)
    }

    private var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }

    private var hasChanges: Bool {
        guard let plan else {
            // No plan: any non-zero time + a chosen distance counts as a change.
            return totalSeconds > 0
        }
        return distance != plan.targetRaceDistance
            || totalSeconds != plan.targetTimeSeconds
            || !Calendar.current.isDate(raceDate, inSameDayAs: plan.endDate)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var body: [String: Any] = [:]
        if let plan {
            body["plan_id"] = plan.id.uuidString
            if distance != plan.targetRaceDistance {
                body["target_race_distance"] = distance
            }
            if distance != "general" && totalSeconds != plan.targetTimeSeconds {
                body["target_time_seconds"] = totalSeconds
            }
            if distance != "general"
               && !Calendar.current.isDate(raceDate, inSameDayAs: plan.endDate) {
                body["end_date"] = formatYMD(raceDate)
            }
        } else {
            // No plan — distance + time are both required for the
            // athlete_pace_profiles upsert.
            body["plan_id"] = NSNull()
            body["target_race_distance"] = distance
            body["target_time_seconds"] = totalSeconds
        }

        do {
            _ = try await callEdgeFunction(name: "update-plan-goal", body: body)
            await viewModel.loadActivePlan()
            dismiss()
            // Defer one tick so the dismiss animation can start before the
            // parent presents the soft-ask sheet. Skip when there's no plan
            // — there's nothing to recompute.
            if plan != nil {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run { onSaved() }
            }
        } catch {
            Log.goals.error("update-plan-goal failed: \(error.localizedDescription)")
            errorMessage = "Couldn't save goal. Try again."
        }
    }

    private func formatYMD(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}

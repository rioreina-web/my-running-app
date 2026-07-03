//
//  WorkoutsAndRepsSection.swift
//  RunningLog
//
//  Training-tab section: recent quality sessions (intervals / threshold /
//  tempo / fartlek / progression / race), each tapping through to the
//  per-workout rep chart (WorkoutRepChart). Self-contained — own fetch and
//  own sheet — so it drops into TrainingTabView with a single line and can't
//  disturb the existing analysis sections.
//
//  Reads training_logs directly (RLS user-scoped; workout_type is set by the
//  WS1 classifier). The rep chart fetches that workout's laps by id.
//

import SwiftUI
import Supabase
import os

struct WorkoutsAndRepsSection: View {
    private struct QualityWorkout: Decodable, Identifiable {
        let id: UUID
        var workout_date: String?
        var workout_type: String?
        var workout_distance_miles: Double?
    }
    private struct SheetID: Identifiable { let id: UUID }

    private static let qualityTypes = ["intervals", "interval", "threshold", "tempo", "fartlek", "progression", "race"]

    @State private var items: [QualityWorkout] = []
    @State private var loaded = false
    @State private var sheet: SheetID?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel
            if !items.isEmpty {
                ForEach(Array(items.prefix(4))) { w in
                    Button { sheet = SheetID(id: w.id) } label: { row(w) }
                        .buttonStyle(.plain)
                }
            } else if !loaded {
                Text("Loading workouts…")
                    .font(.dripStat(11)).foregroundStyle(Color.drip.textTertiary)
                    .padding(.vertical, 12)
            } else {
                Text(errorText ?? "No quality sessions detected recently.")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
        .task { await load() }
        .sheet(item: $sheet) { s in
            NavigationStack {
                ScrollView {
                    WorkoutRepChart(workoutId: s.id).padding(20)
                }
                .background(Color.drip.background.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("WORKOUT").font(.dripStat(10)).tracking(1.0)
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
        }
    }

    private var sectionLabel: some View {
        HStack(spacing: 10) {
            Text("WORKOUTS & REPS")
                .font(.dripStat(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.bottom, 6)
    }

    private func row(_ w: QualityWorkout) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine(w.workout_date))
                    .font(.dripStat(10)).tracking(0.6)
                    .foregroundStyle(Color.drip.coral)
                Text("\(typeLabel(w.workout_type))\(distSuffix(w.workout_distance_miles))")
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    // MARK: data

    private func load() async {
        do {
            items = try await supabase
                .from("training_logs")
                .select("id,workout_date,workout_type,workout_distance_miles")
                .in("workout_type", values: Self.qualityTypes)
                .order("workout_date", ascending: false)
                .limit(12)
                .execute().value
        } catch {
            errorText = "Couldn't load workouts: \(error.localizedDescription)"
            Log.coach.error("WorkoutsAndRepsSection load failed: \(error)")
        }
        loaded = true
    }

    // MARK: format

    private func typeLabel(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "intervals", "interval": return "Intervals"
        case "threshold": return "Threshold"
        case "tempo": return "Tempo"
        case "fartlek": return "Fartlek"
        case "progression": return "Progression"
        case "race": return "Race"
        default: return "Workout"
        }
    }
    private func distSuffix(_ mi: Double?) -> String {
        guard let mi, mi > 0 else { return "" }
        return String(format: " · %.1f mi", mi)
    }
    private func dateLine(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let day = String(iso.prefix(10))
        let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: day) else { return day }
        let outF = DateFormatter(); outF.locale = Locale(identifier: "en_US_POSIX"); outF.dateFormat = "EEE · MMM d"
        return outF.string(from: d).uppercased()
    }
}

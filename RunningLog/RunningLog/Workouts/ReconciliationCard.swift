//
//  ReconciliationCard.swift
//  RunningLog
//
//  "Coach reconciliation" card rendered in the training-log detail sheet.
//  Reads one row from workout_reconciliations (populated by the reconcile-log
//  edge function after every training_logs insert) and translates target vs.
//  actual vs. weather-adjusted target into a one-line verdict.
//

import os
import Supabase
import SwiftUI

// MARK: - Model

struct WorkoutReconciliation: Decodable {
    let id: UUID
    let trainingLogId: UUID
    let scheduledWorkoutId: UUID?
    let targetPaceSecondsPerMile: Double?
    let actualPaceSecondsPerMile: Double?
    let adjustedTargetPaceSeconds: Double?
    let adjustedPaceDeltaSeconds: Double?
    let hitTarget: Bool?
    let toleranceAppliedSeconds: Double
    let weatherActualJsonb: Weather?
    let notesJson: NotesBag?

    struct Weather: Decodable {
        let temperatureF: Double?
        let dewPointF: Double?
        let heatCategory: String?
        enum CodingKeys: String, CodingKey {
            case temperatureF = "temperature_f"
            case dewPointF = "dew_point_f"
            case heatCategory = "heat_category"
        }
    }

    struct NotesBag: Decodable {
        let adjustment: Adjustment?
        struct Adjustment: Decodable {
            let heatCategory: String?
            let adjustmentPercent: Double?
            enum CodingKeys: String, CodingKey {
                case heatCategory = "heat_category"
                case adjustmentPercent = "adjustment_percent"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case trainingLogId = "training_log_id"
        case scheduledWorkoutId = "scheduled_workout_id"
        case targetPaceSecondsPerMile = "target_pace_seconds_per_mile"
        case actualPaceSecondsPerMile = "actual_pace_seconds_per_mile"
        case adjustedTargetPaceSeconds = "adjusted_target_pace_seconds"
        case adjustedPaceDeltaSeconds = "adjusted_pace_delta_seconds"
        case hitTarget = "hit_target"
        case toleranceAppliedSeconds = "tolerance_applied_seconds"
        case weatherActualJsonb = "weather_actual_jsonb"
        case notesJson = "notes_json"
    }
}

// MARK: - Card

struct ReconciliationCard: View {
    let trainingLogId: UUID
    @State private var reconciliation: WorkoutReconciliation?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let r = reconciliation, r.targetPaceSecondsPerMile != nil {
                card(for: r)
            } else {
                EmptyView()
            }
        }
        .task(id: trainingLogId) {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
    }

    private func card(for r: WorkoutReconciliation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("COACH RECONCILIATION")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()
                if let heat = r.weatherActualJsonb?.heatCategory ?? r.notesJson?.adjustment?.heatCategory {
                    heatBadge(heat)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                stat(label: "TARGET", pace: r.targetPaceSecondsPerMile)
                stat(label: "ADJUSTED", pace: r.adjustedTargetPaceSeconds)
                stat(label: "ACTUAL", pace: r.actualPaceSecondsPerMile)
            }

            Text(verdict(for: r))
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    private func stat(label: String, pace: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(1.0)
            Text(formatPace(pace))
                .font(.dripStat(16))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    private func heatBadge(_ category: String) -> some View {
        let human: String = {
            switch category {
            case "ideal": return "Ideal"
            case "warm": return "Warm"
            case "hot": return "Hot"
            case "very_hot": return "Very Hot"
            case "dangerous": return "Dangerous"
            default: return category.capitalized
            }
        }()
        let color: Color = {
            switch category {
            case "ideal": return Color.drip.energized
            case "warm": return Color.drip.textSecondary
            case "hot": return Color.drip.coral
            case "very_hot", "dangerous": return Color.drip.tired
            default: return Color.drip.textTertiary
            }
        }()
        return Text(human)
            .font(.dripCaption(10))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func verdict(for r: WorkoutReconciliation) -> String {
        guard let delta = r.adjustedPaceDeltaSeconds else { return "Logged." }
        let tolerance = r.toleranceAppliedSeconds
        let beatAdjusted = delta < 0 && r.adjustedTargetPaceSeconds != r.targetPaceSecondsPerMile
        if abs(delta) <= tolerance { return "Nailed it — within \(Int(tolerance))s of target." }
        if beatAdjusted { return "Weather-adjusted — you crushed it despite the heat." }
        if delta < -tolerance { return "Faster than target by \(formatDelta(-delta))." }
        return "Slower than target by \(formatDelta(delta))."
    }

    private func formatPace(_ seconds: Double?) -> String {
        guard let s = seconds, s > 0 else { return "—" }
        let total = Int(s.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))/mi"
    }

    private func formatDelta(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 60 {
            return "\(s / 60):\(String(format: "%02d", s % 60))"
        }
        return "\(s)s"
    }

    private func load() async {
        do {
            let rows: [WorkoutReconciliation] = try await supabase
                .from("workout_reconciliations")
                .select()
                .eq("training_log_id", value: trainingLogId.uuidString)
                .limit(1)
                .execute()
                .value
            self.reconciliation = rows.first
        } catch {
            // Silent — card just doesn't render. The reconciler runs async
            // after a log is inserted so an empty result is expected for a
            // brand-new entry.
            Log.coach.info("Reconciliation fetch empty or failed: \(error.localizedDescription)")
        }
    }
}

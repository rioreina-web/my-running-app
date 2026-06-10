//
//  RecomputePacesSheet.swift
//  RunningLog
//
//  Soft-ask card shown after a goal change. Athlete chooses whether the
//  paces on already-scheduled workouts should be re-resolved from the new
//  goal, or stay as authored. Default is "Yes, update them" but the
//  athlete decides.
//
//  See feedback_ai_advises_never_acts.md — paces never silently change.
//

import SwiftUI
import os

struct RecomputePacesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: TrainingPlan
    let onComplete: () async -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("Update workout paces?")
                    .font(.dripDisplay(20))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            Text("Your goal changed. Future workouts in this plan still have paces from the previous goal. Want to recompute them so they match the new goal?")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Text("Past workouts and any workouts you've already completed are not changed.")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)

            if let err = errorMessage {
                Text(err)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.coral)
            }

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Keep current paces")
                        .font(.dripLabel(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Color.drip.textPrimary)
                        .background(Color.drip.divider.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isWorking)

                Button {
                    Task { await recompute() }
                } label: {
                    Text(isWorking ? "Updating…" : "Update paces")
                        .font(.dripLabel(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.drip.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isWorking)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isWorking)
    }

    private func recompute() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            // Walks future scheduled_workouts for this plan and re-resolves
            // every step's target_pace using the current athlete_pace_profile
            // (which itself derived from the freshly-updated plan goal).
            let body: [String: Any] = [
                "plan_id": plan.id.uuidString,
                "from_date": ISO8601DateFormatter.dateOnly.string(from: Date()),
            ]
            _ = try await callEdgeFunction(name: "recompute-plan-paces", body: body)
            await onComplete()
            dismiss()
        } catch {
            Log.goals.error("recompute paces failed: \(error.localizedDescription)")
            errorMessage = "Couldn't update paces. Try again or keep current."
        }
    }
}

private extension ISO8601DateFormatter {
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

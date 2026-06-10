//
//  PlanAdjustmentsView.swift
//  RunningLog
//
//  Athlete-facing "Plan updates" feed. Renders the last 30 days of
//  plan_adjustments rows — every automatic edit and pending proposal the
//  adaptive loop has produced. Each card cites the evidence that triggered
//  it and exposes Accept / Revert affordances.
//

import os
import Supabase
import SwiftUI

// MARK: - Model

struct PlanAdjustment: Decodable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let planId: UUID?
    let triggerType: String
    let triggerEvidence: [String]
    let actionType: String
    let actionPayload: Payload
    let autoApplied: Bool
    let appliedAt: Date
    let acknowledgedByUserAt: Date?
    let revertedAt: Date?
    let proposedUntil: Date?

    struct Payload: Decodable, Equatable {
        let rationale: String?
        let deltaSecondsPerMile: Double?
        let capMiles: Double?
        let pauseDays: Int?
        enum CodingKeys: String, CodingKey {
            case rationale
            case deltaSecondsPerMile = "delta_seconds_per_mile"
            case capMiles = "cap_miles"
            case pauseDays = "pause_days"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case planId = "plan_id"
        case triggerType = "trigger_type"
        case triggerEvidence = "trigger_evidence"
        case actionType = "action_type"
        case actionPayload = "action_payload"
        case autoApplied = "auto_applied"
        case appliedAt = "applied_at"
        case acknowledgedByUserAt = "acknowledged_by_user_at"
        case revertedAt = "reverted_at"
        case proposedUntil = "proposed_until"
    }

    /// Decode a [String] from either ["id1","id2"] or [{...}, {...}] — the
    /// server stores evidence as whichever shape the rule produced.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(UUID.self, forKey: .userId)
        self.planId = try c.decodeIfPresent(UUID.self, forKey: .planId)
        self.triggerType = try c.decode(String.self, forKey: .triggerType)
        self.actionType = try c.decode(String.self, forKey: .actionType)
        self.actionPayload = try c.decode(Payload.self, forKey: .actionPayload)
        self.autoApplied = try c.decode(Bool.self, forKey: .autoApplied)
        self.appliedAt = try c.decode(Date.self, forKey: .appliedAt)
        self.acknowledgedByUserAt = try c.decodeIfPresent(Date.self, forKey: .acknowledgedByUserAt)
        self.revertedAt = try c.decodeIfPresent(Date.self, forKey: .revertedAt)
        self.proposedUntil = try c.decodeIfPresent(Date.self, forKey: .proposedUntil)

        // triggerEvidence is stored as JSONB; could be strings or objects.
        if let raw = try? c.decode([String].self, forKey: .triggerEvidence) {
            self.triggerEvidence = raw
        } else if let rawObjects = try? c.decode([AnyDecodable].self, forKey: .triggerEvidence) {
            self.triggerEvidence = rawObjects.map { String(describing: $0.value) }
        } else {
            self.triggerEvidence = []
        }
    }
}

private struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { self.value = v }
        else if let v = try? c.decode(Int.self) { self.value = v }
        else if let v = try? c.decode(Double.self) { self.value = v }
        else if let v = try? c.decode([String: AnyDecodable].self) { self.value = v.mapValues { $0.value } }
        else { self.value = "?" }
    }
}

// MARK: - View

struct PlanAdjustmentsView: View {
    @State private var adjustments: [PlanAdjustment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if isLoading && adjustments.isEmpty {
                        ProgressView()
                            .padding(.top, 40)
                    } else if adjustments.isEmpty {
                        emptyState
                    } else {
                        ForEach(adjustments) { adj in
                            card(for: adj)
                        }
                    }
                }
                .padding(20)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Plan updates")
                .font(.dripDisplay(22))
                .foregroundStyle(Color.drip.textPrimary)
            Spacer()
            if unreadCount > 0 {
                Text("\(unreadCount) new")
                    .font(.dripCaption(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.drip.coral)
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28))
                .foregroundStyle(Color.drip.textTertiary)
            Text("No plan updates in the last 30 days")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var unreadCount: Int {
        adjustments.filter { $0.acknowledgedByUserAt == nil && $0.revertedAt == nil }.count
    }

    // MARK: Card

    private func card(for adj: PlanAdjustment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verb(for: adj))
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                if adj.revertedAt != nil {
                    tag("Reverted", Color.drip.textTertiary)
                } else if adj.acknowledgedByUserAt != nil {
                    tag(adj.autoApplied ? "Applied" : "Accepted", Color.drip.energized)
                } else if !adj.autoApplied {
                    tag("Proposed", Color.drip.coral)
                } else {
                    tag("Auto", Color.drip.textSecondary)
                }
            }

            Text(rationale(for: adj))
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)

            if adj.revertedAt == nil {
                HStack(spacing: 8) {
                    if adj.acknowledgedByUserAt == nil {
                        Button(adj.autoApplied ? "Got it" : "Accept") {
                            Task { await acknowledge(adj) }
                        }
                        .font(.dripLabel(13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.drip.coral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    Button("Revert") {
                        Task { await revert(adj) }
                    }
                    .font(.dripLabel(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule()
                            .stroke(Color.drip.divider, lineWidth: 1)
                    )
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.dripCaption(10))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func verb(for adj: PlanAdjustment) -> String {
        switch adj.triggerType {
        case "pace_over_target":   return "Updated your pace targets"
        case "pace_under_target":  return "Eased your pace targets"
        case "missed_sessions":    return "Held volume steady"
        case "race_result":        return "Updated your fitness estimate"
        case "volume_ramp_risk":   return "Capped next week's mileage"
        case "heat_forecast":      return "Proposed moving a quality session"
        case "weekly_rebalance":   return "Reviewed your week"
        default:                   return "Plan update"
        }
    }

    private func rationale(for adj: PlanAdjustment) -> String {
        adj.actionPayload.rationale
            ?? "The coach adjusted your plan based on recent data."
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let userId = AuthManager.shared.currentUserId else { return }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 24 * 3600))
        do {
            let rows: [PlanAdjustment] = try await supabase
                .from("plan_adjustments")
                .select()
                .eq("user_id", value: userId)
                .gte("applied_at", value: since)
                .order("applied_at", ascending: false)
                .execute()
                .value
            self.adjustments = rows
            self.errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            Log.coach.error("PlanAdjustmentsView load failed: \(error.localizedDescription)")
        }
    }

    private func acknowledge(_ adj: PlanAdjustment) async {
        do {
            try await supabase
                .from("plan_adjustments")
                .update(["acknowledged_by_user_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: adj.id.uuidString)
                .execute()
            await load()
        } catch {
            Log.coach.error("acknowledge failed: \(error.localizedDescription)")
        }
    }

    private func revert(_ adj: PlanAdjustment) async {
        do {
            _ = try await callEdgeFunction(
                name: "revert-plan-adjustment",
                body: ["adjustment_id": adj.id.uuidString]
            )
            await load()
        } catch {
            Log.coach.error("revert failed: \(error.localizedDescription)")
        }
    }
}

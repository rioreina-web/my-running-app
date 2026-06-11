//
//  CoachReadCard.swift
//  RunningLog
//
//  Coach's Read — a single card at the top of the Training Plan view that
//  surfaces what the adaptive backend is saying. Without this card, all the
//  weekly reviews, post-run reconciliations, and heat warnings just sit in
//  the DB and never reach the athlete.
//
//  Data sources (all populated by backend edge functions):
//    - coaching_adjustments: plan adjustment decisions (weekly-plan-review CUT 2026-06-10; coaching-feedback still writes)
//    - ai_insights (type=run_reconciliation): post-run pace deltas
//    - scheduled_workouts.weather_forecast: heat warnings for upcoming quality days
//

import Foundation
import PostgREST
import Supabase
import SwiftUI

// MARK: - Models

struct CoachNote: Identifiable, Codable {
    let id: UUID
    let kind: Kind
    let title: String
    let message: String
    let createdAt: Date
    /// For adjustments with persistent accept/dismiss state
    let adjustmentId: UUID?
    /// Priority for sorting
    let priority: Int

    enum Kind: String, Codable {
        case weeklyReview      // "soften next week", "hold plan"
        case lastRunDelta      // "tempo ran 12s/mi faster than target"
        case heatWarning       // "Thursday's tempo: 92°F forecast"
        case missedWorkout     // "you missed Tuesday's session"
    }

    var icon: String {
        switch kind {
        case .weeklyReview: "calendar.badge.clock"
        case .lastRunDelta: "chart.line.uptrend.xyaxis"
        case .heatWarning: "thermometer.sun.fill"
        case .missedWorkout: "exclamationmark.circle"
        }
    }

    var accentColor: Color {
        switch kind {
        case .weeklyReview: Color.drip.coral
        case .lastRunDelta: Color.drip.energized
        case .heatWarning: Color.drip.coralLight
        case .missedWorkout: Color.drip.tired
        }
    }
}

// MARK: - Service

@Observable
final class CoachReadService {
    var notes: [CoachNote] = []
    var isLoading = false
    var currentPlanId: UUID?
    private var dismissedIds: Set<UUID> = loadDismissedIds()
    let adaptation = PlanAdaptationService()

    @MainActor
    func load(for planId: UUID) async {
        isLoading = true
        currentPlanId = planId
        defer { isLoading = false }

        async let adjustments = fetchRecentAdjustments()
        async let insights = fetchRecentReconciliations()
        async let heatWarnings = fetchHeatWarnings(planId: planId)
        async let missed = fetchMissedWorkouts(planId: planId)

        let (adj, ins, heat, miss) = await (adjustments, insights, heatWarnings, missed)
        let all = (adj + ins + heat + miss)
            .filter { !dismissedIds.contains($0.id) }
            .sorted { ($0.priority, $0.createdAt) > ($1.priority, $1.createdAt) }

        notes = all
    }

    // MARK: - Acceptance

    /// Apply the action implied by a note. Returns a summary of what happened.
    @MainActor
    func accept(_ note: CoachNote) async -> String? {
        guard let planId = currentPlanId else { return nil }

        var summary: String?
        switch note.kind {
        case .weeklyReview:
            // Interpret the title/message to decide what to do
            if note.title.lowercased().contains("soften") {
                summary = await adaptation.softenUpcomingWeek(planId: planId)
            } else {
                // Hold-plan / flag-for-review: just mark as acknowledged
                summary = "Noted."
            }
            if let adjId = note.adjustmentId {
                await adaptation.markAdjustmentApplied(adjId)
            }
        case .heatWarning:
            // Heat warnings don't auto-apply — the athlete needs to pick a day
            summary = "Acknowledged. Tap the workout to reschedule it."
        case .lastRunDelta:
            summary = "Noted."
        case .missedWorkout:
            summary = "Marked as acknowledged."
        }

        // Remove from current list once applied
        notes.removeAll { $0.id == note.id }
        dismissedIds.insert(note.id)
        Self.saveDismissedIds(dismissedIds)
        return summary
    }

    // MARK: - Dismissal (persisted locally)

    @MainActor
    func dismiss(_ note: CoachNote) async {
        dismissedIds.insert(note.id)
        Self.saveDismissedIds(dismissedIds)
        notes.removeAll { $0.id == note.id }
        if let adjId = note.adjustmentId {
            await adaptation.markAdjustmentDismissed(adjId)
        }
    }

    // MARK: - Missed workouts

    private func fetchMissedWorkouts(planId: UUID) async -> [CoachNote] {
        let missed = await adaptation.fetchMissedWorkouts(planId: planId)
        return missed.prefix(2).map { m in
            let dayStr = m.daysLate == 1 ? "yesterday" : "\(m.daysLate) days ago"
            return CoachNote(
                id: m.id,
                kind: .missedWorkout,
                title: "Missed \(m.name)",
                message: "Scheduled \(dayStr). Mark skipped, complete it late, or carry to next week.",
                createdAt: m.date,
                adjustmentId: nil,
                priority: 88
            )
        }
    }

    private static let dismissedKey = "coach_read_dismissed_ids"

    private static func loadDismissedIds() -> Set<UUID> {
        guard let arr = UserDefaults.standard.array(forKey: dismissedKey) as? [String] else { return [] }
        return Set(arr.compactMap { UUID(uuidString: $0) })
    }

    private static func saveDismissedIds(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map { $0.uuidString }, forKey: dismissedKey)
    }

    // MARK: - Fetches

    private func fetchRecentAdjustments() async -> [CoachNote] {
        guard let userId = AuthManager.shared.currentUserId else { return [] }
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let iso = ISO8601DateFormatter()

        struct AdjustmentRow: Codable {
            let id: UUID
            let adjustment_type: String
            let target_workout: String?
            let recommendation: String
            let source: String?
            let followed: Bool?
            let created_at: String
        }

        do {
            let rows: [AdjustmentRow] = try await supabase
                .from("coaching_adjustments")
                .select()
                .eq("user_id", value: userId)
                .is("followed", value: nil)
                .gte("created_at", value: iso.string(from: oneWeekAgo))
                .order("created_at", ascending: false)
                .limit(3)
                .execute()
                .value

            return rows.map { row in
                let decision = extractDecision(row.recommendation)
                let title = prettyTitle(decision: decision, type: row.adjustment_type)
                return CoachNote(
                    id: row.id,
                    kind: .weeklyReview,
                    title: title,
                    message: stripDecisionPrefix(row.recommendation),
                    createdAt: parseDate(row.created_at),
                    adjustmentId: row.id,
                    priority: decision == "flag_for_coach_review" ? 100 : 80
                )
            }
        } catch {
            print("[CoachRead] Failed to fetch adjustments: \(error)")
            return []
        }
    }

    private func fetchRecentReconciliations() async -> [CoachNote] {
        guard let userId = AuthManager.shared.currentUserId else { return [] }
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        let iso = ISO8601DateFormatter()

        struct InsightRow: Codable {
            let id: UUID
            let summary: String?
            let title: String?
            let priority: String?
            let created_at: String
            let full_analysis: FullAnalysis?
        }
        struct FullAnalysis: Codable {
            let is_quality_session: Bool?
            let pace_delta_vs_adjusted: Int?
            let pace_direction_adjusted: String?
            let heat_category: String?
        }

        do {
            let rows: [InsightRow] = try await supabase
                .from("ai_insights")
                .select("id, summary, title, priority, created_at, full_analysis")
                .eq("user_id", value: userId)
                .eq("insight_type", value: "run_reconciliation")
                .gte("created_at", value: iso.string(from: threeDaysAgo))
                .order("created_at", ascending: false)
                .limit(2)
                .execute()
                .value

            return rows.compactMap { row in
                // Only surface quality sessions or sessions with a significant heat adjustment
                let isQuality = row.full_analysis?.is_quality_session ?? false
                let hadHeat = (row.full_analysis?.heat_category ?? "ideal") != "ideal"
                guard isQuality || hadHeat else { return nil }

                return CoachNote(
                    id: row.id,
                    kind: .lastRunDelta,
                    title: isQuality ? "Quality session recap" : "Recent run",
                    message: row.summary ?? row.title ?? "",
                    createdAt: parseDate(row.created_at),
                    adjustmentId: nil,
                    priority: row.priority == "high" ? 90 : 60
                )
            }
        } catch {
            print("[CoachRead] Failed to fetch reconciliations: \(error)")
            return []
        }
    }

    private func fetchHeatWarnings(planId: UUID) async -> [CoachNote] {
        let today = Calendar.current.startOfDay(for: Date())
        let sevenDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        struct WorkoutRow: Codable {
            let id: UUID
            let date: String
            let workout_type: String
            let workout_data: [String: AnyCodable]?
            let weather_forecast: [String: AnyCodable]?
        }

        do {
            let rows: [WorkoutRow] = try await supabase
                .from("scheduled_workouts")
                .select("id, date, workout_type, workout_data, weather_forecast")
                .eq("plan_id", value: planId.uuidString)
                .gte("date", value: dateFmt.string(from: today))
                .lte("date", value: dateFmt.string(from: sevenDaysOut))
                .in("workout_type", values: ["tempo", "intervals", "long_run", "race", "progression"])
                .order("date")
                .execute()
                .value

            return rows.compactMap { row in
                guard let forecast = row.weather_forecast else { return nil }
                let score = (forecast["composite_score"]?.value as? Double) ?? 0
                guard score >= 130 else { return nil }

                let cat = (forecast["heat_category"]?.value as? String) ?? "hot"
                let temp = Int((forecast["temp_f"]?.value as? Double) ?? 0)
                let dp = Int((forecast["dew_point_f"]?.value as? Double) ?? 0)
                let dayName = dayNameFromIso(row.date)
                let workoutName = (row.workout_data?["name"]?.value as? String) ?? row.workout_type

                return CoachNote(
                    id: row.id,
                    kind: .heatWarning,
                    title: "\(cat.replacingOccurrences(of: "_", with: " ").capitalized) forecast · \(dayName)",
                    message: "\(workoutName): \(temp)°F · dp \(dp)°F. Consider moving to early morning or swapping days.",
                    createdAt: Date(),
                    adjustmentId: nil,
                    priority: score >= 170 ? 95 : (score >= 150 ? 85 : 70)
                )
            }
        } catch {
            print("[CoachRead] Failed to fetch heat warnings: \(error)")
            return []
        }
    }

    // MARK: - Helpers

    private func extractDecision(_ text: String) -> String {
        if let range = text.range(of: #"\[(\w+)\]"#, options: .regularExpression) {
            return String(text[range]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        }
        return ""
    }

    private func stripDecisionPrefix(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\[\w+\]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func prettyTitle(decision: String, type: String) -> String {
        switch decision {
        case "hold_plan": return "On track"
        case "soften_week": return "Soften next week"
        case "swap_quality_session": return "Swap suggested"
        case "flag_for_coach_review": return "Something to look at"
        default: return "Coach's note"
        }
    }

    private func parseDate(_ s: String) -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        return iso2.date(from: s) ?? Date()
    }

    private func dayNameFromIso(_ s: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: s) else { return s }
        let out = DateFormatter()
        out.dateFormat = "EEEE"
        return out.string(from: d)
    }
}

// MARK: - AnyCodable (shallow JSON pass-through)

private struct AnyCodable: Codable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = nil }
        else if let v = try? c.decode(Bool.self) { self.value = v }
        else if let v = try? c.decode(Int.self) { self.value = v }
        else if let v = try? c.decode(Double.self) { self.value = v }
        else if let v = try? c.decode(String.self) { self.value = v }
        else if let v = try? c.decode([String: AnyCodable].self) { self.value = v }
        else if let v = try? c.decode([AnyCodable].self) { self.value = v }
        else { self.value = nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encodeNil()
    }
}

// MARK: - Card View

struct CoachReadCard: View {
    @State private var service = CoachReadService()
    @State private var toastMessage: String?
    @State private var applyingNoteId: UUID?
    let planId: UUID

    var body: some View {
        Group {
            if service.notes.isEmpty && toastMessage == nil {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.drip.coral)
                        Text("COACH'S READ")
                            .font(.dripCaption(10))
                            .tracking(1.4)
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        if let first = service.notes.first {
                            Text(relativeTime(from: first.createdAt))
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }

                    if let toast = toastMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.drip.positive)
                            Text(toast)
                                .font(.dripBody(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.drip.positive.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(spacing: 10) {
                        ForEach(service.notes.prefix(3)) { note in
                            CoachNoteRow(
                                note: note,
                                isApplying: applyingNoteId == note.id,
                                onAccept: note.kind == .weeklyReview || note.kind == .missedWorkout
                                    ? { Task { await applyAccept(note) } }
                                    : nil,
                                onDismiss: { Task { await applyDismiss(note) } }
                            )
                        }
                    }
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.drip.coral.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .task(id: planId) {
            await service.load(for: planId)
        }
    }

    @MainActor
    private func applyAccept(_ note: CoachNote) async {
        applyingNoteId = note.id
        let summary = await service.accept(note)
        applyingNoteId = nil
        if let summary {
            withAnimation(.easeOut(duration: 0.25)) {
                toastMessage = summary
            }
            // Auto-hide toast after 4s
            Task {
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        toastMessage = nil
                    }
                }
            }
        }
    }

    @MainActor
    private func applyDismiss(_ note: CoachNote) async {
        _ = withAnimation(.easeOut(duration: 0.2)) {
            Task { await service.dismiss(note) }
        }
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

// MARK: - Note Row

struct CoachNoteRow: View {
    let note: CoachNote
    var isApplying: Bool = false
    var onAccept: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(note.accentColor)
                    .frame(width: 20, alignment: .top)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.dripLabel(13))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(note.message)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(6)
                        .background(Color.drip.background.opacity(0.5))
                        .clipShape(Circle())
                }
                .disabled(isApplying)
            }

            if let onAccept {
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onAccept) {
                        HStack(spacing: 6) {
                            if isApplying {
                                ProgressView().tint(.white).scaleEffect(0.7)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(isApplying ? "Applying…" : acceptLabel)
                                .font(.dripLabel(12))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(note.accentColor)
                        .clipShape(Capsule())
                    }
                    .disabled(isApplying)
                }
            }
        }
    }

    private var acceptLabel: String {
        switch note.kind {
        case .weeklyReview:
            if note.title.lowercased().contains("soften") { return "Apply" }
            return "Noted"
        case .missedWorkout: return "Acknowledge"
        case .heatWarning: return "Got it"
        case .lastRunDelta: return "OK"
        }
    }
}

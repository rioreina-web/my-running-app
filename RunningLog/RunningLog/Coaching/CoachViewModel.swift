//
//  CoachViewModel.swift
//  RunningLog
//
//  Observable state + Supabase CRUD for the coach training plan feature.
//  Used by CoachTabView and all coach/athlete sub-screens.
//

import Foundation
import Observation
import Supabase

// MARK: - CoachViewModel

@Observable
final class CoachViewModel {

    // MARK: State

    var coachProfile: CoachProfile?
    var workoutTemplates: [WorkoutTemplate] = []
    var planTemplates: [PlanTemplate] = []
    var athletes: [CoachAthleteRelationship] = []

    var isLoading = false
    var error: String?

    // Athlete-side: subscriptions for the current user
    var mySubscriptions: [AthletePlanSubscription] = []

    // MARK: - Load All Coach Data

    @MainActor
    func loadCoachData() async {
        isLoading = true
        defer { isLoading = false }
        async let profile: () = loadCoachProfile()
        async let templates: () = loadWorkoutTemplates()
        async let plans: () = loadPlanTemplates()
        async let athleteList: () = loadAthletes()
        _ = await (profile, templates, plans, athleteList)
    }

    // MARK: - Coach Profile

    @MainActor
    func loadCoachProfile() async {
        let userId = currentUserId
        do {
            let result: [CoachProfile] = try await supabase
                .from("coach_profiles")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            coachProfile = result.first
        } catch {
            // No profile yet — that's fine
            ErrorReporter.shared.report(error, context: "load coach profile")
        }
    }

    @MainActor
    func createCoachProfile(displayName: String, bio: String?, specializations: [String]) async {
        let userId = currentUserId
        let insert = CoachProfileInsert(
            userId: userId,
            displayName: displayName,
            bio: bio,
            specializations: specializations
        )
        do {
            let result: [CoachProfile] = try await supabase
                .from("coach_profiles")
                .insert(insert)
                .select()
                .execute()
                .value
            coachProfile = result.first
        } catch {
            print("❌ createCoachProfile error: \(error)")
            self.error = "Failed to create coach profile: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "create coach profile")
        }
    }

    // MARK: - Workout Templates

    @MainActor
    func loadWorkoutTemplates() async {
        guard let coachId = coachProfile?.id else { return }
        do {
            let result: [WorkoutTemplate] = try await supabase
                .from("workout_templates")
                .select()
                .eq("coach_id", value: coachId.uuidString)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            workoutTemplates = result
        } catch {
            self.error = "Failed to load workout templates: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "load workout templates")
        }
    }

    @MainActor
    func saveWorkoutTemplate(_ template: WorkoutTemplate) async -> WorkoutTemplate? {
        guard let coachId = coachProfile?.id else { return nil }
        let insert = WorkoutTemplateInsert(
            coachId: coachId,
            name: template.name,
            workoutType: template.workoutType.rawValue,
            description: template.description,
            tags: template.tags,
            workoutData: template.workoutData,
            estimatedDistanceMiles: template.estimatedDistanceMiles,
            estimatedDurationMinutes: template.estimatedDurationMinutes,
            isPublic: template.isPublic
        )
        do {
            let result: [WorkoutTemplate] = try await supabase
                .from("workout_templates")
                .insert(insert)
                .select()
                .execute()
                .value
            if let saved = result.first {
                workoutTemplates.insert(saved, at: 0)
                return saved
            }
        } catch {
            self.error = "Failed to save workout template: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "save workout template")
        }
        return nil
    }

    @MainActor
    func updateWorkoutTemplate(_ template: WorkoutTemplate) async {
        let insert = WorkoutTemplateInsert(
            coachId: template.coachId,
            name: template.name,
            workoutType: template.workoutType.rawValue,
            description: template.description,
            tags: template.tags,
            workoutData: template.workoutData,
            estimatedDistanceMiles: template.estimatedDistanceMiles,
            estimatedDurationMinutes: template.estimatedDurationMinutes,
            isPublic: template.isPublic
        )
        do {
            try await supabase
                .from("workout_templates")
                .update(insert)
                .eq("id", value: template.id.uuidString)
                .execute()
            if let idx = workoutTemplates.firstIndex(where: { $0.id == template.id }) {
                workoutTemplates[idx] = template
            }
        } catch {
            self.error = "Failed to update workout template: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "update workout template")
        }
    }

    @MainActor
    func deleteWorkoutTemplate(_ template: WorkoutTemplate) async {
        do {
            try await supabase
                .from("workout_templates")
                .delete()
                .eq("id", value: template.id.uuidString)
                .execute()
            workoutTemplates.removeAll { $0.id == template.id }
        } catch {
            self.error = "Failed to delete workout template: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "delete workout template")
        }
    }

    // MARK: - Plan Templates

    @MainActor
    func loadPlanTemplates() async {
        guard let coachId = coachProfile?.id else { return }
        do {
            let result: [PlanTemplate] = try await supabase
                .from("plan_templates")
                .select()
                .eq("coach_id", value: coachId.uuidString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            planTemplates = result
        } catch {
            self.error = "Failed to load plan templates: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "load plan templates")
        }
    }

    /// Save a new plan template draft (not yet published)
    @MainActor
    func savePlanTemplate(_ plan: PlanTemplate) async -> PlanTemplate? {
        guard let coachId = coachProfile?.id else { return nil }
        let insert = PlanTemplateInsert(
            coachId: coachId,
            name: plan.name,
            description: plan.description,
            targetDistance: plan.targetDistance,
            durationWeeks: plan.durationWeeks,
            weeks: plan.weeks
        )
        do {
            let result: [PlanTemplate] = try await supabase
                .from("plan_templates")
                .insert(insert)
                .select()
                .execute()
                .value
            if let saved = result.first {
                planTemplates.insert(saved, at: 0)
                return saved
            }
        } catch {
            self.error = "Failed to save plan template: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "save plan template")
        }
        return nil
    }

    /// Update an existing plan template's weeks/metadata
    @MainActor
    func updatePlanTemplate(_ plan: PlanTemplate) async {
        do {
            struct UpdatePayload: Codable {
                var name: String
                var description: String?
                var targetDistance: String
                var durationWeeks: Int
                var weeks: [PlanTemplateWeek]

                enum CodingKeys: String, CodingKey {
                    case name, description
                    case targetDistance = "target_distance"
                    case durationWeeks = "duration_weeks"
                    case weeks
                }
            }
            let payload = UpdatePayload(
                name: plan.name,
                description: plan.description,
                targetDistance: plan.targetDistance,
                durationWeeks: plan.durationWeeks,
                weeks: plan.weeks
            )
            try await supabase
                .from("plan_templates")
                .update(payload)
                .eq("id", value: plan.id.uuidString)
                .execute()
            if let idx = planTemplates.firstIndex(where: { $0.id == plan.id }) {
                planTemplates[idx] = plan
            }
        } catch {
            self.error = "Failed to update plan template: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "update plan template")
        }
    }

    /// Publish a plan template — generates a unique 6-char join code
    @MainActor
    func publishPlanTemplate(_ plan: PlanTemplate) async -> String? {
        let code = generateJoinCode()
        do {
            struct PublishPayload: Codable {
                var isPublished: Bool
                var joinCode: String

                enum CodingKeys: String, CodingKey {
                    case isPublished = "is_published"
                    case joinCode = "join_code"
                }
            }
            try await supabase
                .from("plan_templates")
                .update(PublishPayload(isPublished: true, joinCode: code))
                .eq("id", value: plan.id.uuidString)
                .execute()
            if let idx = planTemplates.firstIndex(where: { $0.id == plan.id }) {
                planTemplates[idx].isPublished = true
                planTemplates[idx].joinCode = code
            }
            return code
        } catch {
            self.error = "Failed to publish plan: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "publish plan template")
            return nil
        }
    }

    @MainActor
    func unpublishPlanTemplate(_ plan: PlanTemplate) async {
        do {
            struct UnpublishPayload: Codable {
                var isPublished: Bool
                enum CodingKeys: String, CodingKey {
                    case isPublished = "is_published"
                }
            }
            try await supabase
                .from("plan_templates")
                .update(UnpublishPayload(isPublished: false))
                .eq("id", value: plan.id.uuidString)
                .execute()
            if let idx = planTemplates.firstIndex(where: { $0.id == plan.id }) {
                planTemplates[idx].isPublished = false
            }
        } catch {
            self.error = "Failed to unpublish plan: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "unpublish plan template")
        }
    }

    @MainActor
    func deletePlanTemplate(_ plan: PlanTemplate) async {
        do {
            try await supabase
                .from("plan_templates")
                .delete()
                .eq("id", value: plan.id.uuidString)
                .execute()
            planTemplates.removeAll { $0.id == plan.id }
        } catch {
            self.error = "Failed to delete plan template: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "delete plan template")
        }
    }

    // MARK: - Athlete Management (Coach-side)

    @MainActor
    func loadAthletes() async {
        guard let coachId = coachProfile?.id else { return }
        do {
            let result: [CoachAthleteRelationship] = try await supabase
                .from("coach_athlete_relationships")
                .select()
                .eq("coach_id", value: coachId.uuidString)
                .order("invited_at", ascending: false)
                .limit(200)
                .execute()
                .value
            athletes = result
        } catch {
            self.error = "Failed to load athletes: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "load athletes")
        }
    }

    /// Invite an athlete by their user ID (coach knows their Supabase user ID or email lookup)
    @MainActor
    func inviteAthlete(athleteUserId: String) async {
        guard let coachId = coachProfile?.id else { return }
        let insert = CoachAthleteRelationshipInsert(
            coachId: coachId,
            athleteUserId: athleteUserId
        )
        do {
            let result: [CoachAthleteRelationship] = try await supabase
                .from("coach_athlete_relationships")
                .insert(insert)
                .select()
                .execute()
                .value
            if let rel = result.first {
                athletes.insert(rel, at: 0)
            }
        } catch {
            self.error = "Failed to invite athlete: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "invite athlete")
        }
    }

    /// Assign a plan to a specific athlete (creates a subscription + generates their training plan)
    @MainActor
    func assignPlanToAthlete(athleteUserId: String, planTemplate: PlanTemplate, startDate: Date) async {
        await subscribeAthleteToTemplate(
            athleteUserId: athleteUserId,
            planTemplate: planTemplate,
            startDate: startDate
        )
    }

    // MARK: - Plan Subscription (edge function)

    /// Subscribe an athlete to a plan template by calling the subscribe-to-plan edge function.
    /// This generates real `training_plans` + `scheduled_workouts` rows for the athlete.
    @MainActor
    func subscribeAthleteToTemplate(
        athleteUserId: String,
        planTemplate: PlanTemplate,
        startDate: Date,
        goalTimeSeconds: Int? = nil
    ) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = [
            "planTemplateId": planTemplate.id.uuidString,
            "athleteUserId": athleteUserId,
            "startDate": formatter.string(from: startDate),
            "goalTimeSeconds": goalTimeSeconds as Any,
            "targetRaceDistance": planTemplate.targetDistance
        ]
        do {
            let data = try await callEdgeFunction(name: "subscribe-to-plan", body: body)
            let response = try JSONDecoder().decode(SubscribeToPlanResponse.self, from: data)
            if let err = response.error {
                self.error = err
            }
        } catch {
            self.error = "Failed to subscribe to plan: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "subscribe athlete to plan template")
        }
    }

    // MARK: - Athlete-side: Join by Code

    /// Athlete subscribes to a plan via a 6-char join code.
    @MainActor
    func joinPlanByCode(_ code: String, startDate: Date, goalTimeSeconds: Int? = nil) async -> Bool {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        do {
            // Look up the plan template by join code
            let plans: [PlanTemplate] = try await supabase
                .from("plan_templates")
                .select()
                .eq("join_code", value: normalized)
                .eq("is_published", value: true)
                .limit(1)
                .execute()
                .value
            guard let plan = plans.first else {
                self.error = "Plan not found. Check the join code and try again."
                return false
            }
            let userId = currentUserId
            await subscribeAthleteToTemplate(
                athleteUserId: userId,
                planTemplate: plan,
                startDate: startDate,
                goalTimeSeconds: goalTimeSeconds
            )
            return self.error == nil
        } catch {
            self.error = "Invalid join code: \(error.localizedDescription)"
            ErrorReporter.shared.report(error, context: "join plan by code")
            return false
        }
    }

    /// Load the current athlete's subscriptions
    @MainActor
    func loadMySubscriptions() async {
        let userId = currentUserId
        do {
            let result: [AthletePlanSubscription] = try await supabase
                .from("athlete_plan_subscriptions")
                .select()
                .eq("athlete_user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            mySubscriptions = result
        } catch {
            // Ignore — athlete may not have any subscriptions
            ErrorReporter.shared.report(error, context: "load athlete plan subscriptions")
        }
    }

    // MARK: - Helpers

    private var currentUserId: String {
        AuthManager.shared.userId
    }

    private func generateJoinCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

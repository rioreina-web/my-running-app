import os
import Supabase
import SwiftUI

// MARK: - UserGoal

struct UserGoal: Codable, Identifiable {
    let id: UUID
    let goalTitle: String
    let targetDate: Date
    let status: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case goalTitle = "goal_title"
        case targetDate = "target_date"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    var formattedTargetDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: targetDate)
    }

    var isOverdue: Bool {
        daysRemaining < 0
    }
}

// MARK: - UserGoalInsert

struct UserGoalInsert: Codable {
    var userId: String?
    var goalTitle: String
    var targetDate: Date
    var status: String = "active"

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case goalTitle = "goal_title"
        case targetDate = "target_date"
        case status
    }
}

// MARK: - GoalsView

struct GoalsView: View {
    @State private var goals: [UserGoal] = []
    @State private var isLoading = false
    @State private var showAddGoal = false
    @State private var selectedGoal: UserGoal?
    @State private var showCompletedSection = false

    var activeGoals: [UserGoal] {
        goals.filter { $0.status == "active" }
    }

    var completedGoals: [UserGoal] {
        goals.filter { $0.status == "completed" }
    }

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Active Goals Section
                    if !activeGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader("Active Goals", action: loadGoals, actionIcon: "arrow.clockwise")
                                .padding(.horizontal, 20)

                            LazyVStack(spacing: 12) {
                                ForEach(activeGoals) { goal in
                                    GoalCard(goal: goal)
                                        .onTapGesture {
                                            selectedGoal = goal
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 8)
                    }

                    // Empty State
                    if activeGoals.isEmpty, !isLoading {
                        EmptyGoalsView {
                            showAddGoal = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 40)
                    }

                    // Loading State
                    if isLoading {
                        VStack(spacing: 12) {
                            ForEach(0 ..< 2, id: \.self) { _ in
                                GoalCardSkeleton()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }

                    // Completed Goals Section
                    if !completedGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showCompletedSection.toggle()
                                }
                            } label: {
                                HStack {
                                    Text("COMPLETED (\(completedGoals.count))")
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .tracking(1.5)

                                    Spacer()

                                    Image(systemName: showCompletedSection ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }
                                .padding(.horizontal, 24)
                            }

                            if showCompletedSection {
                                LazyVStack(spacing: 12) {
                                    ForEach(completedGoals) { goal in
                                        GoalCard(goal: goal, isCompleted: true)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.top, 8)
                    }

                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("Logo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)
            }
            ToolbarItem(placement: .principal) {
                Text("GOALS")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddGoal = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task { await fetchGoals() }
        }
        .sheet(isPresented: $showAddGoal) {
            AddGoalSheet {
                Task { await fetchGoals() }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedGoal) { goal in
            GoalDetailSheet(goal: goal) {
                Task { await fetchGoals() }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func loadGoals() {
        Task { await fetchGoals() }
    }

    private func fetchGoals() async {
        await MainActor.run { isLoading = true }

        do {
            let response: [UserGoal] = try await supabase
                .from("user_goals")
                .select()
                .order("target_date", ascending: true)
                .limit(50)
                .execute()
                .value

            await MainActor.run {
                goals = response
                isLoading = false
            }
        } catch {
            Log.goals.error("Failed to fetch goals: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - GoalCard

struct GoalCard: View {
    let goal: UserGoal
    var isCompleted: Bool = false

    var progressColor: Color {
        if isCompleted {
            return Color.drip.energized
        }
        if goal.isOverdue {
            return Color.drip.struggling
        }
        if goal.daysRemaining <= 7 {
            return Color.drip.tired
        }
        if goal.daysRemaining <= 30 {
            return Color.drip.coral
        }
        return Color.drip.energized
    }

    var body: some View {
        HStack(spacing: 16) {
            // Progress indicator
            ZStack {
                Circle()
                    .fill(progressColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(progressColor)
                } else {
                    VStack(spacing: 0) {
                        Text("\(abs(goal.daysRemaining))")
                            .font(.dripStat(18))
                            .foregroundStyle(progressColor)
                        Text(goal.isOverdue ? "AGO" : "DAYS")
                            .font(.dripCaption(8))
                            .foregroundStyle(progressColor.opacity(0.8))
                    }
                }
            }

            // Goal info
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.goalTitle)
                    .font(.dripLabel(16))
                    .foregroundStyle(isCompleted ? Color.drip.textSecondary : Color.drip.textPrimary)
                    .strikethrough(isCompleted)

                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(goal.formattedTargetDate)
                        .font(.dripCaption(12))
                }
                .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCompleted ? Color.drip.divider : progressColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - GoalCardSkeleton

struct GoalCardSkeleton: View {
    var body: some View {
        SkeletonPulse {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color.drip.cardBackgroundElevated)
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBar(width: 180, height: 16)
                    SkeletonBar(width: 100, height: 12)
                }

                Spacer()
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - EmptyGoalsView

struct EmptyGoalsView: View {
    let onAddGoal: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "target")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 8) {
                Text("Set Your First Goal")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Add a race, milestone, or training target to get personalized coaching.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            DripButton("Add Goal", icon: "plus", style: .primary) {
                onAddGoal()
            }
            .frame(width: 160)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - AddGoalSheet

struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var goalTitle = ""
    @State private var targetDate = Date().addingTimeInterval(86400 * 30) // Default 30 days
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    let onSaved: () -> Void

    var isValid: Bool {
        !goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Goal Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GOAL")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        TextField("e.g., Boston Marathon 2026", text: $goalTitle)
                            .font(.dripBody(16))
                            .foregroundStyle(Color.drip.textPrimary)
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                    }

                    // Target Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TARGET DATE")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Color.drip.coral)
                            .colorScheme(.dark)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                    }

                    Spacer()

                    // Save Button
                    DripButton("Save Goal", icon: "checkmark", style: .primary, isLoading: isSaving) {
                        Task { await saveGoal() }
                    }
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.5)
                }
                .padding(20)
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private func saveGoal() async {
        guard isValid else { return }

        await MainActor.run { isSaving = true }

        do {
            let newGoal = UserGoalInsert(
                userId: AuthManager.shared.currentUserId,
                goalTitle: goalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                targetDate: targetDate
            )

            try await supabase
                .from("user_goals")
                .insert(newGoal)
                .execute()

            await MainActor.run {
                isSaving = false
                onSaved()
                dismiss()
            }

            // Fetch race intel in the background for race-related goals
            let title = goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = targetDate
            Task.detached {
                await Self.fetchRaceIntel(raceName: title, raceDate: date)
            }
        } catch {
            Log.goals.error("Failed to save goal: \(error)")
            await MainActor.run {
                isSaving = false
                errorMessage = "Failed to save goal. Make sure the database is set up."
                showError = true
            }
        }
    }

    /// Fetch race intel from the edge function if the goal looks like a race
    private static func fetchRaceIntel(raceName: String, raceDate: Date) async {
        let raceKeywords = ["marathon", "half", "5k", "10k", "15k", "relay", "ultra", "mile", "race"]
        let lower = raceName.lowercased()
        guard raceKeywords.contains(where: { lower.contains($0) }) else { return }

        let userId = AuthManager.shared.userId
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: raceDate)

        do {
            _ = try await callEdgeFunction(
                name: "race-intel",
                body: [
                    "race_name": raceName,
                    "race_date": dateStr,
                    "user_id": userId,
                ]
            )
            Log.goals.info("Race intel fetched for: \(raceName)")
        } catch {
            Log.goals.error("Race intel fetch failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - GoalDetailSheet

struct GoalDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goal: UserGoal
    let onUpdate: () -> Void

    @State private var isUpdating = false
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedDate: Date = .init()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    if isEditing {
                        // Edit Mode
                        VStack(spacing: 20) {
                            // Goal Title Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GOAL")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)

                                TextField("Goal title", text: $editedTitle)
                                    .font(.dripBody(16))
                                    .foregroundStyle(Color.drip.textPrimary)
                                    .padding(16)
                                    .background(Color.drip.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.drip.coral.opacity(0.5), lineWidth: 1)
                                    )
                            }

                            // Target Date Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TARGET DATE")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.2)

                                DatePicker("", selection: $editedDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(Color.drip.coral)
                                    .colorScheme(.dark)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.drip.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.drip.coral.opacity(0.5), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(20)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        // View Mode - Goal Info Card
                        VStack(spacing: 20) {
                            // Days countdown
                            VStack(spacing: 4) {
                                Text("\(abs(goal.daysRemaining))")
                                    .font(.dripStat(60))
                                    .foregroundStyle(goal.isOverdue ? Color.drip.struggling : Color.drip.coral)

                                Text(goal.isOverdue ? "DAYS OVERDUE" : "DAYS TO GO")
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.5)
                            }

                            // Goal title
                            Text(goal.goalTitle)
                                .font(.dripLabel(20))
                                .foregroundStyle(Color.drip.textPrimary)
                                .multilineTextAlignment(.center)

                            // Target date
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14))
                                Text(goal.formattedTargetDate)
                                    .font(.dripCaption(14))
                            }
                            .foregroundStyle(Color.drip.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                    }

                    Spacer()

                    // Action Buttons
                    VStack(spacing: 12) {
                        if isEditing {
                            DripButton("Save Changes", icon: "checkmark", style: .primary, isLoading: isUpdating) {
                                Task { await saveGoalEdits() }
                            }
                            .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                            DripButton("Cancel", icon: "xmark", style: .ghost) {
                                withAnimation(.spring(response: 0.3)) {
                                    isEditing = false
                                }
                            }
                        } else {
                            // Edit button
                            DripButton("Edit Goal", icon: "pencil", style: .secondary) {
                                editedTitle = goal.goalTitle
                                editedDate = goal.targetDate
                                withAnimation(.spring(response: 0.3)) {
                                    isEditing = true
                                }
                            }

                            if goal.status == "active" {
                                DripButton("Mark Complete", icon: "checkmark.circle.fill", style: .primary, isLoading: isUpdating) {
                                    Task { await updateStatus("completed") }
                                }

                                DripButton("Archive Goal", icon: "archivebox", style: .ghost) {
                                    Task { await updateStatus("archived") }
                                }
                            } else {
                                DripButton("Reactivate Goal", icon: "arrow.uturn.left", style: .secondary) {
                                    Task { await updateStatus("active") }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(isEditing ? "Edit Goal" : "Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func saveGoalEdits() async {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        await MainActor.run { isUpdating = true }

        do {
            // Format date for Supabase
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let dateString = formatter.string(from: editedDate)

            try await supabase
                .from("user_goals")
                .update([
                    "goal_title": trimmedTitle,
                    "target_date": dateString
                ])
                .eq("id", value: goal.id.uuidString)
                .execute()

            await MainActor.run {
                isUpdating = false
                onUpdate()
                dismiss()
            }
        } catch {
            Log.goals.error("Failed to update goal: \(error)")
            await MainActor.run { isUpdating = false }
        }
    }

    private func updateStatus(_ newStatus: String) async {
        await MainActor.run { isUpdating = true }

        do {
            try await supabase
                .from("user_goals")
                .update(["status": newStatus])
                .eq("id", value: goal.id.uuidString)
                .execute()

            await MainActor.run {
                isUpdating = false
                onUpdate()
                dismiss()
            }
        } catch {
            Log.goals.error("Failed to update goal: \(error)")
            await MainActor.run { isUpdating = false }
        }
    }
}

#Preview {
    NavigationStack {
        GoalsView()
    }
}

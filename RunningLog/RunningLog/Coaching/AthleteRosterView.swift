//
//  AthleteRosterView.swift
//  RunningLog
//
//  Coach's roster of linked athletes. Shows status, subscribed plan.
//  Tap an athlete to view their detail. Invite via user ID.
//

import SwiftUI

// MARK: - AthleteRosterView

struct AthleteRosterView: View {
    @Environment(CoachViewModel.self) private var viewModel
    @State private var showInviteSheet = false
    @State private var showAthleteDetail: CoachAthleteRelationship? = nil

    private var activeAthletes: [CoachAthleteRelationship] {
        viewModel.athletes.filter { $0.status == .active }
    }

    private var pendingAthletes: [CoachAthleteRelationship] {
        viewModel.athletes.filter { $0.status == .pending }
    }

    var body: some View {
        ZStack {
            DripBackground().ignoresSafeArea()

            if viewModel.athletes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        if !activeAthletes.isEmpty {
                            athleteSection(title: "ACTIVE", athletes: activeAthletes)
                        }
                        if !pendingAthletes.isEmpty {
                            athleteSection(title: "PENDING INVITATION", athletes: pendingAthletes)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.bottom, 60)
                }
            }
        }
        .navigationTitle("Athletes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showInviteSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16))
                        Text("Invite")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteAthleteSheet()
                .environment(viewModel)
        }
        .sheet(item: $showAthleteDetail) { athlete in
            AthleteDetailView(relationship: athlete)
                .environment(viewModel)
        }
        .task {
            if viewModel.athletes.isEmpty {
                await viewModel.loadAthletes()
            }
        }
    }

    private func athleteSection(title: String, athletes: [CoachAthleteRelationship]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)

            VStack(spacing: 0) {
                ForEach(athletes) { athlete in
                    AthleteRow(relationship: athlete) {
                        showAthleteDetail = athlete
                    }
                    if athlete.id != athletes.last?.id {
                        Divider()
                            .background(Color.drip.divider)
                            .padding(.leading, 20)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.drip.textTertiary)
            Text("No athletes yet")
                .font(.dripLabel(17))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Invite athletes by their user ID to link them to your coaching account")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showInviteSheet = true
            } label: {
                Text("Invite an Athlete")
                    .font(.dripLabel(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

// MARK: - AthleteRow

struct AthleteRow: View {
    let relationship: CoachAthleteRelationship
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar placeholder
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.drip.coral)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(relationship.athleteUserId)
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(relationship.status == .active ? Color.drip.positive : Color.drip.tired)
                            .frame(width: 6, height: 6)
                        Text(relationship.status.displayName)
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.drip.cardBackground)
        }
    }
}

// MARK: - InviteAthleteSheet

struct InviteAthleteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel

    @State private var athleteUserId = ""
    @State private var isInviting = false

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ATHLETE USER ID")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                        TextField("Enter athlete's user ID or email", text: $athleteUserId)
                            .font(.dripBody(15))
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        Text("The athlete will receive a notification to accept your coaching invitation.")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }

                    Button {
                        Task {
                            isInviting = true
                            await viewModel.inviteAthlete(athleteUserId: athleteUserId.trimmingCharacters(in: .whitespaces))
                            isInviting = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isInviting {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            } else {
                                Image(systemName: "person.badge.plus")
                            }
                            Text(isInviting ? "Sending..." : "Send Invitation")
                                .font(.dripLabel(15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(athleteUserId.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(athleteUserId.isEmpty || isInviting)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Invite Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AthleteDetailView

struct AthleteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel

    let relationship: CoachAthleteRelationship
    @State private var showAssignPlan = false

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Athlete header
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.drip.coral.opacity(0.12))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color.drip.coral)
                            }
                            Text(relationship.athleteUserId)
                                .font(.dripLabel(17))
                                .foregroundStyle(Color.drip.textPrimary)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(relationship.status == .active ? Color.drip.positive : Color.drip.tired)
                                    .frame(width: 6, height: 6)
                                Text(relationship.status.displayName)
                                    .font(.dripCaption(13))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                        .padding(.top, 8)

                        // Assign plan
                        VStack(alignment: .leading, spacing: 10) {
                            Text("COACHING PLAN")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)

                            Button {
                                showAssignPlan = true
                            } label: {
                                HStack {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.drip.coral)
                                    Text("Assign a Training Plan")
                                        .font(.dripBody(15))
                                        .foregroundStyle(Color.drip.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .sheet(isPresented: $showAssignPlan) {
                AssignPlanSheet(athleteUserId: relationship.athleteUserId)
                    .environment(viewModel)
            }
        }
    }
}

// MARK: - AssignPlanSheet

struct AssignPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachViewModel.self) private var viewModel

    let athleteUserId: String
    @State private var selectedPlan: PlanTemplate? = nil
    @State private var startDate = Date()
    @State private var isAssigning = false

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                VStack(spacing: 20) {
                    // Plan picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SELECT PLAN")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(viewModel.planTemplates) { plan in
                                    Button {
                                        selectedPlan = plan
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(plan.name)
                                                    .font(.dripLabel(14))
                                                    .foregroundStyle(Color.drip.textPrimary)
                                                Text("\(plan.targetDistanceDisplay) · \(plan.durationWeeks) weeks")
                                                    .font(.dripCaption(12))
                                                    .foregroundStyle(Color.drip.textSecondary)
                                            }
                                            Spacer()
                                            if selectedPlan?.id == plan.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.drip.coral)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(Color.drip.cardBackground)
                                    }
                                    Divider().background(Color.drip.divider)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }
                        .frame(maxHeight: 280)
                    }

                    // Start date
                    VStack(alignment: .leading, spacing: 10) {
                        Text("START DATE")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Color.drip.coral)
                    }

                    // Assign button
                    Button {
                        guard let plan = selectedPlan else { return }
                        Task {
                            isAssigning = true
                            await viewModel.assignPlanToAthlete(
                                athleteUserId: athleteUserId,
                                planTemplate: plan,
                                startDate: startDate
                            )
                            isAssigning = false
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isAssigning {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            } else {
                                Image(systemName: "calendar.badge.checkmark")
                            }
                            Text(isAssigning ? "Assigning..." : "Assign Plan")
                                .font(.dripLabel(15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedPlan == nil ? Color.drip.textTertiary : Color.drip.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedPlan == nil || isAssigning)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle("Assign Training Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
    }
}

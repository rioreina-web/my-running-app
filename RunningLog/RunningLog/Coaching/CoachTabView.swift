//
//  CoachTabView.swift
//  RunningLog
//
//  Root view for coach mode. Replaces the Plan tab when a user activates coach mode.
//  Sub-tabs: Workout Library · Training Plans · Athletes
//

import SwiftUI

// MARK: - CoachTabView

struct CoachTabView: View {
    @State private var viewModel = CoachViewModel()
    @State private var selectedSection: CoachSection = .workouts
    @State private var showSetupSheet = false

    enum CoachSection: String, CaseIterable {
        case workouts = "Library"
        case plans = "Plans"
        case athletes = "Athletes"

        var icon: String {
            switch self {
            case .workouts: return "dumbbell.fill"
            case .plans: return "calendar.badge.checkmark"
            case .athletes: return "person.2.fill"
            }
        }
    }

    var body: some View {
        Group {
            if viewModel.coachProfile == nil && !viewModel.isLoading {
                // First launch: coach setup
                CoachSetupView(viewModel: viewModel)
            } else {
                mainContent
            }
        }
        .task {
            await viewModel.loadCoachProfile()
        }
    }

    private var mainContent: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    // Section picker
                    HStack(spacing: 0) {
                        ForEach(CoachSection.allCases, id: \.self) { section in
                            Button {
                                selectedSection = section
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 16, weight: .medium))
                                    Text(section.rawValue)
                                        .font(.dripCaption(11))
                                }
                                .foregroundStyle(selectedSection == section ? Color.drip.coral : Color.drip.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 2)
                                        .foregroundStyle(selectedSection == section ? Color.drip.coral : .clear)
                                        .offset(y: 1),
                                    alignment: .bottom
                                )
                            }
                        }
                    }
                    .background(Color.drip.cardBackground)

                    Divider().background(Color.drip.divider)

                    // Content
                    switch selectedSection {
                    case .workouts:
                        WorkoutTemplateLibraryView()
                            .environment(viewModel)
                    case .plans:
                        PlanTemplateListView()
                            .environment(viewModel)
                    case .athletes:
                        AthleteRosterView()
                            .environment(viewModel)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("COACH MODE")
                            .font(.dripCaption(13))
                            .foregroundStyle(Color.drip.coral)
                        if let coach = viewModel.coachProfile {
                            Text(coach.displayName)
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
            }
            .task {
                if viewModel.coachProfile != nil {
                    await viewModel.loadCoachData()
                }
            }
        }
    }
}

// MARK: - CoachSetupView

struct CoachSetupView: View {
    let viewModel: CoachViewModel
    @State private var displayName = ""
    @State private var bio = ""
    @State private var selectedSpecializations: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    let specializations = ["Marathon", "Half Marathon", "10K", "5K", "Trail", "Track", "Ultra", "Triathlon"]

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // Hero
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.drip.coral.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "figure.run.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color.drip.coral)
                            }
                            Text("Set Up Your Coach Profile")
                                .font(.dripLabel(20))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("Create your coach profile to start building training plans and working with athletes.")
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 20)

                        // Fields
                        VStack(alignment: .leading, spacing: 16) {
                            Text("YOUR NAME")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            TextField("e.g. Alex Smith", text: $displayName)
                                .font(.dripBody(16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("BIO (OPTIONAL)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            TextField("Tell athletes about your coaching background...", text: $bio, axis: .vertical)
                                .font(.dripBody(15))
                                .lineLimit(3...5)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("SPECIALIZATIONS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                            FlowLayout(spacing: 8) {
                                ForEach(specializations, id: \.self) { spec in
                                    let selected = selectedSpecializations.contains(spec)
                                    Button {
                                        if selected {
                                            selectedSpecializations.remove(spec)
                                        } else {
                                            selectedSpecializations.insert(spec)
                                        }
                                    } label: {
                                        Text(spec)
                                            .font(.dripCaption(13))
                                            .foregroundStyle(selected ? .white : Color.drip.textPrimary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selected ? Color.drip.coral : Color.drip.cardBackground)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(selected ? Color.drip.coral : Color.drip.divider, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }

                        if let msg = errorMessage {
                            Text(msg)
                                .font(.dripCaption(13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task {
                                isSaving = true
                                errorMessage = nil
                                await viewModel.createCoachProfile(
                                    displayName: displayName,
                                    bio: bio.isEmpty ? nil : bio,
                                    specializations: Array(selectedSpecializations)
                                )
                                isSaving = false
                                if viewModel.coachProfile == nil {
                                    errorMessage = viewModel.error ?? "Failed to create profile. Check your connection."
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text(isSaving ? "Creating..." : "Create Profile")
                                    .font(.dripLabel(16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(displayName.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(displayName.isEmpty || isSaving)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

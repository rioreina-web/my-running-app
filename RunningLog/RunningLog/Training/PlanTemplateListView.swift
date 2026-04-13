//
//  PlanTemplateListView.swift
//  RunningLog
//
//  Lists the coach's plan templates. Supports create, edit, publish/unpublish,
//  copy join code, and delete via swipe actions.
//

import SwiftUI

// MARK: - PlanTemplateListView

struct PlanTemplateListView: View {
    @Environment(CoachViewModel.self) private var viewModel
    @State private var showBuilder = false
    @State private var editingPlan: PlanTemplate? = nil
    @State private var showPublishConfirm = false
    @State private var planToPublish: PlanTemplate? = nil
    @State private var copiedJoinCode: String? = nil

    var body: some View {
        ZStack {
            DripBackground().ignoresSafeArea()

            if viewModel.planTemplates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.planTemplates) { plan in
                            PlanTemplateRow(
                                plan: plan,
                                onEdit: {
                                    editingPlan = plan
                                    showBuilder = true
                                },
                                onPublish: {
                                    if plan.isPublished {
                                        Task { await viewModel.unpublishPlanTemplate(plan) }
                                    } else {
                                        planToPublish = plan
                                        showPublishConfirm = true
                                    }
                                },
                                onCopyCode: {
                                    if let code = plan.joinCode {
                                        UIPasteboard.general.string = code
                                        copiedJoinCode = code
                                    }
                                },
                                onDelete: {
                                    Task { await viewModel.deletePlanTemplate(plan) }
                                }
                            )

                            Divider()
                                .background(Color.drip.divider)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("Training Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingPlan = nil
                    showBuilder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .sheet(isPresented: $showBuilder) {
            PlanTemplateBuilderView(existingPlan: editingPlan)
                .environment(viewModel)
        }
        .confirmationDialog(
            "Publish \"\(planToPublish?.name ?? "")\"?",
            isPresented: $showPublishConfirm,
            titleVisibility: .visible
        ) {
            Button("Publish & Generate Join Code") {
                guard let plan = planToPublish else { return }
                Task {
                    if let code = await viewModel.publishPlanTemplate(plan) {
                        UIPasteboard.general.string = code
                        copiedJoinCode = code
                    }
                    planToPublish = nil
                }
            }
            Button("Cancel", role: .cancel) { planToPublish = nil }
        } message: {
            Text("Athletes can join using the 6-character code. The code will be copied to your clipboard.")
        }
        .overlay(alignment: .bottom) {
            if let code = copiedJoinCode {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.drip.positive)
                    Text("Join code \(code) copied!")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { copiedJoinCode = nil }
                    }
                }
            }
        }
        .animation(.spring(response: 0.3), value: copiedJoinCode)
        .task {
            if viewModel.planTemplates.isEmpty {
                await viewModel.loadPlanTemplates()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(Color.drip.textTertiary)
            Text("No training plans yet")
                .font(.dripLabel(17))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Create a training plan template that athletes can subscribe to")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                editingPlan = nil
                showBuilder = true
            } label: {
                Text("Build a Plan")
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

// MARK: - PlanTemplateRow

struct PlanTemplateRow: View {
    let plan: PlanTemplate
    let onEdit: () -> Void
    let onPublish: () -> Void
    let onCopyCode: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator
            Circle()
                .fill(plan.isPublished ? Color.drip.positive : Color.drip.textTertiary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(plan.targetDistanceDisplay)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.coral)
                    Text("·")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                    Text("\(plan.durationWeeks) weeks")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                    if plan.subscriberCount > 0 {
                        Text("·")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text("\(plan.subscriberCount) athlete\(plan.subscriberCount == 1 ? "" : "s")")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                if plan.isPublished, let code = plan.joinCode {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text("Code: \(code)")
                            .font(.dripStat(12))
                    }
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Published badge
            if plan.isPublished {
                Text("LIVE")
                    .font(.dripCaption(10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.drip.positive)
                    .clipShape(Capsule())
            } else {
                Text("DRAFT")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.drip.divider)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.drip.cardBackground)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onPublish) {
                Label(
                    plan.isPublished ? "Unpublish" : "Publish",
                    systemImage: plan.isPublished ? "eye.slash" : "checkmark.seal.fill"
                )
            }
            .tint(plan.isPublished ? Color.drip.tired : Color.drip.positive)

            if plan.joinCode != nil {
                Button(action: onCopyCode) {
                    Label("Copy Code", systemImage: "link")
                }
                .tint(Color.drip.coralLight)
            }
        }
    }
}

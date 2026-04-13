import SwiftUI

// MARK: - InjuryListView

struct InjuryListView: View {
    @State private var injuryService = InjuryService()
    @State private var selectedInjury: Injury?
    @State private var showAddInjury = false

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Medical disclaimer
                    MedicalDisclaimerBanner(text: MedicalDisclaimer.short, isCompact: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Active injuries
                    if !injuryService.activeInjuries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Active (\(injuryService.activeInjuries.count))")
                                .padding(.horizontal, 20)

                            LazyVStack(spacing: 10) {
                                ForEach(injuryService.activeInjuries) { injury in
                                    InjuryCard(injury: injury)
                                        .onTapGesture { selectedInjury = injury }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Resolved injuries
                    if !injuryService.resolvedInjuries.isEmpty {
                        ResolvedInjuriesSection(
                            injuries: injuryService.resolvedInjuries,
                            onSelect: { selectedInjury = $0 }
                        )
                    }

                    // Empty state
                    if injuryService.injuries.isEmpty && !injuryService.isLoading {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.drip.positive.opacity(0.5))

                            Text("No injuries tracked")
                                .font(.dripBody(16))
                                .foregroundStyle(Color.drip.textSecondary)

                            Text("Injuries detected in voice memos or coaching will appear here automatically. You can also add them manually.")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.top, 60)
                    }

                    Spacer().frame(height: 80)
                }
            }

            // Floating add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showAddInjury = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.drip.coral)
                            .clipShape(Circle())
                            .shadow(color: Color.drip.coral.opacity(0.4), radius: 8, y: 4)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }

            if injuryService.isLoading {
                ProgressView()
                    .tint(Color.drip.coral)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("INJURIES")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task { await injuryService.fetchInjuries() }
        }
        .sheet(item: $selectedInjury) { injury in
            InjuryDetailSheet(injury: injury, injuryService: injuryService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddInjury) {
            AddInjurySheet(injuryService: injuryService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - InjuryCard

struct InjuryCard: View {
    let injury: Injury

    var body: some View {
        HStack(spacing: 14) {
            // Severity indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(injury.severityColor)
                .frame(width: 4, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(injury.displayName)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    // Status badge
                    HStack(spacing: 3) {
                        Image(systemName: injury.status.icon)
                            .font(.system(size: 8))
                        Text(injury.status.displayName.uppercased())
                            .font(.dripCaption(9))
                            .tracking(0.5)
                    }
                    .foregroundStyle(injury.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(injury.status.color.opacity(0.12))
                    .clipShape(Capsule())

                    Spacer()

                    // Source icon
                    Image(systemName: injury.source.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                HStack(spacing: 12) {
                    // Severity
                    HStack(spacing: 4) {
                        SeverityDots(severity: injury.severity)
                        Text("\(injury.severity)/10")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    // Duration
                    Text("\(injury.daysSinceReported)d")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)

                    if let desc = injury.description, !desc.isEmpty {
                        Text(desc)
                            .font(.dripBody(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - SeverityDots

struct SeverityDots: View {
    let severity: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 10, id: \.self) { level in
                Circle()
                    .fill(level <= severity ? colorForLevel(level) : Color.drip.textTertiary.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

// MARK: - ResolvedInjuriesSection

struct ResolvedInjuriesSection: View {
    let injuries: [Injury]
    let onSelect: (Injury) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("RESOLVED")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(1.2)

                    Text("\(injuries.count)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.drip.textTertiary.opacity(0.15))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 20)

            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(injuries) { injury in
                        InjuryCard(injury: injury)
                            .opacity(0.7)
                            .onTapGesture { onSelect(injury) }
                    }
                }
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - MedicalDisclaimerBanner

struct MedicalDisclaimerBanner: View {
    let text: String
    var isCompact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.circle.fill")
                .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                .foregroundStyle(Color.drip.injured)

            Text(text)
                .font(isCompact ? .dripCaption(11) : .dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.injured.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.injured.opacity(0.2), lineWidth: 1)
        )
    }
}

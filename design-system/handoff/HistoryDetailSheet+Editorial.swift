//
//  HistoryDetailSheet+Editorial.swift
//  RunningLog
//
//  Direction A · "Editorial" port of the Log Details sheet body.
//
//  ⚠️ DROP-IN UPDATE — 2026-06-17
//  Differs from the version currently in the repo in exactly three spots,
//  all inside `editorialBody`. Diff this against your file and take just
//  these three; everything else is byte-for-byte identical:
//
//    1. "AI SUMMARY" eyebrow → "VOICE RECAP".
//         The cleaned-notes block summarizes the dictated voice memo, so
//         "AI SUMMARY" was generic. New term names the source.
//
//    2. WORKOUT NOTES moved ABOVE COACH INSIGHT.
//         The athlete's own notes now read before the coach's reply —
//         input first, AI response last.
//
//    3. COACH INSIGHT generate action is now a persistent button labeled
//         "GENERATE AI INSIGHT →" (was the "Ask the coach →" text link that
//         only appeared when empty). It now also shows as a quiet
//         "REGENERATE →" affordance under an existing insight.
//
//  Drop-in replacement for the `ScrollView { VStack { … } }` block in
//  `HistoryDetailSheet.body`. The wrapping `NavigationStack` + `ZStack` +
//  `Color.drip.background.ignoresSafeArea()` stay. The toolbar wiring,
//  sheets, alert, and `.task`/`.onAppear` hooks at the bottom of the
//  original file all stay as they are.
//
//  Depends on:
//    • DripEditorialPrimitives.swift (DripPlateStrip, DripHairline,
//      DripEyebrow, DripStatStrip, DripTextLink)
//    • Existing tokens: Color.drip.*, .dripCaption(n), .dripDisplay(n),
//      .dripBody(n), .dripLabel(n)
//    • HistoryDetailViewModel.generateCoachInsight() for the
//      "Generate AI Insight →" button wiring
//

import SwiftUI

// MARK: - File-private date helpers
//
// The handoff plate strip wants "MAY 22" + "09:06" — mono, uppercase.
// The shared `Date.shortDateString` returns "May 21, 9:06 AM" and is
// used elsewhere (HistoryView, "Logged …" footers). Don't change it —
// add local helpers instead.

private extension Date {
    var editorialDateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self).uppercased()
    }

    var editorialTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}

extension HistoryDetailSheet {

    // ────────────────────────────────────────────────────────────────────
    // Editorial body
    // ────────────────────────────────────────────────────────────────────
    @ViewBuilder
    var editorialBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Plate strip ──────────────────────────────────────────
                DripPlateStrip(
                    leadingBottom: "JOURNAL · ENTRY DETAIL",
                    trailingTop: vm.currentEntry.displayDate.editorialDateString,
                    trailingBottom: vm.currentEntry.displayDate.editorialTimeString
                )

                // ── Top hairline ─────────────────────────────────────────
                DripHairline().padding(.horizontal, 24).padding(.top, 24)

                // ── Day heading ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.currentEntry.displayDate.dayOfWeekString)
                        .font(.dripDisplay(44))
                        .foregroundStyle(Color.drip.textPrimary)

                    if isEditing {
                        EditableMoodPicker(selectedMood: $editMood)
                    } else if let mood = vm.currentEntry.mood, !mood.isEmpty {
                        MoodBadge(mood: mood)
                    } else {
                        Text("— " + vm.currentEntry.displayDate.fullDateString + " —")
                            .font(.dripBody(13).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 26)

                // ── Editable type + stats (edit mode only) ───────────────
                // These two sections (EditableWorkoutTypeSection /
                // EditableWorkoutStatsSection) existed but were never wired
                // into the editorial port — only the mood picker made it in,
                // so workout type, distance, and duration were uneditable.
                // saveEdits() already persists all three; this binds them.
                if isEditing {
                    VStack(spacing: 16) {
                        EditableWorkoutTypeSection(selectedType: $editWorkoutType)
                        EditableWorkoutStatsSection(
                            distanceText: $editDistanceText,
                            durationText: $editDurationText
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                }

                // ── Stat strip (replaces "ORIGINAL NOTES" stat list +
                //                          LINKED WORKOUT tile) ───────────
                // Read-only; hidden in edit mode where the editable stats
                // section above takes over.
                if !isEditing, let stats = editorialStats {
                    DripStatStrip(stats: stats)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                }

                // ── Linked source row ────────────────────────────────────
                if vm.currentEntry.hasLinkedWorkout {
                    linkedSourceRow
                } else if !isEditing {
                    linkWorkoutRow
                }

                // ── Voice recap / editable notes ─────────────────────────
                // CHANGE 1: "AI SUMMARY" → "VOICE RECAP". This is the
                // AI-cleaned summary of the dictated voice memo.
                // In edit mode the recap is swapped for an editable notes
                // field bound to $editNotesText (persisted by saveEdits as
                // cleaned_notes).
                if isEditing {
                    editorialSection(eyebrow: "NOTES") {
                        TextField("How did the run feel?", text: $editNotesText, axis: .vertical)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(3 ... 10)
                            .padding(12)
                            .background(Color.drip.cardBackgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else if let cleaned = vm.currentEntry.cleanedNotes, !cleaned.isEmpty {
                    editorialSection(eyebrow: "VOICE RECAP") {
                        FormattedSummaryText(text: cleaned)
                    }
                }

                // ── Workout notes (inline composer, no white card) ───────
                // CHANGE 2: moved ABOVE the coach insight — athlete's own
                // notes read before the coach's reply.
                if !isEditing {
                    editorialNotesComposer
                }

                // ── Coach insight (text-link CTA, no pink fill) ──────────
                // CHANGE 3: generate action is now a persistent button
                // ("GENERATE AI INSIGHT →"), plus a quiet "REGENERATE →"
                // under an existing insight.
                if !isEditing {
                    editorialSection(eyebrow: "COACH INSIGHT") {
                        if let insight = vm.coachInsight, !insight.isEmpty {
                            Text(insight)
                                .font(.dripBody(14).italic())
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineSpacing(3)
                            DripTextLink(title: "Regenerate →") {
                                Task {
                                    isLoadingInsight = true
                                    await vm.generateCoachInsight()
                                    isLoadingInsight = false
                                }
                            }
                            .padding(.top, 10)
                        } else if isLoadingInsight {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(Color.drip.coral)
                                    .scaleEffect(0.7)
                                Text("Asking the coach…")
                                    .font(.dripBody(13).italic())
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                            .padding(.top, 4)
                        } else {
                            Text("Not yet generated.")
                                .font(.dripBody(14).italic())
                                .foregroundStyle(Color.drip.textSecondary)
                            GenerateAIInsightButton {
                                Task {
                                    isLoadingInsight = true
                                    await vm.generateCoachInsight()
                                    isLoadingInsight = false
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                }

                // ── Footer: quiet delete + manual-log italic ─────────────
                if !isEditing {
                    HStack {
                        Text("— Logged " + vm.currentEntry.createdAt.shortDateString + ". —")
                            .font(.dripBody(12).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                        Spacer()
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Text("DELETE LOG")
                                .font(.dripCaption(10))
                                .tracking(1.4)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .overlay(alignment: .top) {
                        DripHairline().padding(.horizontal, 24)
                    }
                    .padding(.top, 32)
                }

                Spacer().frame(height: 40)
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // Editorial section — eyebrow + body, no card chrome
    // ────────────────────────────────────────────────────────────────────
    @ViewBuilder
    private func editorialSection<Content: View>(
        eyebrow: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DripEyebrow(text: eyebrow)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    // ────────────────────────────────────────────────────────────────────
    // Stat strip data — pulled from the linked workout when present.
    //
    // Canonical three for now: DIST · TIME · PACE. Handoff 3 also calls
    // for HR and ELEV cells, but TrainingLog has no top-level avg HR
    // field (only per-segment via PaceSegment.avgHeartRate) and no
    // elevation field at all. When we add `workoutAverageHeartRate` and
    // `workoutElevationGainMeters` accessors on TrainingLog, surface
    // them here as additional DripStat cells.
    // ────────────────────────────────────────────────────────────────────
    private var editorialStats: [DripStat]? {
        guard vm.currentEntry.hasLinkedWorkout else { return nil }
        var stats: [DripStat] = []
        if let d = vm.currentEntry.formattedWorkoutDistance {
            stats.append(DripStat("DIST", d, unit: "mi"))
        }
        if let t = vm.currentEntry.formattedWorkoutDuration {
            stats.append(DripStat("TIME", t))
        }
        if let p = vm.currentEntry.formattedWorkoutPace {
            stats.append(DripStat("PACE", p, unit: "/mi"))
        }
        return stats.isEmpty ? nil : stats
    }

    // ────────────────────────────────────────────────────────────────────
    // Linked source — single hairline row, coral "VIEW DETAIL ↗" link
    // ────────────────────────────────────────────────────────────────────
    private var linkedSourceRow: some View {
        Button {
            if vm.matchedVitalWorkout != nil {
                showVitalDetail = true
            }
        } label: {
            HStack {
                DripEyebrow(
                    text: "LINKED · " + (vm.matchedVitalWorkout?.sourceApp.uppercased() ?? "HEALTHKIT")
                )
                Spacer()
                Text("VIEW DETAIL ↗")
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.coral)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 24)
            .overlay(alignment: .bottom) {
                DripHairline().padding(.horizontal, 24)
            }
        }
        .buttonStyle(.plain)
    }

    // ────────────────────────────────────────────────────────────────────
    // "Link a workout" — single hairline row, no card
    // ────────────────────────────────────────────────────────────────────
    private var linkWorkoutRow: some View {
        Button { showWorkoutPicker = true } label: {
            HStack {
                DripEyebrow(text: "LINKED · NONE")
                Spacer()
                Text("LINK A RUN →")
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.coral)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 24)
            .overlay(alignment: .bottom) {
                DripHairline().padding(.horizontal, 24)
            }
        }
        .buttonStyle(.plain)
        .disabled(vm.isLinkingWorkout)
    }

    // ────────────────────────────────────────────────────────────────────
    // Inline notes composer — no card, no gray pill
    // ────────────────────────────────────────────────────────────────────
    private var editorialNotesComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DripEyebrow(text: "WORKOUT NOTES")
                Spacer()
                Text("OPTIONAL")
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            TextEditor(text: $workoutNotesText)
                .font(.dripBody(15).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64)

            if !workoutNotesText.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            let saved = await vm.saveWorkoutNotes(workoutNotesText)
                            if saved { onUpdate() }
                        }
                    } label: {
                        Text(vm.isSavingWorkoutNotes ? "SAVING…" : "SAVE")
                            .font(.dripCaption(10))
                            .tracking(1.4)
                            .foregroundStyle(Color.drip.coral)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .overlay(alignment: .top) {
            DripHairline().padding(.horizontal, 24)
        }
    }
}

// ────────────────────────────────────────────────────────────────────────
// MARK: - GenerateAIInsightButton
//
// Bordered coral pill matching the mock — mono, uppercase, trailing arrow.
// Left-aligned within the editorial section. Reuses Color.drip tokens and
// the .dripCaption font so it sits in the existing type system.
// ────────────────────────────────────────────────────────────────────────
struct GenerateAIInsightButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text("GENERATE AI INSIGHT")
                    .font(.dripCaption(10))
                    .tracking(1.2)
                Text("→")
                    .font(.dripCaption(10))
            }
            .foregroundStyle(Color.drip.coral)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.drip.coral, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

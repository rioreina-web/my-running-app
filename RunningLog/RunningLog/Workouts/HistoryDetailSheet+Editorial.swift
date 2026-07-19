//
//  HistoryDetailSheet+Editorial.swift
//  RunningLog
//
//  Direction A · "Editorial" port of the Log Details sheet body.
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
//    • HistoryDetailViewModel.refreshCoachInsightWhenReady() — the AI Insight
//      section auto-appears once `coach_insight` lands (no manual CTA)
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

                // ── AI Summary / editable notes ──────────────────────────
                // In edit mode the AI summary is swapped for an editable
                // notes field bound to $editNotesText (persisted by
                // saveEdits as cleaned_notes).
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
                    editorialSection(eyebrow: "VOICE SUMMARY") {
                        FormattedSummaryText(text: cleaned)
                    }
                }

                // ── Verbatim transcript ──────────────────────────────────
                // The athlete's actual words (Whisper/Gemini), fetched from the
                // stored transcript file — distinct from the cleaned VOICE
                // SUMMARY above, which is an AI rewrite.
                if !isEditing,
                   let turl = vm.currentEntry.transcriptUrl, !turl.isEmpty {
                    editorialSection(eyebrow: "TRANSCRIPT") {
                        VoiceTranscriptText(url: turl)
                    }
                }

                // ── Workout detail (full analytics, inline) ──────────────
                // The linked run's rep-by-rep charts, telemetry, splits, and
                // route rendered directly in the entry — the same content the
                // "VIEW DETAIL ↗" link opens full-screen (kept above). Placed
                // after the athlete's own words (voice summary + transcript) so
                // the qualitative record reads first, quantitative after.
                //
                // Gated on `vm.linkedStreamLogId` (a Strava training_logs row
                // with a real stream), NOT on hasLinkedWorkout: a stream-less
                // voice/manual entry would otherwise embed an inline "Logged
                // without GPS" block, which is noise inside the journal.
                if !isEditing, vm.linkedStreamLogId != nil {
                    editorialSection(eyebrow: "WORKOUT") {
                        WorkoutRepReceiptView(workoutId: workoutDetailId)
                    }
                }

                // ── AI insight (auto once processed — no manual CTA) ─────
                // Appears on its own once the server has generated the coach
                // insight (voice logs: process-training-memo). Until then the
                // whole section is hidden — no "Not yet generated" placeholder,
                // no "Ask the coach" button, so an entry with nothing to say
                // stays pure record. `refreshCoachInsightWhenReady()` (.task)
                // polls so it slots in live if the sheet is already open when
                // the insight lands.
                if !isEditing, let insight = vm.coachInsight, !insight.isEmpty {
                    editorialSection(eyebrow: "AI INSIGHT") {
                        Text(insight)
                            .font(.dripBody(14).italic())
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // ── Workout notes (inline composer, no white card) ───────
                if !isEditing {
                    editorialNotesComposer
                }

                // ── Footer: quiet delete + manual-log italic ─────────────
                if !isEditing {
                    HStack {
                        // Show when the run happened (workout_date), not when the
                        // row was created — re-imports make created_at "today",
                        // which read as a wrong date for the actual run.
                        Text("— Logged " + (vm.currentEntry.workoutDate ?? vm.currentEntry.createdAt).shortDateString + ". —")
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
// Verbatim voice transcript — fetches the athlete's actual words from the
// stored transcript .txt (public storage URL). Distinct from the cleaned
// "VOICE SUMMARY"; this is exactly what was said. Manages its own load state.
// ────────────────────────────────────────────────────────────────────────
private struct VoiceTranscriptText: View {
    let url: String
    /// Lines shown when collapsed. The full transcript is always fetched + kept;
    /// this only limits the DISPLAY until the athlete taps "Show full transcript".
    private let collapsedLineLimit = 4
    @State private var text: String?
    @State private var failed = false
    @State private var expanded = false

    var body: some View {
        Group {
            if let t = text {
                if t.isEmpty {
                    Text("Transcript is empty.")
                        .font(.dripBody(13).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                } else {
                    // Minimized by default: show a few lines, tail-truncated, with
                    // a coral link to enlarge. `.fixedSize(vertical:)` is dropped
                    // here on purpose — it forces full height and would defeat the
                    // lineLimit collapse. In the sheet's ScrollView the expanded
                    // text lays out fully anyway.
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t)
                            .font(.dripBody(15))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineSpacing(3)
                            .lineLimit(expanded ? nil : collapsedLineLimit)
                            .textSelection(.enabled)
                        if isLong(t) {
                            DripTextLink(title: expanded ? "Show less ↑" : "Show full transcript ↓") {
                                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if failed {
                Text("Couldn't load the transcript.")
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textSecondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.drip.coral).scaleEffect(0.7)
                    Text("Loading transcript…")
                        .font(.dripBody(13).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .task(id: url) { await load() }
    }

    /// Whether the transcript is long enough to be worth collapsing — so a short
    /// memo that already fits within `collapsedLineLimit` lines doesn't get a
    /// pointless toggle. Heuristic: character count (a full column line is ~55
    /// chars) or explicit line breaks beyond the limit.
    private func isLong(_ t: String) -> Bool {
        t.count > collapsedLineLimit * 55 || t.filter { $0 == "\n" }.count >= collapsedLineLimit
    }

    private func load() async {
        guard text == nil else { return }
        guard let u = URL(string: url) else { failed = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: u)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failed = true
                return
            }
            text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            failed = true
        }
    }
}

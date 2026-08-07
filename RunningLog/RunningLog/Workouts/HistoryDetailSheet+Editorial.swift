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
import Supabase

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

                // ── Day heading / custom title ───────────────────────────
                // Header shows the athlete's own title when set, with the
                // day + date carried underneath as an eyebrow so the date
                // context is never lost. With no title, the day-of-week is
                // the header (original behavior). In edit mode the title is
                // a free-text field (blank = falls back to the date).
                VStack(alignment: .leading, spacing: 8) {
                    if isEditing {
                        TextField("Add a title (optional)", text: $editTitle, axis: .vertical)
                            .font(.dripDisplay(30))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(1 ... 3)
                        Text(headerDateEyebrow)
                            .font(.dripEyebrow(11)).tracking(1.2)
                            .foregroundStyle(Color.drip.textTertiary)
                        EditableMoodPicker(selectedMood: $editMood)
                    } else {
                        // The workout is the title (athlete's own title wins if
                        // set); the day-of-week is the fallback only when there's
                        // no workout to name.
                        let headerTitle = vm.currentEntry.resolvedTitle
                        Text(headerTitle ?? vm.currentEntry.displayDate.dayOfWeekString)
                            .font(.dripDisplay(44))
                            .foregroundStyle(Color.drip.textPrimary)

                        if headerTitle != nil {
                            Text(headerDateEyebrow)
                                .font(.dripEyebrow(11)).tracking(1.2)
                                .foregroundStyle(Color.drip.textTertiary)
                        }

                        if let mood = vm.currentEntry.mood, !mood.isEmpty {
                            MoodBadge(mood: mood)
                        } else if headerTitle == nil {
                            Text("— " + vm.currentEntry.displayDate.fullDateString + " —")
                                .font(.dripBody(13).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                        }
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
                    // Label matches read mode's "SUMMARY" eyebrow.
                    editorialSection(eyebrow: "SUMMARY") {
                        TextField("How did the run feel?", text: $editNotesText, axis: .vertical)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineLimit(3 ... 10)
                            .padding(12)
                            .background(Color.drip.cardBackgroundElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else if hasMemoBlock {
                    // Read mode: summary + play row + the words behind a tap.
                    memoBlock
                }

                // ── Workout detail (full analytics, inline) ──────────────
                // The run's rep-by-rep charts, telemetry, splits, and route
                // rendered directly in the entry. Placed after the athlete's own
                // words (voice summary + transcript) so the qualitative record
                // reads first, quantitative after.
                //
                // This is THE workout detail when it renders — the "VIEW DETAIL ↗"
                // link above stands down rather than opening a modal copy of what
                // is already on screen (see `showsViewDetailLink`).
                //
                // Gated on `vm.linkedStreamLogId` (a training_logs row carrying a
                // real GPS stream — possibly this entry's own row), NOT on
                // hasLinkedWorkout: a stream-less voice/manual entry would
                // otherwise embed an inline "Logged without GPS" block, which is
                // noise inside the journal.
                if !isEditing, vm.linkedStreamLogId != nil {
                    editorialSection(eyebrow: "WORKOUT") {
                        WorkoutRepReceiptView(workoutId: workoutDetailId)
                    }
                }

                // ── Compare — "The Effort, compared" entry point ─────────
                // Gated the same way as the WORKOUT section: only a session
                // with a real lap stream can be segmented and compared.
                // Opens the comparison sheet on the auto-suggested fairest
                // prior session (CHANGE ↗ inside for the manual picker).
                if !isEditing, vm.linkedStreamLogId != nil {
                    Button {
                        showComparison = true
                    } label: {
                        HStack {
                            DripEyebrow(text: "VS. YOUR LAST SIMILAR SESSION")
                            Spacer()
                            Text("COMPARE ↗")
                                .font(.dripCaption(10))
                                .tracking(1.4)
                                .foregroundStyle(Color.drip.coral)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .overlay(alignment: .bottom) {
                        DripHairline().padding(.horizontal, 24)
                    }
                }

                // ── The read (AI insight, behind one tap) ────────────────
                // Was an always-on paragraph that ran ~70 words and competed
                // with the athlete's own summary for the page. It is now a
                // single row: coral ✦ + "READ THE INSIGHT". Nothing generated
                // is thrown away — it just waits to be asked for.
                if !isEditing {
                    insightBlock
                }

                // ── Workout notes (inline composer, no white card) ───────
                // Writes `workout_notes` — the SAME column the receipt's
                // "THE WORKOUT" section edits. While `linkedStreamLogId` was
                // permanently nil the receipt never rendered here, so this was
                // the only editor and the duplication was invisible. Now that
                // both can appear in one scroll (S0, 2026-08-07), showing two
                // editors for one column under two different labels — "WORKOUT
                // NOTES" and "THE WORKOUT" — is exactly the "two places" this
                // work is meant to remove.
                //
                // The receipt's is the better home: it sits beside the reps the
                // description describes, and `EditWorkoutNotesSheet` re-fires
                // the structure parser on save. So this composer stands down
                // when the receipt is present, and remains the only way to add
                // a description to a stream-less entry (a voice log with no run
                // that day), where the receipt never appears.
                if !isEditing, vm.linkedStreamLogId == nil {
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

    // Day + date eyebrow shown under a custom title (or above the mood
    // picker in edit mode) so the entry's date context survives when the
    // athlete replaces the day-of-week header with their own title.
    // e.g. "WEDNESDAY  ·  MAY 22".
    private var headerDateEyebrow: String {
        vm.currentEntry.displayDate.dayOfWeekString.uppercased()
            + "  ·  "
            + vm.currentEntry.displayDate.editorialDateString
    }

    // ════════════════════════════════════════════════════════════════════
    // MARK: - The memo block
    //
    // One section covering what used to be two: "VOICE SUMMARY" (an AI
    // paraphrase) stacked directly above "TRANSCRIPT" (the same content,
    // verbatim) — two voices saying one thing, ~95 words before the athlete
    // reached anything they hadn't already lived.
    //
    // Now: the summary reads quiet and small (13.5pt, textSecondary — it is
    // deliberately subordinate to the stat strip), the recording is a single
    // play row, and the verbatim words sit behind "READ THE WORDS ↓".
    //
    // NOTE: the type change only pays off if the summary itself is short.
    // At 13.5pt anything past ~30 words reads as a paragraph again. The
    // `process-training-memo` prompt should be capped at two sentences —
    // what the session was, then how it felt. See the redesign prototype
    // at repo root for the copy spec.
    // ════════════════════════════════════════════════════════════════════

    /// Non-empty cleaned summary, if there is one.
    private var summaryText: String? {
        guard let cleaned = vm.currentEntry.cleanedNotes,
              !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return cleaned
    }

    /// Playable memo audio, if the row has any. Voice logs carry `audio_url`;
    /// Strava imports and manual entries don't, so the play row simply doesn't
    /// render for them — no broken player.
    private var memoAudioUrl: String? {
        guard let a = vm.currentEntry.audioUrl, !a.isEmpty else { return nil }
        return a
    }

    /// Stored verbatim transcript, if the memo was transcribed.
    private var memoTranscriptUrl: String? {
        guard let t = vm.currentEntry.transcriptUrl, !t.isEmpty else { return nil }
        return t
    }

    /// Whether there is anything at all to show — otherwise the section is
    /// hidden entirely rather than rendering an empty labelled block.
    var hasMemoBlock: Bool {
        summaryText != nil || memoAudioUrl != nil || memoTranscriptUrl != nil
    }

    @ViewBuilder
    var memoBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // "SUMMARY" when there's a written summary to edit; "THE MEMO"
                // when all we have is the recording, so the label never
                // promises text that isn't there.
                DripEyebrow(text: summaryText != nil ? "SUMMARY" : "THE MEMO")
                Spacer()
                if summaryText != nil {
                    Button { enterEditMode() } label: {
                        Text("EDIT")
                            .font(.dripCaption(10)).tracking(1.4)
                            .foregroundStyle(Color.drip.coral)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let cleaned = summaryText {
                // Quieter than the old 14pt textPrimary: the summary supports
                // the numbers, it doesn't lead the page.
                FormattedSummaryText(
                    text: cleaned,
                    size: 13.5,
                    color: Color.drip.textSecondary
                )
            }

            if let audio = memoAudioUrl {
                MemoPlayerRow(url: audio)
                    .padding(.top, summaryText == nil ? 0 : 5)
            }

            if let transcript = memoTranscriptUrl {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showTranscript.toggle() }
                } label: {
                    Text(showTranscript ? "HIDE THE WORDS ↑" : "READ THE WORDS ↓")
                        .font(.dripEyebrow(9.5)).tracking(1.14)
                        .foregroundStyle(showTranscript ? Color.drip.coral : Color.drip.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.top, 3)

                if showTranscript {
                    VoiceTranscriptText(url: transcript)
                        .padding(.leading, 14)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.drip.paperDeep)
                                .frame(width: 2)
                        }
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    // ════════════════════════════════════════════════════════════════════
    // MARK: - The read (AI insight, on request)
    //
    // Three states, in priority order:
    //   • open      — the athlete tapped; text + a close affordance
    //   • ready     — an insight exists (server-written or previously
    //                 generated); one coral row invites it
    //   • absent    — nothing generated yet. If the entry has enough to go
    //                 on, the row generates on tap (wiring up the previously
    //                 orphaned `vm.generateCoachInsight()`); if it doesn't,
    //                 a dashed row says why, rather than lying about a
    //                 capability that would fail.
    // ════════════════════════════════════════════════════════════════════

    private var hasInsight: Bool {
        guard let i = vm.coachInsight else { return false }
        return !i.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// An insight needs something to read: either the athlete's own words or a
    /// linked run with telemetry. With neither, `generate-workout-insight`
    /// has no material and would return boilerplate.
    private var canGenerateInsight: Bool {
        summaryText != nil || memoTranscriptUrl != nil || vm.linkedStreamLogId != nil
    }

    @ViewBuilder
    var insightBlock: some View {
        if hasInsight, showInsight, let insight = vm.coachInsight {
            openInsightPanel(insight)
        } else if hasInsight {
            insightRow(label: "READ THE INSIGHT", enabled: true) {
                withAnimation(.easeInOut(duration: 0.2)) { showInsight = true }
            }
        } else if vm.isGeneratingInsight {
            insightRow(label: "WRITING YOUR INSIGHT…", enabled: false, dashed: true, action: nil)
        } else if vm.insightError != nil {
            // Retryable, and deliberately NOT typeset as "THE READ" — an error
            // rendered in the insight panel reads like the coach's actual take.
            insightRow(label: "COULDN'T GET IT · RETRY", enabled: true) {
                Task { await generateThenReveal() }
            }
        } else if canGenerateInsight {
            insightRow(label: "READ THE INSIGHT", enabled: true) {
                Task { await generateThenReveal() }
            }
        } else {
            insightRow(label: "INSIGHT NEEDS A MEMO", enabled: false, dashed: true, action: nil)
        }
    }

    /// Generate on demand, then open the panel — but only if something actually
    /// came back. Revealing unconditionally would open an empty panel on failure.
    private func generateThenReveal() async {
        await vm.generateCoachInsight()
        guard hasInsight else { return }
        withAnimation(.easeInOut(duration: 0.2)) { showInsight = true }
    }

    @ViewBuilder
    private func insightRow(
        label: String,
        enabled: Bool,
        dashed: Bool = false,
        action: (() -> Void)?
    ) -> some View {
        Button { action?() } label: {
            HStack(spacing: 9) {
                if vm.isGeneratingInsight {
                    ProgressView()
                        .tint(Color.drip.coral)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Text("✦")
                        .font(.system(size: 12))
                        .foregroundStyle(enabled ? Color.drip.coral : Color.drip.textTertiary)
                }
                Text(label)
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(enabled ? Color.drip.textPrimary : Color.drip.textTertiary)
                Spacer()
                if enabled {
                    Text("→")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color.drip.divider,
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    @ViewBuilder
    private func openInsightPanel(_ insight: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✦ THE READ")
                    .font(.dripEyebrow(9.5)).tracking(1.14)
                    .foregroundStyle(Color.drip.coral)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showInsight = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                        // Keep the 44pt tap target the 10pt glyph doesn't give.
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide the insight")
            }
            Text(insight)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 17)
        .padding(.top, 14)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackgroundElevated)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.drip.coral).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 24)
        .padding(.top, 20)
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

    /// Should this row offer "VIEW DETAIL ↗"?
    ///
    /// Only when there is somewhere to go that isn't already on this screen.
    /// Two cases where there isn't (2026-08-07):
    ///
    /// 1. **The receipt is already inline.** `linkedStreamLogId != nil` renders
    ///    the full receipt further down this same scroll, against the same id
    ///    the link would open. Offering the link there sends the athlete to a
    ///    modal copy of what they can already see — the opposite of one session,
    ///    one page. (Before today this could not happen: `linkedStreamLogId` was
    ///    always nil, so the inline section never rendered and the link was the
    ///    only door. See `HistoryDetailViewModel.fetchStreamCarryingLogsForDate`.)
    /// 2. **Nothing matched.** The row is shown on `hasLinkedWorkout` (a date
    ///    and a distance) but the tap only acted on `matchedVitalWorkout != nil`,
    ///    which is filled asynchronously and often not at all. That rendered a
    ///    coral affordance that did nothing.
    private var showsViewDetailLink: Bool {
        vm.linkedStreamLogId == nil && vm.matchedVitalWorkout != nil
    }

    /// The row's content, with or without the link. Kept separate so the
    /// non-navigating case can render as plain content rather than a disabled
    /// Button — `.disabled` on a `.plain` button dims its whole label, which
    /// would grey out the "LINKED · STRAVA" eyebrow for no reason.
    private var linkedSourceRowContent: some View {
        HStack {
            DripEyebrow(
                text: "LINKED · " + (vm.matchedVitalWorkout?.sourceApp.uppercased() ?? "HEALTHKIT")
            )
            Spacer()
            if showsViewDetailLink {
                Text("VIEW DETAIL ↗")
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
        .overlay(alignment: .bottom) {
            DripHairline().padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var linkedSourceRow: some View {
        if showsViewDetailLink {
            Button { showVitalDetail = true } label: { linkedSourceRowContent }
                .buttonStyle(.plain)
        } else {
            linkedSourceRowContent
        }
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
            // Collapsed by default. An empty section labelled "WORKOUT NOTES /
            // OPTIONAL" was pure chrome on the great majority of entries —
            // a heading, a subheading, and an empty box saying nothing. It now
            // opens on demand, and stays open whenever there's a note to show.
            if !isEditingWorkoutNotes, workoutNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isEditingWorkoutNotes = true }
                } label: {
                    HStack(spacing: 8) {
                        Text("＋")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.drip.coral)
                        Text("ADD A NOTE")
                            .font(.dripEyebrow(9.5)).tracking(1.14)
                            .foregroundStyle(Color.drip.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            } else {
                notesEditor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .overlay(alignment: .top) {
            DripHairline().padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DripEyebrow(text: "WORKOUT NOTES")
                Spacer()
                // Collapse back down if the athlete opened the composer and
                // typed nothing — otherwise the row is a one-way door.
                if workoutNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isEditingWorkoutNotes = false }
                    } label: {
                        Text("CLOSE")
                            .font(.dripCaption(10))
                            .tracking(1.4)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("OPTIONAL")
                        .font(.dripCaption(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            TextEditor(text: $workoutNotesText)
                .font(.dripBody(15).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64)

            if !workoutNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        // Padding and the top hairline are applied by `editorialNotesComposer`,
        // which wraps this — don't reapply them here.
        .frame(maxWidth: .infinity, alignment: .leading)
        // Sticky once shown. An entry that arrives WITH a note renders this
        // editor while the flag is still false, so select-all-delete (to rewrite
        // the note) would flip the branch back to "＋ ADD A NOTE" mid-edit —
        // tearing down the focused TextEditor and dismissing the keyboard.
        .onAppear { isEditingWorkoutNotes = true }
    }
}

// ────────────────────────────────────────────────────────────────────────
// Verbatim voice transcript — the athlete's actual words (Whisper/Gemini),
// fetched from the stored transcript file in the private `training-memos`
// bucket. Distinct from the cleaned summary; this is exactly what was said.
// Manages its own load state.
//
// The internal "Show full transcript ↓" toggle is gone: disclosure is now
// owned by the parent ("READ THE WORDS ↓" in `memoBlock`), so by the time
// this renders the athlete has already asked for the words. Showing them
// clamped behind a second toggle would be two taps for one intent.
// ────────────────────────────────────────────────────────────────────────
private struct VoiceTranscriptText: View {
    let url: String
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let t = text {
                if t.isEmpty {
                    Text("Transcript is empty.")
                        .font(.dripBody(13).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                } else {
                    // The words, verbatim and in full — italic and quiet, so
                    // they read as a quotation of the recording rather than as
                    // the section's main body copy.
                    Text(t)
                        .font(.dripBody(13.5).italic())
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// Fetch through `TrainingMemoStorage` (see MemoPlayerRow.swift) so the
    /// transcript and the audio resolve the private-bucket path the same way
    /// and can't drift apart. The path/fallback logic used to live inline here.
    private func load() async {
        // No `guard text == nil` here: this runs from `.task(id: url)`, so a
        // changed url must be able to replace an already-loaded transcript
        // (and clear a previous failure) rather than leaving the old words up.
        // Clearing `text` first closes the window where the PREVIOUS entry's
        // words are still on screen under the new entry's heading.
        failed = false
        text = nil
        do {
            let data = try await TrainingMemoStorage.data(for: url)
            // A slow first fetch could otherwise land after a newer one and
            // clobber the correct text.
            guard !Task.isCancelled else { return }
            text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            failed = true
        }
    }
}

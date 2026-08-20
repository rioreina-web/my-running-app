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

// Deliberately NOT file-private: `SignalDayDetail` renders the same run block
// and must show the same label, so this one helper is shared rather than
// re-declared per surface.
extension Date {
    /// "August 8" — the headline `EditWorkoutNotesSheet` shows above the
    /// field, so the athlete can see which run they're describing. Matches
    /// `WorkoutRepReceiptView.displayTitle` so the editor reads identically
    /// whichever surface opened it.
    var workoutBlockDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
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
                    // "WORKOUT", not "JOURNAL · ENTRY DETAIL": this sheet is
                    // reached from the Runs list and reads as one session's
                    // record. The plate names the thing, not the container.
                    leadingBottom: "WORKOUT",
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

                        // Eyebrow ABOVE the headline now, per the handoff — the
                        // date sets up the name rather than trailing after it.
                        // Still only when there IS a name: with no title the
                        // headline is already the day of week, and "SATURDAY ·
                        // AUG 8" over "Saturday" prints the day twice.
                        if headerTitle != nil {
                            Text(headerDateEyebrow)
                                .font(.dripEyebrow(10)).tracking(1.2)
                                .foregroundStyle(Color.drip.textSecondary)
                        }

                        // Tap the headline to rename the entry, in place. The
                        // field that replaces it is set in the same face and
                        // size, so the edit reads as writing on the page
                        // rather than as opening a form. `contentShape` makes
                        // the whole line tappable, not just the glyphs.
                        if isEditingTitleInline {
                            inlineTitleField
                        } else {
                            editorialHeadline(headerTitle ?? vm.currentEntry.displayDate.dayOfWeekString)
                                .contentShape(Rectangle())
                                .onTapGesture { beginInlineTitleEdit() }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Double tap to rename this entry")
                        }

                        if headerTitle == nil,
                           vm.currentEntry.mood?.isEmpty ?? true {
                            Text("— " + vm.currentEntry.displayDate.fullDateString + " —")
                                .font(.dripBody(13).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                        }

                        statusRow
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
                // The source name now rides in `statusRow` above ("STRAVA"),
                // so this row only earns its hairline when it offers an action.
                // A passive "LINKED · STRAVA" here would say the same word twice.
                if vm.currentEntry.hasLinkedWorkout {
                    if showsViewDetailLink { linkedSourceRow }
                } else if !isEditing {
                    linkWorkoutRow
                }

                // ── THE WORKOUT — what the session was meant to be ───────
                //
                // Above the summary on purpose: what the athlete set out to do
                // is the frame the rest of the entry is read through. "I felt
                // comfortable" means one thing under an easy 6 and another
                // under 2 × 20 at threshold, and until today the entry made
                // you scroll past the memo, past the compare row, past the
                // insight and into the receipt to find out which.
                //
                // Renders against `workoutDetailId` — the row the receipt
                // below reads from — and mirrors onto the journal row, so the
                // two rows a Strava-linked run occupies can't disagree about
                // what the workout was. This is the ONLY editor for
                // `workout_notes` now: the receipt's copy stands down when
                // embedded, and `editorialNotesComposer` is deleted.
                if !isEditing {
                    // `line · dot · line` — the canonical section break, in
                    // place of the plain full-width hairlines this sheet used.
                    EditorialRule()
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    editorialSection(eyebrow: nil) {
                        TheWorkoutBlock(
                            workoutId: workoutDetailId,
                            mirrorIds: [entry.id],
                            dateLabel: vm.currentEntry.displayDate.workoutBlockDateLabel,
                            onSaved: { onUpdate() }
                        )
                    }
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
                    EditorialRule()
                        .padding(.horizontal, 24)
                        .padding(.top, 22)

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
                    // A rule, not a label. "WORKOUT" was printed three times on
                    // one page — the plate strip's kicker, this eyebrow, and
                    // the receipt's own "TUESDAY · INTERVALS" header — and the
                    // third one labelled a block that opens with a conditions
                    // plate, not a workout. The break is what's wanted here;
                    // the naming is done above. (2026-08-20)
                    EditorialRule()
                        .padding(.horizontal, 24)
                        .padding(.top, 26)

                    editorialSection(eyebrow: nil) {
                        // `.embedded`: this entry already carries the date (in
                        // the plate strip AND the header eyebrow), the title,
                        // the source, the stat strip, the mood and the memo,
                        // and it hosts THE WORKOUT above — so the receipt drops
                        // all of them and renders only what it alone knows:
                        // conditions, SIGNALS, splits, telemetry, route.
                        // One page, one title, one editor per column.
                        WorkoutRepReceiptView(workoutId: workoutDetailId, placement: .embedded)
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

                // ── Ask this session ─────────────────────────────────────
                // Was an always-on paragraph (~70 words competing with the
                // athlete's own summary), then a single "READ THE INSIGHT"
                // row. It is now a field plus a rail of questions gated to
                // what THIS session can actually answer: one row asked one
                // question and the app picked it, so if the paragraph didn't
                // answer what she actually wondered there was nowhere to go.
                //
                // The read is still here — it's the pinned first chip, and
                // still the safe default when she doesn't know what to ask.
                // The insight panel below is unchanged and still owned here;
                // the chip only opens it.
                if !isEditing {
                    if hasInsight, showInsight, let insight = vm.coachInsight {
                        openInsightPanel(insight)
                    }
                    SessionAskBlock(
                        workoutId: vm.currentEntry.id,
                        dateLabel: vm.currentEntry.displayDate.editorialDateString,
                        hasInsight: hasInsight,
                        canGenerateInsight: canGenerateInsight,
                        isGenerating: vm.isGeneratingInsight,
                        hasInsightError: vm.insightError != nil,
                        onReadTapped: {
                            if hasInsight {
                                withAnimation(.easeInOut(duration: 0.2)) { showInsight = true }
                            } else {
                                Task { await generateThenReveal() }
                            }
                        }
                    )
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

    // ────────────────────────────────────────────────────────────────────
    // Headline — the title, with the period in coral
    // ────────────────────────────────────────────────────────────────────
    //
    // "Moderate" becomes "Moderate." with the full stop set in coral: the
    // single editorial mark that tells you this is a printed record and not
    // a form field. Built by concatenating two `Text`s rather than laying
    // them out in an HStack so a long athlete-written title still wraps as
    // one paragraph.
    //
    // Titles that already end in punctuation ("Easy 6?", "Done!") keep it —
    // adding a period would print "Done!." — and the coral hit is skipped
    // rather than doubled.
    private func editorialHeadline(_ title: String) -> some View {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadyTerminated = trimmed.last.map { ".!?…".contains($0) } ?? true

        // `verbatim:` on the title — it is athlete-written, so a "%" or a brace
        // must not be read as a format specifier by LocalizedStringKey.
        let body = Text(verbatim: trimmed).foregroundStyle(Color.drip.textPrimary)
        let stop = Text(verbatim: alreadyTerminated ? "" : ".")
            .foregroundStyle(Color.drip.coral)

        return Text("\(body)\(stop)")
            .font(.dripDisplay(44))
            .fixedSize(horizontal: false, vertical: true)
    }

    // ────────────────────────────────────────────────────────────────────
    // The headline, editable in place
    // ────────────────────────────────────────────────────────────────────
    //
    // Same 44pt display face as the printed headline so the swap is the
    // cursor appearing, not the layout changing. No Save button by design:
    // the field commits on the keyboard's Done AND on focus loss, so tapping
    // anywhere else on the entry saves. `commitInlineTitle` is idempotent, so
    // the two paths firing in sequence writes once.
    //
    // The coral full stop is dropped while editing — it's a typographic mark
    // on a finished line, and printing it after a live cursor would read as a
    // character the athlete has to delete.
    @ViewBuilder
    private var inlineTitleField: some View {
        TextField("Name this run", text: $inlineTitleText, axis: .vertical)
            .font(.dripDisplay(44))
            .foregroundStyle(Color.drip.textPrimary)
            .lineLimit(1 ... 3)
            .fixedSize(horizontal: false, vertical: true)
            .focused($titleFieldFocused)
            .onChange(of: titleFieldFocused) { _, focused in
                // Only a focus loss that FOLLOWS a real focus is the athlete
                // tapping away. A `false` before the field has ever held focus
                // is SwiftUI resetting an unclaimed value, and committing on
                // that would shut the editor the instant it opened.
                if focused {
                    titleFieldDidFocus = true
                } else if titleFieldDidFocus {
                    commitInlineTitle()
                }
            }
            // Hard floor: if focus is never granted, the gate above never
            // opens and the field would have no way out. Paging away or
            // closing the sheet commits whatever is in it.
            .onDisappear { commitInlineTitle() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { titleFieldFocused = false }
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
    }

    // ────────────────────────────────────────────────────────────────────
    // Status row — how it felt, what hurt, where it came from
    // ────────────────────────────────────────────────────────────────────
    //
    // One line under the headline carrying the two facts an athlete scans for
    // first: how it felt, and where the run came from. The source name is
    // shortened to "STRAVA" (from the old "LINKED · STRAVA" row); the row it
    // came from now only renders when it has an action to offer.
    //
    // Both elements are conditional. A manual entry with no mood and no linked
    // run renders an empty HStack — zero height, no gap.
    //
    // The handoff also puts a `NIGGLE · KNEE` pill here, between the mood pill
    // and the source. It is deliberately not built yet: the pill is cheap, but
    // it needs this sheet to read `body_mentions` (the durable niggle store),
    // which is a data change, not a typographic one. Slot it in after the
    // mood pill when that lands.
    @ViewBuilder
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Tap the pill to change how it felt — the six moods expand
                // underneath and a tap on one saves. With no mood recorded yet
                // the same target asks the question instead of printing an
                // empty cell (hard rule #8: no em-dash placeholders).
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { isPickingMoodInline.toggle() }
                } label: {
                    if let mood = displayedMood {
                        MoodBadge(mood: mood)
                    } else {
                        addMoodChip
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayedMood.map { "Mood: \($0)" } ?? "No mood recorded")
                .accessibilityHint("Double tap to change how this run felt")

                if vm.currentEntry.hasLinkedWorkout {
                    Text(sourceName)
                        .font(.dripEyebrow(9.5))
                        .tracking(0.95)          // 9.5 × 0.10em
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            if isPickingMoodInline {
                EditableMoodPicker(selectedMood: inlineMoodBinding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if inlineSaveFailed {
                // Coral is right — it is the alert palette. The FACE is
                // `dripCaption`, not a tracked eyebrow: eyebrows label
                // sections, and a failure the athlete has to act on should be
                // said in plain sentence case rather than shouted.
                Text("Couldn't save. Try again.")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .padding(.top, 6)
    }

    /// The mood on screen: the one being saved if a save is in flight, else
    /// the stored one. Without the `pendingMood` arm the pill doesn't move
    /// until the network answers, and the tap reads as ignored.
    private var displayedMood: String? {
        if let pending = pendingMood {
            return pending.isEmpty ? nil : pending
        }
        guard let mood = vm.currentEntry.mood, !mood.isEmpty else { return nil }
        return mood
    }

    /// Reads the displayed mood; writing straight through to the row IS the
    /// save.
    ///
    /// `EditableMoodPicker` toggles its own selection, so tapping the selected
    /// pill again sends "" and clears the mood — which is the undo, and why
    /// this needs no confirmation step.
    private var inlineMoodBinding: Binding<String> {
        Binding(
            get: { displayedMood ?? "" },
            set: { newMood in
                commitInlineMood(newMood)
                withAnimation(.easeOut(duration: 0.18)) { isPickingMoodInline = false }
            }
        )
    }

    /// The no-mood-yet tap target. An outlined capsule rather than a filled
    /// pill: it is an invitation, not a recorded value, and must not read as
    /// one more mood in the vocabulary.
    private var addMoodChip: some View {
        Text("HOW DID IT FEEL?")
            .font(.dripEyebrow(10))
            .tracking(1.0)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay {
                // `divider`, not `paperDeep`: paperDeep is a fill token (wells,
                // chart tracks). This is a rule line, and MemoPlayerRow strokes
                // its capsule the same way.
                Capsule().strokeBorder(Color.drip.divider, lineWidth: 1)
            }
    }

    /// "STRAVA" / "GARMIN" / "HEALTHKIT" — same resolution the linked-source
    /// row uses, so the two can never name the run's origin differently.
    private var sourceName: String {
        vm.matchedVitalWorkout?.sourceApp.uppercased() ?? "HEALTHKIT"
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
            // 14pt between the two corner labels — at 9.5pt tracked caps,
            // default spacing reads as one run-on word ("MEMOEDIT").
            HStack(spacing: 14) {
                // "SUMMARY" when there's a written summary to edit; "THE MEMO"
                // when all we have is the recording, so the label never
                // promises text that isn't there.
                DripEyebrow(text: summaryText != nil ? "SUMMARY" : "THE MEMO")
                Spacer()

                // ── The recording, as a corner affordance ────────────────
                //
                // The waveform row used to sit in the reading flow, between
                // the summary and the words — a piece of playback furniture
                // interrupting the athlete's own account of the run. The
                // entry is the writing; the audio is the source. Source
                // material belongs within reach, not in the middle of the
                // page.
                //
                // Only when there IS a summary: with nothing but a recording
                // the section would be a label and two buttons over empty
                // space, so the player stays inline (see below) and this
                // toggle would be hiding the only content there is.
                //
                // Ink-3 → ink-1 when open, deliberately NOT coral: this
                // cluster's one coral hit belongs to THE READ below.
                if memoAudioUrl != nil, summaryText != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showMemoPlayer.toggle() }
                    } label: {
                        Text(showMemoPlayer ? "HIDE MEMO ↑" : "▶ MEMO")
                            .font(.dripEyebrow(9.5)).tracking(1.14)
                            .foregroundStyle(showMemoPlayer ? Color.drip.textPrimary : Color.drip.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if summaryText != nil {
                    Button { enterEditMode() } label: {
                        // Ink-3, not coral. Coral discipline: one coral hit per
                        // visual cluster, and this cluster's belongs to THE READ
                        // directly below. THE WORKOUT's own EDIT stays coral —
                        // it heads a different cluster.
                        Text("EDIT")
                            .font(.dripEyebrow(9.5)).tracking(1.14)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let cleaned = summaryText {
                // The athlete's own account of the run, set as the entry's lead
                // paragraph: PT Serif at 16.5 in full ink, with magazine
                // leading. It was 13.5pt in `textSecondary` — deliberately
                // subordinate to the stat strip — but a training journal is
                // the writing, and the numbers are its apparatus. With the
                // receipt's duplicate header and second stat block gone, this
                // is the one long-form voice on the page and it should read
                // like it. (2026-08-20)
                FormattedSummaryText(
                    text: cleaned,
                    size: 16.5,
                    color: Color.drip.textPrimary,
                    lineSpacing: 6
                )
                .padding(.top, 2)
            }

            // Revealed by the corner "▶ MEMO" above. The `summaryText == nil`
            // arm is the fallback: an entry that is *only* a recording has
            // nothing to hide the player behind, so it stays inline there and
            // the corner toggle doesn't render.
            if let audio = memoAudioUrl, showMemoPlayer || summaryText == nil {
                MemoPlayerRow(url: audio)
                    .padding(.top, summaryText == nil ? 0 : 5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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

    /// Generate on demand, then open the panel — but only if something actually
    /// came back. Revealing unconditionally would open an empty panel on failure.
    ///
    /// Still owned here, not by `SessionAskBlock`: it closes over `vm` and the
    /// sheet's `showInsight` state, and the read chip reaches it through the
    /// `onReadTapped` closure.
    private func generateThenReveal() async {
        await vm.generateCoachInsight()
        guard hasInsight else { return }
        withAnimation(.easeInOut(duration: 0.2)) { showInsight = true }
    }

    // The open panel, retypeset to the handoff (2026-08-10).
    //
    // Two deliberate choices, both about marking machine voice as machine
    // voice rather than dressing it up as the coach:
    //
    //  • THE BODY IS MONO. JetBrains Mono in the design file, SF Mono here.
    //    The athlete's own summary directly above is PT Serif; setting the
    //    generated read in the same serif let the two blur into one voice.
    //  • NO CARD. The elevated fill and 8pt corner radius are gone, replaced
    //    by a 2pt coral rule at 50% and 13pt of indent. This colored left
    //    border is the canonical AI treatment and THE ONLY PLACE in the
    //    system it appears — do not generalize it to other sections.
    //
    // The ✕ stays: the panel is opened by a tap in this build (see
    // `insightBlock`), so it needs a way back to closed. The handoff draws it
    // always-open, which would leave the ✕ with nothing to do.
    @ViewBuilder
    private func openInsightPanel(_ insight: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE READ")
                    .font(.dripEyebrow(9.5))
                    .fontWeight(.semibold)
                    .tracking(1.14)          // 9.5 × 0.12em
                    .foregroundStyle(Color.drip.coral)
                Spacer(minLength: 8)
                Text("GENERATED")
                    .font(.dripEyebrow(8.5))
                    .tracking(0.85)          // 8.5 × 0.10em
                    .foregroundStyle(Color.drip.textTertiary)
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
                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.drip.coral.opacity(0.5))
                .frame(width: 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    // ────────────────────────────────────────────────────────────────────
    // Editorial section — eyebrow + body, no card chrome
    // ────────────────────────────────────────────────────────────────────
    @ViewBuilder
    /// A titled section. `eyebrow: nil` for content that carries its own
    /// heading — THE WORKOUT block labels itself, and stacking a section
    /// eyebrow above its eyebrow would print the name twice.
    private func editorialSection<Content: View>(
        eyebrow: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                DripEyebrow(text: eyebrow)
            }
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

    // The inline notes composer ("WORKOUT NOTES" / "＋ ADD A NOTE", ~110 lines
    // with `notesEditor`) lived here. It was the second editor for
    // `workout_notes` — same column as the receipt's "THE WORKOUT", different
    // label, different row, its own save button and its own collapse state.
    // Both are replaced by `TheWorkoutBlock`, hosted above the summary.
    // (2026-08-10)
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

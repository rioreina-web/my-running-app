//
//  CoachReadView.swift
//  RunningLog
//
//  The Coach Read page. Replaces the legacy `CoachView` chat UI in
//  the Coach tab (self-coached path). Composes the five primitives
//  from Phase 3 into the editorial layout from the design mock:
//
//    Plate strip → Dateline → Byline → Headline → ReadProse →
//    Signature → CantSeeBlock (if present) → SourcesPanel →
//    ConfidenceBar → Editorial rule → Ask bar (pinned).
//
//  Data comes from `DailyReadService.shared`, which already
//  refreshes on app launch + foreground. Pull-to-refresh forces a
//  re-fetch; the service short-circuits on the existing completed
//  row when there's nothing new.
//
//  Phase 4.1 of coach-the-read-prompts.md.
//

import SwiftUI

struct CoachReadView: View {
    @State private var service = DailyReadService.shared

    /// Cross-tab navigation — lets the Volume × Intensity affordance jump
    /// to the Training tab where the spectrum chart lives. Training is
    /// tab index 1 (see DripTab).
    @Environment(\.selectedTab) private var selectedTab

    /// Staged coach question handed off from another surface (e.g. the
    /// Trends ask bar pre-seeds the scrubbed week, then switches to this
    /// tab). When set, we present the `CoachAskSheet` composer pre-filled
    /// with the question + focus label. See CoachAskContext.
    @Environment(\.coachAsk) private var coachAsk

    // Sheet-routing state — chips write their id here, this view
    // reads and presents the matching detail sheet.
    @State private var selectedWorkoutId: UUID?
    @State private var selectedDocId: UUID?
    // v5 niggle ref tap target (body-part string → timeline sheet).
    @State private var selectedNiggle: String?

    // Ask-bar state. The athlete asks AI about their training; the
    // reply is a CoachRead-shaped Training Insight presented in a sheet.
    @State private var askText = ""
    @State private var isAsking = false
    @State private var askReply: CoachRead?
    @State private var askErrorText: String?

    // Weekly-review history, opened from the "↗ HISTORY" masthead button.
    @State private var showWeeklyHistory = false

    // ── Check-in state — the reply point under the Read's soft question. ──
    // The Read ends by asking the athlete something; this is where they
    // answer: a mood rating, a typed line, or a quick voice memo. All three
    // land in the journal through the same pipeline the Log tab uses
    // (VoiceLogViewModel), so the next Read reads its own replies.
    @Environment(CoachCheckInManager.self) private var checkInManager
    @State private var checkInVM = VoiceLogViewModel()
    @State private var checkInRecorder = VoiceRecorder()
    @State private var checkInMood: String?
    @State private var checkInText = ""
    @State private var isSavingCheckIn = false
    @State private var checkInSaved = false
    @State private var checkInErrorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let read = service.todayRead {
                    plateStrip
                    weekBand
                    dateline(for: read)
                    coachByline(for: read)
                    headline(for: read)
                    // v5: render the sectioned coach-snapshot when present;
                    // otherwise the legacy flat paragraph (old rows).
                    if read.hasSections {
                        ReadSectionsView(
                            eyebrow: read.eyebrow,
                            sections: read.sections ?? [],
                            question: read.question,
                            selectedWorkoutId: $selectedWorkoutId,
                            selectedNiggle: $selectedNiggle
                        )
                        .padding(.bottom, 16)
                    } else {
                        prose(for: read)
                    }
                    signatureLine(for: read)

                    checkInBlock
                        .padding(.top, 20)

                    if let cantSee = read.cantSee {
                        CantSeeBlock(block: cantSee)
                            .padding(.top, 16)
                    }

                    SourcesPanel(
                        sources: read.sources,
                        workouts: service.workoutsById,
                        docs: service.docsById,
                        selectedWorkoutId: $selectedWorkoutId,
                        selectedDocId: $selectedDocId
                    )
                    .padding(.top, 12)

                    ConfidenceBar(confidence: read.confidence)
                        .padding(.top, 4)

                    volumeIntensityLink
                        .padding(.top, 16)

                    editorialRule
                        .padding(.vertical, 24)
                } else if service.isLoading {
                    skeleton
                } else if service.lastError != nil {
                    errorState
                } else {
                    // No row yet, not loading, no error — brand-new account
                    // (or today's read was never generated). This used to
                    // render the skeleton, which looked like a permanent
                    // loading state with no way out (beta-audit item #14).
                    // Real empty state per the empty-state component spec;
                    // refresh() generates on a miss (triggered_by=manual).
                    EmptyStateView(
                        variant: .setupNeeded,
                        eyebrow: "THE DAILY READ",
                        title: "No read yet. The coach writes one from your training — log a run or a voice memo first, then generate your first read.",
                        cta: .init(label: "GENERATE TODAY'S READ") {
                            // Explicit user intent → allowed to spend an LLM call.
                            Task { try? await service.refresh(generateIfMissing: true) }
                        }
                    )
                    .padding(.top, 48)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .refreshable {
            // Pull-to-refresh on the mounted Read surface is explicit user
            // intent → allowed to generate (paid call) when today's is missing.
            try? await service.refresh(generateIfMissing: true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The 56pt clears `DripTabBar`. `MainTabView` puts the bar in a
            // `.safeAreaInset` on its ZStack, and that inset does NOT reach
            // inside each tab's `NavigationStack` — without this the bar
            // draws UNDER the tab bar's opaque paper and cannot be tapped
            // (found the day the Read became a tab; same fix as `CoachView`'s
            // ChatInputBar, where the pattern is documented at length).
            askBar
                .padding(.bottom, 56)
        }
        .sheet(item: workoutSheetItem) { item in
            // Detail sheet for a workout chip tap. The actual
            // workout-detail surface lives elsewhere in the app;
            // for v1 we present a lightweight summary.
            workoutDetailSheet(for: item.id)
        }
        .sheet(item: docSheetItem) { item in
            if let doc = service.docsById[item.id] {
                DocDetailSheet(doc: doc)
            }
        }
        .sheet(item: niggleSheetItem) { item in
            niggleTimelineSheet(for: item.value)
        }
        .sheet(item: $askReply) { reply in
            askReplySheet(for: reply)
        }
        .sheet(isPresented: $showWeeklyHistory) {
            WeeklyCoachingReportSheet()
        }
        // Composer for a question staged by another surface (Trends ask
        // bar). Presented when `coachAsk.pendingQuestion` is non-nil;
        // dismissing clears the staged question so it doesn't re-present.
        .sheet(isPresented: askComposerPresented) {
            CoachAskSheet(
                question: coachAsk.pendingQuestion ?? "",
                focus: coachAsk.focusLabel
            )
        }
        .alert(
            "Couldn't get an answer",
            isPresented: Binding(
                get: { askErrorText != nil },
                set: { if !$0 { askErrorText = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(askErrorText ?? "Try again in a moment.")
        }
    }

    // MARK: - Ask action

    /// Send the athlete's question to the AI and present the reply as a
    /// Training Insight sheet. The Read on screen is never mutated.
    private func submitAsk() {
        let q = askText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !isAsking else { return }
        isAsking = true
        Task {
            do {
                let reply = try await service.ask(q)
                askText = ""
                askReply = reply
            } catch {
                askErrorText = "Couldn't reach your training data. Try again."
            }
            isAsking = false
        }
    }

    /// The AI's answer to an "ask about my training" question, rendered in
    /// the same editorial voice as the daily Read.
    @ViewBuilder
    private func askReplySheet(for reply: CoachRead) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline(for: reply)
                    prose(for: reply)
                    if let cantSee = reply.cantSee {
                        CantSeeBlock(block: cantSee)
                            .padding(.top, 16)
                    }
                    ConfidenceBar(confidence: reply.confidence)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color.drip.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("TRAINING INSIGHT")
                        .font(.dripStat(10))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.0)
                }
            }
        }
    }

    // MARK: - Sub-views

    /// Two stacked rows on each side, ink/ink-2 split — matches the
    /// `PlateStrip` primitive in `ui_kits/ios_app/Primitives.jsx`.
    /// Left: brand line in ink, descriptor in ink-2. Right: figure
    /// number in ink; the optional bottom-right "edition" slot is
    /// dropped because the Read's date already lives in the dateline
    /// row below.
    private var plateStrip: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RUNNING LOG")
                    .foregroundStyle(Color.drip.textPrimary)
                Text("— THE READ")
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer()
            if let read = service.todayRead {
                Text(read.readDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .font(.dripStat(10))
        .tracking(1.4) // 0.14em × 10pt
        .padding(.bottom, 12)
    }

    /// The week band — the line that makes a Read an edition of a week
    /// (Fig. 12): a 2pt rule, "THE WEEK OF AUG 24 – 30", and "WK 35 ·
    /// 74.9 MI" on the right. The volume lives here so it never needs a
    /// stat strip further down.
    @ViewBuilder
    private var weekBand: some View {
        if let week = service.readWeek {
            VStack(alignment: .leading, spacing: 9) {
                Rectangle()
                    .fill(Color.drip.textPrimary)
                    .frame(height: 2)
                HStack(alignment: .firstTextBaseline) {
                    Text(week.label)
                        .font(.dripEyebrow(12))
                        .fontWeight(.bold)
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    Text(week.detail)
                        .font(.dripStat(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// "THU · MAY 14 · WK 9 / 16" + "↗ HISTORY".
    /// The week-of-block segment is omitted in modes other than
    /// PLAN_MODE — we'd need to fetch the active plan separately
    /// to compute it, and Phase 1's edge function already knows the
    /// mode but doesn't surface it to iOS. Future enhancement.
    private func dateline(for read: CoachRead) -> some View {
        HStack {
            // Masthead day, byline time, and signature all derive from
            // `generatedAt` (the moment the Read was posted) so the
            // masthead reads as one coherent day. The underlying
            // read_date/generated_at divergence (which produced the
            // "THU · JUN 11" vs "posted Friday" mismatch) is a server
            // date-resolution bug tracked in Phase 2 of the plan.
            Text(Self.datelineString(for: read.generatedAt))
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textPrimary)
                .tracking(1.3) // 0.12em × 11pt — section-eyebrow tracking
            Spacer()
            Button {
                showWeeklyHistory = true
            } label: {
                Text("↗ HISTORY")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.3)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 16)
    }

    /// 28pt black circle with coral border + coral diamond mark inside,
    /// then mono coral "YOUR TRAINING INSIGHT · <weekday> <time>". The
    /// "coach" framing was removed — the Read speaks as the product's own
    /// editorial voice, not an attributed coach persona.
    private func coachByline(for read: CoachRead) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.drip.textPrimary)
                Circle()
                    .stroke(Color.drip.coral, lineWidth: 1.5)
                Text("◆")
                    .font(.dripDisplay(12))
                    .foregroundStyle(Color.drip.coral)
            }
            .frame(width: 28, height: 28)

            Text("YOUR TRAINING INSIGHT · \(Self.bylineTimeString(for: read.generatedAt))")
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.coral)
                .tracking(1.3) // 0.12em × 11pt — coral section eyebrow
        }
        .padding(.bottom, 12)
    }

    /// 32pt display headline. Line-height 1.02 — tight, magazine-cover
    /// register. Approximated via lineSpacing since SwiftUI's `Text`
    /// doesn't expose explicit line-height.
    private func headline(for read: CoachRead) -> some View {
        Text(read.headline)
            .font(.dripDisplay(32))
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(0) // tight; 1.02 lh ≈ default at this size
            .padding(.bottom, 16)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The flowing paragraph with inline chips.
    private func prose(for read: CoachRead) -> some View {
        ReadProse(
            segments: read.paragraph,
            workouts: service.workoutsById,
            docs: service.docsById,
            selectedWorkoutId: $selectedWorkoutId,
            selectedDocId: $selectedDocId
        )
        .padding(.bottom, 16)
    }

    /// "— posted <weekday> morning · N min read" in italic body 12pt.
    private func signatureLine(for read: CoachRead) -> some View {
        Text(Self.signatureString(for: read))
            .font(.dripBody(12))
            .italic()
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.bottom, 8)
    }

    /// Editorial rule: short line · dot · short line, centered.
    /// Same primitive used elsewhere in the design — kept inline
    /// here because no shared component exists yet.
    private var editorialRule: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
            Circle()
                .fill(Color.drip.divider)
                .frame(width: 4, height: 4)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
        .frame(maxWidth: 200)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Volume × Intensity affordance

    /// Tappable editorial row that jumps to the Training tab, where the
    /// Volume × Intensity spectrum chart (PaceVolumeSpectrumChart) lives.
    /// The load number itself is read on the Training side; this is the
    /// "find the chart" entry point from the Read.
    private var volumeIntensityLink: some View {
        Button {
            // Training is tab index 1 (DripTab.training).
            selectedTab.wrappedValue = 1
        } label: {
            HStack(spacing: 8) {
                Text("VOLUME × INTENSITY")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.0)
                Spacer()
                Text("VIEW CHART ↗")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.coral)
                    .tracking(1.0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Byline placeholder.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.drip.divider)
                .frame(width: 160, height: 12)
                .padding(.top, 40)

            // Headline placeholder — two lines.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.drip.divider)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.drip.divider)
                .frame(maxWidth: 240)
                .frame(height: 36)

            // Paragraph placeholder — four lines.
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.drip.divider)
                        .frame(height: 14)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load today's read.")
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Pull to refresh.")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ask bar

    // MARK: - Check-in block

    /// The reply point. Sits directly under the Read's soft question so
    /// answering is one gesture, not a tab switch. Three inputs, all
    /// optional, all landing in the journal:
    ///   • mood radio — athlete-declared rating (`saveMoodCheckIn` when
    ///     it travels alone; rides on the row otherwise)
    ///   • text line  — `saveManualNotes` (same extraction pass as Log notes)
    ///   • mic        — `uploadCheckIn` (the existing `check_in` voice path)
    /// No coral here beyond what the controls already own — the question's
    /// rule above holds this cluster's accent.
    /// The small solid-coral circle both voice buttons here share — the
    /// Log front door's `PulsingRecordButton` identity (solid coral, white
    /// glyph) at inline scale, so "the red button records" holds everywhere.
    private func checkInVoiceGlyph(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.drip.coral)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
    }

    private var checkInBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Replies first, composer after — the question sits directly
            // above this block, so the page reads as an exchange: asked,
            // answered, and room to answer again (Fig. 12).
            repliesLedger

            DripMoodRadio(selection: $checkInMood)

            HStack(spacing: 12) {
                if checkInRecorder.isRecording {
                    // Recording state: pulsing coral dot + m:ss clock,
                    // stop button where the mic was.
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 8, height: 8)
                    Text(VoiceRecorder.clock(checkInRecorder.duration))
                        .font(.dripStat(14).monospacedDigit())
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("RECORDING")
                        .font(.dripStat(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer()
                    Button {
                        finishCheckInRecording()
                    } label: {
                        checkInVoiceGlyph("stop.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop recording")
                } else {
                    TextField(
                        "Answer in your own words…",
                        text: $checkInText,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .disabled(isSavingCheckIn)

                    if isSavingCheckIn {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 26, height: 26)
                    } else if checkInText.trimmingCharacters(in: .whitespaces).isEmpty
                        && checkInMood == nil {
                        // Empty state: voice is the primary action, in the
                        // homepage's solid coral. The mic IS this cluster's
                        // one coral element; the send arrow only appears once
                        // there is something to send.
                        Button {
                            startCheckInRecording()
                        } label: {
                            checkInVoiceGlyph("mic.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Record a voice check-in")
                    } else {
                        // Something to send: the arrow takes the slot (ink,
                        // not coral — the mic owns the red) and the mic
                        // steps back to an outline beside it.
                        Button {
                            startCheckInRecording()
                        } label: {
                            Image(systemName: "mic")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Record a voice check-in")

                        Button {
                            submitCheckIn()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send check-in")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.drip.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.drip.divider, lineWidth: 1)
                    )
            )

            if checkInSaved {
                Text("— logged to your journal")
                    .font(.dripBody(12))
                    .italic()
                    .foregroundStyle(Color.drip.textSecondary)
            }
            if let error = checkInErrorText {
                Text(error)
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.coral)
            }

        }
    }

    /// The answers, typeset back into the Read (Fig. 12): "YOU ANSWERED",
    /// then one hairline-topped row per reply — mono timestamp, the declared
    /// mood in its own colour, the athlete's words in italic — closed by a
    /// quiet "carried into the next read" line, which is literally true:
    /// coaching-daily-read feeds these rows to the model.
    @ViewBuilder
    private var repliesLedger: some View {
        if !service.todayReplies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("YOU ANSWERED")
                    .font(.dripStat(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textPrimary)
                    .padding(.bottom, 10)

                ForEach(service.todayReplies) { reply in
                    HStack(alignment: .top, spacing: 14) {
                        Text(Self.replyStamp(reply.createdAt))
                            .font(.dripStat(10))
                            .foregroundStyle(Color.drip.textTertiary)
                            .frame(width: 58, alignment: .leading)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 7) {
                            if let mood = reply.mood, !mood.isEmpty {
                                Text(mood.uppercased())
                                    .font(.dripEyebrow(10))
                                    .fontWeight(.bold)
                                    .tracking(1.0)
                                    .foregroundStyle(Self.moodColor(mood))
                            }
                            Text(replyWords(reply))
                                .font(.dripBody(13.5))
                                .italic()
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineLimit(4)
                            // A spoken reply is playable HERE — the athlete's
                            // actual voice is the artifact, and the transcript
                            // is a rendering of it. Same player the journal
                            // entry uses, so scrub/duration behave identically.
                            if let audio = reply.audioUrl, !audio.isEmpty {
                                MemoPlayerRow(url: audio)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.drip.divider).frame(height: 1)
                    }
                }

                HStack(spacing: 5) {
                    Text("→")
                        .foregroundStyle(Color.drip.coral)
                    Text("carried into the next read")
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .font(.dripStat(11))
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.drip.divider).frame(height: 1)
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// "MON 9:44" — the reply row's mono stamp.
    private static func replyStamp(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            + " " + date.formatted(date: .omitted, time: .shortened)
                .replacingOccurrences(of: " AM", with: "")
                .replacingOccurrences(of: " PM", with: "")
    }

    /// The reply's words alone — the ledger row carries mood separately, so
    /// this strips `summaryLine`'s "Mood — " prefix duplication by using the
    /// underlying fields directly.
    private func replyWords(_ reply: CoachReadReply) -> String {
        let words = (reply.cleanedNotes ?? reply.notes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { return "\u{201C}\(words)\u{201D}" }
        let pending = reply.processingStatus == "pending"
            || reply.processingStatus == "processing"
            || reply.processingStatus == "uploading"
        return pending ? "voice reply · transcribing" : "voice reply"
    }

    private static func moodColor(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "energized": Color.drip.energized
        case "positive": Color.drip.positive
        case "tired": Color.drip.tired
        case "struggling": Color.drip.struggling
        case "injured": Color.drip.injured
        default: Color.drip.neutral
        }
    }

    private var checkInSubmittable: Bool {
        checkInMood != nil
            || !checkInText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Send the typed line and/or mood rating. A mood travelling alone takes
    /// the no-parse path; anything with words goes through the same
    /// extraction pass as a Log note, so niggles in the reply still surface.
    private func submitCheckIn() {
        guard checkInSubmittable, !isSavingCheckIn else { return }
        let text = checkInText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mood = checkInMood
        isSavingCheckIn = true
        checkInSaved = false
        checkInErrorText = nil
        // Stamp which read this answers — the link that lists the reply
        // under the question and hands it to next week's read as data.
        let readId = service.todayRead?.id
        Task {
            let ok: Bool
            if text.isEmpty, let mood {
                ok = await checkInVM.saveMoodCheckIn(mood, repliedToReadId: readId)
            } else {
                ok = await checkInVM.saveManualNotes(
                    text, selectedWorkout: nil, mood: mood,
                    repliedToReadId: readId
                )
            }
            if ok {
                checkInText = ""
                checkInMood = nil
                checkInSaved = true
                await service.reloadReplies()
            } else {
                checkInErrorText = "Couldn't save — try again in a moment."
            }
            isSavingCheckIn = false
        }
    }

    private func startCheckInRecording() {
        checkInSaved = false
        checkInErrorText = nil
        checkInRecorder.start(
            onDenied: {
                checkInErrorText =
                    "Microphone access is off — enable it in Settings to record."
            },
            onError: { message in
                checkInErrorText = message
            }
        )
    }

    /// Stop the take and push it through the existing check-in voice path.
    /// `uploadCheckIn` owns failure handling (offline queue), so from here a
    /// stopped recording is always "logged" — never lost.
    private func finishCheckInRecording() {
        guard let take = checkInRecorder.stop() else { return }
        checkInRecorder.release()
        let mood = checkInMood
        let readId = service.todayRead?.id
        isSavingCheckIn = true
        Task {
            await checkInVM.uploadCheckIn(
                localURL: take.url,
                checkInManager: checkInManager,
                mood: mood,
                repliedToReadId: readId
            )
            checkInMood = nil
            checkInSaved = true
            isSavingCheckIn = false
            await service.reloadReplies()
        }
    }

    private var askBar: some View {
        HStack(spacing: 12) {
            TextField("Ask AI about my training…", text: $askText)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .submitLabel(.send)
                .disabled(isAsking)
                .onSubmit { submitAsk() }

            if isAsking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 26)
            } else {
                Button {
                    submitAsk()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            askText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.drip.textTertiary
                                : Color.drip.coral
                        )
                }
                .buttonStyle(.plain)
                .disabled(askText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color.drip.cardBackground
                .overlay(
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity, alignment: .top),
                    alignment: .top
                )
        )
    }

    // MARK: - Sheet routing

    /// Bridge between the `Binding<UUID?>` chips write to and the
    /// `Identifiable` shape `.sheet(item:)` expects.
    private var workoutSheetItem: Binding<UUIDItem?> {
        Binding(
            get: { selectedWorkoutId.map(UUIDItem.init) },
            set: { selectedWorkoutId = $0?.id }
        )
    }
    private var docSheetItem: Binding<UUIDItem?> {
        Binding(
            get: { selectedDocId.map(UUIDItem.init) },
            set: { selectedDocId = $0?.id }
        )
    }
    private var niggleSheetItem: Binding<StringItem?> {
        Binding(
            get: { selectedNiggle.map(StringItem.init) },
            set: { selectedNiggle = $0?.value }
        )
    }

    /// Drives the staged-question composer sheet. Reads truthy while a
    /// question is staged (from Trends etc.); clearing it on dismiss resets
    /// `coachAsk` so the sheet doesn't immediately re-present.
    private var askComposerPresented: Binding<Bool> {
        Binding(
            get: { coachAsk.pendingQuestion != nil },
            set: { presented in if !presented { coachAsk.clear() } }
        )
    }

    /// Niggle timeline — v1 surfaces the body part plainly. The full
    /// per-mention verbatim timeline (from `body_mentions`) is the next
    /// wire-up; this proves the tap-through and keeps it surface-not-diagnose.
    @ViewBuilder
    private func niggleTimelineSheet(for bodyPart: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("NIGGLE · \(bodyPart.uppercased())")
                    .font(.dripStat(11)).tracking(1.2)
                    .foregroundStyle(Color.drip.coral)
                Text("Your own words, over time.")
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                Text("The full mention-by-mention timeline lands next — surfaced verbatim, never diagnosed.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("NIGGLE")
                        .font(.dripStat(10)).tracking(0.8)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func workoutDetailSheet(for id: UUID) -> some View {
        // Route to the real workout analysis — Direction A "Rep Receipt":
        // hero rep chart, HR/pace/cadence/elevation telemetry, ANALYSIS +
        // SPLITS, vs-recent comparison, type override.
        //
        // Was a hand-rolled copy of WorkoutRepDetailSheet's chrome (and drifted
        // from it — tracking 0.8 where the canonical sheet uses 1.0). Presents
        // the canonical sheet since 2026-08-07 (S2).
        WorkoutRepDetailSheet(workoutId: id)
    }

    // MARK: - Date helpers

    /// "THU · MAY 14" for now. Plan-week segment ("WK 9 / 16") is
    /// gated on a plan fetch we haven't wired yet.
    private static func datelineString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: date).uppercased()
    }

    /// "THU 7:41 AM" — the byline's time stamp.
    private static func bylineTimeString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return f.string(from: date).uppercased()
    }

    /// "— posted Thursday morning · 3 min read".
    private static func signatureString(for read: CoachRead) -> String {
        let dayF = DateFormatter()
        dayF.locale = Locale(identifier: "en_US_POSIX")
        dayF.dateFormat = "EEEE"
        let day = dayF.string(from: read.generatedAt)
        let words = read.paragraph.reduce(into: 0) { acc, seg in
            if case .text(let s) = seg {
                acc += s.split { !$0.isLetter }.count
            }
        }
        // Generous reading-rate floor — short Reads read fast.
        let mins = max(1, Int((Double(words) / 220.0).rounded(.up)))
        return "— posted \(day) morning · \(mins) min read"
    }
}

/// Wrapper so we can drive `.sheet(item:)` from a `UUID?` binding.
private struct UUIDItem: Identifiable, Hashable {
    let id: UUID
}

/// Same bridge for the niggle ref's `String?` (body-part) binding.
private struct StringItem: Identifiable, Hashable {
    let value: String
    var id: String { value }
}

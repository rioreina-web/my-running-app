//
//  LogWildView.swift
//  RunningLog
//
//  The Log tab, Direction I. Tab 0 when the wild skin is on.
//
//  Two canonical screens, stacked into one scroll:
//
//  PAGE ONE — `Voice Log · canonical`. Masthead, centred lede, the linked
//  run as a ruled block, and the record button floating in whatever room
//  is left. The button is NOT padded into place: the block below the rail
//  is `frame(maxHeight: .infinity)` inside a page sized to the viewport,
//  so the button sits in the middle of the remainder. That is the whole
//  reason the screen reads composed rather than assembled, and it is the
//  one thing padding cannot fake.
//
//  PAGE TWO — `Log Feed · 032c`. Filter chips, week headers, and
//  `JournalWildRow` entries.
//
//  `VoiceLogView` is untouched and still serves the editorial skin. Both
//  read the same `VoiceLogViewModel`, so entries, uploads, niggles and
//  key sessions are the same data either way — flipping skins never
//  changes what is in the journal, only how it is set.
//
//  Prototype: `log-redesign-editorial-prototype.html`.
//

import SwiftUI

// MARK: - Journal filter

/// Voice memo / typed note / check-in. Mirrors `VoiceLogView`'s private
/// `JournalKind`; kept separate so neither file owns the other.
private enum WildJournalKind: String, CaseIterable {
    case all, voice, note, checkIn
    var label: String {
        switch self {
        case .all: return "All"
        case .voice: return "Voice"
        case .note: return "Notes"
        case .checkIn: return "Check-ins"
        }
    }
}

// MARK: - Formatters
//
// File-level, so each is built once for the life of the process.
// `DateFormatter()` is expensive to construct, and every one of these is read
// from inside a view body — a per-call allocation runs on every render of
// every row while scrolling. (Same lesson as the ISO8601DateFormatter note in
// LogView.groupIntoWeeks.)

private let wildWeekKeyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.calendar = Calendar.current
    f.timeZone = .current
    return f
}()

private let wildShortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f
}()

private let wildWeekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEEE"
    return f
}()

private let wildKeyDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE MMM d"
    return f
}()

private let wildISOFormatter = ISO8601DateFormatter()

private struct WildJournalWeek: Identifiable {
    let id: String
    let label: String
    let miles: Double
    let entries: [TrainingLog]
}

// MARK: - Default log mode

/// Which instrument the Log tab hands you first.
///
/// Stored as a plain string rather than a `RawRepresentable` enum so
/// `@AppStorage` needs no custom conformance. `SettingsView` writes it,
/// `LogWildView` reads it, and both go through these constants so a typo
/// cannot quietly split them into two different keys.
enum LogDefaultMode {
    static let key = "defaultLogMode"
    static let voice = "voice"
    static let text = "text"
}

// MARK: - Run phrasing
//
// File scope, not members, because `WildNoteComposerSheet` at the foot of this
// file needs the same phrasing as the front door's linked block. Two copies of
// "Today morning" is how the linked block and the picker ended up disagreeing
// about the same run in the first place.

private func dayPhrase(for date: Date) -> String {
    let cal = Calendar.current
    let hour = cal.component(.hour, from: date)
    let partOfDay = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
    if cal.isDateInToday(date) { return "Today \(partOfDay)" }
    if cal.isDateInYesterday(date) { return "Yesterday \(partOfDay)" }
    return "\(wildWeekdayFormatter.string(from: date)) \(partOfDay)"
}

private func metaLine(for w: RunningWorkout) -> String {
    let pace = w.pacePerMile > 0
        ? PaceCalculator.formatPaceFromMinutes(w.pacePerMile) + "/mi"
        : "—"
    return "\(w.formattedDuration) · \(pace)"
}

private func shortDate(_ d: Date) -> String {
    wildShortDateFormatter.string(from: d)
}

// MARK: - LogWildView

struct LogWildView: View {
    @Environment(CoachCheckInManager.self) private var checkInManager
    @ObservedObject private var healthKitManager = HealthKitManager.shared

    @State private var viewModel = VoiceLogViewModel()
    @State private var recorder = VoiceRecorder()

    // Recording
    @State private var pendingURL: URL?
    @State private var pendingDuration: TimeInterval = 0
    @State private var showConfirmation = false
    @State private var showMicDeniedAlert = false

    // Linked run
    @State private var selectedWorkout: RunningWorkout?
    @State private var showWorkoutPicker = false

    // Typed note. The composer is a sheet now, so the text, the focus and
    // the save all live inside `WildNoteComposerSheet` — this screen only
    // owns the flag that presents it.
    @State private var showComposer = false

    // Journal
    @State private var journalKind: WildJournalKind = .all
    @State private var journalSearch = ""
    @State private var showSearch = false
    @FocusState private var journalSearchFocused: Bool
    @State private var selectedHistoryEntry: TrainingLog?
    /// Week-grouped entries, built ONCE per change rather than per frame.
    ///
    /// This must stay stored `@State`. As a computed property it re-ran on
    /// every body evaluation — a full filter, a `Dictionary(grouping:)`, a
    /// sort, and the weekly mileage dedup — while scrolling. That is the lag.
    /// `LogView.swift` carries the same warning for the same reason.
    @State private var weekGroups: [WildJournalWeek] = []

    @State private var showToday = false

    /// Voice by default. Set in Settings → App → Write notes by default.
    @AppStorage(LogDefaultMode.key) private var defaultLogMode: String = LogDefaultMode.voice

    /// True when the athlete has asked to type first AND nothing is being
    /// recorded. A take in progress always shows the record block, because
    /// that is the only place the stop control lives.
    private var writingFirst: Bool {
        defaultLogMode == LogDefaultMode.text && !recorder.isRecording
    }

    /// The scroll anchor the masthead's "Today ↗" and the lede's
    /// "All runs ↗" both jump to.
    private let journalAnchor = "wild.journal"

    var body: some View {
        ZStack {
            Color.wild.paper.ignoresSafeArea()

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            frontDoor(height: geo.size.height)
                            journal
                                .id(journalAnchor)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(scrollJumpHandler(proxy))
                }
            }
        }
        .toolbar { toolbar }
        .toolbarBackground(Color.wild.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            recorder.prepare()
            Task {
                // Merged across HealthKit + Vital + Strava. This used to
                // fetch HealthKit only, and only when the list was empty —
                // so a Strava-only run never reached the block below, and a
                // run that landed mid-session never reached it either.
                await healthKitManager.refreshRecentRunsIfStale()
                await viewModel.loadHistory()
                rebuildWeekGroups()
            }
        }
        // The feed is rebuilt on the events that change it, and nowhere else.
        // `historyLogs.count` catches loads and new entries; the two filters
        // catch the athlete narrowing the feed; `weeklyMileageRows.count`
        // catches the mileage fetch landing after the entries do.
        .onChange(of: viewModel.historyLogs.count) { _, _ in rebuildWeekGroups() }
        .onChange(of: viewModel.weeklyMileageRows.count) { _, _ in rebuildWeekGroups() }
        .onChange(of: journalKind) { _, _ in rebuildWeekGroups() }
        .onChange(of: journalSearch) { _, _ in rebuildWeekGroups() }
        .sheet(isPresented: $showWorkoutPicker) {
            WildWorkoutPickerSheet(
                healthKitManager: healthKitManager,
                selectedWorkout: $selectedWorkout,
                isPresented: $showWorkoutPicker
            )
        }
        .sheet(isPresented: $showComposer) {
            WildNoteComposerSheet(
                healthKitManager: healthKitManager,
                viewModel: viewModel,
                selectedWorkout: $selectedWorkout,
                isPresented: $showComposer,
                onSaved: {
                    // `saveManualNotes` reloads the journal, but the new note
                    // lands below the fold — so saving looked like nothing
                    // happening. Scroll to it. Seeing the entry IS the
                    // receipt; it beats a toast that says it worked.
                    rebuildWeekGroups()
                    jumpRequest += 1
                }
            )
        }
        .sheet(isPresented: $showConfirmation) {
            RecordingConfirmationSheet(
                duration: pendingDuration,
                selectedWorkout: $selectedWorkout,
                healthKitManager: healthKitManager,
                onConfirm: confirmAndUpload,
                onDiscard: discardRecording
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showToday) {
            NavigationStack {
                TodayHomeView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showToday = false } label: {
                                WildLabel("Done", size: 11, color: Color.wild.redText)
                            }
                        }
                    }
            }
        }
        .sheet(item: $selectedHistoryEntry) { entry in
            HistoryDetailPager(entries: filteredHistoryLogs, initial: entry) {
                Task {
                    await viewModel.loadHistory()
                    rebuildWeekGroups()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if viewModel.showSuccessAnimation {
                SuccessOverlay()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .alert("Microphone access needed", isPresented: $showMicDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Voice memos need the microphone. Enable it in Settings → PostRunDrip → Microphone. You can also type your notes instead.")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            SidebarMenuButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showToday = true } label: {
                WildLabel("Today ↗", size: 10, tracking: 0.14, color: Color.wild.ink)
            }
            .buttonStyle(.plain)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            // The journal search field is the only thing on this screen that
            // takes the keyboard now — the composer brings its own.
            Button("Done") { journalSearchFocused = false }
                .font(.wildData(15))
                .foregroundStyle(Color.wild.redText)
        }
    }

    /// A hidden view that owns the "jump to journal" action, so both the
    /// lede link and any future callers share one implementation.
    private func scrollJumpHandler(_ proxy: ScrollViewProxy) -> some View {
        Color.clear
            .onChange(of: jumpRequest) { _, n in
                guard n > 0 else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(journalAnchor, anchor: .top)
                }
            }
    }

    @State private var jumpRequest = 0

    // MARK: - PAGE ONE · the front door

    private func frontDoor(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            lede
            linkedRun
            if writingFirst { writeBlock } else { recordBlock }
        }
        // One screenful. The nav bar and tab bar are outside this, so the
        // page is the visible scroll viewport — which is what `geo.size`
        // already reports.
        .frame(minHeight: max(height, 480))
    }

    // MARK: Lede

    private var lede: some View {
        VStack(spacing: 0) {
            if recorder.isRecording {
                Text(VoiceRecorder.clock(recorder.duration))
                    .font(.wildData(52, semibold: true))
                    .tracking(52 * -0.05)
                    .monospacedDigit()
                    .foregroundStyle(Color.wild.ink)
                    .contentTransition(.numericText())
                Text("Recording — tap the button to stop.")
                    .font(.wildDek(17))
                    .foregroundStyle(Color.wild.ink2)
                    .padding(.top, 12)
            } else {
                Text("Log your run.")
                    .font(.wildDisplay(46))
                    .tracking(46 * -0.05)
                    .foregroundStyle(Color.wild.ink)
                Text(writingFirst
                     ? "Tap the button to write a note."
                     : "Tap the button to start your voice memo.")
                    .font(.wildDek(17))
                    .foregroundStyle(Color.wild.ink2)
                    .padding(.top, 12)
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.wildProse(16))
                    .foregroundStyle(viewModel.statusMessage.contains("Error")
                                     ? Color.wild.redText : Color.wild.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 40)
        .padding(.bottom, 30)
        .overlay(alignment: .bottom) { WildRule() }
        .animation(.spring(response: 0.3), value: recorder.duration)
    }

    // MARK: Linked run

    private var linkedRun: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WildLabel("Linked to", size: 10, tracking: 0.14)
                Spacer()
                Button {
                    jumpRequest += 1
                } label: {
                    WildLabel("All runs ↗", size: 10, tracking: 0.14, color: Color.wild.ink)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.wild.ink2)
                                .frame(height: 1).offset(y: 3)
                        }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            Button {
                showWorkoutPicker = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    if let w = latestWorkout {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(format: "%.2f", w.distanceMiles))
                                .font(.wildData(32, semibold: true))
                                .tracking(32 * -0.035)
                                .monospacedDigit()
                                .foregroundStyle(Color.wild.ink)
                            WildLabel("mi", size: 10, tracking: 0.14)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dayPhrase(for: w.startDate))
                                .font(.wildDisplay(13))
                                .tracking(13 * -0.02)
                                .foregroundStyle(Color.wild.ink)
                            Text(metaLine(for: w))
                                // Data role, not mono: these are measured
                                // stats. Mono is transcripts and machine
                                // answers, nothing else (system §1).
                                .font(.wildData(11))
                                .foregroundStyle(Color.wild.ink2)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 8)
                        if selectedWorkout == nil || selectedWorkout?.id == w.id {
                            WildLabel("Latest", size: 9, tracking: 0.14, color: Color.wild.paper)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.wild.ink)
                        }
                    } else {
                        Text("Optional — attach to a recent run.")
                            .font(.wildDek(16))
                            .foregroundStyle(Color.wild.ink2)
                        Spacer(minLength: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            railOfRecentRuns
                .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { WildRule() }
    }

    /// The run the block is showing: whatever is selected, else the newest.
    private var latestWorkout: RunningWorkout? {
        selectedWorkout ?? healthKitManager.recentRuns.first
    }

    private var railOfRecentRuns: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(healthKitManager.recentRuns.prefix(6), id: \.id) { w in
                    railChip(
                        date: shortDate(w.startDate),
                        value: String(format: "%.2f", w.distanceMiles),
                        active: latestWorkout?.id == w.id
                    ) {
                        selectedWorkout = w
                    }
                }
                railChip(date: "None", value: nil, active: selectedWorkout == nil
                         && healthKitManager.recentRuns.isEmpty) {
                    selectedWorkout = nil
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func railChip(date: String,
                          value: String?,
                          active: Bool,
                          tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(date.uppercased())
                    // Tracked uppercase → the Label role (Schibsted), not
                    // mono. Tracking derived from size, same value as before.
                    .font(.wildLabel(10))
                    .tracking(10 * 0.10)
                if let value {
                    Text(value)
                        // Data role — a measured distance, not a machine answer.
                        .font(.wildData(10, semibold: true))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? Color.wild.paper : Color.wild.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(active ? Color.wild.ink : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? Color.wild.ink : Color.wild.rule, lineWidth: 1))
            // The chip is 32pt tall by design (it matches the reference).
            // The tap target is padded out to 44pt without moving the pill.
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Record

    private var recordBlock: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            WildRecordButton(
                isRecording: recorder.isRecording,
                isDisabled: viewModel.isUploading
            ) {
                toggleRecording()
            }

            WildLabel(recorder.isRecording ? "Tap to stop" : "Tap to record",
                      size: 11, tracking: 0.16)
                .padding(.top, 12)

            if !recorder.isRecording {
                Button {
                    showComposer = true
                } label: {
                    WildLabel("Type a note instead ↗", size: 10, tracking: 0.14)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { WildRule() }
    }

    /// The front door when the athlete types more than they talk.
    ///
    /// A mirror of `recordBlock`: one primary, its label, and the other
    /// instrument as a quiet link underneath. The primary is a type slab bound
    /// by the 2pt editorial rules rather than a second circular button —
    /// a filled circle reads as "record" everywhere, and the one red belongs
    /// to the record button alone.
    ///
    /// `Record instead ↗` starts the take immediately rather than just
    /// swapping the view. That flips `recorder.isRecording`, which sends
    /// `writingFirst` false and hands the screen back to `recordBlock`, where
    /// the stop control is.
    private var writeBlock: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Button {
                showComposer = true
            } label: {
                Text("Write a note.")
                    .font(.wildDisplay(30))
                    .tracking(30 * -0.045)
                    .foregroundStyle(Color.wild.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .overlay(alignment: .top) { WildRule(strong: true) }
                    .overlay(alignment: .bottom) { WildRule(strong: true) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            WildLabel("Tap to write", size: 11, tracking: 0.16)
                .padding(.top, 12)

            Button {
                toggleRecording()
            } label: {
                WildLabel("Record instead ↗", size: 10, tracking: 0.14)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .disabled(viewModel.isUploading)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { WildRule() }
    }

    // MARK: - PAGE TWO · the journal

    private var journal: some View {
        VStack(spacing: 0) {
            journalHead
            if showSearch { journalSearchField }
            journalContent
        }
        .padding(.bottom, 40)
    }

    private var journalHead: some View {
        HStack(spacing: 7) {
            ForEach(WildJournalKind.allCases, id: \.self) { kind in
                kindChip(kind)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() }
                if !showSearch { journalSearch = "" }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.wild.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { WildRule() }
    }

    private func kindChip(_ kind: WildJournalKind) -> some View {
        let active = journalKind == kind
        return Button {
            journalKind = kind
        } label: {
            Text(kind.label.uppercased())
                .font(.wildLabel(11))
                .tracking(11 * 0.10)
                .foregroundStyle(active ? Color.wild.paper : Color.wild.ink2)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(active ? Color.wild.ink : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.wild.ink : Color.wild.rule, lineWidth: 1))
                .padding(.vertical, 5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var journalSearchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.wild.ink2)
            TextField("Search your words", text: $journalSearch)
                .focused($journalSearchFocused)
                .font(.wildDataRegular(14))
                .foregroundStyle(Color.wild.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !journalSearch.isEmpty {
                Button { journalSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wild.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { WildRule() }
        .transition(.opacity)
    }

    @ViewBuilder
    private var journalContent: some View {
        if viewModel.isLoadingHistory && viewModel.historyLogs.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(Color.wild.ink2)
                Spacer()
            }
            .padding(.vertical, 40)
        } else if viewModel.historyLogs.isEmpty && viewModel.loadFailed {
            // A load error is NOT an empty journal. Never say "no entries"
            // here — the rows are safe on the server and saying otherwise
            // reads as data loss.
            journalMessage("Couldn't load your journal. Your entries are safe — this is a connection hiccup.",
                           action: ("Retry ↗", {
                               Task {
                                   await viewModel.loadHistory()
                                   rebuildWeekGroups()
                               }
                           }))
        } else if viewModel.historyLogs.isEmpty {
            journalMessage("No entries yet — record or type to start your journal.")
        } else if weekGroups.isEmpty {
            // Read the cached groups, not `filteredHistoryLogs` — that filters
            // the whole history and this is evaluated from `body`.
            journalMessage(journalSearch.isEmpty
                           ? "No \(journalKind.label.lowercased()) entries yet."
                           : "Nothing matches \u{201C}\(journalSearch)\u{201D}.")
        } else {
            // Not pinned. A pinned header sticks to the scroll view's top
            // edge, and the scroll view extends under the navigation bar — so
            // the week label was being clipped in half by the toolbar. 032c
            // scrolls its section labels with the content; so does this.
            LazyVStack(spacing: 0) {
                ForEach(weekGroups) { week in
                    Section {
                        ForEach(week.entries, id: \.id) { log in
                            entryRow(log)
                        }
                    } header: {
                        weekHeader(week)
                    }
                }
            }
        }
    }

    private func journalMessage(_ text: String,
                                action: (String, () -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.wildProse(18))
                .foregroundStyle(Color.wild.ink2)
            if let action {
                Button(action: action.1) {
                    WildLabel(action.0, size: 10, tracking: 0.14, color: Color.wild.redText)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
    }

    private func weekHeader(_ week: WildJournalWeek) -> some View {
        HStack {
            Text("\(week.label.uppercased())  ·  \(Int(week.miles.rounded())) MI")
                .font(.wildLabel(11))
                .tracking(11 * 0.12)
                .foregroundStyle(Color.wild.ink2)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 14)
        .background(Color.wild.paper)
    }

    @ViewBuilder
    private func entryRow(_ log: TrainingLog) -> some View {
        if log.isPending || log.isFailed {
            JournalWildProcessingRow(entry: log) {
                Task {
                    await viewModel.retryProcessing(log: log)
                    rebuildWeekGroups()
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) { WildRule() }
        } else {
            Button {
                selectedHistoryEntry = log
            } label: {
                JournalWildRow(entry: log,
                               niggles: viewModel.niggleByLog[log.id.uuidString] ?? [])
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .padding(.bottom, 30)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) { WildRule() }
            }
            .buttonStyle(.plain)
            .contextMenu { keySessionMenu(for: log) }
        }
    }

    /// Long-press to declare the day a key session. Same three explicit
    /// options as the editorial feed, and the same day-scoped store — the
    /// star here can never disagree with the calendar's.
    @ViewBuilder
    private func keySessionMenu(for log: TrainingLog) -> some View {
        let day = log.displayDate
        let current = KeySessionStore.shared.override(on: day)

        Section("KEY SESSION · MARKS \(Self.keyDayLabel(day))") {
            Button {
                Task { await KeySessionStore.shared.set(true, on: day) }
            } label: {
                Label("Key session", systemImage: current == true ? "checkmark" : "star")
            }
            Button {
                Task { await KeySessionStore.shared.set(false, on: day) }
            } label: {
                Label("Not a key session", systemImage: current == false ? "checkmark" : "star.slash")
            }
            if current != nil {
                Button {
                    Task { await KeySessionStore.shared.clear(on: day) }
                } label: {
                    Label("Back to auto", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    private static func keyDayLabel(_ date: Date) -> String {
        wildKeyDayFormatter.string(from: date).uppercased()
    }

    // MARK: - Filtering and grouping

    /// History filtered by the active kind + free-text search over notes.
    private var filteredHistoryLogs: [TrainingLog] {
        let q = journalSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return viewModel.historyLogs.filter { log in
            let kindOK: Bool
            switch journalKind {
            case .all: kindOK = true
            case .voice: kindOK = log.audioUrl != nil && log.source != "check_in"
            case .note: kindOK = log.audioUrl == nil && log.source != "check_in"
            case .checkIn: kindOK = log.source == "check_in"
            }
            guard kindOK else { return false }
            guard !q.isEmpty else { return true }
            let hay = [log.cleanedNotes, log.notes, log.workoutNotes, log.coachInsight]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return hay.contains(q)
        }
    }

    /// Monday 00:00 of the week containing `d` — Monday-start, matching
    /// the dashboard and Trends convention.
    private static func weekStart(_ d: Date) -> Date {
        let cal = Calendar.current
        let sod = cal.startOfDay(for: d)
        let weekday = cal.component(.weekday, from: sod)   // 1=Sun … 7=Sat
        let daysFromMonday = (weekday + 5) % 7             // Mon=0 … Sun=6
        return cal.date(byAdding: .day, value: -daysFromMonday, to: sod) ?? sod
    }

    /// Rebuild the grouped feed. Called on load, on filter change, and after
    /// anything writes an entry — never from `body`.
    private func rebuildWeekGroups() {
        weekGroups = makeWeekGroups()
    }

    private func makeWeekGroups() -> [WildJournalWeek] {
        let totals = weeklyTotalMiles
        let thisWeek = Self.weekStart(Date())
        let grouped = Dictionary(grouping: filteredHistoryLogs) {
            Self.weekStart($0.workoutDate ?? $0.createdAt)
        }
        return grouped.keys.sorted(by: >).map { ws in
            let entries = grouped[ws] ?? []
            let weeksAgo = Int((thisWeek.timeIntervalSince(ws) / (7 * 86400)).rounded())
            let label: String
            switch weeksAgo {
            case 0: label = "This week"
            case 1: label = "Last week"
            default: label = "Week of \(ws.formatted(.dateTime.month(.abbreviated).day()))"
            }
            // True weekly total (all runs, deduped) — not just the authored
            // entries in the feed. Falls back to the entry sum until the
            // mileage fetch lands.
            let miles = totals[Self.weekKey(ws)]
                ?? entries.reduce(0.0) { $0 + ($1.workoutDistanceMiles ?? 0) }
            return WildJournalWeek(id: wildISOFormatter.string(from: ws),
                                   label: label, miles: miles, entries: entries)
        }
    }

    private static func weekKey(_ ws: Date) -> String {
        wildWeekKeyFormatter.string(from: ws)
    }

    private var weeklyTotalMiles: [String: Double] {
        var byWeek: [String: [JournalMileageRow]] = [:]
        for r in viewModel.weeklyMileageRows {
            let key = Self.weekKey(Self.weekStart(r.workoutDate ?? r.createdAt))
            byWeek[key, default: []].append(r)
        }
        return byWeek.mapValues { Self.dedupedMiles($0) }
    }

    /// Mirrors the dashboard dedup: a voice_log / check_in carrying a
    /// distance that matches a same-day run from another source is already
    /// counted on that run — skip it so the week isn't double-counted.
    private static func dedupedMiles(_ rows: [JournalMileageRow]) -> Double {
        let cal = Calendar.current
        let withDist = rows.filter { ($0.miles ?? 0) > 0 }

        // Index the GPS-sourced runs by day ONCE. The original rescanned the
        // whole array for every voice log — O(n²) over 180 days of rows, and
        // it ran on every body evaluation. Same answer, one pass.
        var runsByDay: [Date: [Double]] = [:]
        for r in withDist where r.source != "voice_log" && r.source != "check_in" {
            let day = cal.startOfDay(for: r.workoutDate ?? r.createdAt)
            runsByDay[day, default: []].append(r.miles ?? 0)
        }

        var total = 0.0
        for r in withDist {
            if r.source == "voice_log" || r.source == "check_in" {
                let day = cal.startOfDay(for: r.workoutDate ?? r.createdAt)
                let miles = r.miles ?? 0
                if let sameDay = runsByDay[day],
                   sameDay.contains(where: { abs($0 - miles) <= 0.3 }) {
                    continue
                }
            }
            total += r.miles ?? 0
        }
        return total
    }

    // MARK: - Copy helpers

    // MARK: - Recording

    private func toggleRecording() {
        if recorder.isRecording {
            guard let take = recorder.stop() else {
                viewModel.statusMessage = "Error: No recording found"
                return
            }
            pendingURL = take.url
            pendingDuration = take.duration
            showConfirmation = true
        } else {
            viewModel.statusMessage = ""
            recorder.start(
                onDenied: { showMicDeniedAlert = true },
                onError: { viewModel.statusMessage = $0 }
            )
        }
    }

    private func confirmAndUpload() {
        guard let url = pendingURL else { return }
        showConfirmation = false
        Task {
            await viewModel.uploadAudioAndSaveLog(
                localURL: url,
                selectedWorkout: selectedWorkout,
                checkInManager: checkInManager
            )
            pendingURL = nil
            pendingDuration = 0
            selectedWorkout = nil
            recorder.release()
            rebuildWeekGroups()
        }
    }

    private func discardRecording() {
        showConfirmation = false
        recorder.discard()
        pendingURL = nil
        pendingDuration = 0
        viewModel.statusMessage = ""
    }
}

// MARK: - Note composer

private let wildComposerStampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE · MMM d"
    return f
}()

/// Typing a note is its own surface.
///
/// It used to sit in the record button's slot on the front door — see
/// `LOG-WILD-APPLY.md` §6d, which put it there so "Type a note instead" would
/// not look like a button that did nothing. That reasoning was right about the
/// symptom and this keeps the cure: the sheet opens on the same tap, instantly.
///
/// But the slot is at the foot of a page sized to the whole viewport inside a
/// scroll view. With the keyboard up that left roughly 44pt — enough for the
/// "Note · today" label and the Save link, and nothing at all for the text the
/// athlete came to write. The tab bar still took its own 50pt off the bottom,
/// and the keyboard toolbar's Done button landed on top of it. No arrangement
/// of padding wins that; the slot itself was the problem.
///
/// On a sheet there is no tab bar, nothing scrolls underneath, and the writing
/// surface is simply what is left after four fixed rows — a little over twice
/// what the slot could ever give.
///
/// Prototype: `note-composer-prototype.html`.
struct WildNoteComposerSheet: View {
    @ObservedObject var healthKitManager: HealthKitManager
    /// `@Observable`, so a plain `let` tracks it.
    let viewModel: VoiceLogViewModel
    @Binding var selectedWorkout: RunningWorkout?
    @Binding var isPresented: Bool
    /// Fired after a save lands, so the Log screen can rebuild the feed and
    /// scroll to the new entry.
    var onSaved: () -> Void

    @State private var text = ""
    @State private var showWorkoutPicker = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmed.isEmpty && !viewModel.isUploading }

    /// Whatever the note will attach to: an explicit pick, else the newest run.
    /// Reads `recentRuns` — merged across HealthKit, Vital and Strava — because
    /// a Strava-only run has to be linkable too.
    private var target: RunningWorkout? {
        selectedWorkout ?? healthKitManager.recentRuns.first
    }

    var body: some View {
        ZStack {
            Color.wild.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                bar
                WildRule()
                lede
                WildRule()
                linkedLine
                WildRule()
                writingSurface
                WildRule()
                footer
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showWorkoutPicker) {
            WildWorkoutPickerSheet(
                healthKitManager: healthKitManager,
                selectedWorkout: $selectedWorkout,
                isPresented: $showWorkoutPicker
            )
        }
        .task {
            // The field has to exist before it can take focus — asking in the
            // same render pass that creates it is a no-op.
            try? await Task.sleep(for: .milliseconds(120))
            focused = true
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack {
            Button {
                focused = false
                isPresented = false
            } label: {
                WildLabel("Cancel", size: 10, tracking: 0.14)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            if viewModel.isUploading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.wild.ink2)
                    .frame(minHeight: 44)
            } else {
                Button(action: save) {
                    // Grey until there is something to save, then the one red.
                    // Same verb-plus-arrow as `Mark complete ↗` elsewhere, so
                    // there is no new affordance to learn.
                    WildLabel("Save ↗", size: 10, tracking: 0.14,
                              color: canSave ? Color.wild.redText : Color.wild.ink3)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: Lede

    private var lede: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note.")
                .font(.wildDisplay(34))
                .tracking(34 * -0.045)
                .foregroundStyle(Color.wild.ink)
            Text("Write a note about your run.")
                .font(.wildDek(16))
                .foregroundStyle(Color.wild.ink2)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: Linked run

    /// One line, not the front door's whole block. You need to know where the
    /// note lands; you do not need the 32pt figure and the chip rail twice.
    private var linkedLine: some View {
        Button {
            focused = false
            showWorkoutPicker = true
        } label: {
            HStack(spacing: 10) {
                if let w = target {
                    Text(String(format: "%.2f mi", w.distanceMiles))
                        .font(.wildData(15, semibold: true))
                        .tracking(15 * -0.02)
                        .monospacedDigit()
                        .foregroundStyle(Color.wild.ink)
                    Text("\(dayPhrase(for: w.startDate)) · \(metaLine(for: w))")
                        // Data role — measured stats, not a transcript.
                        .font(.wildData(11))
                        .foregroundStyle(Color.wild.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    WildLabel("Change ↗", size: 10, tracking: 0.14, color: Color.wild.ink)
                } else {
                    WildLabel("Link a run ↗", size: 10, tracking: 0.14, color: Color.wild.ink)
                    Spacer(minLength: 8)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: The writing surface

    private var writingSurface: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                // The canonical prompt. Prose, not mono italic: italic
                // JetBrains Mono is a transcript — the machine quoting the
                // athlete back — and this is the athlete writing.
                Text("How did the run feel?")
                    .font(.wildProse(20))
                    .foregroundStyle(Color.wild.ink3)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.wildProse(20))
                .foregroundStyle(Color.wild.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 17, not 22: TextEditor carries about 5pt of its own leading inset,
        // so this is what lines the first character up with everything above.
        .padding(.horizontal, 17)
        .padding(.top, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                focused = false
                isPresented = false
            } label: {
                // Out of the writing surface. In the old inline composer this
                // sat directly under the field, competing with the thing being
                // typed into.
                WildLabel("Record instead ↗", size: 10, tracking: 0.14)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            WildLabel(wildComposerStampFormatter.string(from: Date()),
                      size: 10, tracking: 0.14, color: Color.wild.ink3)
        }
        .padding(.horizontal, 22)
    }

    // MARK: Save

    private func save() {
        let body = trimmed
        guard !body.isEmpty else { return }
        focused = false
        Task {
            let saved = await viewModel.saveManualNotes(body, selectedWorkout: selectedWorkout)
            // On failure the view model surfaces the error and the sheet stays
            // up with the text intact. Dismissing here would throw away words
            // the athlete cannot get back.
            guard saved else { return }
            text = ""
            selectedWorkout = nil
            isPresented = false
            onSaved()
        }
    }
}

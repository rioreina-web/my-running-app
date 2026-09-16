//
//  SheetTabView.swift
//  RunningLog
//
//  The Sheet — every session as one dense row. Tab 9.
//
//  A scannable table of completed training: one row per SESSION (see
//  `SessionRollup.swift`), week-grouped, totals on top, filter chips and a
//  search box. It is the screen you read to see a block of training at once —
//  the journal (`VoiceLogView`) is for reading one entry at a time.
//
//  DESIGN SYSTEM NOTES — the non-obvious constraints this screen is under.
//
//  • FOUR COLUMNS, NOT SEVEN. An early spec had 52+52+46+62+30+74 plus gaps
//    = 376pt against 345pt of usable width at 393pt minus 24pt padding. Date ·
//    Session · Mi · Pace is what actually fits an iPhone.
//  • CORAL IS ALERT-ONLY (design-system/README.md). Quality sessions read as
//    WEIGHT, not colour and not a glyph. Selected chips are solid ink. A search
//    hit is marked by weight and ink, not a wash. The only coral on this
//    screen is the folded-row alert chip.
//  • NO GLYPH OUTSIDE `· ↗ →`. There is no magnifier icon: the search field
//    carries a placeholder and a text "Clear" button instead.
//  • PACE IS DERIVED, NEVER READ. `workout_pace_per_mile` is populated on 12%
//    of rows. Format through `DistanceFormat.paceMMSS(secPerMile:)`, which
//    rounds the total before splitting — do not hand-roll it, or a 6.1 mi / 48
//    min run prints "7:60".
//

import SwiftUI

struct SheetTabView: View {

    // MARK: State

    @State private var rows: [TodayLogRow] = []
    /// Sessions and week groups are computed ONCE per load and per filter
    /// change, never in `body`. A computed property here re-runs the whole
    /// rollup on every body evaluation — per frame, while scrolling. (Same
    /// lesson as `LogView.weekGroups` and the memo caches in
    /// `TrainingAnalyticsViewModel`.)
    @State private var allSessions: [TrainingSession] = []
    @State private var weekGroups: [SheetWeek] = []
    @State private var chipCounts: [SessionTag: Int] = [:]
    @State private var totals = SheetTotals()

    @State private var range: SheetRange = .eight
    @State private var selectedTags: Set<SessionTag> = []
    @State private var query = ""
    @State private var expanded: Set<UUID> = []

    @State private var loaded = false
    @State private var loadFailed = false

    /// 400 days covers the widest range the picker offers with headroom.
    private let fetchDays = 400

    // MARK: Body

    var body: some View {
        ScrollView {
            // Only WEEK headers pin. The title block scrolls away with the
            // content — pinning it would leave the search field, chips and
            // totals covering the sheet you are trying to read.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                columnHeader
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            Text("Loading…")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 24)
        } else if loadFailed {
            EmptyStateView(
                variant: .error,
                eyebrow: "Couldn't load",
                title: "Your sheet didn't load. Check your connection and try again.",
                cta: .init(label: "Retry") { Task { await load() } }
            )
            .padding(.top, 24)
        } else if weekGroups.isEmpty {
            emptyState.padding(.top, 24)
        } else {
            ForEach(weekGroups) { week in
                Section {
                    ForEach(week.sessions) { session in
                        SheetRowView(
                            session: session,
                            leadsDay: week.leadIDs.contains(session.id),
                            query: query,
                            isExpanded: expanded.contains(session.id),
                            onTap: { toggle(session.id) }
                        )
                    }
                } header: {
                    weekHeader(week).background(Color.drip.background)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LOG · SHEET")
                .font(.dripEyebrow(11)).tracking(1.5)
                .foregroundStyle(Color.drip.textTertiary)

            Text("Every session.")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 4)

            Text(subtitle)
                .font(.dripBody(12))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 2)

            rangePicker.padding(.top, 20)
            searchField.padding(.top, 16)
            chipRow.padding(.top, 12)
            totalsStrip.padding(.top, 8)
        }
        .padding(.top, 16)
    }

    private var subtitle: String {
        var parts = [range.label]
        let tags = SessionTag.allCases.filter { selectedTags.contains($0) }
        if !tags.isEmpty { parts.append(tags.map(\.label).joined(separator: " + ")) }
        if !query.isEmpty { parts.append("“\(query)”") }
        return parts.joined(separator: " · ")
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(SheetRange.allCases) { r in
                let on = r == range
                Button {
                    range = r
                    expanded.removeAll()
                    recompute()
                } label: {
                    Text(r.short.uppercased())
                        .font(.dripEyebrow(10)).tracking(1.0)
                        .foregroundStyle(on ? Color.drip.textPrimary : Color.drip.textSecondary)
                        .fontWeight(on ? .semibold : .regular)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(on ? Color.drip.cardBackground : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.drip.paperDeep))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            // No magnifier: the system's glyph list closes at `· ↗ →`.
            TextField("Search sessions and notes", text: $query)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: query) { _, _ in
                    expanded.removeAll()
                    recompute()
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    expanded.removeAll()
                    recompute()
                } label: {
                    Text("CLEAR")
                        .font(.dripEyebrow(10)).tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.drip.paperDeep))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.drip.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
        )
    }

    /// Horizontal scroll, not a wrap — a wrapping chip row reflows the whole
    /// sheet every time a count changes width.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SessionTag.allCases) { tag in
                    let n = chipCounts[tag] ?? 0
                    let on = selectedTags.contains(tag)
                    Button {
                        if on { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                        expanded.removeAll()
                        recompute()
                    } label: {
                        HStack(spacing: 5) {
                            Text(tag.label.uppercased())
                                .font(.dripEyebrow(10)).tracking(1.0)
                            Text("\(n)")
                                .font(.dripEyebrow(10))
                                .foregroundStyle(
                                    on ? Color.drip.background.opacity(0.55)
                                       : Color.drip.textTertiary
                                )
                        }
                        // Selected is solid ink, never coral.
                        .foregroundStyle(on ? Color.drip.background : Color.drip.textSecondary)
                        .padding(.vertical, 6).padding(.horizontal, 11)
                        .background(
                            Capsule().fill(on ? Color.drip.textPrimary : Color.drip.cardBackground)
                        )
                        .overlay(
                            Capsule().stroke(
                                on ? Color.drip.textPrimary : Color.drip.divider,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    // A zero-count chip dims rather than disappearing: a chip
                    // that vanishes reflows the row and re-reads as a different
                    // control on every keystroke.
                    .opacity(n == 0 ? 0.35 : 1)
                    .allowsHitTesting(n > 0)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var totalsStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            totalCell(
                "Miles",
                value: String(format: "%.0f", totals.miles),
                unit: nil,
                sub: "\(totals.days) days run"
            )
            Rectangle().fill(Color.drip.divider).frame(width: 1)
            totalCell(
                "Avg / week",
                value: String(format: "%.1f", totals.perWeek),
                unit: "mi",
                sub: "\(totals.uploads) uploads"
            )
            .padding(.leading, 12)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private func totalCell(_ key: String, value: String, unit: String?, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.uppercased())
                .font(.dripEyebrow(10)).tracking(1.1)
                .foregroundStyle(Color.drip.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.dripStat(22))
                    .foregroundStyle(Color.drip.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.dripEyebrow(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            Text(sub)
                .font(.dripEyebrow(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hairline: some View {
        Rectangle().fill(Color.drip.divider).frame(height: 1)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("DATE").frame(width: 40, alignment: .leading)
            Text("SESSION").frame(maxWidth: .infinity, alignment: .leading)
            Text("MI").frame(width: 48, alignment: .trailing)
            Text("PACE").frame(width: 52, alignment: .trailing)
        }
        .font(.dripEyebrow(10))
        .tracking(1.0)
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.textPrimary).frame(height: 1)
        }
    }

    private func weekHeader(_ week: SheetWeek) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.drip.textTertiary).frame(width: 16, height: 1)
            Text(week.label.uppercased())
                .font(.dripEyebrow(10)).tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize()
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    /// Two empty states, not one. A filtered-empty result is a dead end unless
    /// it offers the way out, so it carries the reset; the unfiltered one
    /// points at the range control and Strava instead.
    @ViewBuilder
    private var emptyState: some View {
        if isFiltering {
            EmptyStateView(
                variant: .optionalEmpty,
                eyebrow: "No match",
                title: "Nothing matches \(subtitleFilterPhrase).",
                cta: .init(label: "Clear filters") {
                    selectedTags.removeAll()
                    query = ""
                    expanded.removeAll()
                    recompute()
                }
            )
        } else {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing here yet",
                title: "No sessions in this range. Widen the range, or connect Strava so your runs land here on their own."
            )
        }
    }

    private var isFiltering: Bool { !selectedTags.isEmpty || !query.isEmpty }

    private var subtitleFilterPhrase: String {
        let tags = SessionTag.allCases.filter { selectedTags.contains($0) }.map(\.label)
        var parts: [String] = []
        if !tags.isEmpty { parts.append(tags.joined(separator: " + ")) }
        if !query.isEmpty { parts.append("“\(query)”") }
        return parts.joined(separator: " and ")
    }

    // MARK: Actions

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func load() async {
        loadFailed = false

        // Stale-while-revalidate, same shape as LogView: render the disk-backed
        // snapshot instantly, then refresh over the network.
        if rows.isEmpty {
            let cached = TrainingLogStore.shared.cachedRows(days: fetchDays)
            if !cached.isEmpty {
                rows = cached
                allSessions = SessionRollup.sessions(from: cached)
                recompute()
                loaded = true
            }
        }

        do {
            let fetched = try await TrainingLogStore.shared.refresh(days: fetchDays)
            rows = fetched
            allSessions = SessionRollup.sessions(from: fetched)
            recompute()
            loaded = true
        } catch {
            if rows.isEmpty { loadFailed = true }
            loaded = true
        }
    }

    /// Re-derives everything the body reads. Called on load and on every filter
    /// change — never from `body`.
    private func recompute() {
        let cutoff = range.cutoff()
        let inRange = allSessions.filter { $0.day >= cutoff }

        // Chip counts respond to the search box but NOT to tag selection, so
        // the numbers hold still while you toggle chips. Counting after
        // selection collapses every other chip to 0 the moment you tap one.
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let searched = inRange.filter { $0.matches(query: q) }
        var counts: [SessionTag: Int] = [:]
        for tag in SessionTag.allCases {
            counts[tag] = searched.filter { tag.matches($0) }.count
        }
        chipCounts = counts

        let shown = searched.filter { s in
            selectedTags.isEmpty || selectedTags.contains { $0.matches(s) }
        }

        weekGroups = Self.groupIntoWeeks(shown)

        // Weeks come from the RANGE, not the matches: "threshold miles per week
        // of training" is the useful number, not "per week that happened to
        // have one".
        let rangeWeeks = max(1, Self.groupIntoWeeks(inRange).count)
        totals = SheetTotals(
            miles: shown.reduce(0) { $0 + $1.miles },
            days: Set(shown.map(\.day)).count,
            uploads: shown.reduce(0) { $0 + $1.allPieces.count },
            perWeek: shown.reduce(0) { $0 + $1.miles } / Double(rangeWeeks)
        )
    }

    // MARK: Weeks

    private static func groupIntoWeeks(_ sessions: [TrainingSession]) -> [SheetWeek] {
        var cal = Calendar.current
        cal.firstWeekday = 2   // Monday-start, matching the rest of the app.

        let grouped = Dictionary(grouping: sessions) { s -> Date in
            cal.dateInterval(of: .weekOfYear, for: s.day)?.start ?? s.day
        }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start

        return grouped.keys.sorted(by: >).map { start in
            let list = (grouped[start] ?? []).sorted { a, b in
                a.day == b.day ? a.start < b.start : a.day > b.day
            }

            // The date numeral goes to the first VISIBLE session of each day,
            // decided here rather than from `isSecond`: filter to Threshold and
            // an evening session can become the first row of its day, at which
            // point it needs the date back. Deciding this at rollup time leaves
            // rows with no date at all.
            var leads: Set<UUID> = []
            var seen: Set<Date> = []
            for s in list where !seen.contains(s.day) {
                seen.insert(s.day)
                leads.insert(s.id)
            }

            let miles = list.reduce(0) { $0 + $1.miles }
            let dayCount = Set(list.map(\.day)).count
            let quality = list.filter(\.isQuality).count

            var name: String
            if let thisWeek, start == thisWeek {
                name = "This week"
            } else if let thisWeek,
                      let ago = cal.dateComponents([.weekOfYear], from: start, to: thisWeek).weekOfYear,
                      ago == 1 {
                name = "Last week"
            } else {
                let f = DateFormatter()
                f.dateFormat = "MMM d"
                name = "Week of " + f.string(from: start)
            }

            var label = "\(name) · \(String(format: "%.0f", miles)) mi · \(dayCount) \(dayCount == 1 ? "day" : "days")"
            if quality > 0 { label += " · \(quality) quality" }

            return SheetWeek(id: start, label: label, sessions: list, leadIDs: leads)
        }
    }
}

// MARK: - Supporting types

private struct SheetTotals {
    var miles: Double = 0
    var days: Int = 0
    var uploads: Int = 0
    var perWeek: Double = 0
}

private struct SheetWeek: Identifiable {
    let id: Date
    let label: String
    let sessions: [TrainingSession]
    /// Sessions that should render the date numeral rather than a clock time.
    let leadIDs: Set<UUID>
}

private enum SheetRange: String, CaseIterable, Identifiable {
    case four, eight, twelve, all

    var id: String { rawValue }

    var short: String {
        switch self {
        case .four: "4 wk"
        case .eight: "8 wk"
        case .twelve: "12 wk"
        case .all: "All"
        }
    }

    var label: String {
        switch self {
        case .four: "Last 4 weeks"
        case .eight: "Last 8 weeks"
        case .twelve: "Last 12 weeks"
        case .all: "Last 400 days"
        }
    }

    var weeks: Int {
        switch self {
        case .four: 4
        case .eight: 8
        case .twelve: 12
        case .all: 58
        }
    }

    func cutoff() -> Date {
        SessionRollup.localDay(
            Calendar.current.date(byAdding: .day, value: -weeks * 7, to: Date()) ?? Date()
        )
    }
}

// MARK: - Row

private struct SheetRowView: View {
    let session: TrainingSession
    let leadsDay: Bool
    let query: String
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                dateCell.frame(width: 40, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Quality reads as WEIGHT, not as colour and not as a
                        // glyph — coral is alert-only.
                        Text(WorkoutLabel.display(session.typeKey))
                            .font(.dripDisplay(16))
                            .fontWeight(session.isQuality ? .bold : .regular)
                            .foregroundStyle(
                                session.isQuality ? Color.drip.textPrimary : Color.drip.textSecondary
                            )
                            .lineLimit(1)
                        if session.pieces.count > 1 {
                            Text("×\(session.pieces.count)")
                                .font(.dripEyebrow(10))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    snippetView
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(format: "%.1f", session.miles))
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 48, alignment: .trailing)

                Text(paceText)
                    .font(.dripStat(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.vertical, 9)

            if isExpanded { SheetDetailView(session: session) }
        }
        .padding(.leading, 12)
        // Mood rides the left rule, the way JournalLogRow already does it —
        // it keeps the qualitative signal off the numeral columns.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.drip.moodBorderColor(for: session.mood) ?? .clear)
                .frame(width: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// A day's later sessions trade the date numeral for their clock time, so
    /// the day reads as one block.
    @ViewBuilder
    private var dateCell: some View {
        if leadsDay {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dayNumber.string(from: session.day))
                    .font(.dripDisplay(19)).fontWeight(.semibold)
                    .foregroundStyle(Color.drip.textPrimary)
                Text(Self.weekday.string(from: session.day).uppercased())
                    .font(.dripEyebrow(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        } else {
            Text(Self.clock.string(from: session.start).lowercased())
                .font(.dripEyebrow(10)).tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var snippetView: some View {
        if let text = highlighted {
            text
                .font(.dripBody(11))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(1)
        }
    }

    /// The matched sentence with the hit marked, or nil when not searching.
    ///
    /// Marked by WEIGHT and ink, not by a wash: `Text` concatenation cannot
    /// carry a background, and coral is alert-only so it is not an option
    /// here anyway. The hit reads as semibold textPrimary against the
    /// snippet's regular textSecondary.
    private var highlighted: Text? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, let snip = session.snippet(for: q) else { return nil }
        let head = String(snip.text[snip.text.startIndex..<snip.match.lowerBound])
        let hit = String(snip.text[snip.match])
        let tail = String(snip.text[snip.match.upperBound...])
        // All three parts are `verbatim:` — this is voice-log/note prose, so a
        // stray "%" in the athlete's own words must not be read as a format
        // specifier by LocalizedStringKey.
        let headText = Text(verbatim: head).italic()
        let hitText = Text(verbatim: hit).italic()
            .fontWeight(.semibold)
            .foregroundColor(Color.drip.textPrimary)
        let tailText = Text(verbatim: tail).italic()
        return Text("\(headText)\(hitText)\(tailText)")
    }

    private var paceText: String {
        guard let secs = session.paceSeconds else { return "" }
        return DistanceFormat.paceMMSS(secPerMile: secs)
    }

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mma"; return f
    }()
}

// MARK: - Expanded detail

private struct SheetDetailView: View {
    let session: TrainingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Text("UPLOADS").frame(maxWidth: .infinity, alignment: .leading)
                Text("MI").frame(width: 44, alignment: .trailing)
                Text("MIN").frame(width: 34, alignment: .trailing)
                Text("PACE").frame(width: 46, alignment: .trailing)
            }
            .font(.dripEyebrow(10)).tracking(1.0)
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.bottom, 8)

            // Pieces read in clock order — a session is a sequence, not a
            // ranking.
            ForEach(session.allPieces.sorted { $0.date < $1.date }, id: \.id) { p in
                let folded = !session.pieces.contains { $0.id == p.id }
                HStack(spacing: 8) {
                    Text(WorkoutLabel.display(p.typeKey) + (folded ? " · folded in" : ""))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(folded ? Color.drip.textTertiary : Color.drip.textSecondary)
                    Text(String(format: "%.2f", p.miles ?? 0))
                        .frame(width: 44, alignment: .trailing)
                    Text(p.durationMinutes.map { String(format: "%.0f", $0) } ?? "")
                        .frame(width: 34, alignment: .trailing)
                    Text(piecePace(p))
                        .frame(width: 46, alignment: .trailing)
                }
                .font(.dripBody(12))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.vertical, 4)
            }

            if let mood = session.mood, let colour = Color.drip.moodBorderColor(for: mood) {
                HStack(spacing: 5) {
                    Circle().fill(colour).frame(width: 6, height: 6)
                    Text(mood.uppercased())
                        .font(.dripEyebrow(10)).tracking(1.0)
                }
                .foregroundStyle(colour)
                .padding(.vertical, 3).padding(.horizontal, 8)
                .background(Capsule().fill(colour.opacity(0.12)))
                .padding(.top, 12)
            }

            if let note = session.note {
                // Diary quote: ink hairline. The coral left-border is the
                // coach-quote treatment and README says not to generalize it.
                Text(note)
                    .font(.dripBody(13)).italic()
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.drip.divider).frame(width: 1)
                    }
                    .padding(.top, 12)
            }

            if session.foldedCount > 0 {
                // The one coral element on this screen, and it is alert-shaped.
                Text("\(session.foldedCount) DUPLICATE ROW\(session.foldedCount == 1 ? "" : "S") FOLDED IN")
                    .font(.dripEyebrow(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.drip.coral.opacity(0.12)))
                    .padding(.top, 12)
            }
        }
        .padding(.bottom, 12)
    }

    private func piecePace(_ p: TodayLogRow) -> String {
        guard let mi = p.miles, mi > 0.05,
              let min = p.durationMinutes, min > 0 else { return "" }
        return DistanceFormat.paceMMSS(secPerMile: min * 60 / mi)
    }
}

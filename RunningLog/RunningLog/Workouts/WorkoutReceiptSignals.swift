//
//  WorkoutReceiptSignals.swift
//  RunningLog
//
//  Act 2 of the workout detail sheet, "signals-first" (spec:
//  outputs/workout-detail-signals-redesign-2026-08-03.md).
//
//  What used to be THE READ — a multi-sentence AI paragraph behind a
//  "Generate AI insight" button — is now a row of scannable capsules plus a
//  single italic sentence. Each capsule is one measured quantity with a status
//  dot; a capsule whose input is missing DROPS OUT rather than rendering a
//  placeholder (hard rule #8). Nothing here is generated: every number is
//  computed from the run's own imported laps, stream and weather.
//
//  Also here: the workout note rendered as a recipe (warmup → the ×N block →
//  cooldown), the collapsed voice-memo row, and the niggle status chips.
//

import SwiftUI
import Supabase
import AVFoundation
import os

// MARK: - Signals ────────────────────────────────────────────────────────────

/// One measured signal. `key` is the quiet label ("SPREAD"), `value` the
/// number ("±13s"), `tone` the status dot.
struct ReceiptSignal: Identifiable {
    enum Tone { case good, warn, hot, neutral }
    let id = UUID()
    let key: String
    let value: String
    let tone: Tone
}

extension ReceiptSignal.Tone {
    var color: Color {
        switch self {
        case .good:    Color.drip.positive     // sage
        case .warn:    Color.drip.tired        // amber
        case .hot:     Color.drip.injured      // deep rose
        case .neutral: Color.drip.textTertiary
        }
    }
}

/// A capsule: status dot · quiet key · the number. Mono throughout, tabular so
/// a row of chips keeps its rhythm.
///
/// Tapping one opens `SignalExplainer` — the chips are the densest thing on the
/// screen, five abbreviations carrying five different calculations, and there
/// was nowhere to learn what DRIFT or VS PLAN actually measured. The popover
/// is the whole affordance: no help icon, no legend row, no paragraph added to
/// the page for a reader who already knows. (2026-08-20)
struct SignalChip: View {
    let signal: ReceiptSignal
    @State private var explaining = false

    var body: some View {
        Button { explaining = true } label: {
            HStack(spacing: 7) {
                Circle().fill(signal.tone.color).frame(width: 7, height: 7)
                Text(signal.key)
                    .font(.dripStat(9.5)).tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(signal.value)
                    .font(.dripStat(10.5)).tracking(0.7)
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Explains what \(signal.key) measures")
        .popover(isPresented: $explaining) {
            SignalExplainer(signal: signal)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// What one chip measures, in the athlete's language: the number it is showing
/// now, one plain sentence on how it was computed, and what its dot colour
/// means. Nothing here grades the session or advises training — it defines a
/// term (hard rule #2).
struct SignalExplainer: View {
    let signal: ReceiptSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(signal.key)
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.coral)
            Text(signal.value)
                .font(.dripStat(20)).monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
            Text(Self.definition(for: signal.key))
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Circle().fill(signal.tone.color).frame(width: 7, height: 7)
                Text(Self.toneCaption(signal.tone))
                    .font(.dripStat(9)).tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(18)
        .frame(width: 268, alignment: .leading)
        .background(Color.drip.background)
    }

    /// One sentence per chip. Keyed off the same string the chip prints, so a
    /// new signal without an entry falls back rather than mis-defining itself.
    static func definition(for key: String) -> String {
        switch key {
        case "SPREAD":
            "The gap between your fastest and slowest work rep, written as ± either side of the middle. A small number means the reps came out even."
        case "HR":
            "The heart-rate zone that carried the most time in this session, and the first work rep whose average heart rate reached it."
        case "DRIFT":
            "How far your pace-to-heart-rate ratio moved from the first half of the work to the second. Positive means heart rate climbed while the pace held."
        case "HEAT":
            "What the day's heat and humidity cost you against the same effort run in cool air, in the unit the chip shows. It appears only when that cost reaches 3 seconds."
        case "VS PLAN":
            "Your average work pace against the target pace written in the session note. Absent when the note names no target — the session's own average is never treated as one."
        default:
            "A measured signal from this run's own laps, stream and weather. Nothing here is generated."
        }
    }

    /// What the dot colour says — the status, never an instruction.
    static func toneCaption(_ tone: ReceiptSignal.Tone) -> String {
        switch tone {
        case .good:    "IN THE USUAL RANGE"
        case .warn:    "WORTH NOTICING"
        case .hot:     "WELL OUTSIDE THE USUAL RANGE"
        case .neutral: "STATED, NOT GRADED"
        }
    }
}

// MARK: - The workout, as a recipe ───────────────────────────────────────────

/// One line of the prescribed session. `reps` non-nil marks the head of a
/// repeated block (the `×4` tag); `rest` is the recovery leg that follows a
/// work bout, italicised beside it rather than given a row of its own.
struct RecipeStep: Identifiable {

    /// What the row *is*.
    ///
    /// Was a bare `isWork: Bool` whose only job was to pick the colour of a
    /// leading rule. The rule is gone (see `WorkoutRecipeView`), so the flag
    /// became a real three-way distinction instead:
    ///
    ///   • `.work`     — a bout. Sits flush at the margin.
    ///   • `.recovery` — a jog, a warmup, a cooldown, a stated rest. Indents.
    ///   • `.summary`  — NOT a segment: the session's own totals, e.g.
    ///     "6.2 mi overall". These used to fall through as steps, which put a
    ///     6-mile "rep" in the middle of a 3×2 recipe and drew it with the
    ///     work colour. They now render under a rule as a footer.
    enum Kind { case work, recovery, summary }

    let id = UUID()
    var reps: Int?          // ×4 tag — only on the first row of a block
    var kind: Kind = .work
    var distance: String    // "3 mi", "400m", "1 mi"
    var detail: String?     // "warmup", "@ 6:00"
    var rest: String?       // "400m jog"
    /// A row inside a repeated block that isn't its head — what gathers the
    /// rows under one brace.
    var inBlock: Bool = false

    var isWork: Bool { kind == .work }
}

/// Best-effort segmenter for the athlete's / coach's workout note.
///
/// The note is free text, so this is deliberately conservative: it returns
/// `nil` the moment it can't read a structure, and the caller falls back to
/// rendering the note as the single line it always was. A wrong recipe would
/// be worse than no recipe — it would put distances and paces on screen that
/// the athlete never wrote.
///
/// Two real shapes are handled, both taken from live notes:
///
///   Warmup: 3 miles                                   ← labelled, one per line
///   Intervals: 4 sets of (1 mile @ ~6:00/mi, 400m recovery, …)
///   Cooldown: Quick (2 miles)
///
///   1600m @ 5:08 + 2×800m @ 2:33 + 1600m @ 5:13 w/ 90s rec   ← the compact
///                                                              intent pattern
///
/// The pace/effort text is never re-derived — whatever the athlete wrote after
/// the distance is carried through verbatim ("@ HMP", "@ ~6:00/mi", "@ 38-42s").
enum WorkoutRecipeParser {
    /// "3 miles", "1 mi", "400m", "1.5k", "1200 meters".
    private static let distancePattern =
        #"(\d+(?:\.\d+)?)\s*(miles|mile|mi|km|k|meters|metres|m)\b"#
    /// "10 minutes", "5 min" — a leg prescribed by time rather than distance.
    private static let durationPattern = #"(\d+(?:\.\d+)?)\s*(minutes|minute|mins|min)\b"#
    /// "4 × ", "4x", "4 sets of", "3 rounds of" at the head of a piece.
    private static let multiplierPattern =
        #"^\s*(\d+)\s*(?:x|×|sets?\s+of|rounds?\s+of|reps?\s+of)\s*"#

    private static let restWords = ["jog", "rest", "recovery", "recover", "walk", "float", "break"]
    /// Labels that carry a distance but aren't a segment of the session — they
    /// describe the whole run. Rendering these as steps put a 17-mile "rep" in
    /// the recipe; they now become `.summary` rows in the footer.
    private static let summaryLabels: Set<String> = ["distance", "total", "duration", "time"]
    /// The same, minus a distance worth showing — dropped outright.
    private static let metadataLabels: Set<String> = [
        "weather", "recoveries", "pace", "type", "workout type",
        "notes", "effort", "rpe", "elevation",
    ]
    /// Trailing words that turn a bare line into a total rather than a leg:
    /// "6.2 mi overall", "37 min in total". Unlike `summaryLabels` these carry
    /// no colon, so the label pass never sees them — which is exactly how
    /// "6.2 mi overall" ended up drawn as a rep.
    private static let summaryWords = ["overall", "in total", "total", "altogether", "combined"]
    private static let warmupLabels = ["warmup", "warm up", "warm-up", "wu"]
    private static let cooldownLabels = ["cooldown", "cool down", "cool-down", "cd"]

    static func parse(_ raw: String?) -> [RecipeStep]? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let steps: [RecipeStep] = lines.count > 1
            ? lines.flatMap { labelledLine($0) }
            : expand(lines.first ?? text, role: nil)

        // Two rows is the bar: one row is the note with extra chrome around it,
        // and zero means we read nothing at all. Totals don't count toward it —
        // "Distance: 6.2 mi / Duration: 37 min" is a receipt, not a recipe.
        return steps.filter({ $0.kind != .summary }).count >= 2 ? steps : nil
    }

    // MARK: Labelled lines ("Warmup: 3 miles")

    private static func labelledLine(_ line: String) -> [RecipeStep] {
        guard let colon = line.firstIndex(of: ":"),
              line.distance(from: line.startIndex, to: colon) <= 22 else {
            // No label — treat the whole line as a run of segments.
            return expand(line, role: nil)
        }
        let label = String(line[line.startIndex..<colon])
            .trimmingCharacters(in: .whitespaces).lowercased()
        // A pace reads as a colon too, so "4 x (800m @ 2:38, 200m @ 45s)" used
        // to parse as label `4 x (800m @ 2` + value `38, 200m @ 45s` — which
        // silently ate the first rep AND the ×4 tag. A real label is a word:
        // letters, no digits, none of the segment punctuation.
        let labelPunctuation = CharacterSet(charactersIn: "(@×+/")
        guard !label.isEmpty,
              label.rangeOfCharacter(from: .letters) != nil,
              label.rangeOfCharacter(from: .decimalDigits) == nil,
              label.rangeOfCharacter(from: labelPunctuation) == nil
        else {
            return expand(line, role: nil)
        }
        guard !metadataLabels.contains(label) else { return [] }

        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

        // "Distance: 6.2 mi" describes the run, not a leg of it — footer, not step.
        if summaryLabels.contains(label) {
            guard let d = firstDistance(in: value) else { return [] }
            return [RecipeStep(reps: nil, kind: .summary, distance: d.text, detail: label, rest: nil)]
        }
        if warmupLabels.contains(label) { return role(value, "warmup") }
        if cooldownLabels.contains(label) { return role(value, "cooldown") }
        // "Break: 5 minutes" — the label is what makes it a recovery leg; the
        // value alone ("5 minutes") carries no sign of it.
        let rows = expand(value, role: nil)
        guard looksLikeRest(label) else { return rows }
        return rows.map { var r = $0; r.kind = .recovery; r.detail = r.detail ?? label; return r }
    }

    /// A warmup / cooldown line: the label already says what it is, so the
    /// row is just the distance and the role. "Quick (2 miles)" → "2 mi warmup".
    private static func role(_ value: String, _ word: String) -> [RecipeStep] {
        guard let d = firstDistance(in: value) else { return [] }
        return [RecipeStep(reps: nil, kind: .recovery, distance: d.text, detail: word, rest: nil)]
    }

    // MARK: Segment runs

    /// Expands a run of text into rows, unrolling a parenthesised "N sets of
    /// (…)" block and folding each recovery leg into the work row above it.
    private static func expand(_ text: String, role _: String?) -> [RecipeStep] {
        if let block = firstBlock(in: text) {
            return expand(block.before, role: nil)
                + tag(expand(block.body, role: nil), reps: block.count)
                + expand(block.after, role: nil)
        }
        var out: [RecipeStep] = []
        for piece in split(text) {
            guard let step = read(piece) else { continue }
            let isRest = (step.detail.map { looksLikeRest($0) } ?? false) || looksLikeRest(piece)
            if isRest, let last = out.indices.last, out[last].isWork, out[last].rest == nil {
                out[last].rest = [step.distance, step.detail].compactMap { $0 }.joined(separator: " ")
                continue
            }
            out.append(step)
        }
        return out
    }

    /// The ×N tag belongs to the block's first row; the rows beneath keep the
    /// slot's width (`inBlock`) so the block stays aligned under it.
    private static func tag(_ steps: [RecipeStep], reps: Int) -> [RecipeStep] {
        steps.enumerated().map { i, s in
            var s = s
            if i == 0 { s.reps = reps } else { s.inBlock = true }
            return s
        }
    }

    private static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: " then ", with: "+", options: .caseInsensitive)
            .components(separatedBy: CharacterSet(charactersIn: "+,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private struct Block { let before: String; let body: String; let count: Int; let after: String }

    /// Finds "N × ( … )" and returns the text either side of it. Only a
    /// parenthesised block is unrolled — "4 × 800m" with no bracket is a single
    /// row that already reads correctly as "×4  800m".
    private static func firstBlock(in text: String) -> Block? {
        let pattern = #"(\d+)\s*(?:x|×|sets?\s+of|rounds?\s+of|reps?\s+of)\s*\("#
        guard let m = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let head = String(text[m])
        guard let countRange = head.range(of: #"\d+"#, options: .regularExpression),
              let count = Int(head[countRange]), count > 1 else { return nil }

        var depth = 0
        var close: String.Index?
        var i = text.index(before: m.upperBound)   // sits on the "("
        while i < text.endIndex {
            if text[i] == "(" { depth += 1 }
            if text[i] == ")" { depth -= 1; if depth == 0 { close = i; break } }
            i = text.index(after: i)
        }
        guard let close else { return nil }
        return Block(
            before: String(text[text.startIndex..<m.lowerBound]),
            body: String(text[m.upperBound..<close]),
            count: count,
            after: String(text[text.index(after: close)...])
        )
    }

    /// One piece → one row. Nil when the piece names no distance: a fragment we
    /// can't render honestly is dropped rather than guessed at.
    private static func read(_ piece: String) -> RecipeStep? {
        var body = piece
        var reps: Int?
        if let m = body.range(of: multiplierPattern, options: [.regularExpression, .caseInsensitive]) {
            if let r = body[m].range(of: #"\d+"#, options: .regularExpression), let n = Int(body[m][r]), n > 1 {
                reps = n
            }
            body.removeSubrange(m)
        }
        guard let d = firstDistance(in: body) else { return nil }

        // Everything the athlete wrote after the distance, verbatim — the pace,
        // the effort, the zone name. Split off a trailing recovery clause.
        var detail: String?
        var rest: String?
        var tail = String(body[d.range.upperBound...])
        if let w = tail.range(of: #"\s*(?:w/|with)\s+"#, options: [.regularExpression, .caseInsensitive]) {
            rest = tidy(String(tail[w.upperBound...]))
            tail = String(tail[..<w.lowerBound])
        }
        // Whether the row is WORK is decided by the head only. "1200m @ HMP w/
        // 1 min rest" is a rep; the word "rest" belongs to its recovery clause,
        // not to the bout itself.
        let head = tail
        detail = tidy(tail).flatMap { $0.count <= 40 ? $0 : nil }

        // A line that names the whole session ("6.2 mi overall") is not a leg
        // of it. Checked before rest, because "total recovery" is a summary.
        let kind: RecipeStep.Kind = looksLikeSummary(head) ? .summary
            : looksLikeRest(head) ? .recovery : .work

        return RecipeStep(reps: reps, kind: kind,
                          distance: d.text, detail: detail, rest: rest)
    }

    /// Trims the connective punctuation off a fragment and drops a dangling
    /// "(…" the split left open, so a detail never reads "(for Shannon".
    private static func tidy(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: " ()-–·"))
        let opens = t.filter { $0 == "(" }.count, closes = t.filter { $0 == ")" }.count
        if opens > closes, let cut = t.lastIndex(of: "(") {
            t = String(t[..<cut]).trimmingCharacters(in: CharacterSet(charactersIn: " ()-–·"))
        }
        return t.isEmpty ? nil : t
    }

    private static func looksLikeRest(_ s: String) -> Bool {
        let l = s.lowercased()
        return restWords.contains { l.contains($0) }
    }

    private static func looksLikeSummary(_ s: String) -> Bool {
        let l = s.lowercased()
        return summaryWords.contains { l.contains($0) }
    }

    /// A distance, or — when the segment is prescribed by time ("10 minutes @
    /// 5:16/mi") — the duration, which is just as real a leg of the session.
    private static func firstDistance(in text: String) -> (text: String, range: Range<String.Index>)? {
        if let r = text.range(of: distancePattern, options: [.regularExpression, .caseInsensitive]) {
            return (normalise(String(text[r])), r)
        }
        if let r = text.range(of: durationPattern, options: [.regularExpression, .caseInsensitive]) {
            let n = String(text[r]).filter { $0.isNumber || $0 == "." }
            return ("\(n) min", r)
        }
        return nil
    }

    /// "3 miles" → "3 mi", "400 meters" → "400m", "1.5K" → "1.5k".
    private static func normalise(_ token: String) -> String {
        let t = token.lowercased().replacingOccurrences(of: " ", with: "")
        for (suffix, unit) in [("miles", " mi"), ("mile", " mi"), ("mi", " mi"),
                               ("meters", "m"), ("metres", "m"), ("km", "k"), ("k", "k"), ("m", "m")]
        where t.hasSuffix(suffix) {
            return String(t.dropLast(suffix.count)) + unit
        }
        return token
    }
}

/// The hairline brace that gathers a repeated block.
///
/// Arms point LEFT, toward the rows it groups; the stem sits on the right, in
/// the dead space past the paces. That side is deliberate — see the note on
/// `WorkoutRecipeView` for why the recipe's leading edge has to stay empty.
private struct RepeatBrace: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let stem = rect.maxX - 0.5
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + 0.5))
        p.addLine(to: CGPoint(x: stem, y: rect.minY + 0.5))
        p.addLine(to: CGPoint(x: stem, y: rect.maxY - 0.5))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 0.5))
        return p
    }
}

/// The note, readable in one glance.
///
/// **There is no left rule here — that mark belongs to mood** (2026-08-21).
/// Every row used to carry a 2pt rule at its leading edge, filled
/// `Color.drip.coral` on a work leg and `paperDeep` on everything else. That
/// is the same width, the same position and an overlapping hue as the mood
/// spine on `JournalLogRow`, `TodayPlate18` and `HomeDayPager` — so a warm bar
/// meant *"this day went badly"* in the feed and *"this is the hard part"* one
/// tap later in the sheet. Same mark, opposite charge, no announcement.
///
/// It also broke the three-palette rule already written down in
/// `design-system/colors_and_type.css` — *"blue = pace, warm = mood, coral =
/// alert; the three palettes never share hues"*. A 2×2mi rep at 5:28 is not an
/// alert, and scarlet is already spending itself on VOICE / EDIT / TODAY and
/// the key-session star on the same screen.
///
/// So structure is drawn, not coloured:
///
///   • a repeated block gets a hairline brace on the RIGHT, which says the
///     thing the colour never did — *these rows are one thing you repeated* —
///     and costs no left gutter;
///   • recovery legs step right instead of going pale;
///   • the session's own totals sit under a rule as a footer rather than
///     inside the recipe as extra reps (`RecipeStep.Kind.summary`).
///
/// The leading edge of a row is now free everywhere except mood. Keep it that
/// way: if a future surface needs to mark structure here, give it a shape, an
/// indent or a rule of its own — not a coloured bar.
struct WorkoutRecipeView: View {
    let steps: [RecipeStep]

    /// Consecutive rows drawn as one unit. `reps` non-nil is a repeated block
    /// and earns the brace. `rows` is never empty.
    private struct Run: Identifiable {
        let reps: Int?
        let rows: [RecipeStep]
        var id: UUID { rows[0].id }
    }

    /// The segments, gathered: a row carrying `reps` opens a block and every
    /// `inBlock` row beneath joins it.
    private var runs: [Run] {
        let rows = steps.filter { $0.kind != .summary }
        var out: [Run] = []
        var i = rows.startIndex
        while i < rows.endIndex {
            if let n = rows[i].reps {
                var block = [rows[i]]
                var j = rows.index(after: i)
                while j < rows.endIndex, rows[j].inBlock {
                    block.append(rows[j])
                    j = rows.index(after: j)
                }
                out.append(Run(reps: n, rows: block))
                i = j
            } else {
                out.append(Run(reps: nil, rows: [rows[i]]))
                i = rows.index(after: i)
            }
        }
        return out
    }

    /// "6.2 mi overall" — the run's own numbers, never a leg of it.
    private var totals: [RecipeStep] { steps.filter { $0.kind == .summary } }

    private func row(_ step: RecipeStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(step.distance)
                .font(.dripStat(12.5)).monospacedDigit()
                .foregroundStyle(step.isWork ? Color.drip.textPrimary : Color.drip.textSecondary)
            if let d = step.detail {
                Text(d)
                    .font(.dripStat(11)).monospacedDigit()
                    .foregroundStyle(Color.drip.textSecondary)
            }
            if let r = step.rest {
                Text(r)
                    .font(.dripBody(11.5)).italic()
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        // The hierarchy is the indent. Easy legs step back from the margin;
        // no second colour is needed to say the same thing.
        .padding(.leading, step.kind == .recovery ? 16 : 0)
    }

    @ViewBuilder
    private func runView(_ run: Run) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(run.rows) { step in row(step) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let n = run.reps {
                // One row needs no brace — "×4  800m" already reads as a set.
                if run.rows.count > 1 {
                    RepeatBrace()
                        .stroke(Color.drip.textTertiary,
                                style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                        .frame(width: 6)
                        .padding(.vertical, 6)
                }
                Text("×\(n)")
                    .font(.dripStat(10)).tracking(0.8).monospacedDigit()
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(runs) { run in runView(run) }

            if !totals.isEmpty {
                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(height: 1)
                    .padding(.top, 9)
                ForEach(totals) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(step.distance)
                            .font(.dripStat(11.5)).monospacedDigit()
                        if let d = step.detail {
                            Text(d).font(.dripBody(11.5)).italic()
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 7)
                }
            }
        }
    }
}

// MARK: - Voice memo, collapsed ──────────────────────────────────────────────

/// One line of the athlete's own words until tapped. The memo is signal, not a
/// wall — it never dominates the sheet, and it's quoted verbatim either way
/// (niggles rule: surfaced, never interpreted).
struct VoiceMemoRow: View {
    let mood: String?
    let quote: String
    /// "VOICE MEMO" or "NOTE" — the row says which it is rather than calling a
    /// typed note a memo.
    var kind: String = "VOICE MEMO"
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let mood, !mood.isEmpty { MoodBadge(mood: mood) }
                    Text(kind)
                        .font(.dripStat(9)).tracking(1.1)
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                Text("\u{201C}\(quote)\u{201D}")
                    .font(.dripBody(13)).italic()
                    .foregroundStyle(expanded ? Color.drip.textPrimary : Color.drip.textSecondary)
                    .lineSpacing(expanded ? 3 : 0)
                    .lineLimit(expanded ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: expanded)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - No memo? Record one here ───────────────────────────────────────────

/// The one intentional affordance on this sheet. When a run came in from the
/// watch with nothing said about it, the memo slot doesn't drop out — it
/// becomes an invitation, in the same position the memo would have occupied.
struct RecordMemoCard: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.drip.coralWash).frame(width: 26, height: 26)
                    Circle().fill(Color.drip.coral).frame(width: 9, height: 9)
                }
                Text("RECORD VOICE MEMO")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer(minLength: 8)
                Text("30 seconds on how it felt.")
                    .font(.dripBody(12)).italic()
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.drip.divider)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Records a memo and attaches it to a run that already exists. Deliberately
/// self-contained: it never inserts a new `training_logs` row (that's what
/// orphans a memo away from its run), it updates the one we're looking at.
struct AttachMemoSheet: View {
    let workoutId: UUID
    let dateLabel: String
    var onAttached: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var isRecording = false
    @State private var elapsed = 0
    @State private var timer: Timer?
    @State private var uploading = false
    @State private var error: String?
    @State private var micDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VOICE MEMO")
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                Text(dateLabel)
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("How did it feel? Anything the numbers won't show.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: 14) {
                Text(clock(elapsed))
                    .font(.dripStat(34)).monospacedDigit()
                    .foregroundStyle(isRecording ? Color.drip.coral : Color.drip.textTertiary)

                Button {
                    isRecording ? stop() : start()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.drip.coral : Color.drip.coralWash)
                            .frame(width: 76, height: 76)
                        if isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.drip.background)
                                .frame(width: 26, height: 26)
                        } else {
                            Circle().fill(Color.drip.coral).frame(width: 30, height: 30)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(uploading)

                Text(isRecording ? "TAP TO STOP" : recordingURL == nil ? "TAP TO RECORD" : "TAP TO RE-RECORD")
                    .font(.dripStat(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            if let error {
                Text(error)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.injured)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await attach() }
            } label: {
                HStack(spacing: 8) {
                    if uploading { ProgressView().tint(Color.drip.background) }
                    Text(uploading ? "Attaching…" : "Attach to this run")
                        .font(.dripLabel(15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canAttach ? Color.drip.coral : Color.drip.paperDeep)
                .foregroundStyle(canAttach ? Color.drip.background : Color.drip.textTertiary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAttach)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.drip.background)
        .alert("Microphone access is off", isPresented: $micDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn it on in Settings → Privacy → Microphone to record a memo.")
        }
        .onDisappear { cleanUp() }
    }

    private var canAttach: Bool { recordingURL != nil && !isRecording && !uploading }

    private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func start() {
        // Ask before recording — a denied mic used to run the timer over dead
        // air and upload a silent file (beta audit #8).
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            micDenied = true
        case .undetermined:
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                await MainActor.run { granted ? begin() : (micDenied = true) }
            }
        default:
            begin()
        }
    }

    private func begin() {
        error = nil
        let name = "attach_memo_\(workoutId.uuidString)_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let r = try AVAudioRecorder(url: url, settings: settings)
            // `record()` returning false means the route never opened — treat
            // it as a real failure rather than timing silence.
            guard r.record() else {
                error = "Couldn't start recording — another app may be using the microphone."
                return
            }
            recorder = r
            recordingURL = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsed += 1 }
        } catch {
            self.error = "Couldn't start recording."
            Log.coach.error("AttachMemoSheet.begin failed: \(error)")
        }
    }

    private func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate(); timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func attach() async {
        guard let url = recordingURL else { return }
        uploading = true
        error = nil
        let ok = await ReceiptMemoService.attach(workoutId: workoutId, localURL: url)
        uploading = false
        if ok {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            onAttached()
            dismiss()
        } else {
            error = "Couldn't attach the memo. Try again."
        }
    }

    private func cleanUp() {
        if isRecording { stop() }
        timer?.invalidate(); timer = nil
    }
}

/// Uploads the audio and points the EXISTING run at it, then kicks the memo
/// pipeline by hand. The `auto_process_voice_log` trigger is AFTER INSERT
/// only, so an update never enqueues — we invoke `process-training-memo`
/// directly (it re-verifies ownership of the row against the caller's JWT).
///
/// The processor is safe on an imported run: it writes distance, duration and
/// pace_segments only when the row doesn't already carry them, so the watch's
/// data survives the memo.
enum ReceiptMemoService {
    static func attach(workoutId: UUID, localURL: URL) async -> Bool {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return false }
        let publicURL: String
        do {
            // Upload through the service-role edge function, NOT
            // supabase.storage directly — direct client uploads to
            // `training-memos` have been rejected by storage RLS since
            // 2026-06-02 (see uploadVoiceMemoAudio in Supabase.swift). This
            // was the last caller still on the broken path.
            let data = try Data(contentsOf: localURL)
            publicURL = try await uploadVoiceMemoAudio(data)

            struct Patch: Encodable {
                let audio_url: String
                let processing_status: String
            }
            try await supabase
                .from("training_logs")
                .update(Patch(audio_url: publicURL, processing_status: "pending"))
                .eq("id", value: workoutId.uuidString)
                .execute()
        } catch {
            // Upload or row-update failed — the memo genuinely didn't land.
            Log.coach.error("ReceiptMemoService.attach failed: \(error)")
            return false
        }

        // From here the memo is SAFE regardless of what happens next: the
        // UPDATE above set processing_status='pending' with a fresh audio_url,
        // which fires the `auto_process_voice_log_on_attach` trigger
        // (20260806220000) and enqueues a voice_processing_jobs row. The drain
        // worker will process it with the service-role key — bypassing the
        // per-user rate limit — within ~a minute. The direct invoke below is
        // only the fast path; its failure (429 quota, 409 already-processing,
        // network blip) must NOT surface as "Couldn't attach the memo",
        // because the attach already succeeded.
        do {
            struct Record: Encodable { let id: String; let user_id: String; let audio_url: String }
            struct Req: Encodable { let record: Record; let old_record: String? }
            _ = try await supabase.functions.invoke(
                "process-training-memo",
                options: .init(body: Req(
                    record: Record(id: workoutId.uuidString, user_id: userId, audio_url: publicURL),
                    old_record: nil
                ))
            ) as FunctionsIgnoredResponse
        } catch {
            Log.coach.info("ReceiptMemoService fast-path invoke deferred to drain worker: \(error)")
        }
        return true
    }
}

/// `functions.invoke` needs a Decodable to bind to; the memo pipeline's own
/// response is irrelevant here — we reload the sheet from the row instead.
private struct FunctionsIgnoredResponse: Decodable {}

// MARK: - Niggles, as status chips ───────────────────────────────────────────

/// A body-part mention carried on this run, with the status the app already
/// derives elsewhere — nothing new is inferred here. `watching` is the
/// canonical "active niggle" rule (a mention not yet cleared by a later
/// all-clear watermark); `flagged` means a formal injury row is open for that
/// area; `resolved` means a watermark cleared it.
struct ReceiptNiggle: Identifiable {
    enum Status { case watching, flagged, resolved }
    let id: UUID
    let area: String
    let side: String?
    let status: Status

    /// "L CALF" — side initial only, area verbatim. No severity, no diagnosis.
    var label: String {
        let s = side?.lowercased()
        let prefix = (s == "left" || s == "l") ? "L " : (s == "right" || s == "r") ? "R " : ""
        return (prefix + area).uppercased()
    }
}

extension ReceiptNiggle.Status {
    var word: String {
        switch self {
        case .watching: "WATCHING"
        case .flagged:  "FLAGGED"
        case .resolved: "RESOLVED"
        }
    }
    var color: Color {
        switch self {
        case .watching: Color.drip.tired
        case .flagged:  Color.drip.injured
        case .resolved: Color.drip.textTertiary
        }
    }
    var wash: Color { color.opacity(self == .resolved ? 0.0 : 0.14) }
}

struct NiggleChip: View {
    let niggle: ReceiptNiggle
    var onTap: (() -> Void)?

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 7) {
                Circle().fill(niggle.status.color).frame(width: 6, height: 6)
                Text(niggle.status == .resolved ? niggle.label : "\(niggle.label) · \(niggle.status.word)")
                    .font(.dripStat(10)).tracking(0.9)
                    .strikethrough(niggle.status == .resolved)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(niggle.status.color)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(niggle.status == .resolved ? Color.drip.paperDeep : niggle.status.wash)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(niggle.status.color.opacity(niggle.status == .resolved ? 0.25 : 0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - Fetch ──────────────────────────────────────────────────────────────

enum ReceiptNiggleService {
    private struct MentionRow: Decodable {
        let id: UUID
        let body_area: String
        let side: String?
        let mentioned_at: String
    }
    private struct ResolutionRow: Decodable {
        let body_area: String
        let side: String?
        let resolved_at: String
    }
    private struct InjuryRow: Decodable {
        let body_area: String
        let side: String?
        let status: String
    }

    private static func key(_ area: String, _ side: String?) -> String {
        "\(area.lowercased())|\(side?.lowercased() ?? "")"
    }

    /// The niggles mentioned on THIS run, with status. Empty on any failure —
    /// the row simply drops out rather than showing a half-truth.
    static func fetch(workoutId: UUID, userId: String) async -> [ReceiptNiggle] {
        let uid = userId.lowercased()
        guard !uid.isEmpty else { return [] }
        // `mentioned_at` / `resolved_at` are bare DATE columns — decode as
        // String and parse ourselves (the SDK's date decoder throws on them).
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")

        do {
            async let mentionsFetch: [MentionRow] = supabase
                .from("body_mentions")
                .select("id, body_area, side, mentioned_at")
                .eq("user_id", value: uid)
                .eq("training_log_id", value: workoutId.uuidString.lowercased())
                .execute().value
            async let resolutionsFetch: [ResolutionRow] = supabase
                .from("niggle_resolutions")
                .select("body_area, side, resolved_at")
                .eq("user_id", value: uid)
                .limit(500)
                .execute().value
            async let injuriesFetch: [InjuryRow] = supabase
                .from("injuries")
                .select("body_area, side, status")
                .eq("user_id", value: uid)
                .neq("status", value: "resolved")
                .limit(200)
                .execute().value

            let mentions = try await mentionsFetch
            guard !mentions.isEmpty else { return [] }
            let resolutions = try await resolutionsFetch
            let injuries = try await injuriesFetch

            // Latest all-clear per area+side.
            var watermark: [String: Date] = [:]
            for r in resolutions {
                guard let d = df.date(from: r.resolved_at) else { continue }
                let k = key(r.body_area, r.side)
                if let cur = watermark[k], cur >= d { continue }
                watermark[k] = d
            }
            let openInjuries = Set(injuries.map { key($0.body_area, $0.side) })

            // One chip per area+side, not per mention.
            var seen = Set<String>()
            var out: [ReceiptNiggle] = []
            for m in mentions {
                let k = key(m.body_area, m.side)
                guard !seen.contains(k) else { continue }
                seen.insert(k)

                let status: ReceiptNiggle.Status
                if openInjuries.contains(k) {
                    status = .flagged
                } else if let wm = watermark[k], let d = df.date(from: m.mentioned_at), d <= wm {
                    status = .resolved
                } else {
                    status = .watching
                }
                out.append(ReceiptNiggle(id: m.id, area: m.body_area, side: m.side, status: status))
            }
            return out
        } catch {
            Log.database.error("ReceiptNiggleService.fetch failed: \(error)")
            return []
        }
    }
}

// MARK: - Dev scaffolding ────────────────────────────────────────────────────

#if DEBUG
/// Visual iteration on Act 2 without auth or a real run behind it.
/// `-workoutSignals` boots straight into this. Remove with the scaffolding.
struct WorkoutSignalsPreviewScene: View {
    @State private var expanded = false

    private let note = """
    Warmup: 3 miles
    Intervals: 4 sets of (1 mile @ ~6:00/mi, 400m recovery, 2 miles @ ~6:25/mi, 400m recovery)
    Distance: 17 miles (total)
    Cooldown: Quick (2 miles)
    """

    private let signals: [ReceiptSignal] = [
        .init(key: "SPREAD", value: "±13s", tone: .warn),
        .init(key: "HR", value: "Z4 FROM R2", tone: .warn),
        .init(key: "DRIFT", value: "+8%", tone: .warn),
        .init(key: "HEAT", value: "+6s/mi", tone: .warn),
        .init(key: "VS PLAN", value: "ON TARGET", tone: .good),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SIGNALS").font(.dripEyebrow(11)).tracking(1.3)
                        .foregroundStyle(Color.drip.coral)
                    FlowLayout(spacing: 8) { ForEach(signals) { SignalChip(signal: $0) } }
                    Text("8 reps inside a 26-second spread at 6:07/mi, HR pinned to Z4 from the second rep on. Controlled and even — exactly the session you drew up.")
                        .font(.dripBody(13)).italic()
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("THE WORKOUT").font(.dripEyebrow(11)).tracking(1.3)
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer(minLength: 8)
                        Text("4 × (1MI + 2MI)").font(.dripStat(9)).tracking(1.0)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    if let steps = WorkoutRecipeParser.parse(note) {
                        WorkoutRecipeView(steps: steps)
                    } else {
                        Text(note).font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    VoiceMemoRow(
                        mood: "positive",
                        quote: "HR was high and it felt fatiguing in the heat, but I held a good steady effort with the guys the whole way through, and the last two reps actually came back to me.",
                        expanded: $expanded
                    )
                    FlowLayout(spacing: 8) {
                        NiggleChip(niggle: .init(id: UUID(), area: "calf", side: "left", status: .watching))
                        NiggleChip(niggle: .init(id: UUID(), area: "arch", side: "right", status: .resolved))
                        NiggleChip(niggle: .init(id: UUID(), area: "achilles", side: nil, status: .flagged))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NO MEMO STATE").font(.dripStat(9)).tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    RecordMemoCard {}
                }
            }
            .padding(24)
        }
        .background(Color.drip.background)
    }
}
#endif

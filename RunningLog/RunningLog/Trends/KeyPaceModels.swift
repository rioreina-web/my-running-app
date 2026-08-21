//
//  KeyPaceModels.swift
//  RunningLog · Trends
//
//  The pure substrate for Instruments card 02 — key pace, read one session at
//  a time instead of one week at a time.
//
//  **What changed on 2026-08-09.** `InstrumentKeyPaceCard` used to plot
//  `TrendsWeek.keyPaceSec`: one Int per week, described in `TrendsModels.swift`
//  as "pace of the week's key quality session". Four complaints followed from
//  that single field, and they were all the same complaint:
//
//    • A week's number can be a 400m rep session or a marathon-pace long run,
//      so the card's own stat row could honestly report a 4:32 fastest week and
//      an 8:02 slowest week on one line. It was averaging quantities the model
//      elsewhere says are not comparable (`KeySession.kind`: *"their paces are
//      NOT comparable … never plots them on one scale"*).
//    • 26 weeks of history collapsed to ~24 points, and weeks with no quality
//      work were `compactMap`ped away without saying so.
//    • A week carries no `training_log_id`, so a point could not know which run
//      it was, so nothing could be tapped.
//    • The card knew nothing about `PaceSpectrum`, `BandSettings` or the weekly
//      race-pace ladder, though all three already shipped.
//
//  The fix for all four is one fix: read `TrendsService.keySessions`, which
//  already carries `id`, `zone`, work-bout pace (raw and heat-neutral),
//  `workHrAvg`, `structure` and `kind` per session. No backend work, no new
//  fetch — the card was reading the wrong field off a payload that already had
//  the right one.
//
//  **The rules that make it honest** (each mirrors a guard that already exists
//  in `TrendsThresholdModels.swift`, deliberately, so the two surfaces cannot
//  drift apart):
//
//    1. No trend across zones. A least-squares fit through 5K reps and MP long
//       runs measures the training schedule, not fitness.
//    2. No trend under three graded points — two points are a line through
//       anything. Same `count >= 3` guard as `ThresholdRead.trendSecPerMonth`.
//    3. Trend over graded work only. Cruise and unclassed points are drawn and
//       counted, never fitted.
//    4. Long runs are a different quantity and are excluded by default —
//       excluded, reported, never silently dropped.
//
//  No SwiftUI layout here; everything is a value type or a pure function, so
//  the rules are testable without a renderer — see `KeyPaceTests`.
//

import Foundation
import SwiftUI

// MARK: - Zone colour

extension KeyZone {

    /// Work-zone token → the shared pace ramp. the ramp is pace and only pace
    /// (three-palette rule); grade is carried by dot *fill*, never by hue.
    ///
    /// The backend classifier folds LT/threshold into `hmp` (see
    /// `KeySession.zone`), so there is deliberately no `lt` case: inventing one
    /// client-side would put a zone on the chip row that the data cannot fill.
    ///
    /// NB: `TrendsReadView` carries a private copy of this switch. Migrate it
    /// here rather than adding a third.
    ///
    /// Not `nonisolated` (unlike `KeyZone.label`): the module builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `PaceSpectrum`'s stops
    /// are MainActor with it. Every caller here is a view or a MainActor test.
    static func color(_ token: String) -> Color {
        switch token.lowercased() {
        case "mile": PaceSpectrum.mile
        case "3k":   PaceSpectrum.threeK
        case "5k":   PaceSpectrum.fiveK
        case "10k":  PaceSpectrum.tenK
        case "hmp":  PaceSpectrum.hmp
        case "mp":   PaceSpectrum.mp
        default:     PaceSpectrum.steady
        }
    }

    /// Chip order, **slowest first**: MP · HMP · 10K · 5K · 3K · MILE.
    ///
    /// Deliberately not a change to `KeyZone.order`, which is fast → slow and
    /// is the input to `KeyZone.rank`. Four call sites treat that rank as a
    /// meaningful ordinal ("tie goes to the faster zone", a stacking order),
    /// so flipping it would quietly invert decisions that have nothing to do
    /// with how a chip row reads. Taxonomy order and presentation order are
    /// two concepts; this names the second rather than overloading the first.
    ///
    /// NB: the other zone chip rows in the app (Trends detail, Fast segments)
    /// still list fast → slow. Flip those to `chipOrder` too if the slow-first
    /// reading is the one you want everywhere.
    static var chipOrder: [String] { order.reversed() }

    /// The band anchor that corresponds to a work-zone token, so a point can
    /// be measured against its *own* zone rather than against whatever the
    /// band happens to be set to.
    static func anchor(_ token: String) -> BandAnchor? {
        switch token.lowercased() {
        case "mile": .mile
        case "3k":   .k3
        case "5k":   .k5
        case "10k":  .k10
        case "hmp":  .hmp
        case "mp":   .mp
        default:     nil
        }
    }
}

// MARK: - Which pace is the pace

/// Which of a session's two paces the surface leads with.
///
/// **Watch is the default, deliberately.** The heat correction is real and the
/// analysis needs it, but a number the athlete never saw on her wrist is the
/// wrong thing to show first — it reads as the app quietly disagreeing with
/// her watch. So the dot is what she ran, the ghost tick is where conditions
/// put it, and one control moves everything to the corrected basis when she
/// wants the weather taken out.
///
/// Whichever basis is showing, the trend is fitted on the SAME one, so the
/// line always passes through the dots. On `.watch` the note says out loud
/// that the fit still contains the weather.
enum KeyPaceBasis: String, CaseIterable, Identifiable {
    /// `workPaceSec` — what the watch recorded.
    case watch
    /// `workPaceAdjSec` — conditions-adjusted, heat taken out.
    case heatNeutral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watch: "What you ran"
        case .heatNeutral: "Heat-adjusted"
        }
    }

    /// Micro-label for stat details, legends and toggles.
    ///
    /// **Not "WATCH".** That was the first attempt and it failed the only test
    /// that matters: the athlete read it and asked what it meant. Under a
    /// trend value it looked like the name of a metric rather than a statement
    /// that no heat correction had been applied. "AS RECORDED" says the thing
    /// itself, and pairs with "HEAT-ADJUSTED" as an obvious opposite.
    var short: String {
        switch self {
        case .watch: "AS RECORDED"
        case .heatNeutral: "HEAT-ADJUSTED"
        }
    }

    var other: KeyPaceBasis { self == .watch ? .heatNeutral : .watch }
}

// MARK: - What the lane under the plot shows

/// The second track, below the pace plot.
///
/// **Efficiency is the default, and raw heart rate is the fallback.** A bpm
/// number is not comparable between sessions: 176 at 5K pace and 158 at
/// marathon pace say nothing side by side, so a lane of raw HR is a lane of
/// noise unless you already know what each session was. Metres per heartbeat
/// divides that out — it is pace and heart rate in one number, it rises as
/// fitness rises, and a 5K rep and an MP block can honestly sit on the same
/// scale.
///
/// Heart rate stays available because it is what the grade rule is defined on:
/// the HR lane is the only place the floor can be drawn, and seeing a session
/// sit under it is the explanation for a hollow dot.
enum KeyPaceLane: String, CaseIterable, Identifiable {
    case efficiency
    case heartRate
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .efficiency: "Efficiency"
        case .heartRate: "Heart rate"
        case .off: "Off"
        }
    }

    var axisLabel: String {
        switch self {
        case .efficiency: "M / BEAT"
        case .heartRate: "HR"
        case .off: ""
        }
    }

    var isVisible: Bool { self != .off }
}

// MARK: - How the y-axis is read

/// Absolute pace, or every zone folded onto one scale.
enum KeyPaceMode: String, CaseIterable, Identifiable {
    /// y = heat-neutral pace, sec/mi. Faster plots higher.
    case absolute
    /// y = seconds off this point's own zone target. Puts a mile rep and an MP
    /// long run on one scale, because the question becomes "on target?" rather
    /// than "how fast?".
    case vsTarget

    var id: String { rawValue }

    var label: String {
        switch self {
        case .absolute: "Pace / mi"
        case .vsTarget: "Seconds vs target"
        }
    }

    var axisLabel: String {
        switch self {
        case .absolute: "PACE / MI · FASTER ↑"
        case .vsTarget: "S VS TARGET · FASTER ↑"
        }
    }
}

// MARK: - Heart-rate floors, per zone

/// The heart rate a session has to clear to grade as work, **one number per
/// pace zone, derived from the athlete's own sessions in that zone**.
///
/// **Why this replaced a single number.** `BandSettings.hrFloor` is 160 bpm,
/// and that number is honest about where it came from: the 2026-08-02 audit,
/// across nineteen sessions, of one athlete, guarding one band — HMP. It works
/// there. Carried onto a chart with six zones it stops working, because a
/// marathon-pace session legitimately runs at a lower heart rate than a 5K rep.
/// A perfectly good MP workout was grading as *cruise* for the crime of being
/// marathon pace, and it was demoting real sessions out of the trend.
///
/// **What replaces it.** For each zone, the floor is that zone's own median
/// work heart rate minus a margin. The question stops being "was this hard in
/// absolute terms" — which no single number can answer across six zones — and
/// becomes "was this easy *for this kind of session*", which is the question
/// the grade was always trying to ask.
///
/// **When it declines to answer.** Under `minimumSessions` in a zone there is
/// no median worth trusting, and no floor is applied there: an HR-bearing
/// session grades as work. Guessing a floor would demote real sessions, which
/// is the failure this exists to fix. `BandSettings.hrFloor == 0` turns the
/// whole mechanism off, for the athlete training without a strap.
struct KeyPaceFloors: Equatable {

    /// Sessions a zone needs before its median means anything.
    static let minimumSessions = 3

    /// How far under a zone's median counts as easy for that zone. Session to
    /// session HR at a given effort moves by a few beats; eight is outside
    /// that noise without being so wide it catches nothing. Tunable, and the
    /// same class of number as the 160 it replaces — an empirical margin, not
    /// a physiological constant.
    static let margin = 8

    /// Derived floor per zone token. A zone missing from here has too few
    /// sessions to judge.
    let byZone: [String: Int]
    /// `BandSettings.hrFloor`. Zero means the athlete turned grading off.
    let globalFloor: Int

    var isDisabled: Bool { globalFloor <= 0 }

    /// `nil` means "no floor for this zone" — grade an HR-bearing session as
    /// work rather than demoting it on a number we could not derive.
    func floor(for zone: String) -> Int? {
        guard !isDisabled else { return nil }
        return byZone[zone.lowercased()]
    }

    /// Build from the sessions themselves, before any grading happens.
    static func derive(from sessions: [KeySession], settings: BandSettings) -> KeyPaceFloors {
        var byZone: [String: Int] = [:]
        let grouped = Dictionary(grouping: sessions.filter { ($0.workHrAvg ?? 0) > 0 }) {
            $0.zone.lowercased()
        }
        for (zone, group) in grouped {
            guard group.count >= minimumSessions else { continue }
            let rates = group.compactMap(\.workHrAvg).sorted()
            let mid = rates.count / 2
            let median = rates.count.isMultiple(of: 2)
                ? (rates[mid - 1] + rates[mid]) / 2
                : rates[mid]
            byZone[zone] = median - margin
        }
        return KeyPaceFloors(byZone: byZone, globalFloor: settings.hrFloor)
    }

    static let empty = KeyPaceFloors(byZone: [:], globalFloor: BandSettings.default.hrFloor)
}

// MARK: - One session

/// One key session on the chart. Unlike `TrendsWeek.keyPaceSec` this knows
/// which run it is (`id` is the `training_log_id`), which zone it was, and what
/// the weather took.
struct KeyPacePoint: Identifiable, Equatable {
    /// `training_log_id`. A tap opens this.
    let id: String
    /// "2026-08-05"
    let date: String
    /// "Aug 5"
    let dateLabel: String
    /// Days since the epoch, so the x-axis and the fit are over real elapsed
    /// time. Sessions are not evenly spaced and must not be plotted as if they
    /// were.
    let dayNumber: Int
    /// Zone token from the shared classifier: mile | 3k | 5k | 10k | hmp | mp.
    let zone: String
    /// Heat-neutral work-bout pace, sec/mi. This is the y value — a raw pace
    /// would draw the weather, not the athlete.
    let adjSec: Int
    /// What the watch recorded, sec/mi.
    let rawSec: Int
    /// Average heart rate over the work bouts. `nil` when the session carries
    /// none, which is a different fact from a low one.
    let hrAvg: Int?
    /// "5K 5×1km · 6.0 mi", when the payload carried a structure.
    let structure: String?
    let distanceMi: Double?
    /// A long run's pace is a whole-run mean, a quality session's is its work
    /// bouts. They are not the same quantity; the chart draws them apart.
    let isLongRun: Bool
    /// Minutes of work this session did at its own zone's pace or quicker,
    /// measured from `BandLaps` laps. `nil` when the session has no lap detail
    /// — a session with no measured volume is drawn at the base size and says
    /// so, rather than being sized off a guess.
    let bandMinutes: Double?
    /// Miles of that same work. **This is what dot size is proportional to**,
    /// and what the labels state: an athlete describes a session as "five
    /// miles of work", not as twenty-six minutes of it, and a number she can
    /// check against her own memory of the run is worth more than a marginally
    /// better load proxy she cannot.
    let bandMiles: Double?
    /// `KeySession.qualityLoad` — weighted work minutes, the app's existing
    /// effort unit (`TrendsQualityLoad`). The fallback for dot size when there
    /// are no laps to measure.
    let qualityLoad: Double?
    /// This point's own zone target the week it was run, sec/mi. `nil` when no
    /// race-pace ladder is available — the surface then degrades to absolute
    /// pace with no band, rather than guessing a target.
    let zoneAnchorSec: Int?
    let grade: ThresholdGrade

    /// Seconds the heat charged. Never negative: `adjSec` is derived from
    /// `rawSec` by a correction that only ever slows the raw number.
    var correctionSec: Int { max(0, rawSec - adjSec) }
    var hasCorrection: Bool { correctionSec > 0 }

    /// Seconds off this point's own zone target, heat-neutral. Negative is
    /// faster than target. `nil` without a ladder. Prefer `delta(_:)` at call
    /// sites that know which basis is showing.
    var deltaVsZoneSec: Int? { delta(.heatNeutral) }

    var isWork: Bool { grade == .work }

    // MARK: Efficiency

    /// Metres covered per heartbeat during the work bouts.
    ///
    /// Delegates to `InstrumentsData.metresPerBeat` — the same function card 03
    /// uses — so the two surfaces cannot report different efficiency for the
    /// same session. `nil` without heart rate; never estimated.
    ///
    /// Computed on whichever pace basis is showing, so the lane agrees with the
    /// dots above it. On `.watch` in the heat that reads low for the same
    /// reason the pace does, which is the honest coupling: the athlete is
    /// looking at what happened, not at what it would have been.
    func metresPerBeat(_ basis: KeyPaceBasis) -> Double? {
        guard let hrAvg else { return nil }
        return InstrumentsData.metresPerBeat(paceSec: sec(basis), hr: hrAvg)
    }

    /// "1.24 M/BEAT" for the readout.
    func efficiencyLabel(_ basis: KeyPaceBasis) -> String? {
        metresPerBeat(basis).map { String(format: "%.2f M/BEAT", $0) }
    }

    // MARK: Volume

    /// Where a dot's size came from. Carried so the readout can name it —
    /// a measured 24 minutes and an inferred effort score are different
    /// claims and must not look identical.
    enum VolumeSource: Equatable {
        /// Minutes measured from laps inside the session's own zone band.
        case measured
        /// `qualityLoad`, weighted work minutes. No lap detail to measure.
        case load
        /// Neither. The dot draws at base size.
        case none
    }

    var volumeSource: VolumeSource {
        if bandMiles != nil { return .measured }
        if qualityLoad != nil { return .load }
        return .none
    }

    /// The number dot area is proportional to: measured miles of work, or the
    /// weighted-minutes load when there are no laps. Never mixed silently —
    /// `volumeSource` says which, and the two carry different unit labels.
    var volumeValue: Double? { bandMiles ?? qualityLoad }

    /// "24 MIN" / "31 LOAD" — the compact form, for the readout caption and
    /// list rows where the line is already carrying date, zone, HR and grade.
    /// The legend carries "SIZE · MIN AT PACE", so the units are never a
    /// mystery even when the row is terse.
    var volumeShortLabel: String? {
        switch volumeSource {
        case .measured:
            guard let bandMiles else { return nil }
            return String(format: "%.1f MI", bandMiles)
        case .load:
            guard let qualityLoad else { return nil }
            return "\(Int(qualityLoad.rounded())) LOAD"
        case .none:
            return nil
        }
    }

    /// "24 MIN AT PACE" / "31 LOAD". The long form, where there is room.
    var volumeLabel: String? {
        switch volumeSource {
        case .measured:
            guard let bandMiles else { return nil }
            let minutes = bandMinutes.map { " · \(Int($0.rounded())) MIN" } ?? ""
            return String(format: "%.1f MI AT PACE", bandMiles) + minutes
        case .load:
            guard let qualityLoad else { return nil }
            return "\(Int(qualityLoad.rounded())) LOAD"
        case .none:
            return nil
        }
    }

    /// This session's pace on a given basis.
    func sec(_ basis: KeyPaceBasis) -> Int {
        basis == .watch ? rawSec : adjSec
    }

    /// Seconds off this point's own zone target, on a given basis.
    func delta(_ basis: KeyPaceBasis) -> Int? {
        zoneAnchorSec.map { sec(basis) - $0 }
    }

    /// The y value. `nil` in `.vsTarget` when this point has no target — such a
    /// point is omitted from that mode rather than plotted at a made-up zero.
    func value(mode: KeyPaceMode, basis: KeyPaceBasis) -> Int? {
        switch mode {
        case .absolute: sec(basis)
        case .vsTarget: delta(basis)
        }
    }

    /// The OTHER basis on the same axis — drawn as a ghost tick so the
    /// correction is visible being applied rather than applied silently.
    /// `nil` when the two agree, so an unheated session draws no tick.
    func ghostValue(mode: KeyPaceMode, basis: KeyPaceBasis) -> Int? {
        guard hasCorrection else { return nil }
        switch mode {
        case .absolute: return sec(basis.other)
        case .vsTarget: return delta(basis.other)
        }
    }

    /// Spoken by VoiceOver. Zone is never carried by colour alone.
    var accessibilityLabel: String {
        var parts = [dateLabel, KeyZone.label(zone), TrendsFormat.pace(rawSec) + " per mile"]
        if hasCorrection {
            parts.append("\(TrendsFormat.pace(adjSec)) adjusted for heat")
        }
        switch grade {
        case .work: parts.append("work")
        case .cruise: parts.append("cruise, under the heart-rate floor")
        case .unclassed: parts.append("no heart rate")
        }
        if bandMiles != nil {
            parts.append(String(format: "%.1f miles at that pace", bandMiles ?? 0))
        }
        if let hrAvg { parts.append("\(hrAvg) beats per minute") }
        if isLongRun { parts.append("long run") }
        if let structure, !structure.isEmpty { parts.append(structure) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The read

/// Everything card 02 and its detail render, computed once from
/// `TrendsService.keySessions` plus one `BandSettings`.
struct KeyPaceRead {

    /// Every key session inside the window, oldest → newest. **Long runs are
    /// included here** and filtered at read time by `points(zone:includeLongRuns:)`,
    /// so `hiddenLongRuns` can report what a filter is holding back rather than
    /// the builder deleting it.
    let points: [KeyPacePoint]
    /// The settings this read was built under. Carried so the view states the
    /// band it drew rather than restating the rule from its own constants.
    let settings: BandSettings
    /// The race-pace ladder at the end of the window. `nil` against a backend
    /// with no `bandLaps`, or an athlete with no usable fitness anchor.
    let ladder: BandLadder?
    /// The band's anchor and edges at the end of the window, sec/mi. `nil`
    /// without a ladder. `fast` is the lower number — faster pace, drawn higher.
    let anchorSec: Int?
    let fastSec: Int?
    let slowSec: Int?
    /// True when the prediction the band rests on is itself low-confidence.
    /// The view dashes the edges harder rather than drawing a hard claim.
    let lowConfidence: Bool
    /// The per-zone heart-rate floors this read graded against.
    let floors: KeyPaceFloors
    /// One horizontal segment per week for the band anchor, oldest → newest.
    /// The ladder steps weekly; drawing it as a curve would claim resolution
    /// the data has not got.
    let anchorSteps: [KeyPaceAnchorStep]

    var anchor: BandAnchor { settings.anchor }
    var hrFloor: Int { settings.hrFloor }
    var isEmpty: Bool { points.isEmpty }
    /// True when the athlete is looking at her own band rather than the shipped one.
    var isAdjusted: Bool { !settings.isDefault }
    /// A band can only be drawn against a ladder.
    var hasBand: Bool { fastSec != nil && slowSec != nil }

    // MARK: Filtering

    /// The points a given chip shows. `zone == nil` means ALL.
    func points(zone: String?, includeLongRuns: Bool) -> [KeyPacePoint] {
        points.filter { point in
            (includeLongRuns || !point.isLongRun)
                && (zone == nil || point.zone == zone)
        }
    }

    /// Zones with at least one session in the window, in the canonical
    /// fast → slow order. A zone with none keeps its chip and shows a count of
    /// zero — a missing chip reads as "this zone does not exist".
    func zonesPresent(includeLongRuns: Bool) -> [String] {
        let live = Set(points.filter { includeLongRuns || !$0.isLongRun }.map(\.zone))
        return KeyZone.chipOrder.filter { live.contains($0) }
    }

    func count(zone: String?, includeLongRuns: Bool) -> Int {
        points(zone: zone, includeLongRuns: includeLongRuns).count
    }

    /// Long runs the current filter is holding back. Reported in the surface —
    /// a filter that silently deletes running is a filter that lies.
    func hiddenLongRuns(includeLongRuns: Bool) -> Int {
        includeLongRuns ? 0 : points.filter(\.isLongRun).count
    }

    /// Sessions in other zones the chip filter is holding back.
    func hiddenByZone(zone: String?, includeLongRuns: Bool) -> Int {
        guard let zone else { return 0 }
        return points.filter {
            (includeLongRuns || !$0.isLongRun) && $0.zone != zone
        }.count
    }

    // MARK: Band membership

    /// How many of the visible points landed inside the drawn band. `nil`
    /// without a ladder, because there is no band to be inside of.
    ///
    /// Delegates to `BandSettings.contains(paceSec:anchorSec:)` rather than
    /// re-testing the edges here, so the chart cannot disagree with section 04
    /// about what "in band" means.
    func inBandCount(
        zone: String?,
        includeLongRuns: Bool,
        basis: KeyPaceBasis = .heatNeutral
    ) -> Int? {
        guard anchorSec != nil else { return nil }
        return points(zone: zone, includeLongRuns: includeLongRuns)
            .filter { isInBand($0, basis: basis) }
            .count
    }

    func isInBand(_ point: KeyPacePoint, basis: KeyPaceBasis = .heatNeutral) -> Bool {
        guard let anchorSec else { return false }
        return settings.contains(paceSec: point.sec(basis), anchorSec: anchorSec)
    }

    // MARK: Volume and heart rate

    /// The min/max of measured volume across a set of points, for the dot-size
    /// scale. `nil` when nothing in view carries volume, or when every point
    /// carries the same — a scale with no spread would size every dot
    /// differently for no reason.
    func volumeDomain(zone: String?, includeLongRuns: Bool) -> (lo: Double, hi: Double)? {
        let values = points(zone: zone, includeLongRuns: includeLongRuns)
            .compactMap(\.volumeValue)
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return nil }
        return (lo, hi)
    }

    /// The heart-rate domain for the HR lane, padded to include the floor so
    /// the floor line is always on screen. `nil` when nothing in view has HR.
    func hrDomain(zone: String?, includeLongRuns: Bool) -> (lo: Int, hi: Int)? {
        let values = points(zone: zone, includeLongRuns: includeLongRuns).compactMap(\.hrAvg)
        guard var lo = values.min(), var hi = values.max() else { return nil }
        // Per-zone floor when a zone is selected; the global one otherwise.
        // Only the first branch existed, so the all-zones lane — the default
        // view — drew its dashed floor line against a domain computed without
        // it. A block spent entirely above the floor put every point in range
        // and the line itself off the bottom of the chart, which is the one
        // case where the rule being drawn matters most.
        let activeFloor = zone.flatMap { floors.floor(for: $0) }
            ?? (floors.isDisabled ? nil : floors.globalFloor)
        if let floor = activeFloor {
            lo = min(lo, floor)
            hi = max(hi, floor)
        }
        if hi == lo { lo -= 3; hi += 3 }
        return (lo - 2, hi + 2)
    }

    /// The efficiency range for the lane, padded. `nil` when nothing in view
    /// carries heart rate, in which case there is no efficiency to draw.
    func efficiencyDomain(
        zone: String?,
        includeLongRuns: Bool,
        basis: KeyPaceBasis
    ) -> (lo: Double, hi: Double)? {
        let values = points(zone: zone, includeLongRuns: includeLongRuns)
            .compactMap { $0.metresPerBeat(basis) }
        guard var lo = values.min(), var hi = values.max() else { return nil }
        if hi == lo { lo -= 0.05; hi += 0.05 }
        let pad = (hi - lo) * 0.12
        return (lo - pad, hi + pad)
    }

    /// Median efficiency across the visible set — the lane's reference line.
    ///
    /// Median rather than mean: one no-HR-strap outlier or one session run at
    /// the wrong effort should not move the line everything else is read
    /// against.
    func medianEfficiency(
        zone: String?,
        includeLongRuns: Bool,
        basis: KeyPaceBasis
    ) -> Double? {
        let values = points(zone: zone, includeLongRuns: includeLongRuns)
            .compactMap { $0.metresPerBeat(basis) }
            .sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[mid - 1] + values[mid]) / 2
            : values[mid]
    }

    /// Total measured miles of work across the visible set. `nil` when none of
    /// them were measured — reported rather than shown as zero.
    func totalBandMiles(zone: String?, includeLongRuns: Bool) -> Double? {
        let values = points(zone: zone, includeLongRuns: includeLongRuns).compactMap(\.bandMiles)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    // MARK: Trend

    /// Least-squares slope over graded work in ONE zone, sec/mi per 30 days.
    /// Negative is getting faster.
    ///
    /// `nil` in three cases, each deliberate:
    ///   • `zone == nil` — a fit across zones measures which sessions happened
    ///     to be scheduled, not fitness. This is the error the whole rebuild
    ///     exists to remove; do not "improve" it by fitting anyway.
    ///   • fewer than three graded points — two points are a line through
    ///     anything. Same guard as `ThresholdRead.trendSecPerMonth`.
    ///   • no spread on x.
    ///
    /// Cruise and unclassed points are drawn but never fitted: a trend through
    /// cruising miles measures how many long runs clipped the band.
    func trendSecPerMonth(
        zone: String?,
        includeLongRuns: Bool,
        basis: KeyPaceBasis = .heatNeutral
    ) -> Double? {
        guard zone != nil else { return nil }
        let work = points(zone: zone, includeLongRuns: includeLongRuns).filter(\.isWork)
        guard work.count >= 3 else { return nil }
        let xs = work.map { Double($0.dayNumber) }
        let ys = work.map { Double($0.sec(basis)) }
        guard let slope = ThresholdRead.slope(xs: xs, ys: ys) else { return nil }
        return slope * 30
    }

    /// The fit as the chart needs to draw it: slope per day plus the centroid
    /// it passes through. Same guards as `trendSecPerMonth`.
    func trendLine(
        zone: String?,
        includeLongRuns: Bool,
        basis: KeyPaceBasis = .heatNeutral
    ) -> KeyPaceTrend? {
        guard let perMonth = trendSecPerMonth(
            zone: zone, includeLongRuns: includeLongRuns, basis: basis
        ) else { return nil }
        let work = points(zone: zone, includeLongRuns: includeLongRuns).filter(\.isWork)
        let xs = work.map { Double($0.dayNumber) }
        let ys = work.map { Double($0.sec(basis)) }
        let meanDay = xs.reduce(0, +) / Double(xs.count)
        let meanSec = ys.reduce(0, +) / Double(ys.count)
        return KeyPaceTrend(slopePerDay: perMonth / 30, meanDay: meanDay, meanSec: meanSec)
    }

    // MARK: The card's headline

    /// The zone the collapsed card speaks for: the one with the most sessions
    /// in the window, ties broken by whichever ran most recently.
    ///
    /// The headline names a zone precisely so it can never say "5:57 to 5:20"
    /// across a mile rep and a marathon-pace long run again.
    func dominantZone(includeLongRuns: Bool) -> String? {
        let pool = points.filter { includeLongRuns || !$0.isLongRun }
        guard !pool.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        var latest: [String: Int] = [:]
        for point in pool {
            counts[point.zone, default: 0] += 1
            latest[point.zone] = max(latest[point.zone] ?? Int.min, point.dayNumber)
        }
        return counts.keys.sorted { a, b in
            let ca = counts[a] ?? 0, cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return (latest[a] ?? 0) > (latest[b] ?? 0)
        }.first
    }

    /// First and last graded work pace in the dominant zone — the two numbers
    /// the headline states. `nil` when that zone has fewer than two graded
    /// sessions, in which case the card falls back to a headline that makes no
    /// range claim.
    func headlineRange(zone: String, includeLongRuns: Bool) -> (first: KeyPacePoint, last: KeyPacePoint)? {
        let work = points(zone: zone, includeLongRuns: includeLongRuns).filter(\.isWork)
        guard let first = work.first, let last = work.last, work.count >= 2 else { return nil }
        return (first, last)
    }

    /// The latest session in a zone, graded or not — what the collapsed stat
    /// shows. Falls back through the zone's ungraded sessions rather than
    /// showing nothing.
    func latest(zone: String, includeLongRuns: Bool) -> KeyPacePoint? {
        points(zone: zone, includeLongRuns: includeLongRuns).last
    }

    static func empty(settings: BandSettings) -> KeyPaceRead {
        KeyPaceRead(
            points: [],
            settings: settings,
            ladder: nil,
            anchorSec: nil,
            fastSec: nil,
            slowSec: nil,
            lowConfidence: false,
            floors: .empty,
            anchorSteps: []
        )
    }
}

// MARK: - Chart inputs

/// One week-wide horizontal segment of the band anchor.
struct KeyPaceAnchorStep: Equatable {
    let startDay: Int
    let endDay: Int
    let sec: Int
}

/// A fitted trend, expressed so the chart can draw it without refitting.
struct KeyPaceTrend: Equatable {
    let slopePerDay: Double
    let meanDay: Double
    let meanSec: Double

    func sec(atDay day: Double) -> Double { meanSec + slopePerDay * (day - meanDay) }
}

// MARK: - Builder

enum KeyPaceBuilder {

    /// Build the read.
    ///
    /// - Parameters:
    ///   - sessions: `TrendsService.keySessions`, date-sorted oldest → newest.
    ///   - bandLaps: `TrendsService.bandLaps`, the source of the weekly
    ///     race-pace ladder. `nil` degrades the surface to absolute pace with
    ///     no band and no targets — the dots still plot.
    ///   - settings: `BandSettingsStore.shared.settings`. One band, shared with
    ///     Trends section 04.
    ///   - window: the host's `TrendsWindow`. There is one time control.
    ///   - asOf: the day the window is measured back from. Injected for tests.
    static func read(
        sessions: [KeySession],
        bandLaps: BandLaps?,
        settings: BandSettings,
        window: TrendsWindow,
        asOf: Date = Date()
    ) -> KeyPaceRead {

        let (fromDay, toDay) = bounds(window: window, asOf: asOf)

        // Weekly ladders, oldest → newest, keyed by the day they took effect.
        // A key session is measured against the most recent ladder at or before
        // its own date — never against the window's last ladder, which would
        // flatter old sessions by judging them on today's fitness.
        let ladders: [(day: Int, ladder: BandLadder)] = (bandLaps?.sessions ?? [])
            .map { (ThresholdRead.dayNumber($0.date), $0.anchors) }
            .sorted { $0.0 < $1.0 }

        func ladder(onOrBefore day: Int) -> BandLadder? {
            var found: BandLadder?
            for entry in ladders {
                if entry.day <= day { found = entry.ladder } else { break }
            }
            // Sessions that predate the first ladder fall back to the earliest
            // one we have. That is an approximation, and it is a smaller lie
            // than dropping the session off the chart entirely.
            return found ?? ladders.first?.ladder
        }

        // Laps keyed by `training_log_id`, so a key session can be measured
        // against its own laps. Both models key on the same id.
        let lapsById: [String: [BandLap]] = Dictionary(
            (bandLaps?.sessions ?? []).map { ($0.id, $0.laps) },
            uniquingKeysWith: { first, _ in first }
        )

        // Floors are derived from every session the payload carries, not just
        // the windowed ones: a zone's typical heart rate is a property of the
        // athlete, and narrowing the window should not move it.
        let floors = KeyPaceFloors.derive(from: sessions, settings: settings)

        let points: [KeyPacePoint] = sessions.compactMap { session in
            let day = ThresholdRead.dayNumber(session.date)
            guard day >= fromDay, day <= toDay else { return nil }

            let adj = session.effectivePaceSec
            guard adj > 0 else { return nil }

            let zoneAnchor = KeyZone.anchor(session.zone)
                .flatMap { anchor in ladder(onOrBefore: day).map { anchor.sec(in: $0) } }
                .flatMap { $0 > 0 ? $0 : nil }

            // Volume AT THIS PACE: the laps that fell inside the band around
            // this session's own zone anchor, using the athlete's own edge
            // percentages. Deliberately responsive to `BandSettings` — widen
            // the band and more of the session counts, which is the honest
            // behaviour and visible as the dots growing.
            let volume = zoneAnchor.flatMap { anchor -> (minutes: Double, miles: Double)? in
                guard let laps = lapsById[session.id] else { return nil }
                let edges = settings.edges(anchorSec: anchor)

                // **Slow edge only. The fast edge is deliberately not applied.**
                //
                // It was, and it was wrong. A session the classifier labels
                // HMP but which the athlete actually ran at LT effort sits
                // FASTER than the band's fast edge, so nearly all of its work
                // fell outside its own band: a 3mi-1mi-1mi at 5:15 against an
                // HMP fast edge of 5:18 measured as five minutes of work
                // instead of five miles of it. The zone label and the pace
                // genuinely disagree — the classifier folds LT into HMP — and
                // the volume measure must not silently take the label's side.
                //
                // Within one session there is no faster zone to keep out, so
                // the fast edge has no job here. The slow edge does: it is
                // what separates the reps from the recovery jogs, the warmup
                // and the cooldown. Running quicker than target is still work.
                let working = laps.filter { !$0.skip && $0.adjSec <= edges.slow }
                guard !working.isEmpty else { return nil }
                return (
                    minutes: working.reduce(0.0) { $0 + Double($1.sec) } / 60,
                    miles: working.reduce(0.0) { $0 + $1.miles }
                )
            }

            return KeyPacePoint(
                id: session.id,
                date: session.date,
                dateLabel: session.dateLabel,
                dayNumber: day,
                zone: session.zone.lowercased(),
                adjSec: adj,
                rawSec: session.workPaceSec,
                hrAvg: session.workHrAvg,
                structure: session.structure,
                distanceMi: session.distanceMi,
                isLongRun: session.isLongRun,
                bandMinutes: volume?.minutes,
                bandMiles: volume?.miles,
                qualityLoad: session.qualityLoad,
                zoneAnchorSec: zoneAnchor,
                grade: grade(hrAvg: session.workHrAvg, floor: floors.floor(for: session.zone))
            )
        }
        .sorted { $0.dayNumber < $1.dayNumber }

        let latestLadder = bandLaps?.latestLadder
        let anchorSec = latestLadder.map { settings.anchor.sec(in: $0) }.flatMap { $0 > 0 ? $0 : nil }
        let edges = anchorSec.map { settings.edges(anchorSec: $0) }

        return KeyPaceRead(
            points: points,
            settings: settings,
            ladder: latestLadder,
            anchorSec: anchorSec,
            fastSec: edges?.fast,
            slowSec: edges?.slow,
            lowConfidence: bandLaps?.isLowConfidence ?? false,
            floors: floors,
            anchorSteps: steps(ladders: ladders, anchor: settings.anchor, from: fromDay, to: toDay)
        )
    }

    /// How a session's work bouts graded.
    ///
    /// Reuses `ThresholdGrade`'s rule — heart rate over the floor is work,
    /// under it is cruise, absent is not guessed — but applies it to the
    /// session's own work-bout HR rather than to in-band minutes, so a session
    /// outside the band still carries an honest grade. The two agree for
    /// in-band sessions.
    ///
    /// A floor of 0 turns the rule off: every HR-bearing session is work. That
    /// is the right setting for an athlete training without a strap, and the
    /// wrong one for anybody else — see `BandSettings.hrFloor`.
    static func grade(hrAvg: Int?, floor: Int?) -> ThresholdGrade {
        guard let hrAvg, hrAvg > 0 else { return .unclassed }
        // No floor for this zone — too few sessions to derive one, or grading
        // switched off. An unjudged session is work, not cruise: demoting a
        // real workout on a number we could not compute is the failure mode
        // this whole mechanism exists to avoid.
        guard let floor, floor > 0 else { return .work }
        return hrAvg >= floor ? .work : .cruise
    }

    /// The window as a pair of day numbers, inclusive.
    static func bounds(window: TrendsWindow, asOf: Date) -> (from: Int, to: Int) {
        let today = Int(asOf.timeIntervalSince1970 / 86_400)
        switch window {
        case .custom(let from, let to):
            let a = Int(from.timeIntervalSince1970 / 86_400)
            let b = Int(to.timeIntervalSince1970 / 86_400)
            return (min(a, b), max(a, b))
        default:
            return (today - window.days + 1, today)
        }
    }

    /// One flat segment per weekly ladder, clipped to the window. Steps rather
    /// than a smooth line, because the ladder genuinely steps.
    private static func steps(
        ladders: [(day: Int, ladder: BandLadder)],
        anchor: BandAnchor,
        from: Int,
        to: Int
    ) -> [KeyPaceAnchorStep] {
        guard !ladders.isEmpty else { return [] }
        var out: [KeyPaceAnchorStep] = []
        for (index, entry) in ladders.enumerated() {
            let start = index == 0 ? min(entry.day, from) : entry.day
            let end = index == ladders.count - 1 ? to : ladders[index + 1].day - 1
            let clippedStart = max(start, from)
            let clippedEnd = min(end, to)
            guard clippedEnd >= clippedStart else { continue }
            let sec = anchor.sec(in: entry.ladder)
            guard sec > 0 else { continue }
            // Collapse consecutive identical anchors so a flat block draws as
            // one segment rather than a row of abutting ones.
            if let last = out.last, last.sec == sec, last.endDay + 1 >= clippedStart {
                out[out.count - 1] = KeyPaceAnchorStep(
                    startDay: last.startDay, endDay: clippedEnd, sec: sec
                )
            } else {
                out.append(KeyPaceAnchorStep(startDay: clippedStart, endDay: clippedEnd, sec: sec))
            }
        }
        return out
    }
}

// MARK: - Prose

/// The derived observation each surface prints under its chart. Never authored
/// copy: every number in the sentence is a number already on screen, which is
/// the same contract `InstrumentNote` and the Ask surface hold.
enum KeyPaceProse {

    /// The observation under the chart.
    ///
    /// `compact` is the card's version: the finding and nothing else. The
    /// card already carries a headline, a readout, a legend and a three-stat
    /// row — a paragraph underneath all that is the fifth thing saying the
    /// same shape of thing, and it read as noise on device. Anything the
    /// compact form drops is still on screen somewhere: the session count is
    /// in the stat row, and which pace basis is in force is the stat's own
    /// detail line and the segment above the chart.
    static func note(
        read: KeyPaceRead,
        zone: String?,
        includeLongRuns: Bool,
        basis: KeyPaceBasis = .watch,
        compact: Bool = false
    ) -> String {
        let pts = read.points(zone: zone, includeLongRuns: includeLongRuns)

        guard !pts.isEmpty else {
            guard let zone else {
                return "No key sessions in this window. The chart shows what was logged, and nothing else."
            }
            return "No \(KeyZone.label(zone)) sessions in this window. The chart shows what was "
                + "logged, and nothing else."
        }

        // ALL: state the spread, refuse the trend, say why.
        guard let zone else {
            let zones = read.zonesPresent(includeLongRuns: includeLongRuns).count
            if compact {
                return "\(pts.count) sessions across \(zones) zones. Pick one for a trend — pace at 5K "
                    + "and pace at marathon effort are not the same quantity."
            }
            let corrected = pts.filter(\.hasCorrection).count
            return "\(pts.count) key sessions across \(zones) pace \(zones == 1 ? "zone" : "zones"), "
                + "\(corrected) of them heat-corrected. No trend is drawn here: pace at 5K and pace at "
                + "marathon effort are different quantities, and a line through both would only measure "
                + "which sessions happened to be scheduled. Pick a zone to see its trend."
        }

        let work = pts.filter(\.isWork)
        let label = KeyZone.label(zone)

        guard let slope = read.trendSecPerMonth(
                zone: zone, includeLongRuns: includeLongRuns, basis: basis
              ),
              let first = work.first, let last = work.last
        else {
            if compact {
                return "\(work.count) graded of \(pts.count). A trend needs three."
            }
            return "\(pts.count) \(pts.count == 1 ? "session" : "sessions") here, \(work.count) of them "
                + "graded work. A trend needs three, because two points are a line through anything, "
                + "so none is drawn."
        }

        let magnitude = Int(abs(slope).rounded())
        let direction = slope < 0 ? "quicker" : "slower"
        let corrected = pts.filter(\.hasCorrection).count

        // A rounded-to-zero slope has no direction. "0 seconds a mile slower
        // every 30 days" is not a statement about anything, and it appeared on
        // screen — say flat instead.
        let movement = magnitude == 0
            ? "flat to within a second a mile per month"
            : "\(magnitude) \(magnitude == 1 ? "second" : "seconds") a mile \(direction) every 30 days"

        if compact {
            return "\(label) work: \(TrendsFormat.pace(first.sec(basis))) "
                + "to \(TrendsFormat.pace(last.sec(basis))), \(movement)."
        }

        var sentence = "\(label) work: \(TrendsFormat.pace(first.sec(basis))) "
            + "to \(TrendsFormat.pace(last.sec(basis))) over \(work.count) graded sessions, "
            + "\(movement)."

        // Say which pace this is. A trend fitted on watch pace across a summer
        // measures the weather as well as the athlete, and the surface should
        // not let that pass silently.
        switch basis {
        case .watch where corrected > 0:
            sentence += " These are watch paces, and \(corrected) of them were run in conditions worth "
                + "\(meanCorrection(pts)) a mile. The trend still has that weather in it — switch to "
                + "heat-adjusted to take it out."
        case .watch:
            sentence += " These are watch paces; conditions cost nothing across this window."
        case .heatNeutral where corrected > 0:
            sentence += " Heat-adjusted: \(corrected) of these were corrected, and the ghost tick on each "
                + "dot is what the watch actually said."
        case .heatNeutral:
            sentence += " Heat-adjusted, though conditions cost nothing across this window."
        }
        return sentence
    }

    /// "+4s", the mean correction across the sessions that carried one.
    private static func meanCorrection(_ pts: [KeyPacePoint]) -> String {
        let corrected = pts.filter(\.hasCorrection)
        guard !corrected.isEmpty else { return "0s" }
        let mean = Double(corrected.reduce(0) { $0 + $1.correctionSec }) / Double(corrected.count)
        return "+\(Int(mean.rounded()))s"
    }

    /// The collapsed card's headline. Names its zone, always.
    static func headline(
        read: KeyPaceRead,
        includeLongRuns: Bool,
        basis: KeyPaceBasis = .watch
    ) -> String {
        guard let zone = read.dominantZone(includeLongRuns: includeLongRuns) else {
            return "Quality-session pace."
        }
        guard let range = read.headlineRange(zone: zone, includeLongRuns: includeLongRuns) else {
            return "\(KeyZone.label(zone)) work, session by session."
        }
        return "\(KeyZone.label(zone)) work: \(TrendsFormat.pace(range.first.sec(basis))) "
            + "to \(TrendsFormat.pace(range.last.sec(basis)))."
    }

    /// The collapsed card's italic sub.
    static func subtitle(read: KeyPaceRead, includeLongRuns: Bool) -> String {
        let pts = read.points(zone: nil, includeLongRuns: includeLongRuns)
        guard !pts.isEmpty else { return "" }
        let zones = read.zonesPresent(includeLongRuns: includeLongRuns).count
        return "\(pts.count) key \(pts.count == 1 ? "session" : "sessions") across "
            + "\(zones) pace \(zones == 1 ? "zone" : "zones")."
    }

    /// What a filter is holding back, stated rather than implied.
    static func notCounted(read: KeyPaceRead, zone: String?, includeLongRuns: Bool) -> String? {
        var bits: [String] = []
        let longs = read.hiddenLongRuns(includeLongRuns: includeLongRuns)
        if longs > 0 {
            bits.append(
                "\(longs) long \(longs == 1 ? "run is" : "runs are") hidden. A long run's pace is a "
                + "whole-run mean, not work-bout pace, so it is not on the same scale as a rep session. "
                + "Turn long runs on to see them as open diamonds."
            )
        }
        let others = read.hiddenByZone(zone: zone, includeLongRuns: includeLongRuns)
        if others > 0 {
            bits.append(
                "\(others) \(others == 1 ? "session" : "sessions") in other zones are filtered out, "
                + "not dropped. Tap ALL to count them."
            )
        }
        return bits.isEmpty ? nil : bits.joined(separator: " ")
    }

    /// Signed second delta using the editorial minus sign.
    static func signedSec(_ delta: Int) -> String {
        delta == 0 ? "0s" : (delta < 0 ? "\u{2212}" : "+") + "\(abs(delta))s"
    }

    static func signedSec(_ delta: Double) -> String { signedSec(Int(delta.rounded())) }
}

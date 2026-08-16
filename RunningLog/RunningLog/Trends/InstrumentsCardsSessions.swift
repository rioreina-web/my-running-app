//
//  InstrumentsCardsSessions.swift
//  RunningLog · Trends
//
//  Instruments cards 06–10: key sessions, workouts & reps, head to head,
//  mood × volume, pace ladder. All series derived from `TrendsService`.
//

import SwiftUI

// MARK: - 06 · Key sessions

struct InstrumentKeySessionsCard: View {
    let service: TrendsService

    private var sessions: [KeySession] {
        Array(service.keySessions.suffix(6).reversed())
    }

    var body: some View {
        let sessions = self.sessions
        let quality = sessions.filter { !$0.isLongRun }

        InstrumentCard(
            eyebrow: "KEY SESSIONS",
            title: sessions.isEmpty
                ? "Quality work."
                : "\(sessions.count) session\(sessions.count == 1 ? "" : "s") on the board.",
            sub: sessions.isEmpty
                ? ""
                : "Most recent first\(quality.count < sessions.count ? ", long runs included" : "")."
        ) {
            if !sessions.isEmpty {
                InstrumentStat(value: "\(sessions.count)", caption: "LOGGED")
            }
        } content: {
            if sessions.isEmpty {
                InstrumentEmpty(title: "No quality sessions yet. Workouts with lap data land here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        row(session)
                        if session.id != sessions.last?.id { Hairline() }
                    }
                }
                if let adjusted = sessions.first(where: { $0.isHeatAdjusted }) {
                    InstrumentNote(
                        "\(adjusted.dateLabel) carries a conditions-adjusted pace of \(InstrumentsData.pace(adjusted.effectivePaceSec)) against \(InstrumentsData.pace(adjusted.workPaceSec)) measured."
                    )
                }
            }
        }
    }

    private func row(_ session: KeySession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(session.dateLabel.uppercased()) · \(session.zone.uppercased())")
                    .font(.dripEyebrow(8.5))
                    .tracking(0.85)
                    .foregroundStyle(session.isLongRun ? Color.drip.textSecondary : Color.drip.textPrimary)
                Text(session.structure ?? (session.distanceMi.map { "\(InstrumentsData.miles($0)) mi" } ?? session.zone.capitalized))
                    .font(.dripDisplay(15))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(InstrumentsData.pace(session.workPaceSec)) / mi")
                    .font(.dripStat(12))
                    .foregroundStyle(Color.drip.textPrimary)
                if let hr = session.workHrAvg {
                    Text("\(hr) BPM")
                        .font(.dripEyebrow(8))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                } else if session.isHeatAdjusted {
                    Text("ADJ \(InstrumentsData.pace(session.effectivePaceSec))")
                        .font(.dripEyebrow(8))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - 07 · Workouts & reps

struct InstrumentRepsCard: View {
    let service: TrendsService

    private var session: BandSession? {
        InstrumentsData.latestRepSession(service.bandLaps)
    }

    var body: some View {
        let session = self.session
        let laps = session?.laps.filter { !$0.skip } ?? []
        let secs = laps.map(\.sec)
        let fastest = secs.min() ?? 0
        let slowest = secs.max() ?? 0

        InstrumentCard(
            eyebrow: "WORKOUTS & REPS",
            title: laps.isEmpty
                ? "Rep by rep."
                : "\(laps.count) reps inside \(slowest - fastest) second\(slowest - fastest == 1 ? "" : "s").",
            sub: {
                guard let session, !laps.isEmpty else { return "" }
                return "\(session.dateLabel) · \(InstrumentsData.miles(session.sessionMiles)) mi session."
            }()
        ) {
            if !laps.isEmpty {
                InstrumentStat(value: InstrumentsData.pace(fastest), caption: "FASTEST REP")
            }
        } content: {
            if laps.isEmpty {
                InstrumentEmpty(title: "A workout with laps draws itself here, rep by rep.")
            } else {
                chart(laps: laps, fastest: fastest, slowest: slowest).frame(height: 100)
                InstrumentLegendRow(items: [
                    (.fill(Color.drip.paperDeep), "REP PACE"),
                    (.fill(Color.drip.coral), "FASTEST"),
                ])
                InstrumentStatRow(items: statItems(laps: laps, secs: secs))
                InstrumentNote(
                    "\(laps.count) reps between \(InstrumentsData.pace(fastest)) and \(InstrumentsData.pace(slowest)) a mile — a \(slowest - fastest) second spread."
                )
            }
        }
    }

    private func statItems(laps: [BandLap], secs: [Int]) -> [InstrumentStatRow.Item] {
        var items: [InstrumentStatRow.Item] = []
        let mean = secs.reduce(0, +) / max(secs.count, 1)
        items.append(.init(value: InstrumentsData.pace(mean), unit: "MEAN", detail: "PER MILE"))
        items.append(.init(value: InstrumentsData.pace(secs.max() ?? 0), unit: "SLOWEST", detail: "PER MILE"))
        let hrs = laps.compactMap(\.hr)
        if !hrs.isEmpty {
            items.append(.init(value: "\(hrs.reduce(0, +) / hrs.count)", unit: "AVG HR", detail: "ACROSS REPS"))
        } else {
            let distance = laps.reduce(0.0) { $0 + $1.miles }
            items.append(.init(value: InstrumentsData.miles(distance), unit: "WORK MI", detail: "TOTAL"))
        }
        return items
    }

    private func chart(laps: [BandLap], fastest: Int, slowest: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 14
            let slot = w / CGFloat(max(laps.count, 1))
            let barW = slot * 0.6
            // Faster rep = taller bar. Pad the floor so the quickest still reads.
            let floor = Double(fastest) - Double(max(slowest - fastest, 1)) * 0.6
            let span = max(Double(slowest) - floor, 1)
            let height: (Int) -> CGFloat = { h * CGFloat((Double(slowest) - Double($0)) / span + 0.18) }

            ZStack(alignment: .topLeading) {
                ForEach(laps.indices, id: \.self) { i in
                    let barH = max(2, height(laps[i].sec))
                    let isFastest = laps[i].sec == fastest
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isFastest ? Color.drip.coral : Color.drip.paperDeep)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(isFastest ? Color.clear : Color.drip.divider, lineWidth: 1)
                        )
                        .frame(width: barW, height: barH)
                        .position(x: slot * (CGFloat(i) + 0.5), y: h - barH / 2)
                    Text("\(i + 1)")
                        .instrumentTick()
                        .position(x: slot * (CGFloat(i) + 0.5), y: h + 8)
                }

                Rectangle().fill(Color.drip.textTertiary).frame(height: 1)
                    .position(x: w / 2, y: h)
            }
        }
    }
}

// MARK: - 08 · Head to head

struct InstrumentHeadToHeadCard: View {
    let service: TrendsService

    private var pair: (BandSession, BandSession)? {
        InstrumentsData.comparablePair(service.bandLaps)
    }

    var body: some View {
        let pair = self.pair
        let earlier = pair?.0.laps.filter { !$0.skip } ?? []
        let later = pair?.1.laps.filter { !$0.skip } ?? []
        let earlierMean = earlier.isEmpty ? 0 : earlier.map(\.sec).reduce(0, +) / earlier.count
        let laterMean = later.isEmpty ? 0 : later.map(\.sec).reduce(0, +) / later.count

        InstrumentCard(
            eyebrow: "HEAD TO HEAD",
            title: {
                guard let pair else { return "Two sessions, compared." }
                return "\(pair.0.dateLabel) vs \(pair.1.dateLabel)."
            }(),
            sub: pair == nil ? "" : "Two sessions with \(later.count) scored reps each, rep against rep."
        ) {
            if pair != nil {
                InstrumentStat(
                    value: InstrumentsData.signedSec(laterMean - earlierMean),
                    caption: "MEAN REP"
                )
            }
        } content: {
            if let pair, !earlier.isEmpty, earlier.count == later.count {
                chart(earlier: earlier, later: later).frame(height: 100)
                InstrumentLegendRow(items: [
                    (.line(Color.drip.textPrimary), pair.1.dateLabel.uppercased()),
                    (.line(Color.drip.textTertiary), pair.0.dateLabel.uppercased()),
                ])
                InstrumentStatRow(items: [
                    .init(value: InstrumentsData.pace(laterMean), unit: pair.1.dateLabel.uppercased(), detail: "MEAN REP"),
                    .init(value: InstrumentsData.pace(earlierMean), unit: pair.0.dateLabel.uppercased(), detail: "MEAN REP"),
                    .init(value: InstrumentsData.signedSec(laterMean - earlierMean), unit: "DELTA", detail: "PER MILE"),
                ])
                InstrumentNote(
                    laterMean < earlierMean
                        ? "\(pair.1.dateLabel) ran \(earlierMean - laterMean) seconds a mile quicker across the same number of reps."
                        : "\(pair.1.dateLabel) ran \(laterMean - earlierMean) seconds a mile slower across the same number of reps."
                )
            } else {
                InstrumentEmpty(title: "Two sessions with matching rep counts compare here.")
            }
        }
    }

    private func chart(earlier: [BandLap], later: [BandLap]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = min(earlier.count, later.count)
            let slot = w / CGFloat(max(count, 1))
            let all = (earlier + later).map(\.sec)
            let fast = Double(all.min() ?? 0) - 4
            let slow = Double(all.max() ?? 1) + 4
            let span = max(slow - fast, 1)
            let x: (Int) -> CGFloat = { slot * (CGFloat($0) + 0.5) }
            let y: (Int) -> CGFloat = { h * CGFloat((Double($0) - fast) / span) }

            ZStack(alignment: .topLeading) {
                Path { path in
                    for i in 0..<count {
                        let pt = CGPoint(x: x(i), y: y(earlier[i].sec))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round, dash: [5, 4]))

                Path { path in
                    for i in 0..<count {
                        let pt = CGPoint(x: x(i), y: y(later[i].sec))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(Color.drip.textPrimary)
                        .overlay(Circle().stroke(.white, lineWidth: 1.2))
                        .frame(width: 5, height: 5)
                        .position(x: x(i), y: y(later[i].sec))
                    Text("\(i + 1)").instrumentTick().position(x: x(i), y: h + 9)
                }
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - 09 · Mood × volume

struct InstrumentMoodLoadCard: View {
    let service: TrendsService

    private var days: [TrendsDay] {
        Array(service.days.suffix(30))
    }

    var body: some View {
        let days = self.days
        let run = days.filter { $0.miles > 0 }
        let withMood = run.filter { ($0.mood?.isEmpty == false) }

        InstrumentCard(
            eyebrow: "MOOD × VOLUME",
            title: run.isEmpty
                ? "Miles, coloured by feel."
                : "\(withMood.count) of \(run.count) runs carry a check-in.",
            sub: run.isEmpty ? "" : "Bar height is miles, bar colour is that day's word."
        ) {
            if !run.isEmpty {
                InstrumentStat(
                    value: InstrumentsData.miles(run.reduce(0.0) { $0 + $1.miles }),
                    suffix: " mi",
                    caption: "\(days.count) DAYS"
                )
            }
        } content: {
            if run.isEmpty {
                InstrumentEmpty(title: "Logged runs plot here, coloured by how the day felt.")
            } else {
                chart(days: days).frame(height: 130)
                InstrumentLegendRow(items: [
                    (.none, "BAR HEIGHT · MILES"),
                    (.none, "▴ KEY"),
                    (.none, "● LONG"),
                ])
                moodRamp
                if withMood.count < run.count {
                    InstrumentNote("\(run.count - withMood.count) run\(run.count - withMood.count == 1 ? "" : "s") in this window have no check-in, so \(run.count - withMood.count == 1 ? "that bar carries" : "those bars carry") no colour.")
                }
            }
        }
    }

    private var moodRamp: some View {
        HStack(spacing: 8) {
            Text("STRUGGLING")
                .font(.dripEyebrow(8.5)).tracking(0.85)
                .foregroundStyle(Color.drip.textSecondary)
            HStack(spacing: 2) {
                ForEach(TrendsMoodColor.ordered.reversed(), id: \.self) { mood in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(TrendsMoodColor.color(mood))
                        .frame(width: 11, height: 6)
                }
            }
            Text("ENERGIZED")
                .font(.dripEyebrow(8.5)).tracking(0.85)
                .foregroundStyle(Color.drip.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 9)
    }

    private func chart(days: [TrendsDay]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let slot = w / CGFloat(max(days.count, 1))
            let barW = slot * 0.62
            let ceiling = max(days.map(\.miles).max() ?? 1, 1) * 1.1

            ZStack(alignment: .topLeading) {
                ForEach(days.indices, id: \.self) { i in
                    let day = days[i]
                    if day.miles > 0 {
                        let barH = max(1, h * CGFloat(day.miles / ceiling))
                        let cx = slot * (CGFloat(i) + 0.5)
                        // No check-in means no colour — an uncoloured bar is a
                        // true statement, a guessed colour is not.
                        let fill = day.mood.map { TrendsMoodColor.color($0).opacity(0.9) }
                            ?? Color.drip.paperDeep
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(fill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .stroke(day.mood == nil ? Color.drip.divider : Color.clear, lineWidth: 1)
                            )
                            .frame(width: barW, height: barH)
                            .position(x: cx, y: h - barH / 2)
                        if day.type == .key {
                            InstrumentTriangle()
                                .fill(Color.drip.textPrimary)
                                .frame(width: 6, height: 5)
                                .position(x: cx, y: h - barH - 6)
                        }
                        if day.type == .long {
                            Circle()
                                .fill(Color.drip.textPrimary)
                                .frame(width: 4, height: 4)
                                .position(x: cx, y: h - barH - 6)
                        }
                    }
                }

                Rectangle().fill(Color.drip.textTertiary).frame(height: 1)
                    .position(x: w / 2, y: h)
            }
        }
    }
}

// MARK: - 10 · Pace ladder

/// Deliberately **not** a race-prediction card. The app has no prediction model
/// wired into `TrendsService`, and inventing projected finish times is exactly
/// the failure this surface exists to avoid. What is real is the athlete's own
/// derived pace ladder — the zone anchors computed from their sessions — so
/// that is what this shows, labelled for what it is.
struct InstrumentPaceLadderCard: View {
    let service: TrendsService

    private var ladder: BandLadder? {
        service.bandLaps?.latestLadder
    }

    var body: some View {
        let ladder = self.ladder
        let tier = service.bandLaps?.confidenceTier

        InstrumentCard(
            eyebrow: "PACE LADDER",
            title: ladder.map { "\(InstrumentsData.pace($0.mile)) to \(InstrumentsData.pace($0.mp))." }
                ?? "Your zone anchors.",
            sub: ladder == nil ? "" : "Derived from your own sessions, mile pace through marathon pace."
        ) {
            if let tier {
                InstrumentStat(value: tier.uppercased(), caption: "CONFIDENCE")
            }
        } content: {
            if let ladder {
                ladderStrip(ladder)
                InstrumentLegendRow(items: [
                    (.none, "SECONDS PER MILE, BY ZONE"),
                ])
                InstrumentNote(
                    "These are anchors, not predictions — the paces your recent sessions support, not a projected finish time.",
                    eyebrow: "WHAT THIS IS"
                )
            } else {
                InstrumentEmpty(title: "Your pace ladder appears once enough sessions carry lap data.")
            }
        }
    }

    private func ladderStrip(_ ladder: BandLadder) -> some View {
        let rows: [(String, Int)] = [
            ("MILE", ladder.mile), ("3K", ladder.k3), ("5K", ladder.k5), ("10K", ladder.k10),
            ("LT", ladder.lt), ("HMP", ladder.hmp), ("MP", ladder.mp),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.0)
                        .font(.dripEyebrow(9)).tracking(0.9)
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 44, alignment: .leading)
                    Spacer()
                    Text("\(InstrumentsData.pace(row.1)) / mi")
                        .font(.dripStat(14))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                .padding(.vertical, 9)
                if index < rows.count - 1 { Hairline() }
            }
        }
    }
}

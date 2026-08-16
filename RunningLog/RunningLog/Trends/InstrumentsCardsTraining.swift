//
//  InstrumentsCardsTraining.swift
//  RunningLog · Trends
//
//  Instruments cards 01–05: volume, key pace, efficiency, mood, heat.
//  Card 02 (key pace) moved to `KeyPaceCard.swift` on 2026-08-09 — see the
//  tombstone below for why. Its slot in the running order is unchanged.
//  Every series is derived from `TrendsService` via `InstrumentsData` — see
//  InstrumentsCardKit.swift. No card here holds a literal training number.
//

import SwiftUI

// MARK: - 01 · Volume

struct InstrumentVolumeCard: View {
    let service: TrendsService

    private var rows: [(label: String, miles: Double)] {
        InstrumentsData.weeklyMiles(service.weeks)
    }

    var body: some View {
        let rows = self.rows
        let values = rows.map(\.miles)
        let latest = values.last ?? 0
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0

        InstrumentCard(
            eyebrow: "VOLUME",
            title: rows.count >= 2
                ? "\(Int(lo.rounded())) to \(Int(hi.rounded())) across \(rows.count) weeks."
                : "Weekly volume.",
            sub: rows.isEmpty
                ? ""
                : "\(InstrumentsData.miles(latest)) mi this week\(rows.count >= 2 ? ", against a \(InstrumentsData.miles(values.reduce(0, +) / Double(values.count))) mi average" : "")."
        ) {
            if !rows.isEmpty {
                InstrumentStat(value: InstrumentsData.miles(latest), suffix: " mi", caption: "THIS WEEK")
            }
        } content: {
            if rows.isEmpty {
                InstrumentEmpty(title: "No weeks logged yet. Once runs land, your volume shape starts here.")
            } else {
                chart(rows: rows, values: values, hi: hi)
                    .frame(height: 120)
                HStack {
                    Text(rows.first?.label.uppercased() ?? "").instrumentTick()
                    Spacer()
                    Text(rows.last?.label.uppercased() ?? "").instrumentTick()
                }
                .padding(.top, 4)
                InstrumentLegendRow(items: [
                    (.fill(Color.drip.paperDeep), "WEEKLY MILES"),
                    (.fill(Color.drip.coral), "THIS WEEK"),
                    (.line(Color.drip.textPrimary), "4-WK MEAN"),
                ])
                InstrumentStatRow(items: statItems(values: values))
                if let note = note(values: values) {
                    InstrumentNote(note)
                }
            }
        }
    }

    private func statItems(values: [Double]) -> [InstrumentStatRow.Item] {
        var items: [InstrumentStatRow.Item] = []
        let mean4 = InstrumentsData.rollingMean(values).last ?? 0
        items.append(.init(value: InstrumentsData.miles(mean4), unit: "4-WK MEAN", detail: "TRAILING"))
        if let hi = values.max() {
            items.append(.init(value: InstrumentsData.miles(hi), unit: "PEAK WK", detail: "IN RANGE"))
        }
        if let lo = values.min() {
            items.append(.init(value: InstrumentsData.miles(lo), unit: "LOWEST WK", detail: "IN RANGE"))
        }
        return items
    }

    /// A derived observation — the numbers in the sentence are the numbers on
    /// the chart. Nil when there isn't enough history for the claim to be true.
    private func note(values: [Double]) -> String? {
        guard values.count >= 4, let hi = values.max(), let lo = values.min() else { return nil }
        let spread = hi - lo
        let mean = values.reduce(0, +) / Double(values.count)
        let latest = values.last ?? 0
        if latest >= hi - 0.05 {
            return "This is the biggest week in the window, \(InstrumentsData.miles(latest)) mi against a \(InstrumentsData.miles(mean)) mi average."
        }
        return "\(values.count) weeks inside a \(InstrumentsData.miles(spread)) mi spread, averaging \(InstrumentsData.miles(mean)) mi."
    }

    private func chart(rows: [(label: String, miles: Double)], values: [Double], hi: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let slot = w / CGFloat(max(rows.count, 1))
            let barW = slot * 0.62
            let ceiling = max(hi, 1) * 1.08
            let mean = InstrumentsData.rollingMean(values)

            ZStack(alignment: .bottomLeading) {
                ForEach([0.5, 1.0], id: \.self) { frac in
                    Hairline().position(x: w / 2, y: h - h * CGFloat(frac))
                }

                ForEach(values.indices, id: \.self) { i in
                    let isLatest = i == values.count - 1
                    let barH = max(1, h * CGFloat(values[i] / ceiling))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isLatest ? Color.drip.coral : Color.drip.paperDeep)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(isLatest ? Color.clear : Color.drip.divider, lineWidth: 1)
                        )
                        .frame(width: barW, height: barH)
                        .position(x: slot * (CGFloat(i) + 0.5), y: h - barH / 2)
                }

                Path { path in
                    for i in mean.indices {
                        let pt = CGPoint(x: slot * (CGFloat(i) + 0.5), y: h - h * CGFloat(mean[i] / ceiling))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

                Rectangle().fill(Color.drip.textTertiary).frame(height: 1)
            }
        }
    }
}

// MARK: - 02 · Key pace

// MOVED 2026-08-09 → `KeyPaceCard.swift`.
//
// `InstrumentKeyPaceCard` used to live here and plotted `TrendsWeek.keyPaceSec`
// — one averaged pace per week. That single field is why the card's own stat
// row could report a 4:32 fastest week and an 8:02 slowest week on one line:
// a week's number can be a 400m rep session or a marathon-pace long run, and
// averaging those is averaging quantities `KeySession` itself says are not
// comparable. It also meant a point carried no `training_log_id`, so nothing
// on the chart could be tapped.
//
// The card now reads `TrendsService.keySessions` — one dot per session, with
// its zone, its heat-neutral pace and its workout id — and lives in
// `KeyPaceCard.swift` alongside `KeyPaceChart` and `KeyPaceDetailView`.
// Substrate and rules: `KeyPaceModels.swift`.

// MARK: - 03 · Efficiency

struct InstrumentEfficiencyCard: View {
    let service: TrendsService

    private var rows: [(label: String, value: Double)] {
        InstrumentsData.efficiency(service.keySessions)
    }

    var body: some View {
        let rows = self.rows
        let values = rows.map(\.value)
        let latest = values.last ?? 0

        InstrumentCard(
            eyebrow: "EFFICIENCY",
            title: values.isEmpty ? "Metres per heartbeat." : String(format: "%.2f m per beat.", latest),
            sub: values.isEmpty ? "" : "Work-bout pace against average work heart rate, \(values.count) session\(values.count == 1 ? "" : "s")."
        ) {
            if !values.isEmpty {
                InstrumentStat(value: String(format: "%.2f", latest), caption: "M / BEAT")
            }
        } content: {
            if values.count < 2 {
                InstrumentEmpty(title: "This needs quality sessions with heart rate. Two of them and the trend appears.")
            } else {
                chart(values: values).frame(height: 90)
                HStack {
                    Text(rows.first?.label.uppercased() ?? "").instrumentTick()
                    Spacer()
                    Text(rows.last?.label.uppercased() ?? "").instrumentTick()
                }
                .padding(.top, 4)
                InstrumentLegendRow(items: [
                    (.line(Color.drip.textPrimary), "METRES PER BEAT"),
                    (.dot(Color.drip.coral), "LATEST"),
                ])
                InstrumentStatRow(items: [
                    .init(value: String(format: "%.2f", values.max() ?? 0), unit: "BEST", detail: "IN RANGE"),
                    .init(value: String(format: "%.2f", values.reduce(0, +) / Double(values.count)), unit: "MEAN", detail: "\(values.count) SESSIONS"),
                    .init(
                        value: String(format: "%+.0f%%", (latest / (values.first ?? latest) - 1) * 100),
                        unit: "VS FIRST",
                        detail: "IN RANGE"
                    ),
                ])
                InstrumentNote("Distance covered per heartbeat during work bouts. Higher means the same effort is buying more ground.")
            }
        }
    }

    private func chart(values: [Double]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let slot = w / CGFloat(max(values.count, 1))
            let lo = (values.min() ?? 0) * 0.97
            let hi = (values.max() ?? 1) * 1.03
            let span = max(hi - lo, 0.0001)
            let x: (Int) -> CGFloat = { slot * (CGFloat($0) + 0.5) }
            let y: (Double) -> CGFloat = { h - h * CGFloat(($0 - lo) / span) }

            ZStack(alignment: .topLeading) {
                Hairline().position(x: w / 2, y: y(values.max() ?? 0))
                Hairline().position(x: w / 2, y: y(values.min() ?? 0))

                Path { path in
                    for i in values.indices {
                        let pt = CGPoint(x: x(i), y: y(values[i]))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(Color.drip.textPrimary, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

                Circle()
                    .fill(Color.drip.coral)
                    .overlay(Circle().stroke(.white, lineWidth: 1.4))
                    .frame(width: 8, height: 8)
                    .position(x: x(values.count - 1), y: y(values.last ?? lo))
            }
        }
    }
}

// MARK: - 04 · Mood

struct InstrumentMoodCard: View {
    let service: TrendsService

    private var rows: [(date: String, mood: String)] {
        InstrumentsData.moods(service.days)
    }

    var body: some View {
        let rows = self.rows
        let counts = InstrumentsData.moodCounts(rows)
        let top = counts.max { $0.count < $1.count }

        InstrumentCard(
            eyebrow: "MOOD",
            title: {
                guard let top, !rows.isEmpty else { return "Daily check-ins." }
                return "\(top.count) of \(rows.count) days \(top.mood)."
            }(),
            sub: rows.isEmpty ? "" : "Every logged check-in in the window, in the order you felt it."
        ) {
            if let latest = rows.last {
                MoodBadge(mood: latest.mood)
            }
        } content: {
            if rows.isEmpty {
                InstrumentEmpty(title: "No check-ins logged yet. Record how a run felt and the month starts filling in.")
            } else {
                Text("ONE SQUARE, ONE DAY")
                    .instrumentTick()
                calendar(rows: rows).padding(.top, 8)
                Text("THE MIX · \(rows.count) DAYS")
                    .instrumentTick()
                    .padding(.top, 14)
                distribution(counts: counts, total: rows.count).padding(.top, 6)
                InstrumentLegendRow(items: counts.map {
                    (.fill(TrendsMoodColor.color($0.mood)), "\($0.mood.uppercased()) \($0.count)")
                })
                if let top {
                    InstrumentNote("\(top.mood.capitalized) is the most-logged word in this window, \(top.count) of \(rows.count) days.")
                }
            }
        }
    }

    private func calendar(rows: [(date: String, mood: String)]) -> some View {
        let columns = 10
        let rowCount = Int(ceil(Double(rows.count) / Double(columns)))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<max(rowCount, 1), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        if index < rows.count {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(TrendsMoodColor.color(rows[index].mood).opacity(0.92))
                                .aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel("\(rows[index].date), \(rows[index].mood)")
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }

    private func distribution(counts: [(mood: String, count: Int)], total: Int) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, entry in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TrendsMoodColor.color(entry.mood).opacity(0.92))
                        .frame(width: max(0, geo.size.width * CGFloat(entry.count) / CGFloat(max(total, 1)) - 2))
                        .accessibilityLabel("\(entry.mood), \(entry.count) days")
                }
            }
        }
        .frame(height: 12)
    }
}

// MARK: - 05 · Heat

struct InstrumentHeatCard: View {
    let service: TrendsService

    private var rows: [(dewPoint: Int, penalty: Double, label: String)] {
        InstrumentsData.heatPenalties(service.bandLaps)
    }

    var body: some View {
        let rows = self.rows
        let worst = rows.max { $0.penalty < $1.penalty }

        InstrumentCard(
            eyebrow: "HEAT IMPACT",
            title: {
                guard let worst else { return "What the conditions cost." }
                return "\(Int(worst.penalty.rounded())) seconds a mile at \(worst.dewPoint)° dew."
            }(),
            sub: rows.isEmpty ? "" : "Measured pace against conditions-adjusted pace, \(rows.count) session\(rows.count == 1 ? "" : "s")."
        ) {
            if let latest = rows.last {
                InstrumentStat(
                    value: "+\(Int(latest.penalty.rounded()))",
                    suffix: "s",
                    caption: "LATEST · \(latest.dewPoint)° DEW"
                )
            }
        } content: {
            if rows.count < 2 {
                InstrumentEmpty(title: "Sessions logged with dew point plot here, showing what the weather took.")
            } else {
                chart(rows: rows).frame(height: 110)
                InstrumentLegendRow(items: [
                    (.dot(Color.drip.textTertiary), "ONE SESSION"),
                    (.dot(Color.drip.coral), "LATEST"),
                ])
                InstrumentStatRow(items: [
                    .init(value: "\(rows.map(\.dewPoint).min() ?? 0)°", unit: "COOLEST", detail: "DEW POINT"),
                    .init(value: "\(rows.map(\.dewPoint).max() ?? 0)°", unit: "WARMEST", detail: "DEW POINT"),
                    .init(
                        value: "+\(Int((rows.reduce(0.0) { $0 + $1.penalty } / Double(rows.count)).rounded()))s",
                        unit: "MEAN COST",
                        detail: "PER MILE"
                    ),
                ])
                InstrumentNote("Every dot is a session's measured pace minus its conditions-adjusted pace. The gap is weather, not fitness.")
            }
        }
    }

    private func chart(rows: [(dewPoint: Int, penalty: Double, label: String)]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dews = rows.map { Double($0.dewPoint) }
            let lo = (dews.min() ?? 0) - 3
            let hi = (dews.max() ?? 1) + 3
            let span = max(hi - lo, 1)
            let pMax = max(rows.map(\.penalty).max() ?? 1, 1) * 1.15
            let x: (Double) -> CGFloat = { w * CGFloat(($0 - lo) / span) }
            let y: (Double) -> CGFloat = { h - h * CGFloat($0 / pMax) }

            ZStack(alignment: .topLeading) {
                Hairline().position(x: w / 2, y: y(pMax / 2))
                Rectangle().fill(Color.drip.textTertiary).frame(height: 1)
                    .position(x: w / 2, y: h)

                ForEach(rows.indices, id: \.self) { i in
                    let isLatest = i == rows.count - 1
                    Circle()
                        .fill(isLatest ? Color.drip.coral : Color.drip.textTertiary.opacity(0.75))
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                        .frame(width: isLatest ? 8 : 6, height: isLatest ? 8 : 6)
                        .position(x: x(Double(rows[i].dewPoint)), y: y(rows[i].penalty))
                }

                Text("\(Int(lo.rounded()))° DEW").instrumentTick().position(x: 22, y: h + 9)
                Text("\(Int(hi.rounded()))°").instrumentTick().position(x: w - 12, y: h + 9)
            }
        }
        .padding(.bottom, 12)
    }
}

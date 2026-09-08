import Foundation

/// Builds the five-tab workbook from the sessions currently on screen.
/// Export follows the visible set, so what you exported is what you were
/// looking at.
enum ConditionsExport {

    static func build(sessions: [ConditionsSession],
                      weeks: [ConditionsWeek],
                      fastCut: Double) throws -> URL {

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let cut = ConditionsRollup.mmss(fastCut)
        let stamp = df.string(from: sessions.first?.date ?? Date())

        // ---------------------------------------------------------- Read me
        let miles = sessions.reduce(0) { $0 + $1.miles }
        let readMe: [String] = [
            "Post Run Drip · The Conditions",
            "Training export · \(sessions.count) sessions · \(String(format: "%.1f", miles)) miles · through \(stamp)",
            "",
            "What each tab holds",
            "Sessions",
            "One row per training session, newest first. A session is not a day and not an upload: five Strava files on one morning can be two sessions, a track workout and an evening double. Uploads inside 90 minutes of each other join into one session.",
            "Carries distance, moving time, pace, heart rate, mood and RPE, the temperature and dew point it was run in, the heat-adjusted pace, and the workout as you described it into your voice memo.",
            "Splits",
            "One row per split, for every session, with heart rate. is_fast_segment marks a split that is also a fast segment, so reps can be joined to the splits they sit inside without re-running detection.",
            "Fast segments",
            "One row per rep. A fast segment is anything held at or under \(cut) per mile. This is the tab with per-rep heart rate on it, which is the thing a session summary cannot show.",
            "Weeks",
            "One row per Monday-start week: mileage, days run, quality sessions, fast miles and hours. partial_week marks a week the range cut in half, so a short week is not read as a collapse in fitness.",
            "",
            "How the heat adjustment works",
            "Temperature and dew point together decide how hard a given pace feels. The pace penalty is computed server-side when the run is synced and stored with the run, so the number here is the same one the app shows.",
            "The adjusted pace is shown, never substituted. Recorded pace stays the real one, and no training-load or fitness math uses the adjusted value.",
            "Runs with no GPS, including treadmill and hand-entered sessions, get no heat adjustment at all. Attributing outdoor weather to a treadmill run is not a rounding error, it is a wrong number.",
            "",
            "Things worth knowing before you trust a number",
            "A session pace can read far slower than it felt when the upload recorded wall clock rather than moving time. Short-rep sessions are the usual case: the reps are right, the rollup is not.",
            "Heart rate on short reps lags. A 30-second rep ends before heart rate catches up, so its average reads low. The number is right; the intuition it invites is not.",
            "Warm-ups and cooldowns are auto-typed easy or recovery, so recovery is one of the most common labels in the data and means little on its own.",
            "Every pace formatted as m:ss also appears as raw seconds, because m:ss does not sort in a spreadsheet.",
        ]

        // --------------------------------------------------------- Sessions
        var sessionRows: [[XLSXWriter.Cell]] = [[
            "date", "weekday", "start_local", "session", "miles", "moving_min",
            "pace", "pace_sec_per_mi", "avg_hr", "mood", "rpe",
            "temp_f", "dew_point_f", "humidity_pct", "heat_load",
            "heat_penalty_pct", "heat_adj_pace", "heat_adj_pace_sec",
            "heat_cost_sec_per_mi", "fast_segments", "fast_miles", "fast_avg_hr",
            "planned_workout", "voice_memo_recorded", "indoor_no_gps", "uploads",
        ].map { XLSXWriter.Cell.text($0) }]

        let wd = DateFormatter(); wd.dateFormat = "EEE"
        for s in sessions {
            sessionRows.append([
                .text(df.string(from: s.date)),
                .text(wd.string(from: s.date)),
                .text(tf.string(from: s.date)),
                .text(s.label),
                .number(round(s.miles * 100) / 100),
                .number(round(s.durationMinutes * 10) / 10),
                .text(ConditionsRollup.mmss(s.paceSeconds)),
                .opt(s.paceSeconds.map { round($0 * 10) / 10 }),
                .opt(s.avgHeartRate),
                .opt(s.mood),
                .opt(s.rpe),
                .opt(s.weather?.tempF),
                .opt(s.weather?.dewPointF),
                .opt(s.weather?.humidity),
                .opt(s.weather?.heatCategory),
                .opt(s.weather?.adjustmentPct.map { round($0 * 10000) / 100 }),
                .text(ConditionsRollup.mmss(s.adjustedPaceSeconds)),
                .opt(s.adjustedPaceSeconds.map { round($0 * 10) / 10 }),
                .opt(s.heatCostSeconds),
                .int(s.fastSegments.count),
                .number(round(s.fastMiles * 100) / 100),
                .opt(s.fastAvgHeartRate),
                .opt(s.plannedWorkout),
                .bool(s.hasAudio),
                .bool(s.isIndoor),
                .int(s.rows.count),
            ])
        }

        // ----------------------------------------------------------- Splits
        var splitRows: [[XLSXWriter.Cell]] = [[
            "date", "session", "split", "miles", "duration_sec",
            "pace", "pace_sec_per_mi", "avg_hr", "effort", "is_fast_segment",
        ].map { XLSXWriter.Cell.text($0) }]

        for s in sessions {
            for (i, sp) in s.splits.enumerated() {
                let secs = ConditionsRollup.paceSeconds(from: sp.pacePerMile)
                splitRows.append([
                    .text(df.string(from: s.date)), .text(s.label), .int(i + 1),
                    .number(round(sp.distanceMiles * 100) / 100),
                    .int(Int(sp.durationSeconds)),
                    .text(sp.pacePerMile), .opt(secs), .opt(sp.avgHeartRate),
                    .text(sp.effort),
                    .bool(secs.map { $0 <= fastCut } ?? false),
                ])
            }
        }

        // ---------------------------------------------------- Fast segments
        var fastRows: [[XLSXWriter.Cell]] = [[
            "date", "session", "rep", "miles", "duration_sec",
            "pace", "pace_sec_per_mi", "avg_hr", "temp_f", "dew_point_f",
            "heat_adj_pace_sec",
        ].map { XLSXWriter.Cell.text($0) }]

        for s in sessions {
            for (i, f) in s.fastSegments.enumerated() {
                let secs = ConditionsRollup.paceSeconds(from: f.pacePerMile)
                let adj = secs.flatMap { p -> Double? in
                    guard let pct = s.weather?.adjustmentPct, pct > 0 else { return nil }
                    return round(p / (1 + pct) * 10) / 10
                }
                fastRows.append([
                    .text(df.string(from: s.date)), .text(s.label), .int(i + 1),
                    .number(round(f.distanceMiles * 100) / 100),
                    .int(Int(f.durationSeconds)),
                    .text(f.pacePerMile), .opt(secs), .opt(f.avgHeartRate),
                    .opt(s.weather?.tempF), .opt(s.weather?.dewPointF), .opt(adj),
                ])
            }
        }

        // ------------------------------------------------------------ Weeks
        var weekRows: [[XLSXWriter.Cell]] = [[
            "week_start", "miles", "days_run", "sessions", "quality_sessions",
            "fast_miles", "hours", "partial_week",
        ].map { XLSXWriter.Cell.text($0) }]

        for w in weeks {
            weekRows.append([
                .text(df.string(from: w.start)),
                .number(round(w.miles * 10) / 10),
                .int(w.daysRun), .int(w.sessions), .int(w.quality),
                .number(round(w.fastMiles * 100) / 100),
                .number(round(w.hours * 10) / 10),
                .bool(w.isPartial),
            ])
        }

        let sheets: [XLSXWriter.Sheet] = [
            .init(name: "Read me", rows: readMe.map { [XLSXWriter.Cell.text($0)] },
                  freezeHeader: false, columnWidth: 112),
            .init(name: "Sessions", rows: sessionRows),
            .init(name: "Splits", rows: splitRows),
            .init(name: "Fast segments", rows: fastRows),
            .init(name: "Weeks", rows: weekRows),
        ]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("post-run-drip-training-\(stamp).xlsx")
        try XLSXWriter.write(sheets, to: url)
        return url
    }
}

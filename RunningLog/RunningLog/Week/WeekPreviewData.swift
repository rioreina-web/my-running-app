//
//  WeekPreviewData.swift
//  RunningLog · Week
//
//  ⚠️ THERE IS NO SAMPLE DATA IN THIS FILE, AND THERE SHOULD NEVER BE.
//
//  This file used to hold a hand-built fixture — 48 miles a week, six runs,
//  340 load-minutes, fourteen filled mood dots, a threshold at 5:21. Every
//  number was invented by me, and the surface rendered them as confidently as
//  it would have rendered real ones. The athlete asked "what's 48 miles from?"
//  and the honest answer was "nothing."
//
//  The real account, for scale: 52–77 miles a week, 8–16 runs, doubles most
//  days, load 473–711, and a mood logged on one to five runs a week — not
//  fourteen. The fixture wasn't just miscalibrated, it was the wrong SHAPE,
//  and building on it produced a layout that could not represent the athlete.
//
//  So the preview below renders the EMPTY states instead. That is the state a
//  new account genuinely sees, it is the state most likely to ship broken, and
//  it contains nothing that could be mistaken for a real number. If you need
//  to see the tab populated, run it against a real account — `WeekService`
//  derives everything from `TrendsService`, so the simulator shows real data
//  the moment you're signed in.
//

import SwiftUI

extension WeekRead {

    /// What a brand-new account sees: no runs, no bands, no biometrics, and a
    /// plain sentence in every slot explaining why.
    static let previewEmpty = WeekRead(
        plateBlock: "0 weeks on file",
        plateRange: "—",
        eyebrow: "The week ahead",
        title: "Week of —.",
        subtitle: "No runs logged yet this week.",

        days: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map {
            Day(name: $0, miles: nil, label: "—", isQuality: false)
        },
        weekSummary: "Nothing logged yet this week",

        bands: [],
        efficiency: nil,
        efficiencyUnavailable: .notWired(
            "Pace at a fixed heart rate is computed in the efficiency index, but it isn't plumbed to this tab yet."),
        fasterSentence: "",
        bandsUnavailable: .needsHistory(
            "No sessions have held a threshold band long enough to trend yet. This needs runs with laps inside HMP or MP."),

        load: Load(
            current: "—",
            deltaText: "No baseline yet",
            weeks: [],
            baselineAvg: 0,
            baselineLo: 0,
            baselineHi: 0,
            baselineLabel: "Baseline needs more weeks",
            spikeNote: "",
            method: ""
        ),
        recovery: Recovery(
            niggles: [],
            niggleDots: [],
            moods: [],
            moodSummary: "No moods logged in the last 14 days",
            overnight: [],
            quadrantNote: "",
            sentence: "Nothing was logged about how the running felt in the last two weeks, so the side of this that matters most is blank. No body mentions in that window. The overnight numbers aren't flowing yet, so this is one side of the picture, not both."
        ),
        overnightUnavailable: .notCaptured(
            "No overnight data has arrived. `daily_biometrics` exists but nothing writes to it yet, so heart rate, HRV and sleep are blank rather than estimated."),

        longRuns: [],
        longRunSentence: "",
        spectrum: [],
        spectrumNote: "",
        longThreshold: MiniStat(eyebrow: "Threshold volume", value: "—", unit: "",
                                caption: "No band data", note: "",
                                noteTint: Color.drip.textTertiary),
        volume: MiniStat(eyebrow: "Volume", value: "—", unit: "",
                         caption: "No weeks on file", note: "",
                         noteTint: Color.drip.textTertiary),

        proposals: [],
        proposalsUnavailable: .notWired(
            "Nothing proposes yet. The signals above are yours; the change to the week is not written until there's an engine that can cite them.")
    )
}

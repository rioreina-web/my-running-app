//
//  HealthBiometricsSync.swift
//  RunningLog
//
//  Apple Health → `daily_biometrics` (source 'healthkit'). The producer that
//  makes the recovery ledger's Overnight and Sleep factors actually fire.
//
//  Context: the ledger (TrendsRecoveryFactors.overnight / .sleep), the storage
//  (daily_biometrics), and the read path (trends-timeline) were all built for a
//  Garmin-via-Junction producer that has delivered nothing since 2026-04-03.
//  Everything downstream was complete and starved. This reads the same three
//  signals off the watch the athlete is already wearing.
//
//  ── SDNN is not RMSSD ─────────────────────────────────────────────────────
//
//  `.heartRateVariabilitySDNN` is Apple's only HRV type. Garmin reports RMSSD.
//  Different metric, different scale, never poolable. `ingest-biometrics`
//  writes these under source 'healthkit' and `trends-timeline` pins ONE source
//  per window, so the two never meet inside a baseline comparison. The
//  Overnight factor is scale-free (own 28-day baseline, 0.5x own SD), so SDNN
//  works fine — as long as it stays unmixed. See `ingest-biometrics/index.ts`.
//
//  ── What is deliberately not read ─────────────────────────────────────────
//
//  No sleep stages, no efficiency, no "sleep score". Apple exposes stage-level
//  data (.asleepCore/.asleepDeep/.asleepREM) and it is right there. Those are
//  Tier-0 in recovery-trend-v2 §7.4 and were kept out of the schema on purpose.
//  Stages are used HERE only to decide whether a sample counts as asleep at
//  all — never stored, never surfaced.
//

import Foundation
import HealthKit
import Supabase
import os

actor HealthBiometricsSync {
    static let shared = HealthBiometricsSync()

    private let healthStore = HKHealthStore()

    /// Watermark: the last night we successfully pushed. Nil on a fresh
    /// install, which triggers the backfill window below.
    private static let lastSyncedKey = "healthBiometricsLastSyncedDate"

    /// First run pulls two years.
    ///
    /// The Overnight factor only needs ~6 weeks to fire, so this is not about
    /// switching the feature on — it is about what can never be recovered
    /// later. **The first sync sets the watermark**, and every run after it
    /// only reaches back `restatementWindowNights`. So whatever the first sync
    /// skips is skipped for good unless someone clears the watermark by hand.
    /// Apple Health already holds the history; the cost of taking it now is
    /// three chunked requests, and the cost of not taking it is a permanently
    /// truncated baseline.
    ///
    /// Two years also makes the supply side of the recovery-need model
    /// backtestable against real nights — including the July 2026 knee
    /// episode, which is currently the only labelled event in the data.
    private static let backfillNights = 730

    /// Re-push a trailing window every sync, not just new nights. Apple
    /// restates sleep as a watch syncs late, and resting HR for "today" is
    /// recomputed as the day goes on. The upsert is idempotent on
    /// (user_id, date, source), so re-sending is free and keeps late-arriving
    /// samples from being permanently missed by the watermark.
    private static let restatementWindowNights = 7

    /// Set once the backfill window has been walked with HRV actually visible.
    ///
    /// **Why this exists.** The first sync sets the watermark whether or not
    /// HRV was readable, and iOS never reports a denied READ scope — a denied
    /// HRV query returns `[]`, indistinguishable from a watch that recorded
    /// nothing. That is exactly what happened here: 192 nights of resting HR
    /// landed from 2026-01-11 with `hrv_rmssd` empty on every one of them, and
    /// the watermark then capped every later sync at the 7-night restatement
    /// window. Granting the permission afterwards would have filled today
    /// forward and left January–August permanently blank, because Apple Health
    /// holds those samples but nothing would ever ask for them again.
    ///
    /// So the grant must be sufficient on its own. Until this flag is set, each
    /// sync cheaply probes for a single HRV sample; the first one to see any
    /// re-opens the full `backfillNights` window, and the flag is written only
    /// after that wider push succeeds.
    private static let hrvBackfilledKey = "healthBiometricsHRVBackfilled"

    private var isRunning = false

    // MARK: - Entry point

    /// Read the overnight trio and push it. Safe to call on every launch and
    /// on background delivery — it self-throttles, and a failure leaves the
    /// watermark untouched so the next run retries the same nights.
    ///
    /// Silent by design: this is background plumbing, not a user action. A
    /// missing watch, a denied permission, and a signed-out athlete all mean
    /// "nothing to do", not "show an error".
    @discardableResult
    func sync() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        guard !isRunning else { return 0 }
        isRunning = true
        defer { isRunning = false }

        // Cheap "don't bother" check only — it reads a CACHED id, so it is not
        // proof of a usable token. `upload` re-checks against the live session;
        // this guard exists so a signed-out launch doesn't run 730 nights of
        // HealthKit queries just to fail at the last step.
        guard await AuthManager.shared.currentUserId != nil else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let defaults = UserDefaults.standard

        // Window start: the watermark pulled back by the restatement window,
        // or the full backfill on first run.
        //
        // `hrvArrived` overrides the watermark for one sync. It is checked only
        // while the flag is unset, and the probe is a single-sample query, so
        // the steady-state cost once HRV is backfilled — or on a phone-only
        // athlete who will never have it — is one bounded query per launch.
        let fullBackfill = calendar.date(byAdding: .day, value: -Self.backfillNights, to: today) ?? today
        let needsHRVBackfill = !defaults.bool(forKey: Self.hrvBackfilledKey)
        // Not `needsHRVBackfill && await …` — `await` may not sit to the right
        // of a short-circuiting operator, and the probe must stay skipped once
        // the flag is set.
        var hrvArrived = false
        if needsHRVBackfill {
            hrvArrived = await hasAnyHRV(from: fullBackfill, to: today)
        }

        let start: Date
        if let last = defaults.object(forKey: Self.lastSyncedKey) as? Date, !hrvArrived {
            let rewound = calendar.date(byAdding: .day, value: -Self.restatementWindowNights, to: last) ?? last
            start = calendar.startOfDay(for: min(rewound, today))
        } else {
            if hrvArrived {
                Log.health.info("biometrics sync: HRV now readable — reopening the \(Self.backfillNights)-night window")
            }
            start = fullBackfill
        }
        // End of the window is the end of TODAY — last night's sleep is filed
        // under today's date (matching `SleepCheckInPrompt`, which writes the
        // one-tap rating for "last night" under today's local date).
        guard let end = calendar.date(byAdding: .day, value: 1, to: today) else { return 0 }
        guard start < end else { return 0 }

        async let sleepIntervals = mergedAsleepIntervals(from: start, to: end)
        async let restingByDate = dailyRestingHeartRate(from: start, to: end)
        async let hrvSamples = heartRateVariabilitySamples(from: start, to: end)

        let intervals = await sleepIntervals
        let resting = await restingByDate
        let hrv = await hrvSamples

        let nights = buildNights(
            intervals: intervals,
            restingByDate: resting,
            hrvSamples: hrv,
            calendar: calendar
        )
        guard !nights.isEmpty else {
            Log.health.info("biometrics sync: no nights with usable data in window")
            return 0
        }

        do {
            let uploaded = try await upload(nights)
            defaults.set(today, forKey: Self.lastSyncedKey)
            // Only claim the HRV backfill once the FULL window has been walked
            // with HRV actually in hand. A 7-night restatement that happens to
            // carry HRV must not close the door on the two-year history.
            if needsHRVBackfill, start == fullBackfill, nights.contains(where: { $0.hrv_sdnn != nil }) {
                defaults.set(true, forKey: Self.hrvBackfilledKey)
                Log.health.info("biometrics sync: HRV backfill complete")
            }
            Log.health.info("biometrics sync: uploaded \(uploaded) nights")
            return uploaded
        } catch {
            // Watermark deliberately untouched — retry the same window next time.
            Log.health.error("biometrics sync failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Night assembly

    /// One night as we will store it. All three metrics optional: a night the
    /// watch was charging still carries a resting HR worth keeping.
    struct Night: Encodable {
        let date: String
        let hrv_sdnn: Double?
        let resting_hr: Double?
        let sleep_total_min: Int?
    }

    /// A merged span of actual sleep (never "in bed", never "awake").
    struct SleepInterval {
        let start: Date
        let end: Date
    }

    /// Fold the three series onto one row per local date.
    ///
    /// HRV is averaged over the night's OWN sleep interval where one exists —
    /// which is what makes it comparable to Garmin's `average_hrv` (an
    /// overnight mean) rather than a day-average polluted by Breathe sessions
    /// and post-run readings. Nights with no sleep record fall back to a
    /// midnight–08:00 window, which is where a watch worn overnight puts most
    /// of its passive samples anyway.
    private func buildNights(
        intervals: [SleepInterval],
        restingByDate: [String: Double],
        hrvSamples: [(date: Date, value: Double)],
        calendar: Calendar
    ) -> [Night] {
        // Sleep minutes + the night's sleep span, keyed by local date.
        var minutesByDate: [String: Double] = [:]
        var spanByDate: [String: (start: Date, end: Date)] = [:]
        for interval in intervals {
            let key = Self.nightDateKey(for: interval.end, calendar: calendar)
            let minutes = interval.end.timeIntervalSince(interval.start) / 60
            minutesByDate[key, default: 0] += minutes
            if let existing = spanByDate[key] {
                spanByDate[key] = (min(existing.start, interval.start), max(existing.end, interval.end))
            } else {
                spanByDate[key] = (interval.start, interval.end)
            }
        }

        // Every date mentioned by any of the three series.
        var keys = Set(minutesByDate.keys)
        keys.formUnion(restingByDate.keys)
        for sample in hrvSamples {
            keys.insert(Self.nightDateKey(for: sample.date, calendar: calendar))
        }

        var nights: [Night] = []
        for key in keys.sorted() {
            // HRV window: the night's own sleep span where we have one.
            //
            // The fallback spans 18:00 the previous evening → 09:00 this
            // morning, mirroring `nightDateKey`'s 18:00 boundary exactly. A
            // narrower midnight-start window would be inconsistent with it:
            // a 23:00 sample is keyed to THIS date but would fall outside a
            // window that opens at midnight, so it would create a date key and
            // then be excluded from its own average.
            let window: (start: Date, end: Date)?
            if let span = spanByDate[key] {
                window = span
            } else if let midnight = Self.date(fromKey: key, calendar: calendar),
                      let eveningBefore = calendar.date(byAdding: .hour, value: -6, to: midnight),
                      let morning = calendar.date(byAdding: .hour, value: 9, to: midnight) {
                window = (eveningBefore, morning)
            } else {
                window = nil
            }

            var hrvMean: Double?
            if let window {
                let values = hrvSamples
                    .filter { $0.date >= window.start && $0.date <= window.end }
                    .map(\.value)
                if !values.isEmpty {
                    hrvMean = values.reduce(0, +) / Double(values.count)
                }
            }

            let minutes = minutesByDate[key].map { Int($0.rounded()) }
            let resting = restingByDate[key]

            // Mirror the server's rule so we don't ship empty rows over the
            // wire: a date with none of the three is not a night.
            if hrvMean == nil && resting == nil && minutes == nil { continue }

            nights.append(Night(
                date: key,
                hrv_sdnn: hrvMean,
                resting_hr: resting,
                sleep_total_min: minutes
            ))
        }
        return nights
    }

    /// The local date a sleep interval (or overnight sample) belongs to.
    ///
    /// Convention: the date you WOKE UP on. A 23:10 → 06:40 sleep is filed
    /// under the morning date, which is what "last night's sleep" means to the
    /// athlete and what `SleepCheckInPrompt` writes into `daily_checkins` — the
    /// two have to agree or the Sleep factor's self-report preference would be
    /// comparing different nights. Anything ending at/after 18:00 is treated as
    /// the start of the NEXT night rather than a very long lie-in.
    private static func nightDateKey(for end: Date, calendar: Calendar) -> String {
        var anchor = end
        if calendar.component(.hour, from: end) >= 18 {
            anchor = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return dateFormatter.string(from: anchor)
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        guard let parsed = dateFormatter.date(from: key) else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    /// Local-time formatter — `daily_biometrics.date` is a local calendar date,
    /// not an instant. (The repo has been bitten by local-as-UTC once already:
    /// 107 legacy Strava rows sort wrong on multi-run days.)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - HealthKit reads

    /// Actual sleep, with overlaps merged.
    ///
    /// Merging is not optional: an athlete with both an Apple Watch and a
    /// third-party sleep app has two full sets of overlapping samples for the
    /// same night, and naive summing reports ~16 hours of sleep. We union the
    /// spans instead, so double coverage counts once.
    ///
    /// `.inBed` and `.awake` are excluded — reading time and 3am staring do not
    /// count as sleep.
    private func mergedAsleepIntervals(from start: Date, to end: Date) async -> [SleepInterval] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues
        let asleep = samples
            .filter { sample in
                guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
                return asleepValues.contains(value)
            }
            .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }

        // Union of overlapping (or exactly abutting) spans.
        var merged: [SleepInterval] = []
        for interval in asleep {
            if let last = merged.last, interval.start <= last.end {
                if interval.end > last.end {
                    merged[merged.count - 1] = SleepInterval(start: last.start, end: interval.end)
                }
            } else {
                merged.append(interval)
            }
        }

        // Drop micro-fragments. Apple emits brief samples around wake-ups that
        // add noise without adding sleep.
        return merged.filter { $0.end.timeIntervalSince($0.start) >= 300 }
    }

    /// Apple's own daily resting heart rate, one value per local day.
    /// Already a considered daily aggregate — we don't recompute it.
    private func dailyRestingHeartRate(from start: Date, to end: Date) async -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        // Resting HR is stamped to the day it describes, so it keys on the
        // sample's own date — NOT the wake-date shift used for sleep.
        var byDate: [String: [Double]] = [:]
        for sample in samples {
            let key = Self.dateFormatter.string(from: sample.startDate)
            byDate[key, default: []].append(sample.quantity.doubleValue(for: unit))
        }
        return byDate.compactMapValues { values in
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    /// Raw HRV (SDNN, ms) samples with their timestamps — bucketed later
    /// against each night's own sleep window, so this returns them unfolded.
    private func heartRateVariabilitySamples(from start: Date, to end: Date) async -> [(date: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
        let unit = HKUnit.secondUnit(with: .milli)
        return samples.map { (date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Is there ANY HRV sample in the window? One row, no sort, no unit
    /// conversion — this answers "has the permission started producing data",
    /// not "what is it". Deliberately separate from
    /// `heartRateVariabilitySamples` so the per-launch probe never pays for
    /// two years of samples it would immediately discard.
    private func hasAnyHRV(from start: Date, to end: Date) async -> Bool {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return false }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: !(results ?? []).isEmpty)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Upload

    private struct UploadBody: Encodable {
        let nights: [Night]
    }

    private struct UploadResponse: Decodable {
        let upserted: Int?
        let skipped: Int?
        let error: String?
    }

    /// Chunked to stay under `ingest-biometrics`'s 400-night ceiling.
    ///
    /// The Authorization header is set EXPLICITLY rather than left to the SDK.
    /// `sync()` runs from the launch `.task` alongside session restore, and a
    /// cached `currentUserId` outlives an expired or not-yet-restored token —
    /// so the implicit path could send the anon key instead. The anon key is a
    /// structurally valid JWT, so it clears the platform's `verify_jwt` gate
    /// and only fails inside the function, at `auth.getUser`, as a 401. That is
    /// the shape of the 401s seen on 2026-08-06 with `daily_biometrics` empty.
    ///
    /// `supabase.auth.session` refreshes an expired token before returning, so
    /// this both proves and repairs the session. No session means no upload and
    /// no watermark write — the same nights are retried on the next launch.
    private func upload(_ nights: [Night]) async throws -> Int {
        let accessToken: String
        do {
            accessToken = try await supabase.auth.session.accessToken
        } catch {
            throw NSError(
                domain: "HealthBiometricsSync",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey:
                    "no valid auth session (\(error.localizedDescription)) — nothing uploaded, will retry next launch"]
            )
        }

        var total = 0
        for chunk in stride(from: 0, to: nights.count, by: 300).map({ Array(nights[$0..<min($0 + 300, nights.count)]) }) {
            let response: UploadResponse
            do {
                response = try await supabase.functions.invoke(
                    "ingest-biometrics",
                    options: .init(
                        headers: ["Authorization": "Bearer \(accessToken)"],
                        body: UploadBody(nights: chunk)
                    )
                )
            } catch let FunctionsError.httpError(code, data) {
                // `FunctionsError`'s own description is just the status code.
                // Carry the function's `{"error": ...}` body through — the
                // difference between "Authentication required" and a 500 from
                // the upsert is the whole diagnosis, and this path is silent
                // by design, so the log line is the only place it surfaces.
                let detail = String(data: data, encoding: .utf8) ?? "<no body>"
                throw NSError(
                    domain: "HealthBiometricsSync",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: "ingest-biometrics returned \(code): \(detail)"]
                )
            }
            if let error = response.error {
                throw NSError(
                    domain: "HealthBiometricsSync",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: error]
                )
            }
            total += response.upserted ?? 0
        }
        return total
    }
}

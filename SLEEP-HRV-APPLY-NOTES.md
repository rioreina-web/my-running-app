# Sleep + HRV → recovery — apply notes

*Placed 2026-08-04. Follows the repo's `VITAL-GARMIN-APPLY-NOTES.md` convention:
new files are safe/additive; tracked-file edits are shown here to apply by hand.*

Companion design: `outputs/sleep-hrv-recovery-ingestion-spec-2026-08-04.md`.
Evidence base: `docs/specs/recovery-trend-v2-2026-07-27.md`.

Build order: **1 → 2 → 3 → 4 → 5**. You can stop after step 2 and have sleep/HRV
flowing into the DB with nothing else changed. Steps 3–5 put it on the card.

---

## 1. New migrations (additive — just drop them in)

Two new files under `supabase/migrations/`:

- `20260804090000_daily_biometrics.sql` — the device-data table (HRV, resting HR,
  sleep duration). Service-role write, athlete read-only.
- `20260804090100_daily_checkins.sql` — the one-tap self-report table
  (sleep quality). Athlete read/write.

Both are new tables with their own RLS policies (hard rule #1). They touch nothing
existing. Apply with `supabase db push` from a committed SHA (hard rule #9).

While you're pushing: your **stress-load migration `20260731120000` is still
unapplied in production** — this is a good moment to push it too, or the mechanical
and cardiovascular load work keep drifting apart.

---

## 2. Webhook — add the sleep branch (one tracked file)

`supabase/functions/vital-webhook/index.ts`. Insert this block **immediately before**
the workout-event guard. Anchor — this line is currently at index.ts:179–180:

```ts
  const isWorkoutEvent = eventType.endsWith("workouts.created") || eventType.endsWith("workouts.updated");
  if (!isWorkoutEvent) return res(200, { ignored: eventType });
```

Insert directly ABOVE those two lines:

```ts
  // Sleep + HRV -> daily_biometrics. Garmin delivers these on daily.data.sleep.*
  // (backfill included; Garmin uses `daily.`, not `historical.`). Junction restates
  // tentative -> confirmed for the same night, so upsert on the PK and let the
  // confirmed row overwrite the tentative one.
  if (eventType.endsWith("data.sleep.created") || eventType.endsWith("data.sleep.updated")) {
    if (!userId) return res(200, { ignored: "no user mapping", vitalUserId: payload.user_id });
    const d2 = payload.data;
    const sleeps: Record<string, any>[] = Array.isArray(d2) ? d2 : Array.isArray(d2?.sleep) ? d2.sleep : d2 ? [d2] : [];
    let sleepRows = 0;
    for (const s of sleeps) {
      if (!s?.calendar_date) continue;
      const src = s.source ?? {};
      const row = {
        user_id: userId,
        date: s.calendar_date,
        source: "garmin",
        vital_sleep_id: s.id != null ? String(s.id) : null,
        sleep_state: s.state ?? null,                 // 'tentative' | 'confirmed' — confirm on live payload
        hrv_rmssd: typeof s.average_hrv === "number" ? s.average_hrv : null,
        resting_hr: typeof s.hr_resting === "number" ? s.hr_resting : null,
        hr_lowest: typeof s.hr_lowest === "number" ? s.hr_lowest : null,
        sleep_total_min: typeof s.total === "number" ? Math.round(s.total / 60) : null,
        respiratory_rate: typeof s.respiratory_rate === "number" ? s.respiratory_rate : null,
        device_model: src.app_id ?? "Garmin",
        firmware_version: src.firmware_version ?? null,   // confirm field path on live payload
        app_version: src.app_version ?? null,
        updated_at: new Date().toISOString(),
      };
      const { error } = await db
        .from("daily_biometrics")
        .upsert(row, { onConflict: "user_id,date,source" });
      if (error) { console.error(`[vital-webhook] sleep upsert ${s.id}: ${error.message}`); continue; }
      sleepRows++;
    }
    return res(200, { sleep_rows: sleepRows });
  }

```

Redeploy exactly as the workout webhook (the Svix signature check already covers the
new event — no auth change):

```bash
supabase functions deploy vital-webhook --no-verify-jwt
```

Then in the **Junction dashboard**: enable the **sleep** data type on the Garmin
connection, and add `daily.data.sleep.created` + `daily.data.sleep.updated` to the
same webhook endpoint. Tail `supabase functions logs vital-webhook` on the first real
sleep and confirm two field names against the live payload: the restatement field
(`s.state` vs `s.status`) and the firmware path (`s.source.firmware_version`). The rest
(`average_hrv`, `hr_resting`, `hr_lowest`, `total`, `calendar_date`, `id`,
`respiratory_rate`) are confirmed against current Junction docs.

**Stop here for a day.** Verify rows land in `daily_biometrics` for a real athlete
before building any UI on top. Ingestion with no display is a safe, revertible state.

---

## 3. Feed the new data into `TrendsDay`

`RunningLog/RunningLog/Trends/TrendsModels.swift` — add optional fields to the
`TrendsDay` struct (near `mood` / `niggles`, around line 101). All optional: a day
with no watch and no check-in carries none, and it is never fabricated — same contract
as `mood`.

```swift
    /// Nocturnal HRV (rmssd, ms) from daily_biometrics, or nil. Context — never
    /// read on its own or on a single night (see recovery-trend-v2 §2c).
    let hrvRmssd: Double?
    /// Nocturnal resting HR (bpm) from daily_biometrics, or nil. The HRV disambiguator.
    let restingHr: Double?
    /// Total sleep minutes from daily_biometrics, or nil. Tier-3 annotation only.
    let sleepTotalMin: Int?
    /// Self-reported sleep quality for the night, closed vocab, or nil when unrated.
    /// 'rough' | 'ok' | 'good'. The Tier-1 signal.
    let sleepQuality: String?
```

Wherever `TrendsDay` values are constructed from the backing store (the same builder
that fills `mood` from voice logs and `niggles` from `body_mentions`), left-join
`daily_biometrics` on `(user_id, date)` and `daily_checkins` on `(user_id, date)` and
fill these four. Missing rows → `nil`. No other call site changes, because every new
field is optional with a `nil` default behaviour.

---

## 4. Two new ledger factors

`RunningLog/RunningLog/Trends/TrendsSignalModels.swift`. Append these two factors inside
`TrendsRecoveryLedger.ledger(days:at:)`, after factor 5 (`Days on`, ~line 676) and
before the `let raw = base + ...` line. Both obey the existing `Factor` contract and
both degrade to 0-points-with-honest-evidence, exactly like `Mood — not logged today`.

```swift
        // 6 · Overnight — HRV read ONLY paired with resting HR, weekly-aggregated.
        //     Not "HRV": a lone HRV number is uninterpretable (recovery-trend-v2 §2c,
        //     §7.2). Requires >= 5 valid nights in the trailing 7; fewer -> the factor
        //     is absent, not zero. Only ONE of nine HRV x RHR cells subtracts.
        if let overnight = Self.overnightFactor(days: days, at: i) {
            factors.append(overnight)
        }

        // 7 · Sleep — self-reported quality preferred (Tier 1); total sleep time is a
        //     weak Tier-3 fallback. Never sleep stages / score / efficiency (v2 §7.4).
        if let sleep = Self.sleepFactor(days: days, at: i) {
            factors.append(sleep)
        }
```

Then add these two helpers to `TrendsRecoveryLedger` (near `ledger(days:at:)`):

```swift
    // MARK: Overnight (Factor 6)

    /// nil == factor not shown (insufficient nights). Otherwise a Factor whose points
    /// are non-zero ONLY in the one interpretable quadrant: HRV down + resting HR up.
    static func overnightFactor(days: [TrendsDay], at i: Int) -> Factor? {
        let window = Array(days[max(0, i - 6)...i])
        let baseWin = Array(days[max(0, i - 27)...max(0, i - 7)])   // own 28-day baseline

        let hrvNow = window.compactMap { $0.hrvRmssd }
        let rhrNow = window.compactMap { $0.restingHr }
        guard hrvNow.count >= 5, rhrNow.count >= 5 else { return nil }   // >=5 valid nights

        let hrvBase = baseWin.compactMap { $0.hrvRmssd }
        let rhrBase = baseWin.compactMap { $0.restingHr }
        guard hrvBase.count >= 14, rhrBase.count >= 14 else { return nil } // >=2 wks baseline

        // Direction, thresholded at 0.5 x the athlete's OWN between-night SD (SWC).
        func dir(_ now: [Double], _ base: [Double]) -> Int {
            let mNow = now.reduce(0, +) / Double(now.count)
            let mBase = base.reduce(0, +) / Double(base.count)
            let sd = Self.stdev(base)
            guard sd > 0 else { return 0 }
            let delta = mNow - mBase
            if delta >= 0.5 * sd { return 1 }      // up
            if delta <= -0.5 * sd { return -1 }    // down
            return 0                                // flat
        }

        let h = dir(hrvNow, hrvBase)   // HRV direction
        let r = dir(rhrNow, rhrBase)   // resting-HR direction

        // The 3x3 table (v2 §2c), compressed to points.
        switch (h, r) {
        case (-1, 1):   // HRV down, RHR up — the ONE interpretable cell
            return Factor(name: "Overnight", evidence: "7-day HRV down, resting HR up", points: -6)
        case (-1, -1):  // both low — usually adaptation, stay quiet
            return Factor(name: "Overnight", evidence: "HRV & resting HR both low · usually adaptation", points: 0)
        case (1, -1):   // HRV up, RHR down — settled
            return Factor(name: "Overnight", evidence: "overnight numbers settled", points: 3)
        default:
            return Factor(name: "Overnight", evidence: "overnight numbers inside your usual range", points: 0)
        }
    }

    // MARK: Sleep (Factor 7)

    static func sleepFactor(days: [TrendsDay], at i: Int) -> Factor? {
        let day = days[i]

        // Preferred: self-reported quality for the night (Tier 1).
        if let q = day.sleepQuality?.lowercased() {
            switch q {
            case "good":  return Factor(name: "Sleep", evidence: "good · logged", points: 4)
            case "rough": return Factor(name: "Sleep", evidence: "rough · logged", points: -6)
            default:      return Factor(name: "Sleep", evidence: "ok · logged", points: 0)
            }
        }

        // Fallback: total sleep time vs the athlete's own 3-week average. Weak on
        // purpose — single-night TST error is +-83..160 min, so use a 7-day mean and
        // a wide gate, and never react to one night.
        let window = Array(days[max(0, i - 6)...i]).compactMap { $0.sleepTotalMin }
        let base = Array(days[max(0, i - 20)...max(0, i - 7)]).compactMap { $0.sleepTotalMin }
        guard window.count >= 5, base.count >= 7 else {
            return Factor(name: "Sleep", evidence: "not enough sleep data yet", points: 0)
        }
        let mNow = Double(window.reduce(0, +)) / Double(window.count)
        let mBase = Double(base.reduce(0, +)) / Double(base.count)
        let delta = mNow - mBase   // minutes
        if delta <= -45 {
            return Factor(name: "Sleep", evidence: "sleeping ~\(Int(-delta)) min under your average", points: -3)
        } else if delta >= 45 {
            return Factor(name: "Sleep", evidence: "sleeping above your average", points: 2)
        }
        return Factor(name: "Sleep", evidence: "sleep in line with your average", points: 0)
    }

    /// Population SD (n), matches the between-night SD used for the SWC threshold.
    static func stdev(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)
        return v.squareRoot()
    }
```

The clamp (`min(96, max(8, raw))`) is unchanged and still holds — the two factors widen
the range by about -9…+7. The arithmetic line renders itself from the factors array, so
`Starts at 50 − 8 − 4 + 0 − 2 − 5 + 0 + 0 = 31` appears automatically once both factors
are present and quiet.

---

## 5. The one-tap sleep-quality UI

The highest-leverage item in the whole design (v2 §2b: strongest single signal, one
tap, no hardware). A reference SwiftUI control — place it on the Log tab's daily surface
(or wherever mood is captured), styled to match your design register.

```swift
struct SleepQuickRate: View {
    let date: Date                              // the night being rated (local)
    @State private var selected: String?        // 'rough' | 'ok' | 'good'
    @State private var saving = false

    private let options: [(key: String, label: String)] = [
        ("rough", "Rough"), ("ok", "OK"), ("good", "Good"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last night's sleep")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(options, id: \.key) { opt in
                    Button {
                        Task { await save(opt.key) }
                    } label: {
                        Text(opt.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected == opt.key ? .accentColor : .secondary)
                    .disabled(saving)
                }
            }
        }
    }

    private func save(_ quality: String) async {
        selected = quality               // optimistic; it's one tap
        saving = true
        defer { saving = false }

        struct CheckinRow: Encodable {
            let user_id: String
            let date: String
            let sleep_quality: String
            let updated_at: String
        }
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        let row = CheckinRow(
            user_id: currentUserId,      // your existing auth accessor
            date: iso.string(from: date),
            sleep_quality: quality,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await supabase
                .from("daily_checkins")
                .upsert(row, onConflict: "user_id,date")
                .execute()
        } catch {
            Log.app.error("sleep check-in failed: \(error.localizedDescription)")
            selected = nil               // roll back the optimistic tap
        }
    }
}
```

Wire `currentUserId` and `supabase` to your existing accessors (same ones
`SettingsView` uses for the Garmin connect call). One row per night; tapping again
overwrites via the `(user_id, date)` upsert. As soon as this ships, Factor 7 prefers it
over the total-sleep-time fallback automatically — no ledger change needed.

---

## 6. Tests (extend `RunningLogTests/TrendsSignalTests.swift`)

- Overnight: all 9 HRV x RHR combinations return the right points; **only HRV↓/RHR↑ is
  negative** (the regression the design exists to protect). HRV↓/RHR↓ → 0.
- Overnight: 4 valid nights → factor absent; 5 → present. One extreme night never
  flips the factor.
- Sleep: `sleepQuality == "rough"` → −6 regardless of TST. A single 3-hour night inside
  a normal week does not move the 7-day TST mean past the ±45-min gate.
- Missing everything → both factors behave like the existing "not logged" factors, and
  today's score is byte-identical to before this change.
- Clamp: an all-negative week (five existing factors + both new) still floors at 8.
- Webhook: a `tentative` sleep followed by `confirmed` for the same date upserts to one
  row, confirmed wins.

---

## 7. Branch hygiene / known gaps

- The two `.sql` files are new/untracked; commit them on the same branch as the webhook
  edit (a dedicated `sleep-hrv` branch, not folded into unrelated work).
- **Cycle-phase confound is unhandled here.** Factor 6 is honest for men and
  not-currently-cycling users, and systematically confounded for ~half of every cycle
  for others (v2 §3a, §8.3). That's why its weight is a gentle −6. Gating it behind cycle
  capture, or lowering to −4 until then, is the open call in the design doc §8.
- Firmware-drift baseline reset (v2 §3b) is captured in the columns but not yet acted on
  — a later changepoint-detection pass, not needed for first ship.
- `git` writes from the Cowork bridge can hit an `index.lock` warning; run your own
  `git` from Terminal and clear a stale `.git/index.lock` if it complains.

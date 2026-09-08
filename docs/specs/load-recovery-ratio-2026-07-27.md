> ⚠️ **SUPERSEDED, same day, by `recovery-trend-v2-2026-07-27.md`.**
> A literature review run immediately after this draft found the ratio form is not defensible (the ACWR denominator carries no signal; the only RCT was null) and that the signal hierarchy here is inverted — the qualitative stream is the evidenced signal, the biometrics are context. Kept for the Junction API findings in §0 and §4, which still hold. **Do not build from §1–§3.**

# The load–recovery ratio — `C0` detector spec

*2026-07-27 · the recovery trend. Turns six signals (HRV, recovery, mood, niggles, volume, intensity) into one ratio line. Realises the `C0` convergence card already locked in `docs/specs/trends-insights-plan-2026-07-23.md` §10 decision #1, and supersedes the four-separate-cards reading of `outputs/trends-catalog-2026-07-23.md` Group C.*

Companions: `docs/specs/trends-insights-plan-2026-07-23.md` (the function), `outputs/trends-catalog-2026-07-23.md` (the thirteen trends), `outputs/trends-metrics-spec-2026-07-10.md` (formulas), `VITAL-GARMIN-APPLY-NOTES.md` (the Junction ingest this extends).

---

## 0. The finding that shapes this spec

**Garmin's HRV Status and Recovery Time do not come through Junction.** Verified against the Junction OpenAPI spec (682 schemas) and the full 193-event catalog on 2026-07-27: zero occurrences of `hrv_status`, `recovery_time`, or `body_battery` in any resource, field, or event type. `recovery_readiness_score` exists on the sleep summary but documents its sources as Oura, Whoop and Ultrahuman — **it is null on a Garmin-only connection.**

So "HRV status" and "recovery" cannot be *read*. They have to be *computed*, from what Junction does give:

| You asked for | What actually arrives | Where |
|---|---|---|
| HRV status (balanced / unbalanced / low) | Overnight **RMSSD in ms** | `sleep.average_hrv` |
| Recovery / readiness | `sleep.score` (1–100, **Garmin-supported**), `sleep.hr_resting`, `sleep.hr_dip` (**Garmin-only field**), `sleep.efficiency`, `sleep.total` | sleep summary |
| — (bonus) | All-day **stress 0–100** — Garmin is the sole notable provider | `stress_level` timeseries |
| Mood | `training_logs.mood` | already in `TrendsWeekOut.mood` |
| Niggles | `body_mentions` + `severity_hint` | already in `DetectCtx.mentions` |
| Volume × intensity | `intensity_score × duration` weighted minutes | `computeWeightedLoadForLog` |

This is not a downgrade. Computing HRV status against the athlete's *own* rolling baseline is exactly the house rule ("range + confidence, never false precision"), and it's what Garmin does internally anyway. It just means the baseline logic is ours, and it needs ~3 weeks of nights before it can say anything.

---

## 1. The model

Two lines, one ratio.

```
                weekly weighted minutes ÷ own chronic baseline
    R_week  =  ────────────────────────────────────────────────
                geometric mean of recovery ratios (each ÷ own baseline)
```

Both sides are **unitless multiples of the athlete's own normal**, so the ratio is stable, has an honest neutral point at `1.00`, and never divides by something near zero. That last part is why this is a ratio of *baseline-relative percentages* and not a ratio of z-scores — z-scores cross zero, and a ratio that explodes near a mean is not something you put in front of an athlete.

**Reading it:** `R ≈ 1.0` — load and recovery are moving together. `R > 1.15` — load is running ahead of the recovery side. `R < 0.85` — the recovery side is running ahead of the load.

### 1a. Load side

```ts
loadPct(w) = weightedMinutes(w) / chronicWeeklyLoad
```

- `weightedMinutes(w)` = Σ over the week's logs of `computeWeightedLoadForLog(log, features)` — that is `intensity_score × total_duration_seconds / 60`, with the `workout_type × duration` fallback. **Import it from `_shared/weeklyAnalytics.ts`. Do not reimplement.** This is the one number that carries *both* volume and intensity, which is why it's the whole load side.
- `chronicWeeklyLoad` = mean weighted minutes/week over the trailing **8 weeks**, excluding the week being scored. Matches the `chronic_window_days` already used by `athlete_state.load_distribution`.
- Weeks with zero running are held out of the chronic mean, not counted as zero — an injury layoff shouldn't reset the baseline downward and then make the comeback week look like a spike.

### 1b. Recovery side

Five candidate sub-signals. Each becomes a ratio where **higher is better recovered**, each against its own 28-day baseline:

| # | Signal | Source | Ratio (higher = better) | Direction fix |
|---|---|---|---|---|
| r1 | **HRV** | `daily_biometrics.hrv_rmssd` | `exp(mean₇(ln x)) / exp(mean₂₈(ln x))` | none — higher HRV is better |
| r2 | **Resting HR** | `daily_biometrics.resting_hr` | `mean₂₈(x) / mean₇(x)` | **inverted** — lower RHR is better |
| r3 | **Sleep** | `sleep_total_min`, `sleep_efficiency`, `sleep_score` | mean of the available `mean₇ / mean₂₈` | none |
| r4 | **Mood** | `TrendsWeekOut.mood` | `moodShift₇ / moodShift₂₈` | none, after shifting |
| r5 | **Niggle burden** | `DetectCtx.mentions` | `(1 + burden₂₈) / (1 + burden₇)` | **inverted** — fewer/milder is better |
| r6 | **All-day stress** *(optional, v1.1)* | `daily_biometrics.stress_avg` | `mean₂₈(x) / mean₇(x)` | **inverted** |

**Why `ln` for HRV.** RMSSD is log-normally distributed; the sports-science convention is lnRMSSD, and a raw mean lets one good night drag a week. Take the log, average, exponentiate back.

**Mood numeric map** (extends the existing `HEAVY_MOODS` / `LIGHT_MOODS` sets in `detectorsA.ts` — put the map next to them so there's one vocabulary):

```ts
const MOOD_SCORE: Record<string, number> = {
  energized: 2, positive: 1, strong: 1, good: 1,
  neutral: 0,
  flat: -1, tired: -1,
  struggling: -2,
};
// shift into 1..5 before ratioing so the denominator can't hit zero or flip sign
const moodShift = (m: number) => m + 3;
```

**Niggle burden**, weighted by the existing `severity_hint` vocabulary:

```ts
const SEVERITY_WEIGHT: Record<string, number> = { tight: 1, sore: 2, pain: 3, sharp: 4 };
burden(window) = Σ SEVERITY_WEIGHT[m.severity_hint] over mentions in window, per week
// +1 in numerator and denominator so a clean baseline (burden 0) doesn't divide by zero
```

**Combine with a geometric mean**, over whichever sub-signals are present:

```ts
recoveryPct = exp( mean( available.map(Math.log) ) )
```

Geometric because these are ratios: a signal 10% down and one 10% up should cancel to 1.00, which arithmetic averaging doesn't quite give you. It also stops one collapsed signal from dominating.

### 1c. The convergence rule, preserved inside the ratio

The catalog's non-negotiable — *no single biometric ever generates a card* — is not softened by folding the signals into one number. It becomes three gates on `recoveryPct`:

1. **≥2 sub-signals** must be present for the week, or `recoveryPct` is not computed at all (that week is a gap in the line, not a 1.00).
2. **≥1 objective** (r1/r2/r3/r6) **and ≥1 qualitative** (r4/r5) must be present for the card to reach `active`. Objective-only → `quiet`. This is the point of the whole product: Garmin can already tell someone their HRV is down. Only this app can say the logs agree.
3. **≥2 sub-signals must agree in direction** with the divergence before it's called one. A ratio pushed past threshold by r1 alone, with r2–r5 flat, is `quiet`.

---

## 2. Firing rules

Computed weekly over the existing `TrendsWeekOut[]` window.

| Status | Condition |
|---|---|
| `hidden` | < 21 days of `daily_biometrics` rows, **or** < 6 weeks of logs, **or** < 2 sub-signals available |
| `quiet` | Gates met, and either `R` stayed inside `[0.85, 1.15]` all window, or it left the band without convergence (rule 2 or 3 above) |
| `active` — watchful | `R ≥ 1.15` for **2+ consecutive weeks** with ≥2 agreeing sub-signals |
| `active` — positive | Load side up ≥15% over the window **and** `R` held inside the band throughout, with ≥3 sub-signals present |

**Confidence**

| | Requires |
|---|---|
| `high` | ≥4 sub-signals, ≥8 weeks of both sides, ≥28 days of biometrics |
| `medium` | ≥3 sub-signals, ≥6 weeks |
| `low` | 2 sub-signals — the floor |

**Never** render a baseline band from fewer than 21 days (house rule). The 28-day baselines here mean the card is realistically dark for a **full month** after the Garmin connection lands. That is correct and should be designed for, not engineered around — which is the argument for landing the migration and webhook branch now even though the card ships later.

---

## 3. What the card returns

`C0` replaces C1–C4 as the athlete-facing card; the sub-signals become its `evidence`.

```ts
{
  id: "C0",
  group: "C",
  status: "active",
  headline: "Load has been running ahead of recovery for three weeks",
  body: "…",
  evidence: [
    { week: "Jul 13", value: 1.22, label: "load ÷ recovery" },
    { week: "Jul 13", value: 0.94, label: "HRV vs baseline" },
    { week: "Jul 13", value: 1.05, label: "resting HR vs baseline" },
    { week: "Jul 13", value: 0.83, label: "mood vs baseline" },
  ],
  confidence: "medium",
  series: {
    points: [/* R per week */], labels: [/* date_label */],
    unit: "ratio", polarity: "neutral",
    band: { lo: 0.85, hi: 1.15 },
    markerIdx: [/* weeks that fired */],
  },
}
```

### One additive contract change

`TrendSeries` holds a single line; this card wants three (ratio, load, recovery). Add one optional field to `TrendCard` in `contract.ts` — additive, so every existing card still decodes:

```ts
/** Secondary lines drawn behind `series` (load and recovery, for C0).
 *  Optional and additive: a card without overlays renders exactly as today. */
overlay?: TrendSeries[];
```

Swift side: `let overlay: [TrendSeries]?` on `TrendInsightCard` (`Trends/TrendInsightsService.swift:26`, alongside the existing `TrendSeries` at `:55`), defaulted nil. `InsightTrendChart` — which already takes `let series: TrendSeries` — grows an optional overlay array and draws the two faint lines behind the ratio when present. `TrendsInsightsTabView` stays a dumb renderer.

### Copy — three variants, written up front

**active-watchful**

> Your load has run ahead of your recovery for three straight weeks. Weighted minutes are up 18% on your own normal; overnight HRV, resting heart rate and your own logs all moved the other way. Any one of those is noise. Three together is a shape.

**active-positive**

> Volume and intensity both climbed this block — and the recovery side kept pace. HRV stayed inside its band, resting heart rate held, and the mood dots stayed warm. You're absorbing the work, not just surviving it.

**quiet / no-pattern**

> Load and recovery have tracked each other all block — the gap never opened. That's the boring answer, and it's the true one.

**quiet / objective-only** (gate 2 failed — this is the one that keeps the app honest)

> Your overnight numbers dipped this week. Your logs didn't. One signal on its own isn't a pattern here, so this is a note, not a finding.

All four pass the `BANNED_TERMS` lint (`rest`, `ice`, `should`, `must`, `because`, `caused`, `stop running`) — checked. Note the near-misses to keep out of future edits: "you should back off", "the volume caused the dip", "worth a rest week".

---

## 4. Capture — migration + webhook branches

### 4a. `supabase/migrations/2026XXXXXXXXXX_daily_biometrics.sql`

Revised from the plan §6a against the real Junction field names:

```sql
create table daily_biometrics (
  user_id            text not null,
  date               date not null,          -- sleep.calendar_date
  source             text not null,          -- 'garmin'

  -- sleep summary (ClientFacingSleep) — all Junction durations are SECONDS
  vital_sleep_id     text,                   -- sleep.id, for restatement dedup
  sleep_state        text,                   -- 'tentative' | 'confirmed'  (Garmin restates)
  hrv_rmssd          numeric,                -- sleep.average_hrv  (ms)
  resting_hr         numeric,                -- sleep.hr_resting   (bpm)
  hr_dip_pct         numeric,                -- sleep.hr_dip       (Garmin-only)
  sleep_total_min    integer,                -- sleep.total    / 60
  sleep_in_bed_min   integer,                -- sleep.duration / 60
  sleep_efficiency   numeric,                -- sleep.efficiency (%)
  sleep_score        integer,                -- sleep.score (1-100, Garmin-supported)
  respiratory_rate   numeric,

  -- activity summary (ClientFacingActivity)
  resting_hr_day     numeric,                -- activity.heart_rate.resting_bpm  (NESTED)
  steps              integer,

  -- stress_level timeseries, rolled up per local day
  stress_avg         numeric,                -- mean of samples (0-100)
  stress_samples     integer,

  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  primary key (user_id, date, source)
);

alter table daily_biometrics enable row level security;
create policy "owner reads" on daily_biometrics
  for select using (auth.uid()::text = user_id);
-- no client INSERT/UPDATE policy: writes go through the service-role webhook only
create index daily_biometrics_user_date on daily_biometrics (user_id, date desc);
```

RLS lives **in the same migration** (catalog rule), and gets audited against live `pg_policies` after push — append-only migrations can supersede a `CREATE`.

**Upsert semantics matter here.** Three independent events write different column groups to the same `(user_id, date, source)` row. `supabase-js` `.upsert()` compiles to `INSERT … ON CONFLICT DO UPDATE SET <only the provided columns>`, so each branch upserting **only its own columns** merges correctly and never null-stomps a sibling branch's data. Do not build one fat mapper that sends all columns.

### 4b. `vital-webhook` branches

Insert before the `if (!isWorkoutEvent) return res(200, { ignored: eventType })` fall-through in `supabase/functions/vital-webhook/index.ts`. Reuse `verifySvix` and the existing service-role client verbatim — same function, same auth, no new endpoint.

```ts
// Summary events: the object sits at $.data
if (/daily\.data\.sleep\.(created|updated)$/.test(eventType))     → toSleepRow(payload.data)
if (/daily\.data\.activity\.(created|updated)$/.test(eventType))  → toActivityRow(payload.data)
// Timeseries events: samples are one level deeper at $.data.data[]
if (/daily\.data\.stress_level\.(created|updated)$/.test(eventType)) → rollupStressByDay(payload.data.data)
```

Four things that will bite if they're not handled at write time:

1. **Payload depth differs.** Summary resources (`sleep`, `activity`) put the object at `$.data`. Timeseries resources (`stress_level`, `hrv`) put samples at **`$.data.data[]`** with `$.data.source` alongside. One shape assumption for both is a silent no-op.
2. **Garmin restates sleep.** Expect `daily.data.sleep.created` with `state: "tentative"`, then `.updated` events with the *same* `sleep.id`, eventually `confirmed`. Upsert on the primary key and store `sleep_state`; **the detector reads `confirmed` rows only.**
3. **Garmin's backfill arrives on the `daily.` branch, not `historical.`** Junction fires `historical.data.*.created` immediately on connect, but for Garmin there is no historical data behind it — everything, including backfill, streams in as `daily.data.*` events. This is documented as Garmin-exclusive behaviour. It's good news: baselines accrue faster than the calendar suggests.
4. **Stress volume.** Garmin samples stress ~every 15 min (~96/day). Roll up to a daily mean at write time and store the mean plus the sample count. Do not persist raw samples — 35k rows/user/year for a number this card uses once.

Also worth knowing: `daily.` is Junction's own documented misnomer — it means *incremental*, not once-a-day. Branches must be idempotent, which the upsert already gives.

### 4c. `DetectCtx` additions

```ts
export interface DetectCtx {
  weeks: TrendsWeekOut[];
  mentions: TimelineMention[];
  streamRuns: StreamRun[];
  /** NEW — confirmed daily rows in window, ascending by date. Empty until the branch lands. */
  daily: DailyBiometricRow[];
  /** NEW — weighted minutes per week, index-aligned to `weeks`. */
  weeklyLoad: number[];
}
```

`weeklyLoad` is a small but real gap: `TrendsWeekOut` carries `miles` and `quality_miles` but no weighted load, which is why `detectA2` currently proxies effort with `miles` even though the plan specifies Effort. `index.ts` already fetches both `logs` and `features` to build the timeline — so it can compute `weeklyLoad` in the same pass via `computeWeightedLoadForLog` with no extra query. **A2 should then switch to it too**; that's the intensity half of "volume × intensity", and today it's missing from both detectors.

---

## 5. Files

```
supabase/migrations/2026XXXXXXXXXX_daily_biometrics.sql   NEW
supabase/functions/vital-webhook/index.ts                 EDIT  (3 branches + 3 mappers)
supabase/functions/trends-insights/detectorsC.ts          REWRITE (replaces scaffoldC)
supabase/functions/trends-insights/recovery.ts            NEW  (pure ratio math)
supabase/functions/trends-insights/recovery.test.ts       NEW
supabase/functions/trends-insights/detectorsC.test.ts     NEW
supabase/functions/trends-insights/contract.ts            EDIT  (+ overlay?, + DailyBiometricRow, + ctx fields)
supabase/functions/trends-insights/index.ts               EDIT  (fetch daily, compute weeklyLoad)
supabase/functions/trends-insights/detect.ts              EDIT  (detectC0 replaces scaffoldC)
RunningLog/RunningLog/Trends/TrendInsightsService.swift   EDIT  (+ overlay? on TrendInsightCard)
RunningLog/RunningLog/Trends/InsightTrendChart.swift      EDIT  (draw overlay lines behind `series`)
```

(The plan doc points at `TrendsModels.swift` / a `TrendInsightsList` view — both moved. The card model and `TrendSeries` now live in `TrendInsightsService.swift`, the chart in `InsightTrendChart.swift`, and the list is `TrendsInsightsTabView.swift`. Worth fixing in the plan doc while you're in there.)

`recovery.ts` holds every formula as a pure function so the detector stays declarative:

```ts
lnMean(xs: number[]): number | null
ratioVsBaseline(recent: number[], base: number[], invert?: boolean): number | null
moodRatio(weeks: TrendsWeekOut[], recentIdx, baseIdx): number | null
niggleRatio(mentions: TimelineMention[], recentDays, baseDays): number | null
recoveryPct(parts: (number|null)[]): { value: number; n: number } | null   // geometric mean
loadPct(weeklyLoad: number[], idx: number): number | null
loadRecoveryRatio(ctx: DetectCtx): { r: number[]; contributors: …[] }
```

No `Date.now()` anywhere — window anchoring comes from the request and row dates, same as every other detector.

---

## 6. Tests

Unit tests only. No LLM in the path, so no eval cassette and `.github/scripts/check_eval_coverage.py` doesn't fire.

- `lnMean` — log-normal handling; one outlier night doesn't drag the week.
- `ratioVsBaseline` — inversion correct for RHR and stress (elevated → ratio < 1).
- `recoveryPct` — geometric mean; +10% and −10% cancel to 1.00; nulls skipped, not zeroed.
- Zero-guards — `burden = 0` baseline, single-mood week, empty biometrics; every one returns `null`, never `NaN`/`Infinity`.
- Convergence gates — objective-only week → `quiet`; one-signal divergence → `quiet`; 2 agreeing + 1 qualitative → `active`.
- Gate boundaries — 20 days of biometrics → `hidden`, 21 → alive.
- Restatement — a `tentative` row is excluded and doesn't move the ratio.
- Layoff — a zero-running week is held out of the chronic mean, so the comeback week isn't a false spike.
- `BANNED_TERMS` lint across all four copy variants (extend the existing `detectorsA.test.ts` case).

---

## 7. Sequence

1. **This week** — migration + the three webhook branches. Nothing user-facing; baselines start accruing, and the 21-day gate starts its clock. This is the only step with a calendar dependency, so it goes first.
2. **Alongside** — `recovery.ts` + tests against hand-built fixtures. Needs no live data.
3. **+3 weeks** — wire `detectC0` into `detect.ts`, ship `overlay` through the contract and Swift, unhide behind the gates.
4. **Later** — r6 (all-day stress) once the rollup has a month behind it; it's the one signal with no precedent in the existing detectors.

---

## 8. Open questions

1. **`sleep.score` inside r3, or on its own?** It's Garmin's own composite, so folding it into the sleep ratio double-counts duration and efficiency. Leaning: use `sleep_score` **only** when `sleep_total_min`/`sleep_efficiency` are missing, rather than averaging all three.
2. **Which resting HR?** `sleep.hr_resting` (overnight) and `activity.heart_rate.resting_bpm` (all-day) both arrive. Overnight is the cleaner training signal; leaning overnight, with the daily value as fallback only.
3. **Band width.** `[0.85, 1.15]` is a starting guess, not a derived number. It wants calibrating against real data once a month of biometrics exists — worth logging `R` before the card ever renders so the threshold is set from your own distribution rather than a round number.
4. **Does `C0` supersede C1–C4 entirely, or do they stay reachable?** This spec assumes superseded — one card, sub-signals as evidence, per the locked decision. If the Trends tab later wants per-signal drill-downs, they come back as a detail view under `C0`, not as four peers in the list.

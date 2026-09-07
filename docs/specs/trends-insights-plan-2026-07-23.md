# `trends-insights` — engineering plan

*2026-07-23 · turns `trends-catalog-2026-07-23.md` (13 trend cards) into a buildable architecture. Companion to `docs/specs/trends-tab-data-wiring.md` (the `TrendsWeek` pipeline this reuses) and `outputs/trends-metrics-spec-2026-07-10.md` (the metric formulas).*

Detection lives in a **new `trends-insights` edge function**, sibling to `trends-timeline`, not folded into it. Rationale: `trends-timeline` builds the chart substrate (`[TrendsWeek]`); `trends-insights` reads that substrate plus raw signals and emits narrative cards. Separating them keeps the timeline's tested week-bucketing untouched, lets the card surface evolve on its own cadence, and matches the catalog's "one home for the math, no Swift drift" note.

---

## 1. Decisions locked in this plan

| Decision | Choice | Why |
|---|---|---|
| Detection home | New `trends-insights` fn | Isolate card logic from chart substrate; own test suite; no LLM. |
| Reuse timeline math | Import `buildTrendsTimeline` + `_shared` utils | No re-query, no re-bucket, no duplicated Effort/quality-pace logic. |
| Auth pattern | `requireAuthOrServiceRole` + service-role client | Match shipped `trends-timeline`, **not** the caller-JWT design in the wiring spec §5 (that decision was already made in code). |
| LLM in detection | None | Pure TS math → unit tests only, no eval cassette. Card prose is templated. If prose ever goes LLM, that prompt enters the eval gate separately. |
| Card contract | `{ id, group, status, headline, body, evidence, confidence }` | Straight from catalog "Card contract"; view stays a dumb renderer. |
| Group C storage | New `daily_biometrics` table + `vital-webhook` branch | Only new capture in the whole plan; append-only upsert. |
| iOS wiring | New parallel call in `TrendsService`, new `TrendInsightCard` model, dumb card list | Same seam as `[TrendsWeek]`; views untouched. |

---

## 2. Function layout

```
supabase/functions/trends-insights/
  index.ts            # IO: CORS, auth, queries, orchestration, response
  contract.ts         # TrendCard type, TrendStatus, Evidence, Confidence; gate helpers
  detect.ts           # registry: run enabled detectors, apply gates, sort, return TrendCard[]
  detectorsA.ts       # A1 A2 A3   (pure; run on TrendsWeek + rows)
  detectorsB.ts       # B1..B5     (pure; run on per-second streams)
  detectorsC.ts       # C1..C4 + convergence (pure; run on daily_biometrics)
  streams.ts          # per-second stream helpers (pace-band bucketing, half-split, fade, HRR60)
  detectorsA.test.ts
  detectorsB.test.ts
  detectorsC.test.ts
  streams.test.ts
```

Every detector is a **pure function** `(ctx: DetectCtx) => TrendCard` — no IO, no `Date.now()`. `index.ts` gathers `ctx` once and hands the same object to all detectors. Each detector owns its own gate and returns a card with `status: hidden | quiet | active`; `index.ts` never decides visibility.

### `index.ts` responsibilities (mirrors `trends-timeline/index.ts`)

1. `OPTIONS` → `corsHeaders`; parse `{ user_id?, weeks? }`; `requireAuthOrServiceRole`.
2. Build the shared substrate by calling the **exported** `buildTrendsTimeline(input, weeks)` from `../trends-timeline/timeline.ts` — reuse, don't refetch differently. (Refactor note in §7.)
3. Fetch the extra raw signals detectors need that the timeline drops on the floor: full `body_mentions` rows (not just distinct labels), `workout_features` per log, `external_streams` per running log (Group B), `daily_biometrics` (Group C), `athlete_state.data_depth` + `pace_zones`.
4. Assemble `DetectCtx`, run `detect.ts`, return `{ cards: TrendCard[], generated_at }`.

### `detect.ts`

```ts
const DETECTORS = [detectA1, detectA2, detectA3,
                   detectB1, detectB2, detectB3, detectB4, detectB5,
                   detectC1, detectC2, detectC3, detectC4];

export function runDetectors(ctx: DetectCtx): TrendCard[] {
  const cards = DETECTORS.map(d => d(ctx));
  const converged = applyConvergence(cards, ctx);   // Group C gating (§6)
  return converged
    .filter(c => c.status !== "hidden")              // hidden never leaves the server
    .sort(byGroupThenConfidence);
}
```

---

## 3. Card contract

### TypeScript (`contract.ts`)

```ts
export type TrendGroup = "A" | "B" | "C";
export type TrendStatus = "hidden" | "quiet" | "active";
//  hidden → below data gate, never sent
//  quiet  → gate met, no pattern → the honest "no-pattern" sentence
//  active → pattern fired

export interface Evidence { week: string; value: number; label?: string }

export interface TrendCard {
  id: string;                 // "A1", "B3", …
  group: TrendGroup;
  status: TrendStatus;
  headline: string;           // one line, editorial voice
  body: string;               // 1–2 sentences, feeling-before-math
  evidence: Evidence[];       // chart-pluckable points; may be []
  confidence: "low" | "medium" | "high";
}
```

Rules the contract enforces (house rules → code):
- **Range + confidence, never false precision** → numeric copy renders bands/directions; `confidence` always set.
- **Verbatim niggles** → any body mention in `body` is copied from `body_mentions.verbatim_quote`, never re-worded.
- **Absence is honest** → `quiet` is a first-class status with real copy, not an empty card.
- **Detection not diagnosis** → detectors emit observation strings only; a lint test (§7) fails the build on banned verbs (`rest`, `ice`, `should`, `because`).

### Swift (`RunningLog/RunningLog/Trends/TrendsModels.swift`)

```swift
struct TrendInsightCard: Identifiable, Decodable {
    let id: String            // "A1"
    let group: String         // "A"|"B"|"C"
    let status: String        // "quiet"|"active"  (hidden filtered server-side)
    let headline: String
    let body: String
    let evidence: [TrendEvidence]
    let confidence: String
}
struct TrendEvidence: Decodable { let week: String; let value: Double; let label: String? }
```

---

## 4. Group A — ship now (existing `TrendsWeek` pipeline)

Runs entirely on data populated today. `ctx` supplies `weeks: TrendsWeek[]`, `mentions: BodyMentionRow[]`, `features: Map<logId, WorkoutFeaturesRow>`, `moodByWeek`.

| Trend | Detector | Inputs | Fires when | Gate |
|---|---|---|---|---|
| **A1** body talks back to load | `detectA1` | `mentions`, weekly `miles`, weekly Effort | 2+ mentions of same `body_area` land in weeks whose miles/Effort are top-third of window **or** ≥15% above trailing-4wk avg | ≥6 wks logs **and** ≥2 body mentions |
| **A2** felt harder than measured | `detectA2` | weekly Effort (`weeklyAnalytics.computeWeightedLoadForLog`), `mood`, `cleaned_notes` | 3+ consecutive sessions **or** 2+ consecutive weeks pairing low/mod measured Effort with `tired`/`struggling` mood | ≥3 sessions with both mood + Effort |
| **A3** engine growing under fatigue | `detectA3` | slope of `key_pace_sec`, slope of `miles`, modal `mood` | pace slope faster **and** volume slope flat-or-up; then split copy by modal mood (warm→absorbing, tired→paying) | ≥4 wks with a `key_pace_sec` value |

Effort per the metrics spec = `intensity_score × total_duration_seconds` via `computeWeightedLoadForLog` — **do not reimplement**; import it. A1/A2's "high-load" and "low-to-moderate" thresholds compute off that weighted-minutes series, one home for the number.

Each A-detector ships **three copy variants** written up front (catalog "Copy variants" rule): active-positive, active-watchful, quiet/no-pattern. Example A1 quiet: `"Your niggles don't track your mileage — mentions land in easy weeks as often as hard ones. That's reassuring, and it's real."`

---

## 5. Group B — as streams accumulate (per-second `external_streams`)

`external_streams` is a **JSONB column on `training_logs`** (not a table), Strava-shaped: `streams.{ time, heartrate, velocity_smooth, cadence, altitude, temp, watts }`. `ctx` supplies `streamRuns: { logId, date, type, streams }[]` for running logs in-window. All per-second math lives in `streams.ts` so detectors stay declarative and testable.

`streams.ts` helpers:

```ts
paceBandMeanHR(streams, band)          // B1/B4: mean HR for seconds inside a pace band
decoupling(streams)                     // B2: (HR÷pace second-half) ÷ (first-half) − 1
cadenceFade(streams)                    // B3: mean cadence(final third) − mean cadence(first third)
hrr60ByRep(streams, laps)               // B5: HR(rep end) − HR(rep end + 60s), avg per session
```

| Trend | Detector | Extra input | Gate |
|---|---|---|---|
| **B1** same pace, fewer beats | `detectB1` | most-populated easy pace-band, mean HR/band/week | ≥4 wks with enough easy seconds in one shared band |
| **B2** drift inside the long run | `detectB2` | per long/steady run decoupling, trended | ≥4 long/steady runs with HR+velocity |
| **B3** form gets quiet when tired | `detectB3` | weekly `cadenceFade` cross-refd against `body_mentions` same/next week | ≥4 wks cadence data **and** ≥1 mention |
| **B4** heat costing you less | `detectB4` | B1 restricted to runs `temp > ~70°F` | ≥3 hot-day runs in a shared band (seasonal) |
| **B5** how fast you bounce back | `detectB5` | `hrr60ByRep` using `running_workout_laps` rep bounds + `external_streams.heartrate` | ≥3 rep sessions with HR streams |

Reps come from `running_workout_laps` (`is_rest`, `stream_start_index`/`stream_end_index`) and the existing `_shared/workoutSegmentation.ts` (`segmentFromLaps`) — no new rep parser. **Watch-outs from the catalog are code, not comments:** B1 excludes hot days (or pairs with B4); every band comparison requires a minimum seconds-in-band count or the week is skipped (`quiet`, never a thin claim).

---

## 6. Group C — after the webhook branch + baseline accrual

Only part of the plan that needs new capture. Three pieces: a migration, a `vital-webhook` branch, and convergence-gated detectors.

### 6a. Migration `supabase/migrations/2026XXXXXXXXXX_daily_biometrics.sql`

```sql
create table daily_biometrics (
  user_id            text not null,
  date               date not null,
  hrv_rmssd          numeric,
  resting_hr         numeric,
  sleep_duration_min integer,
  sleep_efficiency   numeric,
  respiratory_rate   numeric,
  stress_avg         numeric,
  source             text not null,
  created_at         timestamptz default now(),
  primary key (user_id, date, source)
);
alter table daily_biometrics enable row level security;
-- owner reads; service-role writes only (mirror body_mentions RLS)
create policy "owner reads" on daily_biometrics for select using (auth.uid()::text = user_id);
-- no client INSERT policy → writes go through service-role webhook
```

Append-only via `upsert` on `(user_id, date, source)`. RLS **in the same migration** (per catalog + the RLS-verify principle — audit against live `pg_policies` after push, since append-only migrations can supersede `CREATE`).

### 6b. `vital-webhook` branch

Today the webhook returns `200 { ignored: eventType }` for anything not `workouts.*`. Add a branch before that fall-through for `daily.data.sleep.created` / `daily.data.hrv.created` / `activity` daily events, mapping Junction fields → a `daily_biometrics` upsert. Reuse the existing `verifySvix` plumbing and service-role client verbatim — same function, same auth, one new mapper `toDailyBiometrics(event)`. No new endpoint.

### 6c. Detectors + convergence rule (non-negotiable)

`ctx.daily: DailyBiometricRow[]`. Each C-detector computes its own signal against the athlete's **own baseline** (7d vs 28d), rendered as a band, never a score.

| Trend | Signal | Fires |
|---|---|---|
| **C1** HRV vs own baseline | 7d HRV avg below 28d normal range | **4–5+ consecutive days** sustained |
| **C2** resting-HR drift | 7d RHR vs 28d baseline | sustained ≥3–4 bpm, esp. with same-week volume spike |
| **C3** sleep under big days | sleep duration prior 1–2 nights, landed-vs-struggled sessions | pattern holds across ≥6–8 sessions |
| **C4** stress vs training load | weekly mean daytime stress vs weekly Effort | divergence: modest load + high stress + `struggling` mood |

**`applyConvergence(cards, ctx)`** — the gate that makes Group C safe:
- A lone C-signal is forced to `status: "quiet"` (renders in the chart, says nothing).
- A C-card only reaches `active` when **2+ independent signals agree** — including the qualitative stream. Concretely: count agreeing signals among {C1 suppressed, C2 elevated, C3 short-sleep, C4 high-stress, mood `tired`/`struggling`}; `active` requires ≥2.
- When ≥2 agree, optionally emit a single synthesized **convergence card** (`id: "C0"`) with the catalog's convergence copy, and downgrade the constituents to evidence.
- Whole group stays hidden until baselines are **3–4 weeks deep** (`data_depth` + a `daysOfBiometrics` gate).

---

## 7. Cross-cutting

**Refactor to enable reuse.** `buildTrendsTimeline` currently returns only `TrendsWeekOut`. Extend `trends-timeline/timeline.ts` to also export the intermediate `body_mentions` rows and per-log `workout_features` it already fetched (or export a `buildDetectCtx` that returns both the weeks and the raw rows). One fetch, two consumers. Keep `TrendsWeekOut` byte-identical so the chart is untouched.

**Data gates.** Every detector declares its minimum-data gate and returns `hidden` below it (`data_depth` from `athlete_state`, plus per-trend counts). Never render a baseline band from < ~21 days. `index.ts` filters `hidden` before responding.

**Detection-not-diagnosis lint.** A `detectorsA/B/C.test.ts` case asserts no card `body`/`headline` contains banned tokens (`rest`, `ice`, `should`, `must`, `because`, `caused`). Cheap guard against prose drift.

**No `Date.now()`.** "Today"/window anchoring comes from the request (`weeks`) and row dates, same as `trends-timeline`. Keeps detectors pure and testable.

**Tests, no eval.** Per-detector unit tests with hand-built `ctx` fixtures (Deno test style, like `timeline.test.ts`). No eval cassette — no LLM in the path. `check_eval_coverage.py` does not fire on this function.

---

## 8. iOS wiring (dumb renderer, unchanged seam)

- `TrendsService` (`@Observable`) adds a second fetch to `trends-insights` (parallel to the existing `trends-timeline` call in the `.task` on tab 4), decodes `[TrendInsightCard]`.
- New view `TrendInsightsList` under `RunningLog/RunningLog/Trends/` renders cards top-to-bottom: `active` full, `quiet` muted single-line, filtered `hidden` never arrives. Pure renderer over `[TrendInsightCard]` — no logic.
- Empty/gate states reuse `Shared/EmptyStateView.swift` behind `data_depth` (same pattern as `TrendsTabView.content`). A group with all-hidden cards shows nothing, not a placeholder.
- `TrendsSampleData` gains a few sample cards for previews.

---

## 9. Rollout sequence

1. **Now** — scaffold `trends-insights` (index + contract + detect), refactor `buildTrendsTimeline` to expose raw rows, ship **A1–A3** with three copy variants each + unit tests. iOS `TrendInsightsList` renders Group A.
2. **As streams accumulate** — land `streams.ts` + **B1, B2, B5**; each gated on its minimum (e.g. B2 ≥4 long runs). **B3** once cadence + mentions overlap. **B4** seasonally (hot-day filter). Cards light up per-athlete as data crosses gates — `log()` nothing dropped silently.
3. **Next, in parallel** — write the `daily_biometrics` migration + `vital-webhook` branch **now** so C-group baselines start accruing immediately. Keep C-cards `hidden` until baselines are 3–4 weeks deep, then unhide behind the convergence rule.

---

## 10. Resolved decisions (2026-07-23)

1. **Convergence card vs constituents** — ✅ **One synthesized `C0` card.** When ≥2 C-signals agree, emit a single convergence card; demote C1–C4 constituents to its evidence. Avoids reading as four separate single-biometric alarms — the exact failure the convergence rule exists to prevent.
2. **Response shape** — ✅ **Separate `trends-insights` response.** `{ cards, generated_at }` on its own endpoint; iOS fires it in parallel with `trends-timeline`. Cards evolve independently of the chart substrate; the two functions stay decoupled.
3. **Copy authorship** — ✅ **Templated TS strings now.** Deterministic, unit-testable, no eval cassette. Door left open to move card prose behind the LLM eval gate later (that prompt would enter the eval gate separately).

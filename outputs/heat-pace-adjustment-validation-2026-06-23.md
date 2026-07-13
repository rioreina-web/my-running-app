# Heat → pace adjustment: validation, refinement, and rollout plan — 2026-06-23

## Framing (updated 2026-06-23, Rio): data for analysis, not strict rules

This is **not** a strict pace-correction engine. The goal is to **capture the
conditions a session was run in — heat, humidity, elevation/grade — and surface
them as descriptive context** so the analysis layer (Coach Read, workout
insight, fitness trend) can *learn and reason* about how the weather and terrain
shaped the run. The heat formula below is a **reference estimate + a surfacing
flag**, one input the analysis can lean on — never a mandate that rewrites the
athlete's numbers. (Matches "AI advises, never acts" and the Coach voice:
reads life context, never explains the math.)

Practical consequences:
- Store conditions per workout/lap as **data** (temp, dew, humidity, wind,
  elevation gain, per-bout grade) + the model's *estimate* ("heat ≈ +18 s/mi").
- Feed that context into the analysis prompts so the coach can say things like
  "that easy run was at a 72°F dew point — the pace is honest for the effort,"
  in its own voice — not assert a corrected split.
- `heatSurfacing` decides whether it's even worth mentioning; the *magnitude* is
  a soft reference, shown as a range, not a single corrected pace.

## TL;DR

The heat model ("Emy's Calculator", `_shared/pace-heat-adjustment.ts`) is
**sound** — it's a faithful, slightly conservative implementation of a
well-established coaching standard. Shipped this round: a **rep-length scaling**
refinement (Rio's rule) so short interval reps aren't over-penalized, with tests.
Still to do: it isn't *wired* (no weather data is captured), so it currently has
zero effect on real workouts; and feeding it into the fitness trend is a separate
build.

## 1. Validation vs. research

The model: `dpMultiplier = 1 + max(0,(dew−55)×0.003495)`; `composite = temp +
dew×dpMultiplier`; interpolate composite → adjustment %; `adjusted = pace ×
(1 + %)`.

Compared against the canonical **Hadley "temperature + dew point" chart**
(maximumperformancerunning), which our table is based on:

| Temp+Dew (Hadley sum) | Hadley % | Emy's table @ that score |
|---|---|---|
| ≤100 | 0% | 0% |
| 131–140 | 2.0–3.0% | 2.1% |
| 141–150 | 3.0–4.5% | 3.0% |
| 151–160 | 4.5–6.0% | 4.5% |
| 171–180 | 8.0–10.0% | 9.0% |
| >180 | "not recommended" | 12% (flagged `dangerous`) |

Emy's table takes the **low-to-mid of each Hadley range** → slightly
conservative. The `dpMultiplier` makes it weight dew point a touch more than a
plain sum (correct — dew point matters more to runners than air temp). This is
consistent with **Jack Daniels' VDOT** heat guidance and **Runner's Connect**
dew-point research. The **El Helou (2012)** marathon study independently confirms
air temperature is the dominant environmental driver of running performance.

**Verdict: keep the model.** Three refinements identified:

1. **Rep-length scaling** — the table is for *continuous* running (~1.5 mi+).
   Hadley explicitly says use *half* for repeats. **DONE this round** (see §2).
2. **Acclimatization / personalization** — a static table can't know a runner
   is heat-adapted (summer-trained Austin runner is affected less than the table
   says). Address later via the empirical per-athlete calibration (§4).
3. **Express uncertainty** — Hadley gives *ranges* because individual factors
   vary. Consider surfacing the adjustment as "~+15–20 sec/mi" rather than a
   false-precision single number (matches the product's range+confidence ethos).

## 2. Rep-length scaling (shipped)

Decision (Rio): the adjustment is best for **≥1.5 mi continuous**; **≤0.75 mi**
uses **half**; **0.75–1.5 mi ramps linearly from half to full**. Applied per bout.

Implemented in `_shared/pace-heat-adjustment.ts`:
- `repLengthFactor(distanceMiles)` → 0.5 ≤0.75mi, ramp to 1.0 at 1.5mi, 1.0 ≥1.5mi (1.0 when length unknown = continuous).
- `adjustPace(pace, temp, dew, distanceMiles?)` now returns `repLengthFactor`,
  `effectiveAdjustmentPercent` (= raw × factor), and the scaled seconds.
- `heatAdjustmentPct(temp, dew)` helper for the fitness signal (continuous basis).
- Tests in `pace-heat-adjustment.test.ts` — 7 passing (factor curve, half-penalty
  for a 600m rep, ~0.667 for a 1mi rep, ideal=no-op, Austin ballpark).

### 2.1 Surfacing gate (shipped)

Decision (Rio): only "call" the adjustment when it's genuinely warm; below that,
at most mention it. Implemented as `heatSurfacing(tempF, dewF)`:
- **apply** — dew point ≥ 68°F (or a hot/dry backstop, composite ≥ 150): change
  the pace and show it.
- **mention** — dew point 60–67°F (mildly humid, or composite ≥ 130): note the
  conditions, no pace change.
- **none** — cool & dry: say nothing.

`buildWeatherJson` now carries a `surfacing` field so the UI/coach knows which of
the three to do without re-deriving it. Tested.

**Sync TODO:** `RunningLog/.../Workouts/PaceCalculator.swift` is the original
source of this math (the TS was ported from it). Mirror `repLengthFactor` there
so iOS and backend don't drift — but note iOS mostly uses the *continuous* path
(pace-zone display), so this is low-risk to defer briefly.

## 3. Your run this morning (activity 19035729944)

Start location was **Austin, TX (30.29, −97.69)**, ~6:27am, late June. I couldn't
fetch the exact archived weather (the fetch tool kept timing out), but a typical
Austin June dawn (~76°F air / ~72°F dew) gives composite ≈ 152 → **~4–5%, i.e.
roughly +15–20 sec/mi on a continuous easy/tempo effort**, and about half that on
the short interval reps. So yes — heat materially affected this run, even though
the app showed nothing (the heat columns are null — see §4). Exact number pending
the live pipeline.

## 4. Why it currently does nothing — and the rollout

The math is solid but **no weather is ever captured**, so every heat column on
`running_workout_laps` is null and the HEAT-ADJ toggle is dead. To make it real:

### BUILT 2026-06-23 (pipeline wiring — code complete, deploy pending)

The capture pipeline + insight context are now wired in `main`:

- **`fetch-workout-weather/index.ts`** (rewritten in main): added a
  `{ training_log_id }` mode that locates a run from its **own GPS** (the
  `latlng` stream) and writes `training_logs.weather_actual` via Open-Meteo
  (no API key). Repointed all location lookups off the dead `user_profiles`
  onto `athlete_settings`; fixed local-hour handling; switched to
  `requireAuthOrServiceRole`. Other modes (single-point, forecast_week,
  refresh_one, backfill_actuals) preserved.
- **`strava-sync/index.ts`**: fires `fetch-workout-weather` (fire-and-forget,
  like `fireParseStructure`) on every imported run — both the new-insert and
  streams-just-landed paths.
- **`generate-workout-insight/index.ts`**: the conditions block now reads
  `weather_actual` and injects the dew-point heat read as **descriptive
  context** — temp/dew/category + "conditions cost ~X% continuous, ~half on
  short reps," explicitly told to read paces as honest-for-effort, *not* to
  restate corrected splits. `surfacing` gates apply/mention/none.
- All three `deno check` clean; heat module tests green (8).

**Deploy + activate (team — per hard rules, not done here):**
- [ ] `supabase functions deploy fetch-workout-weather strava-sync generate-workout-insight` from a committed SHA.
- [ ] Back-fill: invoke `fetch-workout-weather { kind:"backfill_actuals", days:90 }` per athlete (uses each run's GPS) to populate `weather_actual` on existing runs — this also unblocks the empirical check (#7).
- [ ] Spot-check today's run (activity 19035729944) gets `weather_actual` ≈ 78°F / 74°F dew, "very hot", and the next insight mentions it.

**Still raw (next):** per-lap `temp_f`/`dew_point_f`/`heat_adjusted_pace_sec_per_mile`
columns (the iOS HEAT-ADJ toggle) are still null — the insight path doesn't need
them, but turning on the toggle means computing per-lap adjusted pace at capture
time. Separate increment.

### (original plan, for reference) (A) Make it run [task #8, partially done]
- Math module is now in `main` and improved. ✅
- Still need: bring `fetch-workout-weather/index.ts` + `_shared/weather.ts` out
  of `.perf-worktree` into `main`, and fire it (fire-and-forget) from
  `strava-sync` right after a run is inserted — mirroring `fireParseStructure`.
  It should write temp/dew per lap and the heat-adjusted pace (using the new
  per-bout scaling).
- Decide the weather provider + secret (the worktree `weather.ts` already picks
  one — confirm the API key is set).
- One-time **back-fill** for recent runs (needed for §B empirical check).

**(B) Empirical check vs. your runs** [task #7 — BLOCKED on (A)]
Can't validate predicted-vs-actual today because no run has weather attached.
Once back-filled, the test is: for easy runs at similar HR, does the model's
predicted slowdown track the actual pace drop on hot vs. cool days? That also
calibrates the acclimatization adjustment (§1.2). Method is ready; data isn't.

**(C) Feed heat into the fitness trend** [task #9 — Phase A of the
conditions-adjusted-fitness doc]
Use `heatAdjustmentPct` (continuous) + per-bout `combineConditions` to feed
*conditions-adjusted* pace into `fitnessSignal.ts`, so a hot block doesn't read
as a fake fitness dip, and down-weight dirty-condition sessions. **Touches a
prompt-adjacent signal and needs `fitnessSignal.test.ts` green + new cases** per
hard rule #3 — worth doing as its own focused change.

## Decisions needed before (A)/(C)

1. Weather provider + API key for `fetch-workout-weather` (what does the worktree
   version use, and is the secret configured in prod?).
2. Back-fill scope — last N weeks of runs, or everything with GPS?
3. Adjust pace zones live by current weather too (the `adjustAllPaces` path), or
   only annotate completed runs?

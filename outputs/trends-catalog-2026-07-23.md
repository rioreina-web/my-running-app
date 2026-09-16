# Trends catalog — thirteen trends for the Trends tab (spec)

*2026-07-23 · narrative trend cards for the "What the chart shows" surface · tested against Maya (self-coached, 3:28 PB chasing a 3:16 BQ off ~40 mpw, journals mood + niggles, Garmin connected via Junction/Vital).*

This catalog consolidates three design rounds into one buildable list. Every trend fuses at least two signals — and the best ones fuse a **feeling with a number**, which is the app's differentiator: Strava and Garmin can't triangulate against the athlete's own words.

Companion docs: `outputs/trends-metrics-spec-2026-07-10.md` (the metric formulas these trends draw on), `docs/specs/trends-tab-data-wiring.md` (the `TrendsWeek` pipeline), `VITAL-GARMIN-APPLY-NOTES.md` (the stream ingest).

---

## House rules (apply to every trend)

- **Range + confidence, never false precision.** Baselines render as bands; trends as direction, not decimals.
- **Detection, not diagnosis.** Cards observe patterns and stop. No "rest," no "ice," no cause claims — sequence and correlation only, stated as such.
- **AI advises, never acts.** The athlete decides what a pattern means.
- **Verbatim niggles.** Body mentions surface in the athlete's own words, closed vocabulary, never interpreted.
- **No single biometric ever generates a card** (§Group C convergence rule).
- **Absence is honest.** "Your niggles don't track your mileage" is a real finding. A trend with no pattern says so or stays quiet — it never manufactures signal.
- **Editorial voice.** Observation over congratulation; feeling before math.
- **Empty states** use `EmptyStateView` behind the `data_depth` gate — a thin-data chart never pretends.

---

## Group A — Qual × quant fusions (ship first; data fully populated today)

These run on `training_logs`, `workout_features`, and `body_mentions` — nothing new to capture.

### A1. The body talks back to the load

*Injury mentions × volume/effort. The chart's core promise, made explicit.*

- **Watches:** whether `body_mentions` cluster in high-load weeks.
- **Detection:** for each mention, test whether its week's mileage (or weekly Effort) is in the top third of the window, or ≥15% above the trailing 4-week average. Trend fires on **2+ mentions of the same `body_area`** landing in high-load weeks.
- **Sources:** `body_mentions.body_area` / `side` / `mentioned_at`, weekly miles from `training_logs`, weekly Effort from `weeklyAnalytics`.
- **Example copy:**
  > Your right-achilles mentions all land in your three biggest weeks — 49, 53, and 53 miles. Nothing in the down weeks. The pattern is load-shaped, in your own words.
- **Honest state:** mentions scattered across low and high weeks → say so; it's reassuring and true.

### A2. Felt harder than it measured

*Mood × computed Effort — the early-fatigue tripwire.*

- **Watches:** disagreement between measured Effort (intensity × minutes, per the Effort model) and the qualitative read (`mood`, notes).
- **Detection:** fires when **3+ consecutive sessions** (or 2+ consecutive weeks) pair low-to-moderate measured effort with `tired`/`struggling` mood — the feeling and the number disagreeing in the fatigue direction. The reverse (`energized` on big weeks) earns a quiet positive line.
- **Sources:** Effort v1 (`intensity_score × duration`), `training_logs.mood`, `cleaned_notes`.
- **Example copy:**
  > Three runs in a row felt harder than they measured — easy paces, tired words. The load isn't unusual, but the recovery under it might be. Worth watching, not worth panicking.
- **Guard:** observes the gap and stops. Never prescribes.

### A3. The engine is growing under the fatigue

*Key-session pace × volume × mood — fitness proved the honest way.*

- **Watches:** key-session pace improving while volume climbs; mood tells you what it cost.
- **Detection:** simple slope over the window on key-session pace and on weekly miles. Pace falling (faster) + volume flat-or-rising = fitness. Then split the sentence by modal mood: mostly `positive`/`energized` → absorbing; mostly `tired` → improving but paying.
- **Sources:** `key_pace_sec` from the `TrendsWeek` pipeline, weekly miles, weekly modal `mood`.
- **Example copy (absorbing):**
  > Quality pace dropped 6:58 → 6:41 while weekly miles climbed 38 → 53 — and the mood dots stayed warm. You're not just surviving this block, you're absorbing it.
- **Example copy (paying):**
  > The pace is coming down, but so is the mood — the last four weeks read tired. Fitness is being built; it's being paid for too.

---

## Group B — Inside-the-run trends (Garmin per-second streams; ship as `external_streams` populates)

The `vital-webhook` already writes per-second `time / heartrate / velocity_smooth / cadence / altitude / temp / watts` into `external_streams` in the Strava-shaped blob. All five below run on that — **no new capture**.

### B1. Same pace, fewer beats

*HR at a fixed easy pace — the aerobic engine, finally measurable without a race.*

- **Detection:** bucket every easy-run second into pace bands (e.g. 8:45–9:15/mi); compute mean HR per band per week; trend the athlete's most-populated band. Falling HR at the same pace = engine growing.
- **Sources:** `external_streams.streams.heartrate` + `velocity_smooth`.
- **Example copy:**
  > Nine-minute miles cost you 152 bpm in May. They cost 144 now. Same pace, seven fewer beats — that's the base building.
- **Watch-out:** heat inflates HR. Pair with B4's temp stream, or exclude hot days until neutral-pace adjustment lands. Only compare like pace bands with enough seconds in them.

### B2. The drift inside the long run

*Aerobic decoupling — durability, the marathon-specific confidence signal.*

- **Detection:** per steady/long run, `drift = (HR ÷ pace, second half) ÷ (HR ÷ pace, first half) − 1`. Trend across the block. ~5% is the classic durability line — show the trend, not the threshold.
- **Sources:** per-second HR + velocity on runs tagged long/steady.
- **Example copy:**
  > Your heart rate used to climb 8% through the back half of long runs. Last three: 3%. You're holding together deeper into the run — the marathon-specific win.

### B3. Your form gets quiet when you're tired

*Cadence fade × niggles — the qual-quant fusion nobody else can do.*

- **Detection:** per run, `cadence fade = mean cadence(final third) − mean cadence(first third)`; trend weekly. Cross-reference weeks where fade deepens against `body_mentions` in the same or following week.
- **Sources:** `external_streams.streams.cadence`, `body_mentions`.
- **Example copy:**
  > Your cadence dropped 6 steps/min late in runs the week before each achilles mention. The stride goes quiet first; the body speaks second.
- **Guard:** observes sequence, never claims cause. Detection-not-diagnosis applies doubly here.

### B4. The heat is costing you less

*HR-at-pace × watch temp stream — the summer answer to the fake plateau.*

- **Detection:** for runs above ~70°F (watch `temp` stream — no Open-Meteo backfill needed), compute HR at the easy pace band; trend across the hot block. Falling HR at the same pace in the same heat = acclimation.
- **Sources:** `external_streams.streams.temp` + `heartrate` + `velocity_smooth`.
- **Example copy:**
  > Same pace, same 78° evening — 11 fewer beats than four weeks ago. The summer is building you, not burying you.
- **Why it matters now:** July paces look stalled and mood reads tired; this is the trend that stops a hot block from reading as failure.

### B5. How fast you bounce back

*Heart-rate recovery between reps — within-workout freshness.*

- **Detection:** the interval parser already finds reps in the stream. Per rep: `HRR60 = HR(rep end) − HR(rep end + 60s)`. Average per session, trend across sessions. A session 8–10 beats below the athlete's norm + a `tired` mood log = the same story from two sources.
- **Sources:** per-second HR + the server-side interval parse; `training_logs.mood` for the pairing.
- **Example copy:**
  > Between reps, your heart rate is coming down 28 beats a minute — up from 21 in May. You're recovering faster inside the workout, not just between them.

---

## Group C — Recovery-side trends (needs the daily-biometrics webhook branch)

Junction also sends daily Garmin events: overnight HRV (RMSSD), sleep stages/duration/efficiency, resting HR, respiratory rate, all-day stress, steps. `vital-webhook` currently ignores non-workout events — these trends need one new branch (`daily.data.sleep.created` etc.) writing to a small `daily_biometrics` table (RLS in the same migration, append-only, same Svix plumbing).

### The convergence rule (non-negotiable for this group)

**No single biometric ever generates a card.** Every recovery signal below is individually noisy — alcohol, a late meal, travel, one bad night all move them. A recovery observation surfaces only when **2+ independent signals agree** (e.g. HRV suppressed *and* resting HR elevated; short sleep *and* tired mood *and* felt > measured). A lone signal renders quietly in the chart and says nothing. This rule is what keeps the app on the right side of detection-not-diagnosis while Whoop and Garmin ping people over single bad mornings — and it only works because the qualitative stream (mood, niggles) exists to triangulate with.

> **Convergence copy:** Three things moved together this week: HRV down, resting heart rate up, and your logs read tired. Each alone is noise. Together it's a pattern worth watching.

### C1. HRV against your own baseline — never against a score

- **Detection:** 7-day rolling HRV average vs 28-day norm, rendered as a **band**, never a point. Flags only *sustained* suppression: 7d average below the 28d normal range for **4–5+ consecutive days**. Single low mornings stay silent.
- **Sources:** overnight RMSSD from `daily_biometrics`; `mood` for convergence.
- **Example copy:**
  > Your overnight HRV has sat below its usual range for five days — the longest stretch this block. Paired with two 'tired' logs, worth noticing.

### C2. Resting HR drift — the boring signal that's usually right

- **Detection:** 7d resting HR vs 28d baseline; flag sustained elevation of **≥3–4 bpm**, especially coinciding with a volume spike in the same window (the load-response pairing on one chart).
- **Sources:** `daily_biometrics.resting_hr`, weekly miles.
- **Example copy:**
  > Resting heart rate is up 5 beats over the last week — the same week volume jumped to 53. The body is working overtime on the recovery side.

### C3. Sleep underneath the big days

*Not a sleep score — a relationship. Evidence about this athlete, not guilt.*

- **Detection:** for each quality session, take sleep duration over the prior 1–2 nights. Split sessions into "landed" vs "struggled" (execution vs plan, or the A2 felt-vs-measured gap) and compare the sleep behind each. Report only when a real pattern holds across enough sessions (≥6–8).
- **Sources:** `daily_biometrics.sleep_duration` (+ efficiency), key sessions from `workout_features`.
- **Example copy:**
  > Your five strongest sessions this block all followed nights over 7½ hours. The three that felt like grinding — all under 6:40. Your data, your pattern.

### C4. Stress load vs training load

*Life-load is the thing training plans ignore.*

- **Detection:** weekly mean daytime stress (non-run hours) alongside weekly Effort. Surface the **divergences**: modest training load + elevated life stress + `struggling` mood — the mismatch the legs already know about.
- **Sources:** `daily_biometrics.stress` (Garmin all-day), weekly Effort, `mood`.
- **Example copy:**
  > Training load was medium this week, but your all-day stress ran high — the legs weren't lying when the easy runs felt hard. Load is load, wherever it comes from.

---

## Build priority vs data readiness

| # | Trend | Data today | New work | Ship |
|---|---|---|---|---|
| A1 | Body talks back to the load | ✅ populated | detection query | **Now** |
| A2 | Felt harder than it measured | ✅ populated | detection query | **Now** |
| A3 | Engine growing under fatigue | ✅ populated | two slopes + mood split | **Now** |
| B1 | Same pace, fewer beats | streams landing per run | pace-band bucketing | **As streams accumulate** |
| B2 | Drift inside the long run | streams | half-split ratio | As streams accumulate |
| B3 | Form gets quiet when tired | streams + `body_mentions` | fade calc + cross-ref | As streams accumulate |
| B4 | Heat costing you less | streams (`temp`) | hot-day filter + B1 | As streams accumulate (seasonal) |
| B5 | How fast you bounce back | streams + interval parser | HRR60 calc | As streams accumulate |
| C1 | HRV vs own baseline | ❌ webhook branch | branch + table + baselines | After branch + ~4 wk baseline |
| C2 | Resting HR drift | ❌ webhook branch | same | After branch + ~4 wk baseline |
| C3 | Sleep under the big days | ❌ webhook branch | same + session pairing | After branch + enough sessions |
| C4 | Stress vs training load | ❌ webhook branch | same | After branch |
| — | Convergence rule | — | gating logic across C1–C4 + mood | With Group C |

**Recommended sequence:** ship A1–A3 on the existing `TrendsWeek` pipeline; let B1–B5 light up per-athlete as Garmin streams accumulate (gate each on minimum data, e.g. 4+ long runs for B2); write the daily-biometrics webhook branch next so C-group baselines start accruing now, and unhide C-cards only once baselines are 3–4 weeks deep.

## Engineering notes

- **Where detection runs:** extend the `trends-timeline` edge function (or a sibling `trends-insights` function) — TypeScript, next to `weeklyAnalytics.ts`, so the math has one home and no Swift drift. No LLM in detection → unit tests only, no eval cassette. If card prose is later LLM-phrased, that prompt goes through the eval gate.
- **Card contract:** each trend emits `{ id, group, status: hidden|quiet|active, headline, body, evidence: [{week, value}], confidence }` — the view stays a dumb renderer, same seam as `[TrendsWeek]`.
- **Baselines & gates:** every trend declares its own minimum-data gate (weeks of logs, runs with streams, days of biometrics) and hides below it via the `data_depth` pattern. Never render a baseline band from fewer than ~21 days.
- **New table (Group C only):** `daily_biometrics (user_id, date, hrv_rmssd, resting_hr, sleep_duration_min, sleep_efficiency, respiratory_rate, stress_avg, source)` — unique `(user_id, date, source)`, RLS in the same migration, append-only updates via upsert.
- **Copy variants:** each trend needs at least the positive, the watchful, and the no-pattern sentence written up front — the honest state is a first-class deliverable, not a fallback.

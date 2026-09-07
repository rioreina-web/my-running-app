# Sleep + HRV → the recovery read — ingestion & ledger spec

**Date:** 2026-08-04
**Status:** design, ready to build
**Author:** Rio + Claude
**Companions:** `docs/specs/recovery-trend-v2-2026-07-27.md` (the evidence base — this
spec implements its capture layer), `RunningLog/RunningLog/Trends/TrendsSignalModels.swift`
(the shipped `TrendsRecoveryLedger`), `VITAL-GARMIN-APPLY-NOTES.md`,
`outputs/fitness-score-stress-load-design-2026-07-31.md`.

---

## 0. TL;DR

Your Garmin data already flows to the app through Vital/Junction — but the webhook
only ingests **workouts**. Sleep and HRV arrive on a different event and are being
dropped on the floor because there is nowhere to put them. This spec adds that
missing piece and wires it to the recovery number.

Three parts:

1. **Ingest** — one new webhook branch (`daily.data.sleep.*`) + the `daily_biometrics`
   table your `recovery-trend-v2` spec already designed. Small, additive, unblocks
   everything.
2. **Reconcile** — the honest part. Your own evidence review (`recovery-trend-v2`)
   says HRV **cannot** be added to the daily ledger the way mood and load are. This
   spec explains why and gives the design that respects it.
3. **The ledger factors** — a weekly-aggregated **Overnight** factor (HRV paired with
   resting HR, firing only in the one interpretable case) and a **Sleep** factor built
   on the signal the evidence actually supports.

You can ship part 1 today. Parts 2–3 are the design decision this doc exists to make.

---

## 1. Where it stands right now (verified against the live DB)

I checked the production database (`RunningAppMVP2`), not just the repo:

- `training_logs` has **278 rows** and carries `vital_workout_id` — so Garmin → Vital →
  Supabase is live and working for **workouts**.
- **No sleep/HRV data exists anywhere.** I searched every column in the `public`
  schema for `hrv`, `sleep`, `resting`, `body_battery`, `vital` — the only hit is
  `training_logs.vital_workout_id`. There is no `daily_biometrics` table.
- The `vital-webhook` function (`supabase/functions/vital-webhook/index.ts`) has
  branches for `provider.connection.created`, `*workout_stream.created`, and
  `*workouts.created/updated`. **Any event that isn't a workout is dropped** at the
  `if (!isWorkoutEvent) return res(200, { ignored: eventType })` line (index.ts:180).

So the connection is real; sleep and HRV are simply not subscribed/handled yet.

Two adjacent things I noticed in the live DB, flagged so they don't bite later:

- **The `stress_load` migration is not applied in production.** `training_logs` has no
  `stress_load` / `stress_source` columns. Your Phase-1 stress-load work
  (`20260731120000_...`) is authored but never `db push`ed. It matters here because
  the *cardiovascular* side of load (HR) and the *mechanical* side (stress_load) are
  cousins — see §6.
- **RLS is disabled on `_dup_cleanup_backup_20260803`.** Anyone with the anon key can
  read/write it. If it's a finished backup, drop it; otherwise
  `ALTER TABLE public._dup_cleanup_backup_20260803 ENABLE ROW LEVEL SECURITY;` (then
  add policies, or it blocks all access). Not part of this feature — just don't leave
  it open.

---

## 2. The part you have to decide first (read before building)

You asked "can we calculate the recovery score based on HRV and sleep as well" —
meaning: add HRV and sleep as two more lines on the ledger card in your screenshot,
next to Mood, Recent load, Body mentions, Load, Days on.

Here's the tension, and it's entirely inside your own repo. The shipped ledger
(`TrendsRecoveryLedger`) is a **base-50 point composite**: each factor adds or
subtracts points and you read the arithmetic. But your `recovery-trend-v2` spec —
written *after* a full literature review, explicitly so "nobody re-adds [the naive
version] in six months" — concluded four things that directly constrain what an HRV
or sleep factor is allowed to be:

1. **A single night never moves the read.** Isolated daily HRV has a meta-analytic
   effect of **−0.45 (wrong sign, non-significant)**; only the **weekly average**
   carries signal (0.81). A `−8` HRV factor that reacts to last night is exactly the
   thing the spec bans.
2. **HRV is not directional on its own.** Rising HRV means adaptation *and*
   overreaching. It's only interpretable **paired with resting HR**, and even then in
   just **one of nine quadrants** (HRV↓ + RHR↑). A simple "HRV low → minus points"
   term is unsupported by the evidence.
3. **Most "sleep" data from Garmin is Tier 0 — excluded.** Sleep stages (κ≈0.21),
   sleep efficiency (±24-pt error), and Garmin Sleep Score (zero independent
   validation) are all thrown out. **Total sleep time survives only as annotation.**
4. **The real sleep signal is self-reported quality** (strongest single predictor in
   the runner literature) — and the app doesn't capture it yet.

So the faithful answer to "add HRV and sleep as factors" is: **yes, but not as two
more ±point lines that react to last night.** That would contradict the evidence you
already paid to gather. The design below gives you biometrics on the card in a form
that survives your own spec.

**Recommendation:** ship §3 (ingest) now regardless — it's pure upside and unblocks
the weekly `C0` card too. Then add the two factors in §5, which are deliberately
shaped to obey the four constraints: weekly-aggregated, HRV-paired-with-RHR,
quiet-by-default, and honest in copy when they can't say anything.

---

## 3. Ingest (build this first — small, additive, no decisions)

### 3.1 Migration — `daily_biometrics`

This is lifted almost verbatim from `recovery-trend-v2` §5, which already did the
Junction field mapping. New table → **needs its own RLS policy** (hard rule #1).

```sql
-- supabase/migrations/20260804xxxxxx_daily_biometrics.sql
create table if not exists public.daily_biometrics (
  user_id            text not null,
  date               date not null,          -- sleep.calendar_date
  source             text not null,          -- 'garmin'

  vital_sleep_id     text,                   -- sleep.id (restatement dedup)
  sleep_state        text,                   -- 'tentative' | 'confirmed'
  hrv_rmssd          numeric,                -- sleep.average_hrv (ms)   — Tier 2
  resting_hr         numeric,                -- sleep.hr_resting (bpm)   — Tier 2
  hr_lowest          numeric,                -- sleep.hr_lowest (bpm)    — context
  sleep_total_min    integer,                -- sleep.total / 60         — Tier 3
  respiratory_rate   numeric,                -- context only

  device_model       text,                   -- drift detection (v2 §3b)
  firmware_version   text,                   -- drift detection
  app_version        text,                   -- drift detection

  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  primary key (user_id, date, source)
);

alter table public.daily_biometrics enable row level security;

-- match the pattern used by training_logs (user_id = auth.uid()::text)
create policy "own biometrics read"  on public.daily_biometrics
  for select using (auth.uid()::text = user_id);
create policy "own biometrics write" on public.daily_biometrics
  for all    using (auth.uid()::text = user_id)
             with check (auth.uid()::text = user_id);
-- the webhook writes with the service role, which bypasses RLS.
```

Note vs. the v2 draft: I kept `hr_lowest` (it's free and useful as a sanity check on
`hr_resting`) and dropped nothing else. Tier-0 columns (`sleep_efficiency`,
`sleep_score`, `stress_avg`) stay out — capturing them invites someone to use them.

### 3.2 Webhook branch

Add to `vital-webhook/index.ts`, **before** the `isWorkoutEvent` check at line 179.
Junction delivers Garmin backfill on `daily.` events (not `historical.`), and restates
`tentative` → `confirmed` — so upsert on the PK and let a later confirmed row overwrite
a tentative one.

```ts
// Sleep + HRV → daily_biometrics. Garmin sends these on daily.data.sleep.*
if (eventType.endsWith("data.sleep.created") || eventType.endsWith("data.sleep.updated")) {
  if (!userId) return res(200, { ignored: "no user mapping", vitalUserId: payload.user_id });
  const d = payload.data;
  const sleeps: Record<string, any>[] = Array.isArray(d) ? d : Array.isArray(d?.sleep) ? d.sleep : d ? [d] : [];
  let wrote = 0;
  for (const s of sleeps) {
    if (!s?.calendar_date) continue;
    const src = s.source ?? {};
    const row = {
      user_id: userId,
      date: s.calendar_date,
      source: "garmin",
      vital_sleep_id: s.id ? String(s.id) : null,
      sleep_state: s.state ?? null,               // 'tentative' | 'confirmed'
      hrv_rmssd: s.average_hrv ?? null,
      resting_hr: s.hr_resting ?? null,
      hr_lowest: s.hr_lowest ?? null,
      sleep_total_min: typeof s.total === "number" ? Math.round(s.total / 60) : null,
      respiratory_rate: s.respiratory_rate ?? null,
      device_model: src.app_id ?? "Garmin",
      firmware_version: src.firmware_version ?? null,   // confirm field name on live payload
      app_version: src.app_version ?? null,
      updated_at: new Date().toISOString(),
    };
    const { error } = await db
      .from("daily_biometrics")
      .upsert(row, { onConflict: "user_id,date,source" });
    if (error) { console.error(`[vital-webhook] sleep upsert ${s.id}: ${error.message}`); continue; }
    wrote++;
  }
  return res(200, { sleep_rows: wrote });
}
```

**Junction dashboard:** enable the **sleep** data type for the Garmin connection and
add `daily.data.sleep.created` / `daily.data.sleep.updated` to the webhook
subscription (same endpoint, same signing secret — the Svix verify already covers it).

### 3.3 One thing to confirm on a live payload

The exact restatement field (`s.state` vs `s.status`) and the firmware field path
(`s.source.firmware_version`?) can only be nailed down against a real sandbox event.
The names above follow the current Junction docs (`average_hrv`, `hr_resting`,
`hr_lowest`, `total`, `calendar_date`, `id`, `respiratory_rate` — all verified), but
tail `supabase functions logs vital-webhook` on the first real sleep and adjust the two
uncertain names. Everything else is confirmed.

---

## 4. Two recovery surfaces — don't conflate them

Your codebase has (or is heading toward) **two** recovery displays, and this matters
for where sleep/HRV land:

| | **The daily ledger** (your screenshot) | **The `C0` weekly card** (`recovery-trend-v2`) |
|---|---|---|
| Cadence | today, one number | the training block / window |
| Form | base 50 ± point factors, "show the receipt" | two lines + a sentence, no composite |
| Built? | shipped (`TrendsRecoveryLedger`) | designed, not yet built |
| HRV role | see §5 (constrained) | the HRV×RHR quadrant, weekly (v2 §2c) |

The ingestion in §3 feeds **both**. The `C0` card is where the full quadrant logic
lives and is the *more* evidence-faithful home for HRV. §5 below is specifically about
the **daily ledger** — the card you're looking at — because that's what you asked about.

---

## 5. The ledger factors (daily card)

Design rule for both: they follow the existing `Factor` contract in
`TrendsSignalModels.swift` — a name, an uppercase evidence line that is never a
conclusion, and points — and they **degrade to 0 points with an honest evidence line**
when they can't speak, exactly like the current "Mood — not logged today" and
"Load — not enough history yet" do.

### 5.1 Factor 6 · Overnight (HRV paired with resting HR)

Not "HRV." **Overnight** — because a lone HRV number is uninterpretable and your spec
proved it. This factor is a compressed, honest version of the v2 quadrant.

**Inputs (from `daily_biometrics`, computed in the ledger's data layer, not SwiftUI):**
- 7-day mean HRV vs. the athlete's own 28-day baseline → direction (↑ / flat / ↓),
  thresholded at **0.5 × their own between-night SD**.
- 7-day mean resting HR vs. 28-day baseline → same.
- Requires **≥5 valid nights** in the trailing 7. Fewer → the factor is *absent* (not
  zero-with-alarm — just not shown), same as how "Recent load" is skipped on day 0.

**Points — one cell fires, the rest are quiet:**

| HRV vs base | RHR vs base | Points | Evidence line |
|---|---|---|---|
| ↓ | ↑ | **−6** | `7-DAY HRV DOWN, RESTING HR UP` |
| ↓ | ↓ | **0** | `HRV & RESTING HR BOTH LOW · USUALLY ADAPTATION` |
| ↑ | ↓ | **+3** | `OVERNIGHT NUMBERS SETTLED` |
| any other | | **0** | `OVERNIGHT NUMBERS INSIDE YOUR USUAL RANGE` |
| <5 nights | | *absent* | (factor not rendered) |

Only the top row subtracts, and only when both signals agree in the one direction the
literature can read. This is the whole point: it stops the card doing what Garmin/Whoop
do — pinging you over one bad night in a direction the evidence doesn't support.

**Late-luteal suppression (if/when cycle tracking ships, v2 §3a):** in that window,
force this factor to 0 with `CYCLE PHASE TYPICALLY MOVES THESE — NOT READING IT AS
FATIGUE`. Until cycle tracking exists, this factor is honest for men and
not-currently-cycling users and *systematically confounded for ~half of every cycle*
for others — which is itself an argument for keeping its weight low (−6, not −15) and
for prioritizing §5.2.

### 5.2 Factor 7 · Sleep

Here the evidence points somewhere you might not expect: **the best sleep factor is
not built from Garmin data at all.** Your spec is blunt that self-reported sleep
quality is "the strongest single prospective signal" and "a cheaper and better input
than the entire Garmin biometrics pipeline." So:

**Preferred — self-reported sleep quality (needs a one-tap logging surface):**
A nightly 1-tap rating (e.g. rough / ok / good). This is a small new logging UI, not a
backend change, and on the evidence it outperforms everything in §3. Points scale
modestly: `good +4 · ok 0 · rough −6`, evidence `SLEEP: ROUGH · LOGGED`.

**Fallback until that ships — total sleep time as Tier-3 annotation:**
From `daily_biometrics.sleep_total_min`, 7-day mean vs. the athlete's own 3-week
average. **Weak on purpose** — total sleep time has ±83–160 min single-night error, so
never react to one night, and keep the swing small:

| 7-day mean vs own baseline | Points | Evidence |
|---|---|---|
| ≥45 min below | **−3** | `SLEEPING ~40 MIN UNDER YOUR AVERAGE THIS WEEK` |
| within ±45 min | **0** | `SLEEP IN LINE WITH YOUR AVERAGE` |
| ≥45 min above | **+2** | `SLEEPING ABOVE YOUR AVERAGE` |
| <5 nights of data | 0 | `NOT ENOUGH SLEEP DATA YET` |

Do **not** add sleep stages, efficiency, or Garmin Sleep Score as inputs — they're
Tier 0 in your spec for good reasons (§7.4 there). If they ever appear on this card it
should be a deliberate reversal, documented.

### 5.3 What the arithmetic line becomes

Today: `Starts at 50 − 8 − 4 + 0 − 2 − 5 = 31`. With both factors present and quiet:
`Starts at 50 − 8 − 4 + 0 − 2 − 5 + 0 + 0 = 31` — i.e. **biometrics visibly on the
card, contributing 0 until they have something real to say.** That's the honest default
and it's a feature: the athlete sees that overnight data is being watched and that it
isn't currently claiming anything.

**Clamp check:** `total` is currently `min(96, max(8, raw))`. Two new factors widen the
range by roughly −9…+7. The clamp still holds; no change needed, but re-run
`TrendsSignalTests` bands after wiring.

---

## 6. Sequence

1. **Ingest (no decisions):** migration §3.1 → deploy `vital-webhook` with §3.2 branch
   (`--no-verify-jwt`, as today) → enable sleep in Junction dashboard → tail logs on the
   first real sleep, confirm the two uncertain field names §3.3. **Ship this now.**
2. **Backfill:** Junction sends history on `daily.` events after connect; verify rows
   land for a real athlete before building UI on top.
3. **Factor 6 (Overnight):** data layer (7-day means, 28-day baselines, SD thresholds,
   quadrant) → the single-cell point map §5.1 → tests: every quadrant returns the right
   points, **HRV↓/RHR↓ → 0** is the regression test the whole thing exists to protect,
   <5 nights → absent, one extreme night never changes the factor.
4. **Factor 7 (Sleep):** ship the Tier-3 total-sleep fallback first (data's already
   there), then the self-reported one-tap when you build the logging surface — and once
   it exists, it becomes primary.
5. **Later:** the full `C0` weekly card (v2), which is the richer home for the quadrant
   and the load/recovery relationship.

## 7. Tests to add (extending `TrendsSignalTests`)

- Overnight factor: all 9 HRV×RHR combinations → correct points; only HRV↓/RHR↑ is
  negative.
- A single extreme night with <5 valid nights in the window → factor absent, score
  unchanged.
- Sleep factor: one 3-hour night inside an otherwise-normal week does **not** move the
  7-day mean past the ±45-min gate.
- Missing biometrics entirely → both factors behave like the existing "not logged"
  factors (0 points, honest evidence line), score identical to today.
- Clamp: a maximally-bad week (all factors negative + both new negatives) still floors
  at 8, not below.
- Restatement: a `tentative` sleep row followed by a `confirmed` one for the same date
  upserts to one row, confirmed values win.

## 8. Open questions (yours to call)

1. **Self-reported sleep — build the one-tap now?** It's the strongest signal and a
   small UI. Strong recommend; it's the highest-leverage item in this whole doc.
2. **Overnight factor weight.** −6 is deliberately gentle given the cycle confound.
   Comfortable, or lower it to −4 until cycle tracking exists?
3. **Cycle tracking.** Without it, Factor 6 is confounded for a large share of users
   half the time. Ship Factor 6 anyway (honestly labeled) or gate it behind cycle
   capture? This is the one genuinely uncomfortable call — your spec §8.3 lays out both
   sides.
4. **Apply the stress-load migration** (`20260731120000`) while you're in the DB, so the
   mechanical-load and cardiovascular-load work stop drifting apart.

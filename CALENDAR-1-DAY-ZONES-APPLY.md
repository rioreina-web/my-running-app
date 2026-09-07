# Calendar · slice 1 — day-level pace zones

*Server only. Nothing changes in the UI. Read `CALENDAR-BUILD-PLAN.md` first — in particular
**slice 0**, which must be decided before this is built.*

---

## What this gives you

One API call returns everything the calendar needs, one row per calendar day: how far you ran, how
that distance split across pace zones, which runs were key sessions, your mood, your journal note,
and any body mentions. Today this data exists but is scattered across three places and two
incompatible zone models.

After this slice the UI has a single source to read from, and the pace breakdown finally agrees with
what Trends says.

---

## Paste this to Claude Code

> Build a new Supabase edge function `calendar-days` in `supabase/functions/calendar-days/`,
> following the exact conventions of the existing `trends-timeline` function (read that whole
> directory first — `index.ts`, `timeline.ts`, `keySessions.ts` — and match its structure, error
> handling, auth, and file split).
>
> Read `CALENDAR-1-DAY-ZONES-APPLY.md` in the repo root for the full contract, then build it. Follow
> the response shape in that document exactly. Reuse `_shared/workoutSegmentation.ts` and
> `_shared/quality-volume.ts` — do not write new pace maths. Write Deno tests covering every case
> listed in the Tests section. Run `deno check` and `deno test --allow-all` before you finish.
>
> Do not touch any Swift file. Do not touch any tracked file outside `supabase/functions/`.

---

## Contract

### Request

`POST /functions/v1/calendar-days`

```ts
{
  user_id?: string,   // omitted → derive from JWT, same as trends-timeline
  from: string,       // "YYYY-MM-DD" inclusive, local calendar date
  to: string          // "YYYY-MM-DD" inclusive
}
```

Clamp the range to **186 days**. Reject anything larger with a 400 rather than silently truncating —
a silent truncation reads as "you ran nothing in March."

### Response

```ts
{
  generated_at: string,          // ISO
  zone_order: string[],          // fastest → slowest, e.g. ["mile","3k","5k","10k","hmp","mp","steady","easy","recovery"]
  days: CalendarDay[],           // one per date in range, INCLUDING zero days
  weeks: CalendarWeek[]          // Monday-keyed, covering every week the range touches
}

interface CalendarDay {
  date: string,                  // "YYYY-MM-DD"
  miles: number,                 // logged, 0 for rest
  seconds: number,
  elevation_ft: number,
  run_count: number,
  is_rest: boolean,              // no run logged AND in the past
  is_future: boolean,
  zone_miles: Record<string, number>,   // keys from zone_order; omit zeroes
  quality_miles: number,         // sum of MP-and-faster, per _shared/quality-volume.ts
  mood: string | null,           // closed vocabulary, see below
  note: string | null,           // cleaned_notes, trimmed; null when empty
  runs: CalendarRun[],
  body_mentions: BodyMention[]
}

interface CalendarRun {
  training_log_id: string,
  started_at: string,            // ISO, local
  title: string | null,
  miles: number,
  seconds: number,
  pace_sec_per_mile: number | null,
  elevation_ft: number,
  is_key: boolean,
  key_structure: string | null,  // "6x1mi" — from keySessions, null when not a key session
  key_zone: string | null,       // dominant work zone
  work_pace_sec: number | null,  // rep pace, NOT whole-run pace
  zone_miles: Record<string, number>
}

interface BodyMention {
  body_area: string,
  side: string | null,
  verbatim_quote: string,
  severity_hint: string          // the WORD — "tight", "sore". Never a number.
}

interface CalendarWeek {
  week_start: string,            // Monday "YYYY-MM-DD"
  miles: number,
  quality_miles: number,
  run_count: number,
  rest_days: number,
  key_dates: string[],
  zone_miles: Record<string, number>,
  acwr: number | null,           // from athlete_state, null when unavailable
  mood: string | null            // dominantMood, reuse trends-timeline's helper
}
```

### Rules that are easy to get wrong

**Return every day in range, including zeroes.** A calendar with holes is a calendar the client has
to backfill, and it will backfill it differently from the server. `is_rest` is `!miles && !is_future`.

**Day boundaries are the athlete's local calendar day**, not UTC. `training_logs.workout_date` is
`TIMESTAMPTZ`. Get this wrong and every early-morning run in a UTC-behind timezone lands on the
previous day. `trends-timeline` already solves this — copy its approach exactly, do not invent one.

**Zone assignment comes from laps, with a documented fallback ladder**, mirroring
`segmentFromLaps` → `segmentFromPaceSegments` → `segmentFromOverall`:

1. `running_workout_laps` where `is_rest = false` — assign each lap's distance to
   `paceToZone(avg_pace_sec_per_mile, anchors)`. Best resolution.
2. `training_logs.pace_segments` — measured pace per segment. **Ignore the `effort` label**;
   `quality-volume.ts` documents why it is untrustworthy.
3. The run's overall average pace, whole distance in one zone.

Set a `zone_source: "laps" | "segments" | "overall"` field on each run so the UI can be honest about
resolution and so you can measure coverage later.

**Reconcile rounding against logged miles.** `TrainingAnalyticsViewModel.split(for:)` already does
this at line 693 — sum the zone miles, scale to the row's logged miles. Do the same, or the day total
and the sum of its bars will disagree on screen.

**Warm-up and cool-down are easy.** On a key session, rep distance goes to the rep's zone and the
remainder goes to easy. Do not smear the session pace across the whole run.

**Zone anchors are per-athlete and change over time.** Read `athlete_state.pace_zones` the way
`trends-timeline/index.ts:270–282` does. If they are missing, return the days with
`zone_miles: {}` and `zone_source: "none"` rather than failing the whole request — a calendar with no
pace colours is still a useful calendar.

**Excluded workouts.** `training_logs.stats_excluded` exists. Honour it, and match whatever
`trends-timeline` does so the two never disagree on a week total.

---

## Files

**New, additive — safe to place automatically:**

```
supabase/functions/calendar-days/index.ts        request handling, auth, range clamp
supabase/functions/calendar-days/days.ts         per-day rollup + zone assignment
supabase/functions/calendar-days/weeks.ts        Monday rollup, reuses dominantMood
supabase/functions/calendar-days/days.test.ts
supabase/functions/calendar-days/weeks.test.ts
```

**Tracked files edited: none.** If you find yourself needing to change `_shared/`, stop — that means
the contract is wrong, not the shared code. Bring it back to slice 0.

---

## Tests

Deno, `deno test --allow-all`. CI already runs every `*.test.ts` under `supabase/functions/`, so
these are covered from the moment they land.

Cover at minimum:

- [ ] A range with no runs returns every day with `miles: 0`, `is_rest: true`
- [ ] Future days come back `is_future: true`, `is_rest: false`
- [ ] Zone miles sum to the day's logged miles within 0.01 after reconciliation
- [ ] Fallback ladder: a run with laps, one with only `pace_segments`, one with neither — each gets
      the right `zone_source` and a sensible split
- [ ] A key session puts rep distance in the rep zone and the remainder in easy
- [ ] `quality_miles` matches `isQualityPace` from `_shared/quality-volume.ts` on the same input —
      assert against the shared function, do not reimplement the threshold
- [ ] A run starting 23:30 local lands on the right calendar day, in a UTC-behind and a UTC-ahead zone
- [ ] Missing `athlete_state.pace_zones` returns days with empty `zone_miles`, not a 500
- [ ] `stats_excluded` rows are excluded, and the week total matches `trends-timeline` for the same week
- [ ] A range over 186 days returns 400
- [ ] Week rollup: `rest_days`, `key_dates`, and `zone_miles` sum correctly across a partial week

The `trends-timeline` parity test is the important one. If `calendar-days` and `trends-timeline`
ever disagree about a week's mileage, the app shows two different numbers for the same week and the
athlete stops trusting both.

---

## Deploy

Per `APPLY-NOTES.md` ordering:

```bash
supabase functions deploy calendar-days
```

No migration — this slice adds no tables and no columns. It reads what is already there.

Then smoke it against a real range before touching any UI:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/calendar-days" \
  -H "Authorization: Bearer $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"from":"2026-05-01","to":"2026-07-27"}' | jq '.days | length, (.weeks | length)'
# expect: 88, 13
```

---

## Done when

- `deno check` and `deno test --allow-all` pass
- The curl above returns 88 days and 13 weeks
- Summing `days[].miles` for a given week equals that week's `miles` in `trends-timeline`
- No Swift file changed, no tracked file outside `supabase/functions/calendar-days/` changed

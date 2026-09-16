# Pace Band surface — design spec

**Status:** ready for design · **Date:** 2026-08-02 · **Surface:** Trends (drill-down from the
threshold tile) · **Prototype:** `band-toggle-prototype.html`

Built and validated against live RunningAppMVP2 data — 1,348 laps, 19 qualifying sessions,
23 Mar – 2 Aug 2026. Every number in this doc is real, not placeholder.

---

## 1. What this surface answers

> *"Am I doing the work at the pace I'm supposed to be doing it at, and what is it costing me?"*

One pace band at a time. The athlete picks **HMP** or **MP**; the whole surface re-renders for
that anchor. Three lanes share a single session axis so relationships read vertically.

It is an **observation** surface, not a prescription. It reports what landed in the band. It never
says a number is good, bad, too low, or what to do next. (Hard rule #2.)

---

## 2. The band

### Math

```
anchor      = weekly median from fitness_snapshots
              HMP → predicted_half_seconds / 13.1094
              MP  → predicted_marathon_seconds / 26.2188
band_fast   = anchor × 0.95
band_slow   = anchor × 1.05
```

The band **moves weekly**. It is a step function across the session axis, not a smooth curve —
a run is judged against the anchor that was current in its week.

### Membership

A lap is in band when its **heat-adjusted** pace falls inside the range:

```
membership_pace = COALESCE(heat_adjusted_pace_sec_per_mile, avg_pace_sec_per_mile)
in_band         = membership_pace BETWEEN band_fast AND band_slow
```

This is the single most important behavioural decision on the surface. A lap qualifies on what
the conditions say the effort was worth, not what the watch recorded. Raw pace is still shown —
as a hollow ring with a stem to the adjusted value — so the athlete can always see the correction
being applied to her.

### Current values (2 Aug 2026)

| Band | Anchor | Range | Sessions | Time | Distance | Avg adj. pace | Avg HR |
|---|---|---|---|---|---|---|---|
| **HMP** | 5:23 | 5:07 – 5:39 | 14 | 246 min | 46 mi | 5:21 | 165 bpm |
| **MP** | 5:38 | 5:21 – 5:55 | 11 | 120 min | 21 mi | 5:44 | 168 bpm |

### ⚠️ Known overlap — design must acknowledge this

MP sits **only 15 s/mi** off HMP for this athlete. At ±5% each band is ~33 s wide, so they
**overlap by 18 s/mi in every week of the window without exception**. 47 minutes qualify for both.

The toggle makes the bands *legible* separately. It does not make them *independent*. Copy under
the chart must say so — the persistent note in §6 is not optional.

---

## 3. Layout

```
┌──────────────────────────────────────────────────────────┐
│  PLATE STRIP                                             │
│  One band at a time.                       ← display-l   │
│                                                          │
│  [ HALF MARATHON ][ MARATHON ]             ← segmented   │
│                                                          │
│  5:23   band 5:07 – 5:39 /mi · ±5% · moves weekly        │
│  ↑ mono 40px, band-coloured    ↑ mono 14px, ink-2        │
│                                                          │
│  <one paragraph, body, explaining heat-adjusted entry>   │
│                                                          │
│  ┌────────┬────────┬────────┬────────┐   ← stat row      │
│  │246 min │ 46 mi  │  5:21  │165 bpm │                   │
│  │IN BAND │ MILES  │ ADJ PACE│ HR    │                   │
│  └────────┴────────┴────────┴────────┘                   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │ PACE        heat-adjusted · hollow ring = raw    │    │
│  │  ▓▓▓▓ band ribbon ▓▓▓▓  ● adjusted  ○ raw        │    │
│  │──────────────────────────────────────────────────│    │
│  │ HEART RATE  average bpm while in band            │    │
│  │  ● ● ● ● ●                                       │    │
│  │──────────────────────────────────────────────────│    │
│  │ VOLUME      session miles · dark = miles in band │    │
│  │  ▐▌▐▌▐▌▐▌                                        │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  │ coral rule — the overlap note                         │
│                                                          │
│  PER SESSION            ← eyebrow                        │
│  <table>                                                 │
└──────────────────────────────────────────────────────────┘
```

Sessions run left→right in the **same order and same x-position in all three lanes**. That vertical
alignment is the whole point — never re-sort one lane independently.

---

## 4. Lane specs

### Lane 1 — PACE (height 236)

| Element | Spec |
|---|---|
| Y axis | Pace, **inverted** (faster = up). Range 5:00–6:20, gridlines every 20s |
| Band ribbon | Step polygon, `fill-opacity 0.14`, 1.3px stroke at `opacity 0.55` |
| Anchor line | Dashed `4 3`, 1.7px, band colour |
| Adjusted mark | Filled circle r=5, band colour, 1.6px paper ring |
| Raw mark | Hollow circle r=3.5, paper fill, 2px coral stroke — **only rendered when raw ≠ adjusted** |
| Correction stem | 2px coral line connecting the two |

The stem always points toward faster. That directionality is a feature — it makes "the heat cost
you this much" legible without a legend.

### Lane 2 — HEART RATE (height 100)

Y range 145–180 bpm, gridlines at 150/160/170. Filled circles r=4.2 in band colour, joined by a
1.6px line at `opacity 0.28`. The line is a reading aid, not data — keep it recessive.

### Lane 3 — VOLUME (height 128)

Y range 0–18 mi. Two overlaid bars per session, both anchored to baseline:

- **Session total** — `--pace-easy` pale blue, always visible in both toggle states
- **In band** — band colour, drawn over it, with a mono 8px direct label

The pale bar staying put across the toggle is deliberate: it's the constant against which each
band's contribution reads.

---

## 5. Tokens

Everything comes from `design-system/colors_and_type.css`. **No new tokens required.**

| Role | Token | Value |
|---|---|---|
| Page | `--paper` | `#F5F3F0` |
| Card | `--card` | `#FFFFFF` |
| Rules / gridlines | `--rule` | `#E8E4E0` |
| Primary text | `--ink` | `#1A1815` |
| Labels, sub-headers | `--ink-2` | `#6B6560` |
| Axis values, captions | `--ink-3` | `#9B9590` |
| **HMP band** | `--pace-lt` (navy end) | `#12294F` |
| **MP band** | `--pace-mp` (mid) | `#4E80AB` |
| Session-total bar | `--pace-easy` | `#8FB3CE` |
| Heat correction | `--coral` | `#D4592A` |

Band colours are two steps off the canonical `PaceSpectrum` ramp — single hue, light→dark, so
HMP reading darker than MP is semantically correct (faster = deeper). This respects the
three-palette rule: **blue is pace, and only pace.**

Type: mono for all numerals and axis labels (`font-variant-numeric: tabular-nums`, always).
Crimson Pro for the display headline. PT Serif for body copy.

### 🔴 Open question for design

The three-palette rule says **coral is alert-only, never a pace fill**. The heat-correction stem is
coral and sits inside the pace lane. My read: it's an *attention* mark on a data-quality
correction, not a pace fill, so it's within the rule. But it is the one place this surface pushes
on the palette and it should be a deliberate call, not a drive-by. Alternatives if we decide
against: `--ink-3` stem (loses the "this matters" signal), or a dotted stem in band colour.

---

## 6. Copy

### Fixed strings

| Slot | Text |
|---|---|
| Headline | `One band at a time.` |
| Toggle | `HALF MARATHON` / `MARATHON` |
| Band line | `band {fast} – {slow} /mi · ±5% · moves weekly` |
| Lane 1 label | `PACE` · sub: `heat-adjusted · hollow ring = raw` |
| Lane 2 label | `HEART RATE` · sub: `average bpm while in band` |
| Lane 3 label | `VOLUME` · sub: `session miles · dark = miles in band` |
| Chart caption | `SESSIONS RUN LEFT TO RIGHT, SAME ORDER IN ALL THREE LANES. HOVER ANY MARK.` |

### The overlap note — required, persistent

> **Heads up.** Your MP sits only 15 s/mi off your HM, so at ±5% the two bands overlap by 18 s/mi
> — 47 minutes across this window qualify for both. Toggling shows each band on its own terms; it
> doesn't make them independent.

Coral left rule, `--ink-2` body, coral bolded lead-in. This is honesty about the metric's limits,
which is the house posture. Do not bury it in a tooltip.

### Voice rules

- Report, never grade. `246 min in band` — never `good week` or `below target`.
- Every claim cites a number (data_depth ≥ 2 rule).
- No em-dashes as empty-state placeholders. (Hard rule #8.)
- Never suggest an action. No "add more threshold work."

---

## 7. States

| State | Trigger | Render |
|---|---|---|
| **Default** | `data_depth ≥ 2`, ≥ 1 qualifying session | Full surface, HMP selected |
| **Toggled** | Athlete taps MARATHON | Anchor, range, 4 stats, 3 lanes, table all swap. Session x-positions do **not** move |
| **Band empty** | 0 sessions in selected band | Keep the axis and ribbon. `EmptyStateView`: eyebrow `NO {BAND} WORK YET` + `Nothing has landed between {fast} and {slow} in this window.` |
| **No weather** | `heat_adjusted_pace` null | Fall back to raw. **Suppress the hollow ring and stem entirely** — do not draw a zero-length correction |
| **Sparse** | `data_depth ≤ 1` | Don't ship this surface. Route to the threshold tile |
| **Low confidence** | `fitness_snapshots.confidence_tier = 'low'` | Render the band with a dashed outer edge + `LOW CONFIDENCE` chip beside the anchor |

---

## 8. Interaction

- **Toggle** — segmented control, `--r-pill`, selected segment fills with that band's colour and
  goes white text. 150ms `--ease-out` on the fill. Everything below re-renders; no layout shift.
- **Hover / tap any mark** — tooltip with date, adjusted pace, raw pace, band range, HR, miles,
  minutes, dew point. Hit target ≥ 44×44 regardless of mark size.
- **No dual axis, ever.** Three separate lanes with their own scales. If a fourth measure is
  wanted, it becomes a fourth lane.

---

## 9. Data

### Source

- `running_workout_laps` — `avg_pace_sec_per_mile`, `heat_adjusted_pace_sec_per_mile`,
  `avg_heart_rate`, `distance_meters`, `moving_time_seconds`, `is_rest`, `dew_point_f`
- `fitness_snapshots` — `predicted_half_seconds`, `predicted_marathon_seconds`, `confidence_tier`

### Filters

```
is_rest IS NOT TRUE
distance_meters >= 350          -- drop GPS fragments
session qualifies if in-band time > 120s
```

### Anchor sanity filter — required

Two snapshots in the current series are junk: half-marathon paces of 6:01 and 6:25 on days when the
real estimate was 5:20. Filter `predicted_half_seconds / 13.1094 < 350` and take the **weekly
median**, not the latest value. Without this the band jumps ~40 s/mi for a week and the chart lies.

### Query

```sql
WITH a AS (
  SELECT date_trunc('week', created_at)::date wk,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY predicted_half_seconds/13.1094)     hmp,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY predicted_marathon_seconds/26.2188) mp
  FROM fitness_snapshots
  WHERE predicted_half_seconds IS NOT NULL
    AND predicted_half_seconds/13.1094 < 350
  GROUP BY 1
),
lap AS (
  SELECT l.lap_start_at::date d, l.moving_time_seconds sec, l.distance_meters dm,
    l.avg_pace_sec_per_mile p,
    COALESCE(l.heat_adjusted_pace_sec_per_mile, l.avg_pace_sec_per_mile) pa,
    l.avg_heart_rate hr, l.dew_point_f dew,
    (SELECT hmp FROM a WHERE a.wk <= date_trunc('week', l.lap_start_at)::date
     ORDER BY a.wk DESC LIMIT 1) hmp,
    (SELECT mp  FROM a WHERE a.wk <= date_trunc('week', l.lap_start_at)::date
     ORDER BY a.wk DESC LIMIT 1) mp
  FROM running_workout_laps l
  WHERE COALESCE(l.is_rest, false) = false
    AND l.avg_pace_sec_per_mile IS NOT NULL
    AND l.distance_meters >= 350
),
f AS (
  SELECT *,
    (pa BETWEEN hmp*0.95 AND hmp*1.05) h,
    (pa BETWEEN mp*0.95  AND mp*1.05 ) m
  FROM lap
)
SELECT d,
  round((sum(sec)      FILTER (WHERE h)/60.0)::numeric, 1) h_min,
  round((sum(dm)       FILTER (WHERE h)/1609.34)::numeric, 2) h_mi,
  round((sum(sec*pa)   FILTER (WHERE h)/nullif(sum(sec) FILTER (WHERE h),0))::numeric, 0) h_pace,
  round((sum(sec*p)    FILTER (WHERE h)/nullif(sum(sec) FILTER (WHERE h),0))::numeric, 0) h_raw,
  round((sum(sec*hr)   FILTER (WHERE h)/nullif(sum(sec) FILTER (WHERE h),0))::numeric, 0) h_hr,
  -- repeat the five above with FILTER (WHERE m) for the MP band
  round((sum(sec) FILTER (WHERE h AND m)/60.0)::numeric, 1) both_min,
  round((sum(dm)/1609.34)::numeric, 2) sess_mi,
  round(avg(dew), 0) dew,
  round(max(hmp)::numeric, 0) hmp, round(max(mp)::numeric, 0) mp
FROM f
GROUP BY d
HAVING sum(sec) FILTER (WHERE h) > 120 OR sum(sec) FILTER (WHERE m) > 120
ORDER BY d;
```

All aggregates are **time-weighted**, not lap-count-weighted. A 6-minute mile lap and a 90-second
400m rep must not carry equal weight in the average pace.

---

## 10. Known issues this surface exposes

1. **Mile auto-laps pollute rep detection.** A long run with two rest laps parses as a 24-rep
   session. Gate on 4–16 reps *and* mean rep distance under 2,000m.
2. **`workout_type` has been null since 29 Jul.** Doesn't break this surface (it reads laps, not
   labels) but it breaks anything trying to caption a session by type.
3. **Lap coverage has holes** — laps start 25 Mar, with gaps 19 May–10 Jun and 16 Jun–21 Jul. The
   session axis should show what it has and not imply continuity across a gap.

---

## 11. Open questions

| # | Question | My lean |
|---|---|---|
| 1 | Coral for the heat stem vs the alert-only palette rule | Keep coral — it's a correction flag, not a pace fill |
| 2 | Does the toggle persist across sessions, or reset to HMP? | Persist. She's training for a half; MP is the occasional check |
| 3 | Should the overlap note be dismissible? | No. It's a limit of the metric, not a notification |
| 4 | Add an HR discriminator to separate the bands? | Yes, eventually — HM laps run 165 bpm vs 168 in MP, which separates better than pace does. Needs its own spec |
| 5 | Third band for LT? | Not yet. LT sits ~1 min/mi off HMP so it wouldn't overlap, but three toggle states is a different control |

---

## 12. Build order

1. Lane 1 alone, HMP only, no toggle — answers the core question and ships standalone
2. Add the heat-adjusted membership + raw/adjusted stem
3. Add lanes 2 and 3
4. Add the MP toggle and the overlap note
5. Table + tooltips

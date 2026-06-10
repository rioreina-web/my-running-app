# Fitness Predictor — Redesign (May 2026)

Companion to `fitness-predictor-audit.md` and `fitness-predictor-scenarios.md`.
The audit identified what's broken; this is the rebuilt design.

## TL;DR — what changes

Today the predictor is a calculator: race anchor → arithmetic → five numbers.
It produces an answer with no story behind it. The redesign shifts to
**explanatory coaching**: every prediction comes with the evidence that
produced it, the trend it sits in, and the soft spots that justify its
range. The user reads it like a coach's note, not a calculator readout.

Three governing principles:

1. **Show your work.** Every number cites evidence. Never "your half is
   1:09" alone; always "your half is 1:09 because of your March 21 tempo
   segment at 5:21/mi for 7 miles."
2. **Editorial register climbs with `data_depth`.** Depth 0–1 says "log
   more, here's what would unlock a real read." Depth 2+ gets paragraph-
   style coach analysis with numbered pull quotes.
3. **Range tells the story.** A wide range isn't a bug; it's the coach
   saying "I'm not sure yet, and here's what would tighten it."

## Data inputs — what the predictor reads

### From `training_logs`
- Workouts (last 30 / 180 / 365 days windows)
- Voice logs: notes, mood, parsed_structure
- Pace segments (GPS-derived effort segments)
- Weather data: `weather_actual` JSONB + `weather_adjusted_pace_delta_seconds_per_mile`
- Workout style (new column): outdoor_run / treadmill / indoor_track / trail / etc.
- Linked race results (`race_result` JSONB)

### From `fitness_snapshots`
- Snapshot history — the demonstrated-fitness ledger
- Trend over time (used for chart + improvement detection)

### From `training_plans`
- Active goal race + target time
- Block phase indicators (build / peak / taper marked in plan)

### From `user_profiles`
- Sex, age (for race-equivalence calibration when relevant)
- Self-reported PRs (when available)
- Home location (for weather context lookups)

### Derived signals (computed each prediction)
- Volume trend: recent 2-week mi/wk vs. prior 4-week baseline
- Pace-specific volume per zone: mile / 3K / 5K / 10K / HMP / MP
- Matched-workout pace deltas: same-structure workouts compared over time
- Subjective trend: mood pattern + niggle frequency + effort-vs-pace mismatch
- Phase: build / maintain / taper / recovery / overreach / detrain
- Progression: improving / stable / regressing

## Data analysis pipeline

The pipeline is a sequence of stages. Each stage produces structured output
that the next stage consumes. The editorial layer at the end narrates over
the structured result.

### Stage 1 — Workout structure extraction (the Observer)

The Observer (`parse-workout-structure`) runs on every workout that has
notes or GPS streams. It extracts a `WorkoutExtraction`:

```
WorkoutExtraction {
  workoutId: UUID
  segments: [
    {
      type: "interval" | "tempo" | "easy" | "recovery"
      distance_meters: Int
      duration_seconds: Int
      pace_per_mile: String              // "5:21"
      intensity_zone: "mile" | "3K" | "5K" | "10K" | "HMP" | "MP" | "easy"
      rep_count: Int?                     // for interval segments
      rest_seconds: Int?                  // for interval segments
    }
  ]
  workout_style: "outdoor_run" | "treadmill" | "indoor_track" | "trail" | "track" | "race" | "unknown"
  conditions: {
    temp_f: Float?
    humidity_pct: Int?
    surface: "road" | "trail" | "track" | "treadmill"
    elevation_gain_ft: Int?
  }
  is_long_run: Bool                       // total ≥12mi → eligible for long-run-finish bonus
  effort_vs_pace_signal: "easier" | "matches" | "harder" | null
  niggle_mentions: [String]               // closed-vocab body parts mentioned
  mood: "energized" | "positive" | "neutral" | "tired" | "struggling" | "injured" | null
}
```

The Observer recognizes workout-context phrases (tempo run, x 400, mile
repeat) so it doesn't misread a workout description as a race. It also
detects treadmill mentions and speed-in-mph syntax ("6 × mile at 10 mph"
→ pace 6:00/mi).

**Coverage requirement:** the Observer must run on every voice log with
notes AND every auto-synced workout with GPS streams. Today's gap (most
post-April voice logs have `parsed_structure = null`) is fixed by adding
a database trigger that fires on `training_logs` insert/update.

### Stage 2 — Per-zone volume accumulation

For each fitness zone, sum the in-zone segment volume across workouts in
the trailing 6–8 week window:

| Zone | Pace window (% of zone pace) | Typical reps | Per-session volume threshold |
|---|---|---|---|
| Mile | 95–110% mile pace | 300m–800m | 2K–4K |
| 3K | 95–110% 3K pace | 400m–1600m | 3K–5K |
| 5K | 95–110% 5K pace | 400m–2000m | 4K–7K |
| 10K | 95–110% 10K pace | 600m–3200m | 8K–12K |
| HMP | 90–110% HMP | 1K–6mi | 10K–15K |
| MP | 90–110% MP | 1mi–15mi | 15K–30K |

A single workout can contribute volume to multiple zones — e.g. "10min
tempo at 10K pace + 8×600 at 5K pace" adds 3K to the 10K pool and 4.8K
to the 5K pool.

**Long-run-finish bonus:** when in-zone work is in the second half of a
≥12mi run, those segments get **1.3× volume credit**. Fatigue resistance
is part of race fitness; finishing MP work tired is more predictive than
fresh-legs MP work.

### Stage 3 — Per-distance evidence assessment

For each race distance, classify the evidence quality:

- **Tight** — 3+ qualifying sessions in last 6 weeks, OR a recent race at
  this distance (≤16 weeks).
- **Moderate** — 1–2 qualifying sessions, or qualifying sessions at an
  adjacent distance.
- **Wide** — no in-zone evidence; extrapolating from a different distance.

The state drives the range width:

| State | Range multiplier on tier base |
|---|---|
| Tight | 1.0× |
| Moderate | 1.5× |
| Wide | 2.5× |

Additionally, distance-specific volatility multipliers apply (mile fitness
is inherently more volatile; marathon has race-day execution variance):

| Distance | Volatility multiplier |
|---|---|
| Mile | 1.6× |
| 5K | 1.3× |
| 10K | 1.0× (anchor) |
| Half | 1.1× |
| Marathon | 1.2× |

### Stage 4 — Anchor selection (implemented May 11)

Pick the fastest race-equivalent pace in the trusted window (last 36
weeks). The race-anchor recency curve replaces the binary 6-week cliff:

| Race age | Anchor strength |
|---|---|
| 0–12 weeks | full credit |
| 12–16 weeks | full credit (race-primary window) |
| 16–24 weeks | full unless a fresh training anchor (≤4wk) exists |
| 24–36 weeks | fresh training anchor preferred when available |
| 36+ weeks | not used as anchor |

Multiple agreeing races within the window increase confidence. The
selected race's date becomes the start of the post-anchor training
stimulus window.

### Stage 5 — Trend assessment (the four-signal composite read)

Four signals combine into a phase + progression verdict:

| Signal | What's measured |
|---|---|
| **Global volume trend** | Recent 2wk miles/wk vs prior 4-week baseline |
| **Pace-specific volume trend** | Per-zone volume, recent vs prior |
| **Matched-workout PRs** | Same-structure workouts compared over time; pace deltas |
| **Subjective trend** | Mood pattern, niggle frequency, effort-vs-pace mismatches in voice logs |

Verdict matrix (composite read):

| Volume | Pace-specific | Workout PRs | Subjective | Verdict |
|---|---|---|---|---|
| ↑ | ↑ | ↑ | positive | **Improving — adapting to load** |
| ↑ | ↑ | flat or ↓ | tired | **Overreach — working but not adapting** |
| flat | ↑ | ↑ | positive | **Sharpening — peak window** |
| ↑ | flat | flat | positive | **Building base — fitness pop pending** |
| ↓ | ↓ | n/a | tired/sick/injured | **Detraining — decay applies** |
| flat | flat | flat | mixed | **Stable — at demonstrated ceiling** |
| ↑ | ↑ | ↓ | crushed | **Maladaptive — coach should intervene** |

The **progression** signal sits alongside the phase:

- **Progressing** — same-structure workouts faster over time
- **Stable** — same paces at same volumes
- **Regressing** — same workouts slowing

### Stage 6 — Context discounting

Apply environmental adjustments to anchor and workout paces before they
feed the fitness inference:

- Weather: read `weather_adjusted_pace_delta_seconds_per_mile` from the
  reconciliation pipeline. Only applies to outdoor workout styles.
- Hills: if elevation_gain_ft / distance_miles > 30 ft/mi, apply
  ~3 sec/mi adjustment per 50 ft of gain (rule of thumb).
- Surface: trail gets ~10–15 sec/mi adjustment vs road equivalent.
- Treadmill: paces adjusted ~3 sec/mi slower for outdoor equivalence.
- Effort signal: when voice log says "felt easy" at a hard pace, that's a
  *positive* signal — fitness is higher than the pace suggests. Don't
  shift the point estimate, but tighten the range.

### Stage 7 — Detraining gate (implemented May 12)

Decay applies only when detraining evidence is present:

- Low volume: recent 2wk mi/wk < 50% of 4-week baseline, OR < 15 mi/wk
- Zero quality: no in-zone qualifying segments in last 3 weeks
- Layoff: ≥7-day gap between consecutive workouts in last 4 weeks
- Niggle escalation: 3+ niggle mentions of the same body part in 14 days

Severity scales with number of triggers (1 → 0.4; 2 → 0.7; 3 → 1.0).
Decay rate is 0.3%/wk × severity.

### Stage 8 — Per-distance prediction with range

For each race distance:

```
point_estimate = convert(anchor_pace, from=anchor_distance, to=this_distance)
                 × maintenance_factor              // training stimulus adjusts toward today
                 × context_adjustment              // weather, hills, etc

range_base = tier_base[tier]                       // 1.5% / 3.0% / 5.0%
range = point_estimate
        × range_base
        × distance_volatility[distance]            // mile 1.6×, 5K 1.3×, etc
        × evidence_multiplier[distance][state]     // tight 1.0×, moderate 1.5×, wide 2.5×
        × subjective_range_modifier                // 1.1–1.3× when fatigue signal present
```

## Outputs

### Structured data (for the app)

```
FitnessPrediction {
  // Per-distance predictions
  races: [
    RacePredictionItem {
      distance: "MILE" | "5K" | "10K" | "HALF" | "MARATHON"
      point_seconds: Int
      range_seconds: Int
      state: "tight" | "moderate" | "wide"
      anchor_summary: String              // "race-anchored (Feb 7 31:24)"
      reasoning: String                   // editorial one-liner per distance
      soft_spot: String?                  // what would tighten this prediction
    }
  ]

  // Top-level state
  anchor_race: RaceAnchor?
  confidence_tier: "high" | "medium" | "low"
  
  // Trend assessment
  trend: TrendVerdict {
    phase: "build" | "maintain" | "taper" | "recovery" | "overreach" | "detrain"
    progression: "progressing" | "stable" | "regressing"
    evidence_lines: [String]              // human-readable, e.g. "volume +18% over 4 weeks"
  }
  
  // Evidence breakdown
  evidence: EvidenceReport {
    workouts_in_window: Int
    voice_logs_in_window: Int
    races_used: [DetectedRace]
    qualifying_sessions_by_distance: [Distance: Int]
    parsed_structure_coverage_pct: Int    // diagnostic — flags Observer gaps
  }
  
  // Context applied
  context_notes: [
    ContextNote {
      workout_date: Date
      type: "weather" | "hills" | "treadmill" | "niggle" | "fatigue" | "effort-vs-pace"
      detail: String                      // "Apr 12: 70°F + 98% humidity, -12 sec/mi adj"
      magnitude_sec_per_mi: Int?
    }
  ]
  
  // Goal-vs-truth gap
  goal_gap: GoalGapAnalysis? {
    plan_race_distance: String
    plan_target_seconds: Int
    current_fitness_seconds: Int
    delta_seconds: Int                    // positive = fitness ahead, negative = behind
    delta_pct: Float
    interpretation: String                // "tracking ahead", "edge of capability", "well behind"
  }
  
  // Editorial summaries (LLM-generated, at depth 2+)
  editorial: EditorialReport? {
    headline: String                      // 1-2 sentence top-level coach read
    paragraphs: [String]                  // 2-4 paragraphs of full analysis
    coachable_next: String?               // "what would sharpen this"
  }
}
```

### Editorial outputs (the user-facing text)

The editorial layer is generated by an LLM (Haiku 4.5 for the per-distance
reasoning, Sonnet 4.6 for the trend synthesis and top-level paragraphs).
The Swift engine produces the structured `FitnessPrediction`; the LLM
narrates over it. The math never lives in the prompt.

#### `data_depth` register ladder

| Depth | Trigger | Editorial register |
|---|---|---|
| 0 | New account | Empty state. Plain UI text, no pull-quotes. "Log a run or record a voice note to start." |
| 1 | 1+ run OR 1+ voice log, <7 days | Plain UI text. One muted pull-quote OK if it cites a specific number. |
| 2 | 7+ days of data | Editorial register creeping in. Trend deltas allowed. Short paragraphs. |
| 3 | 21+ days of data OR goal set | Full editorial system. Multi-paragraph coach analysis, every section cites numbers. |

#### Example outputs at depth 3

**Headline (top of screen, 1–2 sentences):**

> Your 10K fitness reads 31:24, anchored to your Feb 7 race in cool weather
> and confirmed by Apr 12's heat-adjusted equivalent. Fitness is stable;
> training has been maintenance, not building.

**Per-distance reasoning (one line each, under each prediction card):**

| Distance | Reasoning |
|---|---|
| Mile | Wide — no anaerobic work shorter than 400m strides in window. |
| 5K | Moderate — Jan 28 mile reps at 5:03 + April track sessions, no recent 5K race. |
| 10K | Tight — two races within 30 seconds, three months apart. |
| Half | Moderate — anchored on March 21 (7mi tempo at 5:21 in a long run), strong but solo. |
| Marathon | Wide — zero textbook MP sessions in last 8 weeks. |

**Trend paragraph (the coach's read on trajectory):**

> Volume is solid at 59 mi/wk but the last 3 weeks have no structured
> quality work in your parsed logs — just steady running. Three voice
> notes mentioning "tired" or "struggling" in the last 10 days. **Phase
> reads as maintaining, not building**; progression signal is stable
> (no matched-workout PRs since the Cap 10K block).

**Soft-spot callout (what would sharpen the read):**

> A tempo session at HMP this week — 7 miles with 4–5 miles at 5:25/mi —
> would move the half from moderate to tight. An 18-mile long run with
> the last 6 at MP would collapse the marathon range by roughly 40%.

**Goal-vs-current (when a plan exists):**

> Plan goal is 2:35 marathon; current fitness reads 2:27–2:32. You're
> tracking 3–8 minutes ahead of plan, contingent on building the
> marathon-specific endurance currently missing.

## Reasoning surfaces — how the predictor explains itself

Every editorial claim must trace to structured evidence. The reasoning
surfaces in the UI:

### 1. **Tap a prediction → evidence drawer**

Tapping any of the 5 distance cards expands a drawer showing:

- Anchor used (race or training anchor, with date and conditions)
- Qualifying sessions for this distance, listed with date + paces
- Adjacent-distance evidence applied (with weight)
- Context adjustments (weather, hills, treadmill)
- What would change the state (e.g., "1 more 18-mile run with MP segment → tight")

### 2. **"Why this trend?" — trend evidence panel**

Below the trend phase tag, an expand-to-reveal shows the four signals:

- Volume: 59 mi/wk (4w avg), prior 4w 61 mi/wk → -3%, stable
- Quality (HMP-zone volume): 7 miles in last 4 weeks vs 14 in prior 4 → -50%, declining
- Matched workouts: tempo paces from April vs March averaged within 5 sec/mi → stable
- Subjective: 4 of last 6 voice logs mention fatigue or struggle → negative

### 3. **Context log**

A timeline view showing which workouts had context adjustments applied:

> Apr 12 (Cap 10K) — adjusted -12 sec/mi for heat + humidity
> May 5 (tempo) — adjusted -8 sec/mi for humidity  
> May 9 (long run) — flagged as "first long run in a while," range widened

### 4. **Data quality dashboard**

A diagnostic section (collapsed by default at depth 3, expanded at depth 1
when coverage is low):

- Workouts with `parsed_structure`: 14 / 81 (17%) ← red flag, needs Observer backfill
- Workouts with weather data: 0 / 81 (0%) ← red flag, reconciliation gap
- Voice logs in last 14 days: 5 (good coverage)
- Days since last hard effort: 9 ← yellow flag

This surface makes data-collection gaps visible and actionable — the
predictor tells the user *why* its read isn't sharper.

## UI layout (proposed screen structure)

```
┌─────────────────────────────────────────────┐
│  FITNESS PREDICTOR                          │
│  ┌───────────────────────────────────────┐  │
│  │ 10K  31:24  ·  Feb 7  ·  14w ago      │  │
│  │ Cool conditions, all-out effort       │  │
│  │ Confirmed by Apr 12 (heat-adjusted)   │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ━━━━━━━ COACH READ ━━━━━━━                 │
│  "Your fitness reads ~31:00–32:00 in cool   │
│   weather, anchored on Feb 7. Two races     │
│   agreeing within 30 sec. Trend is          │
│   maintaining, not building — quality work  │
│   has lightened in the last 3 weeks."       │
│                                             │
│  ━━━━━━━ RACE PREDICTIONS ━━━━━━━           │
│  ┌─────┐ ┌─────┐ ┌─────┐                    │
│  │MILE │ │ 5K  │ │ 10K │                    │
│  │4:25 │ │15:08│ │31:24│                    │
│  │±:12 │ │ ±:25│ │ ±:30│                    │
│  │wide │ │ mod │ │tight│                    │
│  └─────┘ └─────┘ └─────┘                    │
│  ┌─────────────┐ ┌─────────────┐            │
│  │   HALF      │ │  MARATHON   │            │
│  │  1:09:30    │ │   2:30      │            │
│  │   ±1:00     │ │   ±2:30     │            │
│  │ moderate    │ │   wide      │            │
│  └─────────────┘ └─────────────┘            │
│  Tap any card for evidence & reasoning      │
│                                             │
│  ━━━━━━━ TREND ━━━━━━━                      │
│  Phase: Maintaining (post-race)             │
│  Progression: Stable                        │
│  ▸ Why? (expand)                            │
│                                             │
│  ━━━━━━━ WHAT WOULD SHARPEN ━━━━━━━         │
│  • HMP tempo this week → tightens half      │
│  • 18mi long run w/ MP finish → marathon    │
│  • Voice log on May 5 + May 9 needs parse   │
│                                             │
│  ━━━━━━━ GOAL vs CURRENT ━━━━━━━            │
│  Plan: 2:35 marathon (Chicago, Oct 12)      │
│  Current: ~2:30 → tracking 5 min ahead      │
│                                             │
│  ━━━━━━━ EVIDENCE ━━━━━━━ (collapsed)       │
│  ▸ 81 workouts · 81 voice logs · 27 snaps   │
│  ▸ Confidence: HIGH                         │
│  ▸ Data quality: parsed coverage 17% ⚠     │
└─────────────────────────────────────────────┘
```

## Failure modes the redesign explicitly prevents

The current predictor fails silently in several ways. The redesign
addresses each with a structural fix:

| Failure | Cause | Redesign fix |
|---|---|---|
| Wrong race anchors the prediction | `detectedRaces.first` picks most recent | Anchor selection picks fastest in trusted window (May 11 fix) |
| Tempo workouts misdetected as races | Loose keyword match on "race"/"mile" | Workout-context filters in `detectRaces` (May 12 fix) |
| Snapshot decays even when training continues | Unconditional 0.3%/wk decay | Decay gated by detraining signal (May 11 fix) |
| Stale snapshot keeps stale prediction visible | "Skip if today exists" save behavior | Upsert on today's row (May 12 fix) |
| Marathon prediction inherits 10K confidence | Flat percentage range per tier | Per-distance evidence + volatility multipliers |
| Voice log notes ignored | Predictor reads pace + parsed_structure but not narrative | LLM narrative layer reads notes for context, niggles, mood, effort signals |
| Weather context discarded | Column populated but not read | Wire `weather_adjusted_pace_delta` into anchor + workout pace adjustments |
| Treadmill workouts get weather adjustment | No workout_style distinction | Add `workout_style` column; gate weather/context by style |
| Goal masks current fitness | Plan goal used as anchor when no race | Plan goal only at depth 0/1; tier ceiling at "medium" when goal-anchored |
| Trend invisible to user | "improving / maintaining" tag in `dataSource` but not surfaced | Explicit phase + progression signal in output, narrated by LLM |
| Editorial output is one sentence | Today's `fitnessSummary` is a single-line summary | Multi-paragraph paragraph-style coach analysis, depth-gated |

## Implementation order (suggested)

1. ✅ Snapshot decay → conditional on detraining (May 11)
2. ✅ Anchor selection → fastest race in trusted window (May 11)
3. ✅ Race detection → workout-context filters (May 12)
4. ✅ Snapshot save → upsert today's row (May 12)
5. **Observer trigger + backfill** — Items 4 from leverage stack. Single migration. Highest unblocker.
6. **`workout_style` column** — Schema migration. Defaults to outdoor_run. UI toggle for after-the-fact correction.
7. **Weather adjustment wiring** — Swift model field, fetchTrainingLogs select, generateLocalPrediction adjustments (gated by workout_style).
8. **Per-zone volume accumulation** — Replace the current `hardEffortTypes` stimulus model with the segment-by-zone accumulator. Requires `parsed_structure` coverage from #5.
9. **Per-distance evidence assessment** — Tight/moderate/wide state per distance, with range multipliers.
10. **Matched-workout comparison engine** — Cluster segments by family + similarity, compute pace deltas.
11. **Trend assessment (four-signal composite)** — Phase + progression detection.
12. **Editorial narrative layer** — New edge function `fitness-predictor.v2` (Sonnet 4.6) that reads the structured `FitnessPrediction` and writes the headline + paragraphs + soft spots.
13. **UI redesign** — New layout per the proposed structure above. Tap-to-expand evidence drawers. Trend panel with "why" expander.

Steps 1–4 are shipped. Step 5 (Observer trigger + backfill) is the highest
remaining unblocker — without parsed_structure coverage, steps 8+ have
no structured data to consume. Steps 6 and 7 can run in parallel with 5.

## Open questions for review

1. **`workout_style` vocabulary scope.** Proposed: outdoor_run, treadmill,
   indoor_track, track, trail, race, unknown. Tight or want more?
2. **Long-run-finish bonus magnitude.** 1.3× felt right. Tune?
3. **Tier base ranges.** 1.5% / 3% / 5%. Reasonable for high/medium/low?
4. **Evidence-state thresholds.** 3+ qualifying sessions = tight, 1–2 =
   moderate, 0 = wide. Tune the thresholds?
5. **Trend window.** 4-week recent vs 4-week prior. Match training-block
   reality, or shorter (2v2) to catch fast changes faster?
6. **Editorial register intensity.** How chatty should the depth-3 paragraphs
   be? Single tight paragraph, or up to 4? Length affects scan speed.

When you sign off on direction, the implementation order above is concrete
enough to start crossing items off.

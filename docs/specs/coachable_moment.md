# coachable_moment — V1 spec

## Purpose

A single piece of attention a coach should give to one athlete, right now.
Generated automatically when rule conditions are met. Coach handles or dismisses.

A coachable moment is the V1 surface of the real-time synthesis path: it
fuses qualitative voice-log signal with quantitative training-load context
into a single actionable card the coach sees in their dashboard.

## Schema

| Field             | Type        | Notes                                                                 |
|-------------------|-------------|-----------------------------------------------------------------------|
| `id`              | uuid, pk    | `gen_random_uuid()`                                                   |
| `athlete_user_id` | text        | `auth.uid()::text` of the athlete (matches existing convention)       |
| `coach_id`        | uuid, fk    | `coach_profiles.id` — denormalized so we don't recompute on read      |
| `triggered_at`    | timestamptz | When the rule fired                                                   |
| `rule_id`         | text        | Which rule fired — e.g. `load_spike_plus_injury`                      |
| `severity`        | text enum   | `low` \| `med` \| `high`                                              |
| `action_type`     | text enum   | `send_check_in` \| `suggest_deload` \| `recommend_evaluation` \| `monitor` \| `suggest_extra_recovery` |
| `summary`         | text        | Templated, ~2 sentences                                               |
| `source_log_ids`  | uuid[]      | training_log ids that triggered the moment                            |
| `status`          | text enum   | `open` \| `handled` \| `dismissed` (default `open`)                   |
| `handled_at`      | timestamptz | Set when status leaves `open`                                         |
| `created_at`      | timestamptz | Default `now()`                                                       |

## V1 trigger rules

### 1. `load_spike_plus_injury`

- Weekly volume in last 7d is **>20% above** the rolling 4-week weighted average
- AND ≥1 injury keyword present in voice logs in last 14d
- → severity: `high`, action: `recommend_evaluation`

### 2. `low_mood_streak`

- Last 3 voice logs all have mood label in `{tired, struggling, injured}`
- → severity: `med`, action: `suggest_deload`

### 3. `missed_workouts`

- 2+ scheduled workouts skipped in current week
- → severity: `low`, action: `send_check_in`

### 4. `weather_impacted_quality`

- Most recent quality session (tempo / threshold / interval / long_run / MP / race) in last 3 days
- AND dewpoint at workout time ≥ 65°F
- AND heat-adjusted pace delta ≥ 10 sec/mi (real performance penalty)
- AND athlete mood label in `{tired, struggling, injured}`
- → severity: `med`, action: `suggest_extra_recovery`

The recovery framing is intentional: athlete didn't fail the workout, the
weather cost the raw pace. Coach response should protect 24-48h of recovery
and defer the next quality session if residual fatigue persists, rather than
treat it as a fitness regression.

## Lifecycle

```
open → handled    (coach hit "Take Action")
open → dismissed  (coach hit "Dismiss")
```

No expiration, no snooze, no re-fire suppression. V2 problems.

## Templated summary format

```
"{athlete_name} — {plain-English signal}. Source: {n} voice logs, {m} workouts."
```

Example:
```
"Sarah — weekly volume 22% above rolling avg with 'right hip tight' in 2 of last 3 logs. Source: 3 voice logs, 4 workouts."
```

No LLM in V1. Templates only.

## Coach UI (one card)

```
[severity color stripe]
{summary}
[Take Action]  [Dismiss]
```

Tap card → athlete detail with source logs highlighted.

## Athlete UI

None in V1.

## Out of scope (explicit V2)

- Multi-athlete pattern moments
- LLM-written summaries
- Personalized severity baselines
- Confidence scoring
- Snooze / re-fire suppression
- Athlete-facing surface
- Intensity load analysis (fast-volume, MP+ time, workout density)
- Skip-reason routing (rule 3 splits into 3a body / 3b schedule)
- `reschedule_workouts` action_type

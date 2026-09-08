# AI Feedback Loop: Codebase Exploration Report
**Date:** 2026-07-07  
**Status:** Medium-thorough exploration complete  
**Purpose:** Map existing feedback capture, memory architecture, prompt system, and coach surfaces so new AI feedback loop design builds on proven patterns, not duplicates.

---

## 1. EXISTING FEEDBACK CAPTURE

### Tables & Columns

| Table | Columns | Purpose | State |
|-------|---------|---------|-------|
| `coaching_feedback` (20260318100000) | `id`, `user_id`, `conversation_id`, `message_id`, `rating` (-1/1, thumbs), `feedback_text`, `message_content` (snapshot), `query_complexity`, `model_used`, `created_at` | Athlete rate individual coaching AI messages; **prompt feedback loop input** | **Working** — indexes on user/conversation/rating/created; RLS athlete-writable |
| `coaching_adjustments` (20260318100000) | `id`, `user_id`, `week_start`, `adjustment_type` (volume/intensity/recovery/workout_swap/pace_target/cross_training/other), `target_workout`, `recommendation`, `source`, `source_reference_id`, `followed` (bool), `outcome_notes`, `outcome_metrics` (JSONB), `created_at`, `resolved_at` | Track AI/coach suggestions → whether athlete followed → outcome | **Working** — unresolved index; soft-gated for future analysis |
| `plan_adjustments` (20260417600000) | `id`, `user_id`, `plan_id`, `trigger_type`, `trigger_evidence` (JSONB), `action_type`, `action_payload` (before/after/diff), `auto_applied`, `applied_at`, `acknowledged_by_user_at`, `reverted_at`, `proposed_until` | **Comprehensive audit ledger** of every plan mutation: system-driven *and* user/coach actions. **Recent extension (20260703120000):** added `trigger_type: 'user_action'` and `'coach_rewrite'`; `action_type: 'rewrite_block'`; reason_code field for coach rationale | **Working** — feeds coach portal adjustments feed; **NOTE:** `shift-day` was inserting `trigger_type='user_action'` since April but the CHECK rejected it silently. Fixed in 20260703120000. |
| `scheduled_workouts` (planned, not yet live) | `coach_instruction` (TEXT), `athlete_feedback` (JSONB), `athlete_feedback_at` (TIMESTAMPTZ) | **Per-workout athlete quick-take** after completion: RPE + feel chip (nailed_it/solid/struggled/cut_short) + optional comment. Coach view: plan calendar shows planned-vs-actual + feedback chip; week strip rolls up compliance % + mileage vs range + key-session outcomes | **Designed in adaptive-coach-plan-builder-spec-2026-07-03 §R7**; migration not yet applied. **Will close the feedback loop at two grains:** per-workout (athlete reaction) + per-coach (reply via coach_notes threaded to workout_id). |
| `user_memories` (20260202) | `id`, `user_id`, `category`, `content`, `source_conversation_id`, `extracted_from`, `importance`, `expires_at`, `created_at`, + **new hygiene columns (20260702190000):** `status` (active/archived), `source` (chat_regex/memo_llm/consolidation), `their_words`, `memory_date`, `last_confirmed_at`, `mention_count` | **Durable fact store** — athlete's preferences, PRs, life context, constraints. The foundation for **per-athlete preference profile** injection into prompts. See §2 below. | **Implemented 2026-07-02** — 10 rows from chat regex; new memo LLM extraction ready (process-training-memo.v3 shipped, Step 2 complete). Memory is revocable (athlete swipe-to-forget DELETE policy). |

### Edge Functions Capturing Feedback

| Function | Captures | Channels To | Notes |
|----------|----------|------------|-------|
| `coaching-feedback/index.ts` | Thumbs ±1 on coaching messages (direct athlete POST) | `coaching_feedback` table | Stores message snapshot + query complexity + model used — **ready for prompt-refinement loop** if an LLM learns from negatives. Unconnected to any ML yet. |
| `post-run-reconciliation` | RPE from voice log → reconciles against `scheduled_workouts` | `training_log.rpe` column | Athlete never *sees* this as feedback UI; purely internal signal. **Future:** tie to the planned `athlete_feedback` column. |
| `process-training-memo/index.ts` | Athlete's memo text (free-form voice/text) → LLM extracts facts + tone + goals + niggles | `user_memories` (memo LLM source), `niggle_mentions`, `training_log.coach_insight` | **Memory extraction is the key feedback loop.** Memo is *continuous* athlete feedback on training + life + mood. Step 2 of long-term-memory plan (20260702) complete — v3 prompt now extracts `memory_candidates` array with no extra LLM call. |
| `evaluate-coachable-moment` | Rule engine reads athlete's recent logs + injury + mood + load + plan → fires triggers | `coachable_moments` table | Coach-facing only. Rules live in `_shared/rules/` (load_spike_plus_injury, low_mood_streak, missed_workouts). **Not athlete feedback, but a coach signal based on athlete data.** |
| `coaching-daily-read` | Builds Daily Read prompt → LLM generates `sections` array | `athlete_state` context (athlete's preference profile is read here) | **Read is the output that closes the loop:** if athlete's feedback says "too much intensity," the next Read should reflect that. Done via athlete_state + memory. |

### Summary: What's Captured Today

1. **Thumbs ±1 on advice** → `coaching_feedback` table (exists, unused downstream)
2. **Advice followed/not followed + outcome** → `coaching_adjustments` table (schema ready, no inference loop yet)
3. **Memos as continuous feedback** → `user_memories` (memo LLM extraction live as of Step 2, 2026-07-02)
4. **Plan adjustments audit trail** → `plan_adjustments` ledger (comprehensive, coach-authored + user-authored rows)
5. **Per-workout quick-take** → **Planned (not yet live)** `scheduled_workouts.athlete_feedback` + `athlete_feedback_at` (spec in §R7 of adaptive-coach-plan-builder-spec)

---

## 2. ATHLETE_STATE: The Per-Athlete Preference Profile

**Location:** `/supabase/functions/_shared/athlete-state.ts` (~2,555 LOC, heavily tested)  
**Backing table:** `athlete_state` (20260410200000_create_athlete_state.sql)  
**Consumers:** 12 edge functions read via `getOrBuildAthleteState()` → `stateToPromptContext()`

### What athlete-state Builds (Top-Level Shape)

```typescript
interface AthleteState {
  // Identity + goals
  user_id: string;
  experience_level: string;  // "beginner" | "intermediate" | "advanced"
  current_phase: string;      // "base" | "build" | "specific" | "taper"
  goal_race: string;
  goal_time_seconds: number;
  
  // Load + fatigue
  acwr: number;                      // acute-chronic workload ratio
  rolling_7d_miles: number;
  rolling_28d_miles: number;
  monotony_7d: number;
  strain_7d: number;
  
  // Mood + trend
  last_mood: string;                 // "great" | "good" | "okay" | "tired" | "heavy"
  mood_trend: string;                // rolling 14d direction
  
  // Fitness
  fitness_trend: string;             // "rising" | "stable" | "dipping"
  fitness_vs_6mo_ago_label: string;
  
  // Schedule adherence
  week_compliance_pct: number;       // % of planned workouts completed
  
  // Injuries (safe guardrails)
  current_niggles: Niggle[];         // keyword scan + athlete-reported; never diagnose
  possible_injuries: string[];       // conservative language, flag for coach
  
  // Memories (the preference profile!)
  top_memories: UserMemory[];        // quota-selected: up to 3 constraints, 3 preferences, 2 life, 2 PR/race, 2 episodes
  year_ago_arc: string;              // "This time last year: ~32 mpw, mood mostly neutral"
  
  // Data depth (UI gate)
  data_depth: number;                // 0–3 (new account → 21+ training days + goal)
  
  // Context for prompt budget
  cant_see: string[];                // gaps in the data (e.g., "no VO2 fitness numbers yet")
  
  // Computed once, stored
  created_at: string;
  updated_at: string;
}
```

### How athlete_state Is Consumed

**The prompt-inject pattern:**

```typescript
// In any edge function that calls an LLM:
const athleteState = await getOrBuildAthleteState(supabase, userId);
const athleteContext = stateToPromptContext(athleteState);  // bounded ~400 tokens

// Inject into prompt template:
const promptText = loadPrompt("coaching-daily-read.v5", {
  athlete_context: athleteContext,
  this_week_workouts: "...",
  // ...other subs...
});
```

**Key builders (in `athlete-state.ts` — all pure functions, heavily unit-tested):**

- `buildIdentity()` → profile, goal, phase
- `buildLoadMetrics()` → 7d/28d rolling miles, ACWR (Acute-Chronic Workload Ratio), monotony, strain
- `buildMoodTrend()` → rolling 14d mood from voice logs + check-ins
- `buildPaceZones()` → reads athlete_pace_profiles table (V2 alignment)
- `buildRecentWorkouts()` → last 14 days
- `buildScheduled()` → this week's plan
- `buildPossibleInjuries()` → keyword scan with guardrails (never diagnose; flag for coach)
- `buildBlocks()` → 4-week rollups
- `buildTrajectory()` → fitness trend (rising/stable/dipping)
- ✅ **NEW (Step 5, 2026-07-02):** `buildYearAgoArc()` → 365d history; one line per Read ("this time last year: ~32 mpw")

### The Preference Profile Injection (Memories)

**Location of memory selection:** `_shared/memorySelection.ts` (Step 5, implemented 2026-07-02)

```typescript
export function selectMemoriesForPrompt(
  allMemories: UserMemory[],
  budget: PromptBudget
): QuotaSelection {
  // Quota: 3 constraint + 3 preference + 2 life + 2 pr·race + 2 episode = 12 max
  // Within each quota: score by importance × recency(last_confirmed_at)
  // Status filter: active only, not archived
  // Episode dates included: "Jan 14 — their words: 'the day it clicked'"
  
  return selected;
}
```

**How memories feed prompts:**

- **Daily Read (coaching-daily-read.v5):** Up to 2 episode callbacks per Read max (warm, not surveilled)
- **Coaching Agent:** Full quota for nuanced advice
- **Injury Analysis:** Constraints + injury history
- All: **"What I remember about you"** summary section (athlete-facing; visible in Model of You)

---

## 3. PROMPT ARCHITECTURE

**Location:** `/supabase/functions/_shared/prompt-library.ts` (barrel export + registry)  
**Prompts live in:** `/supabase/functions/_shared/prompts/`

### Prompt Registration Pattern

```typescript
// prompt-library.ts
import { TEMPLATE as COACHING_DAILY_READ_V1 } from "./prompts/daily-read.v1.ts";
import { TEMPLATE as COACHING_DAILY_READ_V5 } from "./prompts/daily-read.v5.ts";
// ... 50+ prompts registered ...

const REGISTRY = new Map<string, string>([
  ["coaching-daily-read.v1", COACHING_DAILY_READ_V1],
  ["coaching-daily-read.v5", COACHING_DAILY_READ_V5],
  // ...
]);

export function loadPrompt(name: string, subs: Record<string, string>): string {
  const template = REGISTRY.get(name);
  if (!template) throw new Error(`Prompt not found: ${name}`);
  
  // Strict substitution: unresolved {{placeholder}} and unused vars throw
  return strictSubstitute(template, subs);
}
```

**Why this pattern (from prompt-library.ts header):**
- **Versioning:** Filename suffix `.v1`/`.v2` = version. A/B test against priors.
- **Drift control:** Prompts in dedicated `.ts` files, diffable in PR review.
- **Eval coverage:** Centralized registry lets the eval harness run prompts.
- **Atomicity:** Static TS imports bundled with edge functions; prompts deploy with functions.

### Key Prompts (Especially Coaching & Feedback-Relevant)

| Prompt | Versions | Purpose | Context Injected | Notes |
|--------|----------|---------|------------------|-------|
| `coaching-daily-read` | v1–v5 (v5 current, 2026-06-16) | Weekly top-of-screen snapshot — athlete's training, mood, goals, race prep. **The main AI output the athlete sees.** | `{{athlete_context}}`, `{{this_week_workouts}}`, `{{mood_trend}}`, `{{possible_injuries}}`, `{{goal_race}}`, `{{long_run_details}}` | v5 added editorial sections (The Week, Hard Days, Long Run, How You Felt, One Thing) + eyebrow scope line + standalone question field. Memories with episodes can be referenced: `{text: "the long run", workout_id: uuid}`. **Voice rule:** athlete's words, never inferred psychology; predictions = range + confidence. |
| `coaching-agent-*` | simple/moderate/complex/proactive (v1 each) | Chat with athlete during a conversation; four complexity levels | Full athlete_state including memories | Complex version can reference memories; proactive version uses coachable_moments + plan context to surface advice before athlete asks. |
| `process-training-memo` | v1, v2, **v3 (2026-07-02)** | Parse voice memo → extract facts, mood, niggle mentions, **memory candidates** | Memo text; **v3 NEW:** memo context + previous memories for dedup | **v3 adds `memory_candidates` array to JSON output:** category, content, their_words, durable, importance. Zero extra LLM call. Dedup-or-reinforce logic lives in `_shared/memoryWriter.ts`. |
| `generate-workout-insight` | v1–v5 (v5 current) | One-liner after athlete logs a run; contextual coaching take | Workout data, athlete mood, recent trend, coach's instruction if set | Pulls from `scheduled_workouts.coach_instruction` if coach annotated the day. |
| `injury-analysis` | v1 | Deep-dive on a niggle mention; coach-facing advisory | Niggle text, medical history, 28-day load trend, injury_mentions table | **Conservative language enforced:** no diagnosis; flag for coach review. |
| `reschedule-plan` | v1 | AI proposes a plan rewrite after athlete requests or after event (sickness, race, life event) | Current plan, target start date, athlete's pace profile, ACWR-safe ramp constraints | Closed workout library; auto_applied=false (coach reviews diff first); one rewrite per day max. See revert-plan-adjustment for undo. |
| `parse-goal` | v1 | Parse athlete's written race goal → {distance, target_time, confidence_pct} | Goal text, athlete's recent PRs | Registered in user_goals; feeds race-prediction models. |
| `parse-manual-workout` | v1 | Parse shorthand ("5×1000 at 5K pace" from iOS app) → structured steps | Shorthand; pace zones for the athlete | Bridges human language → structured data. |

### How Daily Read Gets athlete_context (The Feedback Loop Injection Point)

**In `coaching-daily-read/index.ts`:**

```typescript
// Fetch the preference profile
const athleteState = await getOrBuildAthleteState(supabase, userId);
const athleteContext = stateToPromptContext(athleteState);

// This context includes:
// - "You're chasing a 3:16 marathon; your 3:28 was 18 months ago"
// - "Over the last 4 weeks your mood has been trending toward 'heavy'"
// - "Achilles has been mentioned 3 times in the last 8 weeks"
// - "You love early mornings and hate treadmills" (from memories)
// - "This time last year: ~32 mpw, mood mostly neutral"
// - "Right now: 42 mpw, fitness rising, strain high"

// Load the prompt and inject it
const prompt = loadPrompt("coaching-daily-read.v5", {
  athlete_context: athleteContext,
  this_week_workouts: JSON.stringify(weeklyWorkouts),
  goal_race: athleteState.goal_race,
  // ...
});

// Call LLM
const response = await model.generateContent(prompt);
```

**The athlete_context renders as one section in the prompt:**
```
You're coaching ${experience_level}. They're ${current_phase} phase, chasing ${goal_race} in ${weeks_until} weeks.
...
What you remember about them:
- ${memories[0].content}
- ${memories[1].content}
...
Right now: ${rolling_7d_miles} mi this week (${rolling_28d_miles} over 4wks), 
mood trending ${mood_trend}, fitness ${fitness_trend}.
...
Cant see yet: ${cant_see.join("; ")}
```

---

## 4. EVAL HARNESS

**Location:** `/supabase/functions/_evals/`

### Cassette Structure

**Per-prompt directory:** `_evals/cassettes/<prompt-name>.<version>/`

```
process-training-memo.v3/
├── input_1.json          # { memo_text, context? }
├── rubric_1.json         # { checks: [{ id, title, pass_criteria }] }
├── recorded_response_1.json  # { memory_candidates: [...], niggle_mentions: [...] }
├── input_2.json
├── rubric_2.json
├── recorded_response_2.json
└── ... (≥3 cassettes per prompt required by CI gate)
```

**Rubric format:**
```json
{
  "checks": [
    {
      "id": "memory_extraction_no_health_infer",
      "title": "Memory candidates don't infer health diagnosis",
      "pass_criteria": "No 'seems stressed', 'possible anxiety', etc. Only athlete's words."
    },
    {
      "id": "episode_has_their_words",
      "title": "Episodes include verbatim phrase",
      "pass_criteria": "their_words field populated when category=='episode'"
    }
  ]
}
```

### CI Eval Gate

**Trigger:** Commit touches a file matching `supabase/functions/_shared/prompts/<name>.ts`

**Check (`.github/scripts/check_eval_coverage.py`):** Directory `_evals/cassettes/<name>.<version>/` must exist with ≥1 file.

**Status:**
- ✅ Gate enforces cassette presence for all existing prompts
- ✅ Process-training-memo.v3 cassettes authored (6 files), includes v2 regression guards
- ⏳ **Cassette *recording* (populating recorded_response) needs GEMINI_API_KEY** — only done at deploy time (Step 8 of long-term-memory plan)

### What's Needed to Add Coverage for a New/Changed Prompt

1. **Create cassette input files** with representative examples (3+ cases)
2. **Write rubrics** — one per example, 3–5 checks each
3. **Leave `recorded_response` empty** (string: `""`)
4. **Commit the cassette dir** → CI gate passes
5. **At deploy time:** Run `deno run -A _evals/record.ts <prompt-name>.<version>` with `GEMINI_API_KEY` → records live responses
6. **Manual review:** Spot-check 3–5 records against rubric + design principles

---

## 5. EXISTING PER-ATHLETE SETTINGS & MEMORY STORAGE

### athlete_plan_subscriptions (20260425200000)

**Columns:** All nullable, athlete overrides coach defaults

| Column | Type | Purpose | Used By |
|--------|------|---------|---------|
| `rest_dows` | INTEGER[] | Days athlete wants complete rest (e.g., [0,3] = Sun, Wed) | `subscribe-to-plan` materializer |
| `preferred_quality_dows` | INTEGER[] | Days athlete prefers hard sessions (e.g., [2,6] = Tue, Sat) | Materializer templates onto same skeleton |
| `long_run_dow` | INTEGER | Single day for long run (typically Sat/Sun) | Materializer |
| `volume_ramp` | JSONB | Shape: {start_mileage, ramp_to_coach_target, ramp_weeks} | Ramp scheduler in materializer |
| `shape_prefs` | JSONB | {strides_pre_quality, recovery_after_long, doubles_on_easy_days} | Materializer structure |
| (unnamed baseline col) | — | Athlete-reported starting fitness at subscription time | Pre-populates from 4-week rolling avg if logs exist |

**Used By:** `subscribe-to-plan/index.ts` (1255 LOC) — materializer that fills easy days per athlete's schedule preferences + paces + recovery weighting.

### athlete_state.data_depth (20260522130643)

**Type:** INTEGER (0–3)  
**Computed in:** `rebuildAthleteState()` → `computeDataDepth()`

| Level | Condition |
|-------|-----------|
| 0 | New account, no runs/voice logs |
| 1 | 1+ run OR 1+ voice log |
| 2 | 7+ distinct training days |
| 3 | 21+ distinct training days, OR goal set + 1+ run |

**Used for:** UI register gate (don't show certain features until athlete has logged enough data). Rendered in athlete_state prompt context.

### user_memories (20260202 + 20260702190000 Hygiene)

**Columns (post-hygiene update 2026-07-02):**

| Column | Type | Purpose |
|--------|------|---------|
| `id` | UUID | PK |
| `user_id` | TEXT | auth.uid()::text |
| `category` | TEXT | pr \| race \| preference \| constraint \| life \| gear \| episode |
| `content` | TEXT | One sentence (athlete's framing) |
| `source_conversation_id` | UUID | FK; legacy |
| `extracted_from` | TEXT | Memo excerpt (≤200 chars) or chat msg excerpt |
| `importance` | INTEGER | 1–10; bumped on re-mention |
| `status` | TEXT | active \| archived (new, 20260702) |
| `source` | TEXT | chat_regex \| memo_llm \| consolidation (new, 20260702) |
| `their_words` | TEXT | Verbatim phrase (episodes only; new, 20260702) |
| `memory_date` | DATE | When the remembered thing happened (episodes only; new, 20260702) |
| `last_confirmed_at` | TIMESTAMPTZ | Most recent re-mention (new, 20260702) |
| `mention_count` | INTEGER | How many times re-mentioned; dedup-or-reinforce signal (new, 20260702) |
| `expires_at` | TIMESTAMPTZ | For transient memories (life context; +60d if durable=false in LLM output) |
| `created_at` | TIMESTAMPTZ | Insertion time |

**RLS:** Athlete can SELECT (all rows) and DELETE (own rows only).

**Lifecycle (2026-07-02 Step 3):**
- **New memory:** LLM identifies candidate in memo → `_shared/memoryWriter.ts:planMemoryWrites()` dedup-checks (token overlap ≥0.7) → if near-dup exists, bump mention_count + importance, update last_confirmed_at (no new row) → else INSERT
- **Weekly consolidation:** `consolidate-memories` edge function (pg_cron Sun 04:30 UTC) → merge remaining dupes / archive expired + stale-low-importance / cap per category (10 active max per category, lowest importance archived first)
- **Deletion:** Athlete swipe-to-forget in Model of You surface → DELETE via RLS policy

---

## 6. COACHABLE_MOMENTS PIPELINE

**Table:** `coachable_moments` (20260428100000 + 20260429110000 unique-open-per-rule constraint)

### Schema

| Column | Type | Purpose |
|--------|------|---------|
| `id` | UUID | PK |
| `athlete_user_id` | TEXT | auth.uid()::text of athlete |
| `coach_id` | UUID | FK to coach_profiles |
| `triggered_at` | TIMESTAMPTZ | now() |
| `rule_id` | TEXT | load_spike_plus_injury \| low_mood_streak \| missed_workouts |
| `severity` | TEXT | low \| med \| high |
| `action_type` | TEXT | send_check_in \| suggest_deload \| recommend_evaluation \| monitor |
| `summary` | TEXT | Templated, ~2 sentences (no LLM text; safe) |
| `source_log_ids` | UUID[] | training_log IDs cited as evidence |
| `status` | TEXT | open \| handled \| dismissed |
| `handled_at` | TIMESTAMPTZ | Stamped when status leaves 'open' |
| `created_at` | TIMESTAMPTZ | now() |

### Rules Engine

**Location:** `_shared/rules/index.ts` (rule registry) + individual rule files

| Rule | File | Triggers | Evidence |
|------|------|----------|----------|
| `load_spike_plus_injury` | loadSpikePlusInjury.ts | Acute-chronic workload ratio spike + recent niggle mention | 7d-vs-28d miles + injury_mentions table |
| `low_mood_streak` | lowMoodStreak.ts | Mood "heavy" or "tired" for 4+ consecutive days | training_log.mood (last 10 days) |
| `missed_workouts` | missedWorkouts.ts | Athlete skipped 2+ scheduled quality sessions in a week | scheduled_workouts.status vs training_log reconciliation |
| `build_vs_last_cycle` | buildVsLastCycle.ts | Current block significantly harder/easier than comparable historical block | weekly_analytics rollups (4-week blocks) |
| `weather_impacted_quality` | weatherImpactedQuality.ts | Athlete had bad weather on hard day + performance dipped | weather_actual + workout_pace_per_mile vs target |

### Pipeline Flow: Observation → Coachable Moment → Coach Action

1. **Trigger:** `evaluate-coachable-moment` edge function (called by pg_cron for all active athletes with active coaches, post-logging)
   - Input: athlete_user_id
   - Fetches: last 14 days of training_logs + current injuries + plan context
   - Runs: all 5 rule functions against the context
   - Output: array of fired rules

2. **Write:** For each fired rule:
   - Check unique constraint: `(athlete_user_id, coach_id, rule_id, status='open')` — only one open per rule+athlete per coach
   - If exists: skip (don't spam)
   - Else: INSERT coachable_moment

3. **Outbox/Drain:** `drain-coachable-moment-jobs` (pg_cron, runs hourly)
   - Read recent open moments
   - Push to coach dashboard / notification service
   - Mark status=handled (or remain open if coach hasn't seen)

4. **Coach action:** Coach sees moment in dashboard → handles/dismisses → updates status
   - Status change triggers `set_coachable_moment_handled_at()` trigger
   - Audit trail: coach can review "what flagged this athlete and when?"

### Outbox Pattern (Used for All Async Work)

**Tables:**
- `coachable_moment_outbox` (20260518100000) — outbox entry per moment
- `coach_insight_outbox` (20260609233455) — for workout insights
- `voice_processing_jobs_outbox` (20260610230012) — for voice transcription

**Pattern:** Insert → Drain function reads → publishes → clears

**Cron schedule:** varies per outbox (hourly / nightly / on-demand).

---

## 7. COACH PORTAL SURFACES

**Web path:** `/web/src/app/(app)/coach-portal/`

### Athlete Detail Page (`athletes/[id]/page.tsx`)

**Surfaces:**
1. **Header** — athlete name, current plan, week N of M, goal time + race date
2. **This Week Calendar** — 7-day strip with status pills (completed/upcoming/skipped/modified) + miles
3. **Recent Activity** — last 14 days of training_logs; prescribed-vs-actual
4. **Training Load Metrics** — compliance %, ACWR, rolling miles, fitness trend
5. **Coachable Moments Card** — recent open/dismissed moments via `evaluate-coachable-moment`
6. **Plan Adjustments Feed** — `plan_adjustments` ledger (coach + athlete edits), newest first, tier-colored

**Components:**
- `CoachableMomentCard` — displays severity + action + summary; coach can mark handled/dismissed
- `PlanAdjustmentsFeed` — shows reason + payload diffs; coach can review or act

### Edit Plan Page (`athletes/[id]/edit-plan/page.tsx`)

**Planned (20260703 spec §R5, not yet live):**
- **Scope selector:** pick week range for rewrite (future-only)
- **Two modes:** Manual (drag/drop week grid) OR Assisted (AI proposes, coach reviews, applies)
- **Apply:** writes `plan_adjustments` row with trigger_type='coach_rewrite' + reason_code (sickness/injury_niggle/race_change/life_event/performance/other)

### Coach Notes (`coach-note-composer.tsx`)

**Used everywhere:** Coaches send athlete-visible notes. **Planned wiring (20260703 §R7):** add nullable `scheduled_workout_id` reference so notes thread to specific workouts. Already deployed; just needs the reference.

---

## 8. OUTPUTS DESIGN DOCS — PLANNED ARCHITECTURE

### adaptive-coach-plan-builder-spec-2026-07-03.md (§R7 — Feedback Loop for Coaches)

**Current state (2026-07-03):**
- Pieces exist separately (voice logs reconcile, RPE extracted, coach_notes exist, coachable_moments flag patterns)
- **Loop doesn't exist:** system can't yet take athlete feedback and feed it back into coach decisions

**Design in §R7:**

| Level | Mechanism | Table | State |
|-------|-----------|-------|-------|
| **Per-workout** | Athlete's quick-take after completing a key session: RPE + feel (nailed_it/solid/struggled/cut_short) + optional comment | `scheduled_workouts.athlete_feedback` (JSONB), `athlete_feedback_at` | **Spec written; migration not yet applied** |
| **Per-coach** | Coach's reply threaded to the workout | `coach_notes.scheduled_workout_id` (new FK) | **Spec written; small migration needed** |
| **Per-week** | Coach portal shows plan calendar with planned-vs-actual + feedback chip; week strip rolls up compliance % + mileage vs range + key-session outcomes | N/A (UI-only, reads existing data) | **Designed in spec; not yet built** |
| **Feedback loop closure** | Coach sees compliance + outcomes → decides to rewrite a block | `plan_adjustments` with trigger_type='coach_rewrite' | **Uses existing audit trail; rewrite function planned in §R5** |

### long-term-memory-implementation-plan-2026-07-02.md

**Status:** Steps 0–7 implemented + unit-tested (70 passing tests). Step 8 (prod deploy) pending team execution.

**What shipped 2026-07-02:**

| Step | Description | Status | Files |
|------|-------------|--------|-------|
| 0 | Verify current state (10 chat_regex rows, single Gemini call structure, RLS, CI eval gate) | ✅ Complete | Findings in doc |
| 1 | Migration: add `status`, `source`, `their_words`, `memory_date`, `last_confirmed_at`, `mention_count` + DELETE policy | ✅ Implemented | `20260702190000_user_memories_hygiene.sql` |
| 2 | Extend process-training-memo.v3 prompt → extract `memory_candidates` array (zero extra calls) | ✅ Implemented | `prompts/process-training-memo.v3.ts` + `prompt-library.ts` registered |
| 3 | Write path: dedup-or-reinforce (token overlap ≥0.7, mention_count↑, importance↑, expires on transients) | ✅ Implemented | `_shared/memoryWriter.ts` (+ `.test.ts`, 16 tests) |
| 4 | Consolidation: weekly merge dupes / archive expired + stale / cap per category | ✅ Implemented | `consolidate-memories/index.ts` + `_shared/memoryConsolidation.ts` (+ `.test.ts`, 8 tests) |
| 5 | Surfacing: smarter memory selection (quotas) + episode dates + year-ago arc | ✅ Implemented | `_shared/memorySelection.ts` (+ `.test.ts`, 7 tests); athlete-state updated |
| 6 | Evals: cassettes recorded + manual Read review | ✅ Cassettes authored; recording ⏳ team-gated | `_evals/cassettes/process-training-memo.v3/` (6 files) |
| 7 | iOS Model of You surface: visibility + athlete control (read + swipe-to-forget) | ✅ Implemented | `RunningLog/Coaching/ModelOfYou/ModelOfYouMemories.swift` |
| 8 | Deploy: push migrations → functions → schedule cron → verify | ⏳ Team-gated (hard rule #9) | Checklist in doc |

**Key insight:** Memory is **revocable** (athlete swipe-to-forget DELETE policy) and **athlete-controllable** (Model of You visibility). Not shipped without these guardrails.

### athlete-state-refactor-design.md (Phase 6 — Structural Alignment)

**Status:** Week 1 (P0 correctness) shipped; structural refactor pending.

**Shipped (hotfixes H.1 + H.2):**
- ✅ Tenant leak in goal query (scoped + tested)
- ✅ Rebuild race fixed via `claim_athlete_state_rebuild` RPC
- ✅ Null fields fixed (monotony_7d, strain_7d, week_compliance_pct, fitness_trend all computed)
- ✅ Hardcoded pace multipliers deleted; now project from PaceEngine
- ✅ formatPace rounding bug fixed ("7:60/mi" → "8:00/mi")

**Pending (Phase 6 structural):**
- Event-driven invalidation (not 60-min wall clock)
- Slices split into separate builders (each pure, testable)
- Aligned with `athlete_pace_profiles` table (done; pace zones now read v2 table)

---

## 9. HARD RULES & CONVENTIONS (From CLAUDE.md & Design Docs)

### Hard Rules That Govern New Feedback Loop Design

| Rule # | Rule | Implication for Feedback Loop |
|--------|------|-------------------------------|
| #1 | Migrations are append-only. No column drops. Backfill in same migration. | Feedback columns (`athlete_feedback`, `athlete_feedback_at` on scheduled_workouts, `scheduled_workout_id` on coach_notes) must be added, not replaced. |
| #2 | Never diagnose injury. Always defer to coach. Injuries live in `body_mentions` or `niggle_mentions`, not `user_memories`. | **Memories extract facts only:** "treadmill aggravates it" not "IT band syndrome." Injury feedback drives coach review, not ML inference. |
| #3 | Every new LLM prompt ships with eval cassettes or doesn't ship. CI gate enforces. | Any new prompt for feedback analysis (e.g., "coach prefers this feedback style") must have ≥1 cassette authored before commit. Recording happens at deploy time. |
| #4 | All data mutations by AI go through service-role edge functions (never client-side). | Feedback writes (athlete_feedback, coach corrections) go through edge functions with service-role key, not client SQL. |
| #5 | Every deployed migration & function is reversible or clearly states why it's not. | Feedback tables must have audit trails (who, when, what changed). Use plan_adjustments pattern. |
| #7 | No per-athlete personalization sneaks in without the athlete knowing. Memory control (visibility + deletion) ships first. | **Before any feedback loop uses athlete data to change AI behavior, athletes must be able to see and delete the data driving that change.** Model of You is non-negotiable. |
| #9 | Team sign-off required for schema changes & new crons. | Feedback tables + new crons go through PR review + team approval before deploy. |

### Naming & Versioning Conventions

- **Prompts:** `<name>.v<n>.ts` (name is kebab-case, immutable once shipped)
- **Migrations:** `<timestamp>_<kebab_case_description>.sql` (append-only)
- **Edge functions:** kebab-case directory, `index.ts` entry point
- **Memory categories:** `pr | race | preference | constraint | life | gear | episode` (7 categories; injury excluded)
- **Status enums:** Closed vocabularies in CHECK constraints (no open strings)

---

## 10. SUMMARY: WHAT'S READY FOR FEEDBACK LOOP DESIGN

### Fully Implemented & Live

✅ **Feedback capture tables:**
- `coaching_feedback` (thumbs ±1 on advice)
- `coaching_adjustments` (advice → followed? → outcome)
- `plan_adjustments` (comprehensive audit ledger, coach + user actions)

✅ **Memory system:**
- `user_memories` table (hygiene columns added 2026-07-02)
- `process-training-memo.v3` LLM extraction (memory_candidates output, zero extra calls)
- `_shared/memoryWriter.ts` (dedup-or-reinforce logic)
- `consolidate-memories` edge function (weekly merge + archive)
- `_shared/memorySelection.ts` (quota-based selection for prompts)
- `athlete-state.ts` (reads memories, injects into prompts)
- iOS Model of You surface (read + swipe-to-forget)

✅ **Per-athlete context injection:**
- `athlete_state` (AthleteState interface with memories + year-ago arc)
- `stateToPromptContext()` (bounded ~400 tokens for prompt budget)
- `athlete_plan_subscriptions` (schedule prefs, shape prefs, volume ramp)
- `data_depth` (UI register gate)

✅ **Prompt architecture:**
- `prompt-library.ts` (centralized registry, strict substitution)
- 50+ versioned prompts (v1–v5 for key ones like daily-read)
- Eval harness with cassettes (CI gate enforces coverage)

✅ **Coach surfaces:**
- Coach portal athlete detail page (coachable_moments + plan_adjustments feed)
- Coach note composer (threaded per-athlete)
- Coachable moments dashboard (rule-based coach signals)

### Ready for Integration (Specs Written, Partially Implemented)

🟡 **Per-workout athlete feedback:**
- `scheduled_workouts.athlete_feedback` (JSONB, nailed_it/solid/struggled/cut_short + comment)
- `scheduled_workouts.athlete_feedback_at` (TIMESTAMPTZ)
- Spec: adaptive-coach-plan-builder-spec-2026-07-03.md §R7
- **Status:** Spec complete; migration not yet applied

🟡 **Feedback-informed rewrite:**
- `plan_adjustments` extended with trigger_type='coach_rewrite' + reason_code
- `rewrite-block` edge function (proposed, not yet built)
- Spec: adaptive-coach-plan-builder-spec-2026-07-03.md §R5
- **Status:** Spec + data model designed; function not yet written

🟡 **Coach reply threading:**
- `coach_notes.scheduled_workout_id` (FK to scheduled_workouts)
- Spec: adaptive-coach-plan-builder-spec-2026-07-03.md §R7
- **Status:** Spec complete; small migration needed

### Patterns to Reuse for New Feedback Loop

1. **Feedback capture → memory extraction:** `coaching-feedback` → process-training-memo.v3 → `user_memories` (dedup-or-reinforce)
2. **LLM extraction with zero extra calls:** Extend existing prompt output (no new API call)
3. **Audit trail for everything:** `plan_adjustments` + `action_payload` (before/after/diff) + timestamps
4. **Per-athlete context injection:** athlete-state → memorySelection → stateToPromptContext → prompt template
5. **Outbox + cron drain:** Async work via outbox tables + scheduled edge functions
6. **Service-role mutations only:** No client-side data write; all changes go through edge functions
7. **Eval cassettes first, deploy second:** New prompt → cassette dir → CI gate → recording → review → deploy
8. **Athlete control first:** Visibility + deletion shipped before features that use the data
9. **RLS + CHECK constraints:** Column-level guards, role-based access, closed status vocabularies

---

## 11. KEY FILE PATHS FOR REFERENCE

### Core Feedback Structures
- `/supabase/migrations/20260318100000_coaching_feedback_and_outcomes.sql` — coaching_feedback, coaching_adjustments, goal_outcomes tables
- `/supabase/migrations/20260417600000_plan_adjustments.sql` — plan_adjustments ledger
- `/supabase/migrations/20260703120000_plan_adjustment_vocab_for_coach_plans.sql` — extends plan_adjustments for coach rewrites

### Memory System
- `/supabase/migrations/20260202_user_memories.sql` — user_memories table (legacy)
- `/supabase/migrations/20260702190000_user_memories_hygiene.sql` — hygiene columns (status, source, their_words, memory_date, last_confirmed_at, mention_count)
- `/supabase/functions/_shared/memory.ts` — legacy chat_regex extractor (now stamps source='chat_regex')
- `/supabase/functions/_shared/memoryWriter.ts` — dedup-or-reinforce logic + write path
- `/supabase/functions/_shared/memoryConsolidation.ts` — weekly archive + merge
- `/supabase/functions/_shared/memorySelection.ts` — quota-based selection for prompts
- `/supabase/functions/process-training-memo/index.ts` — calls v3 prompt, writes memories via memoryWriter

### Prompt System
- `/supabase/functions/_shared/prompt-library.ts` — registry + loadPrompt()
- `/supabase/functions/_shared/prompts/coaching-daily-read.v5.ts` — current Read prompt (editorial sections)
- `/supabase/functions/_shared/prompts/process-training-memo.v3.ts` — memo extraction with memory_candidates
- `/supabase/functions/_shared/prompts/` — all versioned prompts

### Athlete State & Context
- `/supabase/functions/_shared/athlete-state.ts` — AthleteState interface, getOrBuildAthleteState(), stateToPromptContext()
- `/supabase/migrations/20260410200000_create_athlete_state.sql` — athlete_state table
- `/supabase/migrations/20260522130643_add_data_depth_to_athlete_state.sql` — data_depth column

### Coach Surfaces
- `/web/src/app/(app)/coach-portal/athletes/[id]/page.tsx` — athlete detail (coachable_moments + plan_adjustments feed)
- `/web/src/components/coach/coachable-moment-card.tsx` — coachable moments display
- `/web/src/components/coach/plan-adjustments-feed.tsx` — adjustments ledger display
- `/web/src/components/coach/coach-note-composer.tsx` — coach notes UI

### Coachable Moments & Rules
- `/supabase/migrations/20260428100000_create_coachable_moments.sql` — coachable_moments table
- `/supabase/functions/evaluate-coachable-moment/index.ts` — rule evaluator
- `/supabase/functions/_shared/rules/` — rule implementations (loadSpikePlusInjury, lowMoodStreak, missedWorkouts, buildVsLastCycle, weatherImpactedQuality)
- `/supabase/functions/drain-coachable-moment-jobs/index.ts` — outbox drain

### Evals
- `/supabase/functions/_evals/runner.ts` — test harness runner
- `/supabase/functions/_evals/cassettes/process-training-memo.v3/` — v3 cassettes (6 authored)
- `/supabase/functions/_evals/cassettes/coaching-daily-read.v5/` — daily-read cassettes
- `.github/scripts/check_eval_coverage.py` — CI gate (enforces cassette existence)

### Test Files
- `/supabase/functions/_shared/athlete-state.test.ts` — athlete_state correctness tests (32 passing)
- `/supabase/functions/_shared/memoryWriter.test.ts` — dedup-or-reinforce logic (16 passing)
- `/supabase/functions/_shared/memoryConsolidation.test.ts` — archive/merge logic (8 passing)
- `/supabase/functions/_shared/memorySelection.test.ts` — quota selection (7 passing)

---

## 12. WHAT'S MISSING (Design Gap — Ready to Fill)

### The Per-Athlete Feedback Preference Profile

**Gap:** System captures athlete feedback on AI outputs (thumbs, advice outcomes, memos), but doesn't yet have a structured mechanism to:
1. **Analyze patterns** in that feedback (e.g., "athlete consistently marks complex advice as not helpful")
2. **Build a preference profile** (e.g., {tone: "conversational", detail_level: "moderate", prefers_ranges_over_points: true})
3. **Inject that profile into prompts** to teach the AI per-athlete voice/style preferences

**Where the loop breaks today:**
- `coaching_feedback` records thumbs ±1, but no analysis pipeline consumes it
- `coaching_adjustments.outcome_metrics` is a schema placeholder; no metrics are computed
- Athlete's voice/style preferences live implicit in memories, not as an explicit preference object

**Design work for you:**
- Schema: Add `athlete_ai_feedback_profile` table (or extend athlete_state) with structured preferences
- Analysis: Rules that consume `coaching_feedback` + `coaching_adjustments` → derive profile signals
- Injection: Extend athlete-state + prompt-library to include the profile in context
- Eval: Cassettes for any new feedback-consumption prompt
- Athlete control: Model of You surface to view/override derived preferences (memory pattern)

This is what your "AI feedback loop" spec should address — making the loop **explicit and controllable** rather than emerging from implicit patterns.

---

## CONCLUSION

The codebase has **deep infrastructure for feedback capture, memory storage, per-athlete context injection, and coach visibility.** The pieces exist:

- ✅ Feedback tables (thumbs, adjustments, audit trail)
- ✅ Memory extraction (memo LLM, dedup-or-reinforce, consolidation, quota selection)
- ✅ Athlete state (AthleteState interface, memory-aware prompts, year-ago arc)
- ✅ Prompt versioning & eval harness (CI-gated cassettes)
- ✅ Coach surfaces (detail page, coachable_moments, adjustments feed)
- ✅ Hard rules & conventions (append-only, service-role-only, evals-first, athlete-control-first)

**To build an explicit "AI feedback loop," you're integrating and formalizing what's already implicit:**

1. **Formalize preference profile** (athlete_ai_feedback_profile table or extended athlete_state)
2. **Add analysis rules** (consume coaching_feedback → derive style/detail/tone preferences)
3. **Extend coach surfaces** (show coach the per-athlete AI preference score + let coach override)
4. **Test with evals** (cassettes showing the LLM adapts output per athlete preference)
5. **Gate behind athlete control** (Model of You shows preferences + athlete can reset them)

The architecture is ready. The missing piece is **making the preference adaptation explicit, measurable, and controllable.**

# AI Feedback Loop — Tables Quick Reference

## The Feedback Capture Tables (Today's State)

```
┌─────────────────────────────────────────────────────────────────────┐
│                      COACHING_FEEDBACK                              │
├─────────────────────────────────────────────────────────────────────┤
│ id (UUID PK)                                                        │
│ user_id (TEXT) — athlete's auth.uid()                              │
│ conversation_id (UUID FK) — which chat session                     │
│ message_id (UUID) — which message in the conversation              │
│ rating (SMALLINT) — -1 = thumbs down, 1 = thumbs up               │
│ feedback_text (TEXT) — optional athlete comment                    │
│ message_content (TEXT) — snapshot of the AI message being rated    │
│ query_complexity (TEXT) — simple/moderate/complex at response time │
│ model_used (TEXT) — which LLM generated it                         │
│ created_at (TIMESTAMPTZ)                                            │
│                                                                     │
│ Indexes: (user_id), (conversation_id), (user_id, rating),          │
│          (created_at DESC)                                          │
│ RLS: Athletes insert/read own feedback                             │
│ Status: ✅ LIVE — ready for consumption by feedback analysis rules │
└─────────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COACHING_ADJUSTMENTS                             │
├─────────────────────────────────────────────────────────────────────┤
│ id (UUID PK)                                                        │
│ user_id (TEXT) — athlete                                            │
│ week_start (DATE)                                                   │
│ adjustment_type (TEXT) — volume | intensity | recovery |           │
│                         workout_swap | pace_target |               │
│                         cross_training | other                      │
│ target_workout (TEXT) — which workout (e.g., "Tuesday tempo")      │
│ recommendation (TEXT) — what the coach/AI suggested                │
│ source (TEXT) — weekly_report | conversation | proactive           │
│ source_reference_id (UUID FK) — to report or message               │
│ followed (BOOL) — did athlete follow the advice? (null = unknown)  │
│ outcome_notes (TEXT) — what happened (athlete or coach input)      │
│ outcome_metrics (JSONB) — {pace_change, mood_change, volume_delta} │
│ created_at (TIMESTAMPTZ)                                            │
│ resolved_at (TIMESTAMPTZ) — when outcome was recorded              │
│                                                                     │
│ Indexes: (user_id), (user_id, week_start DESC),                    │
│          (user_id) WHERE followed IS NULL                          │
│ RLS: Athletes read/write own                                       │
│ Status: ✅ LIVE — schema complete; outcome analysis not yet done   │
└─────────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────────┐
│                      PLAN_ADJUSTMENTS                               │
├─────────────────────────────────────────────────────────────────────┤
│ id (UUID PK)                                                        │
│ user_id (UUID)                                                      │
│ plan_id (UUID FK) — which training plan                            │
│ trigger_type (TEXT CHECK) — pace_over_target | pace_under_target | │
│                            missed_sessions | race_result |         │
│                            volume_ramp_risk | heat_forecast |      │
│                            weekly_rebalance |                       │
│                            user_action | coach_rewrite  ← NEW      │
│ trigger_evidence (JSONB) — [reconciliation_id, log_id, ...]       │
│ action_type (TEXT CHECK) — reprice_future_paces |                 │
│                           reduce_volume | cap_volume |            │
│                           propose_swap | update_fitness |         │
│                           pause_quality |                          │
│                           rewrite_block  ← NEW                     │
│ action_payload (JSONB) — {before: {...}, after: {...}, diff: [...]}│
│ auto_applied (BOOL) — true = live, false = proposal               │
│ applied_at (TIMESTAMPTZ)                                            │
│ acknowledged_by_user_at (TIMESTAMPTZ) — athlete saw and accepted  │
│ reverted_at (TIMESTAMPTZ) — athlete undo                            │
│ proposed_until (TIMESTAMPTZ) — proposals expire if ignored         │
│ reason_code (TEXT) — sickness | injury_niggle | race_change |     │
│                     life_event | performance | other               │
│ reason_text (TEXT) — free-form coach rationale                      │
│ week_number (INTEGER) — which week affected                         │
│                                                                     │
│ Indexes: (user_id, applied_at DESC), (plan_id)                    │
│ RLS: Users read own; users can update only                         │
│      acknowledged_by_user_at + reverted_at (via column guard)      │
│ Status: ✅ LIVE — comprehensive audit ledger, coach extended 7/3  │
└─────────────────────────────────────────────────────────────────────┘
```

## The Memory System (The Preference Profile Foundation)

```
┌─────────────────────────────────────────────────────────────────────┐
│                      USER_MEMORIES                                  │
├─────────────────────────────────────────────────────────────────────┤
│ id (UUID PK)                                                        │
│ user_id (TEXT) — auth.uid()::text                                  │
│ category (TEXT) — pr | race | preference | constraint | life |    │
│                   gear | episode                                    │
│ content (TEXT) — one sentence, athlete's framing                   │
│ source_conversation_id (UUID FK) — legacy (for chat regex)        │
│ extracted_from (TEXT) — snippet where we found it (≤200 chars)     │
│ importance (INT) — 1–10; bumped on re-mention                      │
│ expires_at (TIMESTAMPTZ) — transient memories +60d from creation  │
│ created_at (TIMESTAMPTZ)                                            │
│                                                                     │
│ *** HYGIENE COLUMNS (added 2026-07-02) ***                         │
│ status (TEXT) — active | archived                                  │
│ source (TEXT) — chat_regex | memo_llm | consolidation             │
│ their_words (TEXT) — verbatim phrase (episodes only)               │
│ memory_date (DATE) — when the thing happened (episodes only)       │
│ last_confirmed_at (TIMESTAMPTZ) — most recent re-mention          │
│ mention_count (INT) — how many times re-mentioned                  │
│                                                                     │
│ Indexes: (user_id, status, importance DESC), partial on status     │
│ RLS: Athletes SELECT all own; DELETE own only                      │
│ Status: ✅ LIVE (2026-07-02) — hygiene complete, LLM extraction    │
│         ready (process-training-memo.v3 extracts memory_candidates)│
└─────────────────────────────────────────────────────────────────────┘

DEDUP-OR-REINFORCE LOGIC:
┌─────────────────────────────────────────┐
│ New memory_candidate from LLM            │
├─────────────────────────────────────────┤
│ → normalize & check vs active memories  │
│ → token overlap ≥0.7 with existing?     │
│    YES: bump mention_count,             │
│         raise importance (cap 10),      │
│         set last_confirmed_at = now()   │
│         (NO new row)                    │
│    NO: INSERT new row with              │
│         source='memo_llm'                │
│         expires_at = now() +60d if      │
│         LLM output said durable=false    │
└─────────────────────────────────────────┘

CONSOLIDATION (Weekly, pg_cron Sun 04:30 UTC):
┌─────────────────────────────────────────┐
│ consolidate-memories edge function      │
├─────────────────────────────────────────┤
│ → merge remaining dupes (keep oldest id)│
│ → archive expired transients            │
│ → archive stale-low-importance          │
│   (12+ months, importance ≤4)           │
│ → cap per category (10 active max;      │
│   archive lowest-importance overflow)   │
│ → log audit trail (visible in logs)     │
│ → IDEMPOTENT (run twice = no-op 2nd)   │
└─────────────────────────────────────────┘
```

## The Preference Profile (athlete-state injection point)

```
┌─────────────────────────────────────────────────────────────────────┐
│                  ATHLETE_STATE (in-memory cache)                    │
├─────────────────────────────────────────────────────────────────────┤
│ Backing table: athlete_state (20260410200000)                      │
│                                                                     │
│ Key fields relevant to feedback loop:                              │
│                                                                     │
│ // Memories — quota selected by importance × recency               │
│ top_memories: UserMemory[]                                         │
│   • Up to 3 constraints (e.g., "treadmill aggravates achilles")   │
│   • Up to 3 preferences (e.g., "early morning runs")              │
│   • Up to 2 life (e.g., "two kids under five")                    │
│   • Up to 2 PRs/races (e.g., "sub-3 marathon goal")               │
│   • Up to 2 episodes (e.g., Jan 14 — "the day it clicked")        │
│                                                                     │
│ // Context for prompts                                             │
│ experience_level: "beginner" | "intermediate" | "advanced"        │
│ current_phase: "base" | "build" | "specific" | "taper"            │
│ goal_race: string                                                  │
│ rolling_7d_miles: number                                           │
│ rolling_28d_miles: number                                          │
│ acwr: number (acute-chronic workload ratio)                       │
│ fitness_trend: "rising" | "stable" | "dipping"                   │
│ year_ago_arc: string  ← NEW (2026-07-02)                          │
│                "This time last year: ~32 mpw, mood mostly neutral"│
│ current_niggles: Niggle[]                                          │
│ data_depth: 0-3 (UI gate: new account to 21+ training days)       │
│ cant_see: string[] (gaps in the data)                              │
│                                                                     │
│ Method: stateToPromptContext(athleteState)                        │
│   → Renders as ~400-token bounded prompt block                    │
│   → Injected as {{athlete_context}} into every LLM prompt         │
│                                                                     │
│ Consumers: 12 edge functions                                       │
│   coaching-daily-read, coaching-agent, process-training-memo,     │
│   generate-workout-insight, injury-analysis, reschedule-plan, ... │
│                                                                     │
│ Status: ✅ LIVE — memories quota-selected (Step 5, 2026-07-02)   │
└─────────────────────────────────────────────────────────────────────┘
```

## Planned (Not Yet Live) — Per-Workout Feedback

```
┌─────────────────────────────────────────────────────────────────────┐
│              SCHEDULED_WORKOUTS (new columns planned)               │
├─────────────────────────────────────────────────────────────────────┤
│ [existing columns... ]                                              │
│                                                                     │
│ *** NEW (spec: adaptive-coach-plan-builder-spec §R7, not applied)   │
│ coach_instruction (TEXT) — coach's prose "settle into MP by mi 2"  │
│                                                                     │
│ athlete_feedback (JSONB) — after athlete completes workout:        │
│                           {                                        │
│                             rpe: 1-10,                             │
│                             feel: "nailed_it" | "solid" |          │
│                                   "struggled" | "cut_short",       │
│                             comment: "felt heavy",                 │
│                             recorded_at: now()                     │
│                           }                                        │
│ athlete_feedback_at (TIMESTAMPTZ) — when athlete submitted it      │
│                                                                     │
│ RLS: Athletes UPDATE own (athlete_feedback + athlete_feedback_at   │
│      only); coaches INSERT/UPDATE coach_instruction via service    │
│      role function                                                 │
│                                                                     │
│ Status: 🟡 DESIGNED (spec complete) — migration not yet applied   │
└─────────────────────────────────────────────────────────────────────┘
```

## Cross-Table Relationships

```
                    coaching_feedback (athlete thumbs ±1)
                            ↓
                  plan_adjustments.reason_code
                    ("AI advice feedback")
                            ↓
         ┌───────────────────┴──────────────────┐
         ↓                                      ↓
    coaching_adjustments              coaching_adjustments
    (was advice followed?)            (what was the outcome?)
         ↓                                      ↓
         └───────────────────┬──────────────────┘
                             ↓
                    user_memories
                  (aggregate patterns)
                             ↓
      ┌──────────────────────┴──────────────────┐
      ↓                                         ↓
 memoryConsolidation              memorySelection
 (weekly archive/merge)       (quota-based filter)
      ↓                                         ↓
      └──────────────────────┬──────────────────┘
                             ↓
                       athlete_state
                    (injected context)
                             ↓
              ┌──────────────┬──────────────┐
              ↓              ↓              ↓
        Daily Read    Coaching Agent  Injury Analysis
        (athlete       (chat with      (coach advisory)
         sees it)      athlete)
```

## The Feedback Loop Gap (What Your Design Should Fill)

```
TODAY'S STATE (feedback captured but not analyzed):
┌─────────────────┐
│coaching_feedback│ ←─ athlete: "that was too complex"
│coaching_adjustm-│ ←─ athlete: "I didn't follow it"
│ents outcome_    │
│metrics          │ ← outcome: athlete compliance fell
└────────┬────────┘
         │
         → [collected but NOT analyzed]
         → [no preference profile derived]
         → [AI still generates same way for next Read]

WHAT YOU'RE DESIGNING (explicit feedback loop):
┌─────────────────┐
│coaching_feedback│ ←─ athlete: "too complex" × 3 times
│coaching_adjustm-│ ←─ athlete: "didn't follow" × 2 times
│ents outcome_    │
│metrics          │ ← low compliance pattern detected
└────────┬────────┘
         │
         → ANALYZE: "athlete responds better to conversational tone"
         → DERIVE: athlete_ai_preference_profile
         │           {
         │             tone: "conversational",
         │             detail_level: "moderate",
         │             prefers_ranges_over_points: true
         │           }
         └─→ INJECT into athlete-state
              │
              ↓ (next Daily Read)
         "You're somewhere between 32-35 mpw this week —
          it's a solid volume for where you're at." ← simpler, ranges not points
              ↑
         (adapted per athlete preference profile)

REQUIRED ADDITIONS:
  1. athlete_ai_feedback_profile table (or extend athlete_state)
  2. Analysis rules (consume coaching_feedback + coaching_adjustments)
  3. Derivation logic (compute preference signals)
  4. Injection into athlete-state
  5. Athlete control (Model of You: see/override)
```

## Eval Cassettes (CI-Gated Coverage)

```
Cassettes required for any new/changed prompt:

_evals/cassettes/<prompt-name>.<version>/
├── input_1.json        # test case 1 input
├── rubric_1.json       # expected output checks
├── recorded_response_1.json  # (empty "" until deploy-time recording)
├── input_2.json
├── rubric_2.json
├── recorded_response_2.json
└── [must have ≥3 complete triplets]

CI gate (.github/scripts/check_eval_coverage.py):
  If you touch supabase/functions/_shared/prompts/<name>.ts
  Then _evals/cassettes/<name>.<version>/ MUST exist and be non-empty
  Otherwise: commit rejected, PR cannot merge

For feedback-consumption prompts:
  • Write cassettes for: normal feedback, negative feedback, conflicting signals
  • Rubric checks: does AI adapt style? respect athlete preferences?
  • Record at deploy time: GEMINI_API_KEY=... deno run -A _evals/record.ts
```

---

## Schema Evolution Pattern (Append-Only)

All new feedback loop tables must follow hard rule #1: **append-only migrations**.

✅ DO THIS:
```sql
-- migration_timestamp_description.sql
ALTER TABLE table_name ADD COLUMN new_col TYPE;
ALTER TABLE table_name ADD CONSTRAINT ...;
CREATE POLICY ... ON table_name ...;

-- Backfill in same migration if needed
UPDATE table_name SET new_col = computed_value WHERE condition;
```

❌ DON'T DO THIS:
```sql
DROP TABLE old_feedback_format;  -- NEVER
DROP COLUMN athlete_feedback;     -- NEVER
```

---

## Hard Rules Affecting Feedback Loop Design

1. **#1 — Append-only:** No column drops; backfill in migration
2. **#2 — No diagnosis:** Injuries stay in body_mentions, not user_memories
3. **#3 — Evals first:** New prompt → cassettes → CI gate → deploy
4. **#4 — Service-role only:** All AI mutations via edge functions
5. **#7 — Athlete control first:** Visibility + deletion before features use data
6. **#9 — Team sign-off:** Schema changes + new crons need PR review

---

## Quick Checklist for Your Feedback Loop Design

- [ ] Define athlete_ai_preference_profile table (or extend athlete_state)
- [ ] Write analysis rules (coaching_feedback + coaching_adjustments → signals)
- [ ] Implement preference derivation (what patterns trigger what pref changes?)
- [ ] Extend athlete-state to read preference profile
- [ ] Extend prompt templates to accept preference_context injection
- [ ] Write eval cassettes for feedback-aware prompts
- [ ] Add Model of You section for athlete control (visibility + override)
- [ ] RLS: service-role for writes, athlete for reads
- [ ] Test: reproduce "athlete marks advice as 'too complex'" → verify next Read is simpler
- [ ] Migrations: all append-only, backfill in same file
- [ ] Cron: if deriving preferences async, schedule via pg_cron + outbox pattern
- [ ] Audit: log every preference override (athlete or system)

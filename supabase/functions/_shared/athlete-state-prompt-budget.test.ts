import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  approxTokenCount,
  type AthleteState,
  stateToPromptContext,
} from "./athlete-state.ts";

// ── A fully-populated default AthleteState; tests override slices. ──
function baseState(over: Partial<AthleteState> = {}): AthleteState {
  const defaults: AthleteState = {
    user_id: "u1",
    experience_level: "intermediate",
    current_phase: "build",
    active_plan_id: null,
    goal_race: null,
    goal_time_seconds: null,
    acwr: null,
    monotony_7d: null,
    strain_7d: null,
    rolling_7d_miles: 40,
    rolling_28d_miles: 160,
    weekly_avg_miles: 40,
    hard_sessions_7d: 2,
    easy_sessions_7d: 4,
    runs_last_7d: 6,
    longest_run_14d: 16,
    predicted_5k_seconds: null,
    predicted_10k_seconds: null,
    predicted_half_seconds: null,
    predicted_marathon_seconds: null,
    fitness_trend: null,
    fitness_snapshot_id: null,
    fitness_snapshot_at: null,
    last_mood: null,
    last_readiness_score: null,
    mood_trend: null,
    last_check_in_at: null,
    active_injuries: [],
    injury_risk_score: null,
    injury_risk_signals: [],
    possible_injuries: [],
    niggle_recurrence: [],
    pace_zones: { mp: 320, tenK: 290, fiveK: 280, mile: 260 },
    pace_zone_ranges: {},
    recent_training_summary: null,
    recent_workouts: [],
    today_workout: null,
    upcoming_workouts: [],
    week_compliance_pct: null,
    fitness_vs_6mo_ago_seconds: null,
    fitness_vs_6mo_ago_label: null,
    injury_history_summary: [],
    trajectory_framing: null,
    trajectory_reason: null,
    active_goals: [],
    recent_blocks: [],
    confirmed_races: [],
    data_depth: 3,
    load_distribution: null,
    fitness_prediction: null,
    memories: [],
    year_ago: null,
    environment: [],
    execution: [],
    fitness_signal: null,
    life_context: null,
    patterns: [],
    data_gaps: [],
    last_updated_at: new Date().toISOString(),
    last_updated_by: "test",
    version: 1,
  };
  return { ...defaults, ...over };
}

// A data-rich state that spans low- and high-priority sections.
function richState(): AthleteState {
  return baseState({
    memories: [
      { category: "constraint", content: "Works night shifts twice a week.", their_words: null, importance: 8, memory_date: null, last_confirmed_at: "2026-06-20T00:00:00Z", mention_count: 3 },
      { category: "preference", content: "Hates treadmills; runs outside in all weather.", their_words: null, importance: 4, memory_date: null, last_confirmed_at: "2026-06-15T00:00:00Z", mention_count: 1 },
      { category: "episode", content: "trail 20-miler", their_words: "the day it clicked", importance: 8, memory_date: "2026-01-14", last_confirmed_at: "2026-01-14T00:00:00Z", mention_count: 1 },
    ],
    year_ago: { weekly_avg_miles: 32, mood_summary: "neutral" },
    recent_blocks: [
      { block_start: "2026-05-01", block_end: "2026-05-29", total_miles: 160, weekly_avg_miles: 40, quality_sessions: 6, easy_sessions: 14, races_entered: 0, avg_easy_pace_sec: 460, injury_mentions: 0, mood_summary: "positive" },
      { block_start: "2026-04-03", block_end: "2026-05-01", total_miles: 150, weekly_avg_miles: 37.5, quality_sessions: 5, easy_sessions: 13, races_entered: 1, avg_easy_pace_sec: 470, injury_mentions: 1, mood_summary: "neutral" },
    ],
    patterns: [
      { kind: "pacing_fade", statement: "You tend to go out too hot — most quality sessions slow through the reps.", evidence: "3 of 4 sessions faded (avg +2.1%)", confidence: "medium" },
    ],
    active_injuries: [
      { body_area: "achilles", severity: 3, status: "monitoring", first_reported_at: "2026-06-01" },
    ],
  });
}

Deno.test("approxTokenCount: ~4 chars per token, ceil", () => {
  assertEquals(approxTokenCount(""), 0);
  assertEquals(approxTokenCount("abcd"), 1);
  assertEquals(approxTokenCount("abcde"), 2);
});

Deno.test("default budget (Infinity) does NOT prune — all sections render", () => {
  const prompt = stateToPromptContext(richState());
  // Low-priority sections present when unbudgeted (proves no pruning by default).
  assert(prompt.includes("What I remember about you"), "memories missing");
  assert(prompt.includes("Training blocks"), "blocks missing");
  assert(prompt.includes("Patterns I've noticed"), "patterns missing");
  // High-priority always present.
  assert(prompt.includes("Training pace zones"), "pace zones missing");
  assert(prompt.includes("Active injuries"), "injuries missing");
});

Deno.test("tiny budget prunes low-priority sections but keeps priority-1 (pace zones, injuries, identity)", () => {
  const prompt = stateToPromptContext(richState(), { budget: 40 });
  // Priority-1 survives no matter what.
  assert(prompt.includes("=== ATHLETE STATE ==="), "header missing");
  assert(prompt.includes("Training pace zones"), "P1 pace zones must survive");
  assert(prompt.includes("Active injuries"), "P1 injuries must survive");
  // Lowest-priority sections (P6/P5/P4) dropped first.
  assert(!prompt.includes("What I remember about you"), "memories (P6) should be dropped");
  assert(!prompt.includes("Training blocks"), "blocks (P6) should be dropped");
  assert(!prompt.includes("Patterns I've noticed"), "patterns (P5) should be dropped");
});

Deno.test("pruning is monotonic — a smaller budget never keeps MORE than a larger one", () => {
  const state = richState();
  const big = stateToPromptContext(state, { budget: 1000 });
  const small = stateToPromptContext(state, { budget: 40 });
  assert(approxTokenCount(small) <= approxTokenCount(big));
  // Identity is priority-1 and tiny — should survive even the small budget.
  assert(small.includes("Level: intermediate"));
});

Deno.test("priority-1-only floor: even an impossibly small budget keeps safety-critical context", () => {
  // Budget of 1 token can't fit P1 sections, but they must NOT be dropped.
  const prompt = stateToPromptContext(richState(), { budget: 1 });
  assert(prompt.includes("Training pace zones"), "pace zones must never drop");
  assert(prompt.includes("Active injuries"), "injuries must never drop");
});

// ── life_context section (audit fix #1, 2026-07-02) ──

function lifeState(): AthleteState {
  return baseState({
    life_context: {
      sleep: { poor_mentions_7d: 2, mentions_28d: 4, last: { date: "2026-07-01", quality: "poor", hours: 5 } },
      fatigue: [{ date: "2026-07-01", label: "wiped" }, { date: "2026-06-29", label: "tired" }],
      effort: [{ date: "2026-07-01", label: "hard" }, { date: "2026-06-30", label: "hard" }, { date: "2026-06-29", label: "hard" }],
      hard_7d: 3,
      stress: { work_high_7d: 2, life_high_7d: 0, any_high_28d: 3, last_mention: "2026-07-01" },
      illness: { active: true, detail: "fighting a cold", date: "2026-06-30" },
      travel: { recent: false, detail: null, date: null },
      motivation: { low_7d: 1, last: "low" },
      felt_vs_looked: [{ date: "2026-07-01", value: "harder than it looks" }],
      avg_rpe_7d: 6.5,
      summary: "sleep poor ×2 this week · work stress high ×2",
    },
  });
}

Deno.test("life_context renders: sleep, stress, illness verbatim, guidance line", () => {
  const prompt = stateToPromptContext(lifeState());
  assert(prompt.includes("Life context"), "life context header missing");
  assert(prompt.includes("poor ×2 this week"), "sleep rollup missing");
  assert(prompt.includes("high ×2 this week"), "stress rollup missing");
  assert(prompt.includes('"fighting a cold"'), "illness must be verbatim");
  assert(prompt.includes("Never prescribe rest or treatment"), "guardrail line missing");
});

Deno.test("life_context omitted when null; drops under tiny budget (priority 3 > 1)", () => {
  const withoutLc = stateToPromptContext(baseState());
  assert(!withoutLc.includes("Life context"), "must not render for null slice");
  const tiny = stateToPromptContext(lifeState(), { budget: 40 });
  assert(!tiny.includes("Life context"), "P3 section must drop under a tiny budget");
  assert(tiny.includes("Training pace zones"), "P1 still survives");
});

// ── Long-term memory rendering (roadmap 4.1) ──

Deno.test("memories: episodes render with date + verbatim words, separate from general", () => {
  const prompt = stateToPromptContext(richState());
  assert(prompt.includes("What I remember about you"), "general memory header missing");
  assert(prompt.includes("Works night shifts twice a week."), "constraint memory missing");
  assert(prompt.includes("Moments worth a callback"), "episode header missing");
  assert(prompt.includes('their words: "the day it clicked"'), "episode verbatim missing");
  assert(prompt.includes("2026-01-14"), "episode date missing");
  assert(prompt.includes("reference sparingly"), "episode restraint guidance missing");
});

Deno.test("year-ago arc line renders inside the blocks section", () => {
  const prompt = stateToPromptContext(richState());
  assert(prompt.includes("This time last year: ~32 mpw"), "year-ago line missing");
  assert(prompt.includes("mood mostly neutral"), "year-ago mood missing");
});

Deno.test("STILL LEARNING YOU fires for an athlete with training data but < 3 memories", () => {
  const sparse = baseState({ memories: [{ category: "life", content: "New job started.", their_words: null, importance: 5, memory_date: null, last_confirmed_at: null, mention_count: 1 }] });
  const prompt = stateToPromptContext(sparse);
  assert(prompt.includes("STILL LEARNING YOU"), "data_gap nudge should fire");
  assert(prompt.includes("New job started."), "the few memories we have still surface");
});

Deno.test("STILL LEARNING YOU does NOT fire once the athlete has ≥3 memories", () => {
  const prompt = stateToPromptContext(richState()); // 3 memories
  assert(!prompt.includes("STILL LEARNING YOU"), "nudge must retire at ≥3 memories");
});

Deno.test("token cost: the memory-rich state stays well under the 1,800-token ceiling", () => {
  // Plan Step 5 done-when: measure the token cost of the heaviest rendered
  // state; if it routinely exceeds ~1,800 tokens, enforce a finite budget.
  const tokens = approxTokenCount(stateToPromptContext(richState()));
  assert(tokens < 1800, `rendered state is ${tokens} tokens, exceeds the 1,800 ceiling`);
});

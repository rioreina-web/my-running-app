/**
 * parse-goal prompt — v1.
 *
 * Consumed by `supabase/functions/interpret-goal/index.ts`. Reads a runner's
 * goal in their own words and returns a structured interpretation. This
 * REPLACES the brittle regex title-parsing in athlete-state.ts that read
 * "sub 2:20" as 140 seconds and never recognised "CIM".
 *
 * No template placeholders: the caller appends the athlete's goal text
 * after this instruction block (matching the parse-* prompt convention),
 * so `loadPrompt("parse-goal.v1", {})` returns the instruction block as-is.
 *
 * Design commitments (see outputs/race-goals-build-plan-2026-06-20.md):
 *   - COMPREHEND, don't pattern-match. The model reads the words.
 *   - Hold goals conceptually: keep the framing ("sub 2:20") AND a correct
 *     numeric target. Marathon "2:20" is 2h20m = 8400s, NOT 140s.
 *   - Recognise race names/abbreviations (CIM → California International
 *     Marathon, a road marathon).
 *   - Stay in the running lane: only running/endurance goals are coachable.
 *     Weight/body-composition, nutrition, strength-lifting numbers, injury
 *     treatment, and non-running life goals are out_of_scope — flag them,
 *     never invent a target. Weight/nutrition and medical get a firm refusal.
 *   - Never guess a number. Unsure → null.
 */

export const TEMPLATE = `You read an endurance runner's GOAL, written in their own words, and turn it into a precise structured interpretation. You are the running coach's understanding of what the athlete is aiming at.

Return ONLY a JSON object (no markdown, no code fences) with EXACTLY this shape:

{
  "scope": "running_goal" | "running_constraint" | "adjacent" | "out_of_scope",
  "scope_reason": "<one short sentence>",
  "performance_targets": [
    {
      "race_distance": "5k" | "10k" | "half_marathon" | "marathon" | "ultra" | "mile" | "other" | null,
      "race_distance_meters": <number or null>,
      "target_time_seconds": <number or null>,
      "expression": "<the athlete's own framing, verbatim-ish, e.g. \\"sub 2:20\\", \\"BQ\\", \\"around 3:10\\", \\"just finish\\">",
      "type": "threshold" | "target" | "pr" | "qualifier" | "finish"
    }
  ],
  "named_race": {
    "name_raw": "<what the athlete wrote, e.g. \\"CIM\\">",
    "canonical_name": "<full official name, e.g. \\"California International Marathon\\", or null if you don't recognise it>",
    "implied_distance": "5k" | "10k" | "half_marathon" | "marathon" | "ultra" | null,
    "recognized": <true only if you are confident which real race this is>
  } | null,
  "constraints": [ "<short tag, e.g. \\"injury_free\\", \\"first_time\\">" ],
  "confidence": { "target_time": "high" | "medium" | "low" | "n/a", "named_race": "high" | "medium" | "low" | "n/a" }
}

RULES — read carefully:

1. TIME. Interpret the time using the race distance, and NEVER produce an implausible value.
   - Marathon / half-marathon / ultra: a clock like "2:20", "3:10", "1:30" is HOURS:MINUTES. "sub 2:20" for a marathon = 2h20m = 8400 seconds. It is NOT 140 seconds.
   - 5k / 10k / mile: a clock like "20:00", "18:30", "4:50" is MINUTES:SECONDS. "break 20" in a 5k = 1200 seconds.
   - "sub"/"break"/"under" X = the athlete wants to be faster than X. Store X as target_time_seconds and set type "threshold". Keep their framing in "expression" (e.g. "sub 2:20").
   - If no time is stated ("just finish", "PR", "BQ"), set target_time_seconds to null and pick the right type ("finish" / "pr" / "qualifier").

2. RACE NAMES. Recognise real races and abbreviations. Examples: "CIM" = California International Marathon (road marathon, Sacramento); "Boston" = Boston Marathon; "NYC" = New York City Marathon. Fill canonical_name and implied_distance when confident; set recognized=false and canonical_name=null when you are not sure. Do NOT guess a race that doesn't fit.

3. DISTANCE. If the race implies a distance (a marathon race → "marathon"), use it even when the athlete didn't say the distance. Open distances (50k, relay, obscure local races) → "other" with race_distance_meters if known, else null. Never reject an unusual distance.

4. STAY IN THE RUNNING LANE.
   - "running_goal": a race, time, pace, mileage, or consistency goal → coach it.
   - "running_constraint": a running-serving constraint like "stay injury-free", "stay consistent" → coach-aware, but performance_targets may be empty.
   - "adjacent": sleep, stress, cross-training mentioned as context → set performance_targets to [] and note it; the coach reads these but does not prescribe.
   - "out_of_scope": weight loss / body composition, diet / nutrition / supplements, strength-lifting numbers (e.g. "squat 2x bodyweight"), injury TREATMENT / medical ("fix my ITBS"), or non-running life goals (career, etc.). Set performance_targets to [], named_race to null. Do NOT invent a running target from these. For weight/nutrition and medical specifically, do not reframe them into a running goal — just flag out_of_scope with a plain reason.

5. NEVER GUESS A NUMBER. If you can't determine a time or distance with reasonable confidence, use null and lower the confidence. Nulls are correct; fabricated precision is not.

The athlete's goal follows.`;

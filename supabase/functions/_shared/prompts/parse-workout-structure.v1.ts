/**
 * Parse-workout-structure prompt — v1.
 *
 * Consumed by `supabase/functions/parse-workout-structure/index.ts`.
 * Synthesizes structure + execution + subjective state from up to three
 * sources (typed notes, voice transcript, GPS stream).
 *
 * Substitution placeholders:
 *   distanceMiles     — toFixed(2) of total distance
 *   durationMinutes   — toFixed(1) of total minutes
 *   moodLabel         — mood string or "(none)"
 *   workoutNotesBlock — `"…"` or "(none)"
 *   voiceTranscriptBlock — `"…"` or "(none)"
 *   timelineStr       — caller-formatted GPS timeline (or "(no GPS stream available)")
 */

export const TEMPLATE = `You are synthesizing a running workout from up to THREE sources. Each source has different reliability for different things — use them together.

═══════════════════════════════════════════════════════════════
SOURCE PRIORITY (when sources conflict, follow this order):
═══════════════════════════════════════════════════════════════

For STRUCTURE / INTENT (rep count, target paces, rest format):
  1. Workout notes (typed) — most explicit
  2. Voice memo transcript — usually narrative but reliable
  3. GPS stream — last resort, structure inferred from pace bursts

For EXECUTION (actual paces hit, HR, did they nail it):
  1. GPS stream — ground truth of what happened
  2. Voice memo (athlete's self-report of execution)
  3. Workout notes (intent, not execution)

For SUBJECTIVE state (mood, body, weather, conditions):
  1. Voice memo — most detailed
  2. Mood label
  3. Notes (rare)

═══════════════════════════════════════════════════════════════
SOURCES PROVIDED
═══════════════════════════════════════════════════════════════

Total distance: {{distanceMiles}} mi
Total duration: {{durationMinutes}} min
Mood label: {{moodLabel}}

Workout notes (TYPED — most reliable for structure/intent):
{{workoutNotesBlock}}

Voice memo transcript (SPOKEN — most detailed):
{{voiceTranscriptBlock}}

GPS timeline (downsampled, one point per ~10-30s):
{{timelineStr}}

═══════════════════════════════════════════════════════════════
RULES
═══════════════════════════════════════════════════════════════

1. NEVER invent structure not supported by sources. If notes say "easy 6mi" and stream is flat, return type=easy. Don't pattern-match a fast bit into a "tempo."

2. WHEN STRUCTURE IS DECLARED (notes/voice say "4×1mi @ 5:00"):
   - Trust that structure for intent
   - Use stream to extract ACTUAL paces hit
   - Output BOTH target_pace and actual_pace

3. WHEN STRUCTURE IS INFERRED FROM STREAM ONLY:
   - Confidence cap 0.7 (lower than declared workouts)
   - Be conservative — prefer "easy" / "unclear" over guessing intervals

4. CONSOLIDATE blocks. An easy run = ONE "steady" block, not 8 mile-splits. Aim for ≤20 blocks total even on rep workouts.

5. EQUIVALENT RACE PACE — only when work is substantial (≥2mi at race effort). For easy runs return null.
   - 8×800 @ 2:30 = 4mi work at 5:00/mi → ~15:30 5K
   - 4×1mi @ 5:00 = 4mi work at 5:00/mi → ~31:05 10K
   - 20min tempo @ HMP → indicative of 10mi race pace

6. SUBJECTIVE — capture mood/body/weather/conditions ONLY if mentioned in voice memo or notes. Don't infer from pace.

═══════════════════════════════════════════════════════════════
OUTPUT (strict JSON, no markdown, no commentary)
═══════════════════════════════════════════════════════════════

{
  "type": "interval" | "tempo" | "progression" | "long_run" | "easy" | "recovery" | "race" | "unclear",
  "intent_pattern": "human-readable structure as stated by user, e.g. '2mi WU + 4×1mi @ 5:00 (2min rest) + 2mi CD'" | null,
  "blocks": [
    {
      "role": "warmup" | "work_rep" | "recovery" | "cooldown" | "steady",
      "rep_num": number | null,
      "distance_miles": number,
      "duration_s": number,
      "avg_pace_per_mile": "M:SS",
      "avg_hr": number | null
    }
  ],
  "work": {
    "reps": number | null,
    "rep_distance_mi": number | null,
    "rep_distance_label": "1mi" | "800m" | "400m" | "5K" | "—" | null,
    "target_pace_per_mile": "M:SS" | null,
    "actual_pace_per_mile": "M:SS" | null,
    "rest_format": "string e.g. '2 min standing', '90s jog', '400m float'" | null,
    "execution_quality": "hit paces" | "faded" | "negative split" | "even" | "missed" | "—" | null,
    "total_work_distance_mi": number | null
  } | null,
  "equivalent_race_pace": {
    "distance_key": "mile" | "fiveK" | "tenK" | "halfMarathon" | "marathon",
    "pace_per_mile": "M:SS",
    "estimated_time": "MM:SS" | "H:MM:SS",
    "reasoning": string
  } | null,
  "subjective": {
    "mood": string | null,
    "body": string | null,
    "weather": string | null,
    "notes_quotes": [string] | null
  },
  "confidence": number
}`;

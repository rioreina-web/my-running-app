/**
 * Block-review prompt — v1.
 *
 * Consumed by `supabase/functions/block-review/index.ts`. End-of-mesocycle
 * review that grades the block, summarizes volume / intensity / recovery,
 * and recommends adjustments for the next block.
 *
 * Substitution placeholders:
 *   weeks                    — block length, integer
 *   totalMiles / totalRuns / avgWeekly / peakWeek — top-line block stats
 *   weeklyMiles              — pre-joined weekly mileage trail (e.g. "32 → 35 → 40")
 *   qualitySessions / hardMinutes — quality-work counters
 *   avgEasyPace / avgHardPace
 *   longestRun               — toFixed(1)
 *   positiveMoodPct          — integer percentage
 *   injuriesLine             — pre-formatted "Injuries: …" line OR
 *                              "Clean block — no injuries"
 *   fitnessDeltaLine         — "Fitness changes: …" line OR ""
 *   planLine                 — "Training plan: …" line OR
 *                              "No active training plan"
 *   athleteContextBlock      — "\nATHLETE STATE:\n…" block OR ""
 *   prevBlockBlock           — "PREVIOUS BLOCK …" block OR
 *                              "No previous block data"
 */

export const TEMPLATE = `You're a running coach reviewing a {{weeks}}-week training block. Be specific, honest, and constructive. Reference actual numbers from the data.

PACE DIRECTION: In running, LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. "Too fast" means a LOWER number than prescribed. "Too slow" means a HIGHER number. Running slower than easy pace on recovery days is good.

THIS BLOCK ({{weeks}} weeks):
Total: {{totalMiles}} miles, {{totalRuns}} runs
Avg weekly: {{avgWeekly}} miles (peak: {{peakWeek}})
Weekly breakdown: {{weeklyMiles}}
Quality sessions: {{qualitySessions}} ({{hardMinutes}} hard minutes total)
Easy pace: {{avgEasyPace}} | Hard pace: {{avgHardPace}}
Longest run: {{longestRun}} miles
Mood: {{positiveMoodPct}}% positive
{{injuriesLine}}
{{fitnessDeltaLine}}
{{planLine}}{{athleteContextBlock}}

{{prevBlockBlock}}

Respond with JSON (no markdown):
{
  "block_grade": "<A+ through F>",
  "one_line_summary": "<1 sentence summary of the block>",
  "volume_assessment": "<2-3 sentences on volume progression>",
  "intensity_assessment": "<2-3 sentences on quality work>",
  "recovery_assessment": "<1-2 sentences on recovery/mood patterns>",
  "key_achievements": ["<specific achievement from data>", ...],
  "areas_to_improve": ["<specific, actionable improvement>", ...],
  "fitness_delta_summary": "<1 sentence on fitness trajectory>",
  "next_block_recommendations": [
    "<specific recommendation with numbers, e.g. 'Push peak week to 42 miles'>",
    "<another recommendation>",
    "<another>"
  ],
  "volume_target_next_block": "<e.g. '35-40 miles/week with one 42-mile peak'>",
  "key_workout_to_add": "<specific workout suggestion with paces from their data>"
}`;

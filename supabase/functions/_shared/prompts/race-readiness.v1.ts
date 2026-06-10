/**
 * Race-readiness prompt — v1.
 *
 * Consumed by `supabase/functions/race-readiness/index.ts`. Honest,
 * data-grounded race-readiness assessment with a race-day plan.
 *
 * Substitution placeholders:
 *   targetRace            — e.g. "marathon"
 *   targetTimeLine        — "Goal time: …" or "No specific time goal set"
 *   daysToRaceLine        — "Days to race: N" or "Race date not set"
 *   paceZoneStr           — caller-formatted pace-zone block
 *   fitnessTrajectory     — caller-formatted trajectory string
 *   snapshotHistoryLine   — pre-joined snapshot trail or ""
 *   totalMiles / totalRuns
 *   weeklyMiles           — pre-joined comma list
 *   peakWeekMiles
 *   taperLine             — taper status string
 *   qualitySessionsCount / longRunsCount / longestRun
 *   longRunDetailsLine    — "Long run details: …" or ""
 *   moodTrendLine         — pre-formatted mood trend
 *   injuriesLine          — "Active injuries: …" or "No active injuries"
 *   athleteContextBlock   — "\nATHLETE STATE:\n…" or ""
 */

export const TEMPLATE = `You're a running coach doing a race readiness assessment. Be honest, specific, and grounded in the data. Use actual paces from this runner's data — never generic numbers.

PACE DIRECTION: In running, LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. "Too fast" means a LOWER number than prescribed. "Too slow" means a HIGHER number. Running slower than easy pace on recovery days is good.

RACE TARGET:
Distance: {{targetRace}}
{{targetTimeLine}}
{{daysToRaceLine}}

CURRENT FITNESS:
{{paceZoneStr}}
Fitness trajectory: {{fitnessTrajectory}}
{{snapshotHistoryLine}}

8-WEEK TRAINING SUMMARY:
Total: {{totalMiles}} miles across {{totalRuns}} runs
Weekly mileage (oldest→newest): {{weeklyMiles}}
Peak week: {{peakWeekMiles}} miles
{{taperLine}}
Quality sessions: {{qualitySessionsCount}} in 8 weeks
Long runs: {{longRunsCount}} (longest: {{longestRun}} miles)
{{longRunDetailsLine}}
Mood trend: {{moodTrendLine}}
{{injuriesLine}}{{athleteContextBlock}}

Respond with a JSON object (no markdown, just raw JSON):
{
  "readiness_score": <0-100>,
  "readiness_label": "<Not Ready | Getting There | Race Ready | Peak Fitness>",
  "confidence": "<Low | Medium | Medium-High | High>",
  "fitness_assessment": "<2-3 sentences on current fitness level>",
  "strengths": ["<specific strength from data>", ...],
  "concerns": ["<specific concern from data>", ...],
  "taper_assessment": "<1-2 sentences on taper quality, or note if not tapering yet>",
  "race_day_plan": {
    "target_time": "<predicted finish time based on current fitness>",
    "strategy": "<1 sentence race strategy>",
    "splits": [
      {"segment": "<e.g. miles 1-3>", "pace": "<M:SS/mi>", "note": "<brief tactical note>"}
    ],
    "fueling": "<fueling strategy>",
    "warmup": "<pre-race warmup suggestion>"
  },
  "what_if": [
    {"scenario": "<condition>", "adjustment": "<what to change>"}
  ],
  "one_thing_to_remember": "<the single most important thing for race day>"
}

Ground everything in THIS runner's actual data. Pace plan must use their real fitness numbers. Be direct about concerns — better to know now than on race day.`;

/**
 * Race Readiness Check
 *
 * On-demand deep analysis of race preparedness.
 * Analyzes 6-8 weeks of training, fitness trajectory, taper quality.
 * Generates a race-day pace plan with specific splits from real data.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// ============================================================================
// Utilities
// ============================================================================

function fmtPace(s: number): string {
  return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}/mi`;
}

function fmtTime(secs: number): string {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = Math.round(secs % 60);
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
}

interface PaceSegment {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string | null;
}

// ============================================================================
// Main handler
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, race_distance, race_date } = await req.json();

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "user_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Race readiness check for user ${user_id}`);

    // ── Athlete state ──
    const athleteState = await getOrBuildAthleteState(supabase, user_id);
    const athleteContext = stateToPromptContext(athleteState);

    const eightWeeksAgo = new Date(Date.now() - 56 * 24 * 60 * 60 * 1000).toISOString();

    // ── Parallel data fetch ──
    const [logsResult, snapshotsResult, snapshotHistoryResult, injuryResult, planResult, profileResult, goalsResult] = await Promise.all([
      // 8 weeks of training logs
      supabase
        .from("training_logs")
        .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, pace_segments, mood, cleaned_notes, workout_notes, source")
        .eq("user_id", user_id)
        .gte("workout_date", eightWeeksAgo)
        .order("workout_date", { ascending: true }),

      // Latest fitness snapshot
      supabase
        .from("fitness_snapshots")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", { ascending: false })
        .limit(1),

      // Fitness snapshot history (trajectory)
      supabase
        .from("fitness_snapshots")
        .select("created_at, predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds")
        .eq("user_id", user_id)
        .order("created_at", { ascending: true })
        .limit(20),

      // Active injuries
      supabase
        .from("injuries")
        .select("body_area, side, severity, status, notes")
        .eq("user_id", user_id)
        .in("status", ["active", "recovering"]),

      // Active training plan
      supabase
        .from("training_plans")
        .select("name, target_race_distance, target_time_seconds, start_date, end_date, status")
        .eq("user_id", user_id)
        .eq("status", "active")
        .limit(1),

      // Athlete profile
      supabase
        .from("athlete_profiles")
        .select("profile_data")
        .eq("user_id", user_id)
        .single(),

      // Goals
      supabase
        .from("user_goals")
        .select("goal_type, target_value, target_date, status")
        .eq("user_id", user_id)
        .eq("status", "active")
        .limit(5),
    ]);

    const logs = (logsResult.data || []) as Array<Record<string, unknown>>;
    const snapshot = snapshotsResult.data?.[0] || null;
    const snapshotHistory = snapshotHistoryResult.data || [];
    const injuries = injuryResult.data || [];
    const plan = planResult.data?.[0] || null;
    const profile = profileResult.data?.profile_data || null;
    const goals = goalsResult.data || [];

    // ── Compute training summary ──
    const runsWithDistance = logs.filter((l: Record<string, unknown>) => (l.workout_distance_miles as number) > 0);
    const totalMiles = runsWithDistance.reduce((s: number, l: Record<string, unknown>) => s + ((l.workout_distance_miles as number) || 0), 0);
    const totalRuns = runsWithDistance.length;

    // Weekly breakdown
    const weeklyMiles: number[] = [];
    for (let w = 0; w < 8; w++) {
      const weekStart = new Date(Date.now() - (8 - w) * 7 * 24 * 60 * 60 * 1000);
      const weekEnd = new Date(weekStart.getTime() + 7 * 24 * 60 * 60 * 1000);
      const weekMiles = runsWithDistance
        .filter((l: Record<string, unknown>) => {
          const d = new Date(l.workout_date as string);
          return d >= weekStart && d < weekEnd;
        })
        .reduce((s: number, l: Record<string, unknown>) => s + ((l.workout_distance_miles as number) || 0), 0);
      weeklyMiles.push(Math.round(weekMiles * 10) / 10);
    }

    // Peak week and taper detection
    const peakWeekMiles = Math.max(...weeklyMiles.slice(0, 6)); // exclude last 2 weeks
    const lastTwoWeeks = weeklyMiles.slice(-2);
    const isTapering = lastTwoWeeks.every(w => w < peakWeekMiles * 0.8);
    const taperReduction = peakWeekMiles > 0 ? Math.round((1 - lastTwoWeeks[1] / peakWeekMiles) * 100) : 0;

    // Long run tracking
    const longRuns = runsWithDistance
      .filter((l: Record<string, unknown>) => (l.workout_distance_miles as number) >= 10)
      .map((l: Record<string, unknown>) => ({
        date: l.workout_date as string,
        miles: l.workout_distance_miles as number,
        pace: (l.workout_duration_minutes as number) > 0 ? ((l.workout_duration_minutes as number) * 60) / (l.workout_distance_miles as number) : 0,
      }));
    const longestRun = longRuns.length > 0 ? Math.max(...longRuns.map(r => r.miles)) : 0;

    // Quality sessions
    const hardEfforts = ["interval", "tempo", "threshold", "race_pace", "speed"];
    const qualitySessions = runsWithDistance.filter((l: Record<string, unknown>) => {
      const segs = l.pace_segments as PaceSegment[] | null;
      if (segs && segs.length > 0) return segs.some(s => hardEfforts.includes(s.effort));
      return l.workout_type && ["interval", "tempo", "race"].includes(l.workout_type as string);
    });

    // Mood trend
    const moods = runsWithDistance.map((l: Record<string, unknown>) => l.mood as string).filter(Boolean);
    const positiveMoods = moods.filter(m => m === "energized" || m === "positive").length;
    const negativeMoods = moods.filter(m => m === "tired" || m === "struggling").length;
    const moodTrend = positiveMoods > negativeMoods ? "positive" : negativeMoods > positiveMoods ? "declining" : "neutral";

    // Fitness trajectory from snapshots
    let fitnessTrajectory = "unknown";
    if (snapshotHistory.length >= 2) {
      const first = snapshotHistory[0];
      const last = snapshotHistory[snapshotHistory.length - 1];
      const key = "predicted_half_seconds";
      if (first[key] && last[key]) {
        const diff = (first[key] as number) - (last[key] as number);
        fitnessTrajectory = diff > 30 ? "improving" : diff < -30 ? "declining" : "stable";
      }
    }

    // Pace zones from snapshot
    let paceZoneStr = "No pace zone data available";
    if (snapshot) {
      const marathonMi = 26.2188, halfMi = 13.1094, tenKMi = 6.2137, fiveKMi = 3.1069;
      const paces: string[] = [];
      if (snapshot.predicted_5k_seconds) paces.push(`5K: ${fmtTime(snapshot.predicted_5k_seconds)} (${fmtPace(snapshot.predicted_5k_seconds / fiveKMi)})`);
      if (snapshot.predicted_10k_seconds) paces.push(`10K: ${fmtTime(snapshot.predicted_10k_seconds)} (${fmtPace(snapshot.predicted_10k_seconds / tenKMi)})`);
      if (snapshot.predicted_half_seconds) paces.push(`Half: ${fmtTime(snapshot.predicted_half_seconds)} (${fmtPace(snapshot.predicted_half_seconds / halfMi)})`);
      if (snapshot.predicted_marathon_seconds) paces.push(`Marathon: ${fmtTime(snapshot.predicted_marathon_seconds)} (${fmtPace(snapshot.predicted_marathon_seconds / marathonMi)})`);
      if (paces.length > 0) paceZoneStr = paces.join("\n");
    }

    // Determine race context
    const targetRace = race_distance || plan?.target_race_distance || goals.find((g: Record<string, unknown>) => g.goal_type === "race")?.target_value || "half marathon";
    const targetDate = race_date || plan?.end_date || goals.find((g: Record<string, unknown>) => g.target_date)?.target_date;
    const targetTime = plan?.target_time_seconds ? fmtTime(plan.target_time_seconds) : null;
    const daysToRace = targetDate ? Math.round((new Date(targetDate).getTime() - Date.now()) / (24 * 60 * 60 * 1000)) : null;

    // ── AI prompt ──
    const prompt = `You're a running coach doing a race readiness assessment. Be honest, specific, and grounded in the data. Use actual paces from this runner's data — never generic numbers.

PACE DIRECTION: In running, LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. "Too fast" means a LOWER number than prescribed. "Too slow" means a HIGHER number. Running slower than easy pace on recovery days is good.

RACE TARGET:
Distance: ${targetRace}
${targetTime ? `Goal time: ${targetTime}` : "No specific time goal set"}
${daysToRace !== null ? `Days to race: ${daysToRace}` : "Race date not set"}

CURRENT FITNESS:
${paceZoneStr}
Fitness trajectory: ${fitnessTrajectory}
${snapshotHistory.length >= 2 ? `Snapshots over time: ${snapshotHistory.map((s: Record<string, unknown>) => {
  const d = new Date(s.created_at as string);
  return `${d.getMonth() + 1}/${d.getDate()}: HM ${s.predicted_half_seconds ? fmtTime(s.predicted_half_seconds as number) : "?"}`;
}).join(" → ")}` : ""}

8-WEEK TRAINING SUMMARY:
Total: ${totalMiles.toFixed(0)} miles across ${totalRuns} runs
Weekly mileage (oldest→newest): ${weeklyMiles.join(", ")}
Peak week: ${peakWeekMiles} miles
${isTapering ? `Tapering: volume reduced ${taperReduction}% from peak` : "Not tapering"}
Quality sessions: ${qualitySessions.length} in 8 weeks
Long runs: ${longRuns.length} (longest: ${longestRun.toFixed(1)} miles)
${longRuns.length > 0 ? `Long run details: ${longRuns.map(r => `${new Date(r.date).getMonth() + 1}/${new Date(r.date).getDate()}: ${r.miles.toFixed(1)}mi ${r.pace > 0 ? `@ ${fmtPace(r.pace)}` : ""}`).join(", ")}` : ""}
Mood trend: ${moodTrend} (${positiveMoods} positive, ${negativeMoods} negative out of ${moods.length})
${injuries.length > 0 ? `Active injuries: ${injuries.map((i: Record<string, unknown>) => `${i.body_area} (${i.side || "bilateral"}, severity ${i.severity}/10, ${i.status})`).join(", ")}` : "No active injuries"}
${athleteContext ? `\nATHLETE STATE:\n${athleteContext}` : ""}

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

    // ── AI call ──
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        maxOutputTokens: 8000,
        temperature: 0.7,
        responseMimeType: "application/json",
      },
    });

    const result = await model.generateContent(prompt);
    const rawText = result.response.text().trim();

    let analysis: Record<string, unknown>;
    console.log("Race readiness raw response length:", rawText.length, "starts with:", rawText.slice(0, 50));
    try {
      analysis = JSON.parse(rawText);
    } catch (e1) {
      console.error("Direct parse failed:", (e1 as Error).message);
      // Strip markdown fences and retry
      const cleaned = rawText
        .replace(/^[\s\S]*?```json\s*/m, "")
        .replace(/```[\s\S]*$/m, "")
        .replace(/```/g, "")
        .trim();
      try {
        analysis = JSON.parse(cleaned);
      } catch (e2) {
        console.error("Cleaned parse failed:", (e2 as Error).message, "cleaned starts with:", cleaned.slice(0, 100));
        // Last resort: try to find the JSON by looking for the first { and last }
        const firstBrace = cleaned.indexOf("{");
        const lastBrace = cleaned.lastIndexOf("}");
        if (firstBrace !== -1 && lastBrace > firstBrace) {
          try {
            analysis = JSON.parse(cleaned.substring(firstBrace, lastBrace + 1));
          } catch (e3) {
            console.error("Substring parse failed:", (e3 as Error).message);
            throw new Error("Failed to parse AI response as JSON");
          }
        } else {
          throw new Error("No JSON found in AI response");
        }
        if (endIdx === -1) throw new Error("Unbalanced JSON in AI response");
        analysis = JSON.parse(cleaned.substring(startIdx, endIdx + 1));
      }
    }
    console.log("Race readiness analysis parsed successfully");

    // ── Generate summary ──
    const score = (analysis.readiness_score as number) || 0;
    const label = (analysis.readiness_label as string) || "Unknown";
    const summary = `${label} (${score}/100). ${(analysis.fitness_assessment as string || "").split(".")[0]}.`;

    // ── Store insight ──
    const { error: insertError } = await supabase
      .from("ai_insights")
      .insert({
        user_id,
        insight_type: "race_readiness",
        trigger_source: "on_demand",
        title: `Race Readiness: ${targetRace}`,
        summary: summary.slice(0, 200),
        full_analysis: analysis,
        priority: score >= 70 ? "normal" : "high",
        expires_at: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(),
      });

    if (insertError) {
      console.error(`Failed to store insight: ${insertError.message}`);
    }

    return new Response(
      JSON.stringify({ success: true, ...analysis }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Race readiness error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

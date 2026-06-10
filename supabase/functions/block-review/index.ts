/**
 * Training Block Review
 *
 * End-of-mesocycle (4-6 week) review.
 * Analyzes the block: pace zone improvements, load management, mood.
 * Recommends changes for the next block.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

function fmtPace(s: number): string {
  return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}/mi`;
}

function fmtTime(secs: number): string {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = Math.round(secs % 60);
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id: bodyUserId, weeks = 4 } = await req.json();

    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId: user_id, isServiceRole } = auth;

    const rlBlocked = await enforceFeatureRateLimit(user_id, "analysis", corsHeaders, { isServiceRole });
    if (rlBlocked) return rlBlocked;

    const blockDays = weeks * 7;
    const blockStart = new Date(Date.now() - blockDays * 24 * 60 * 60 * 1000).toISOString();
    const blockStartDate = new Date(Date.now() - blockDays * 24 * 60 * 60 * 1000);

    // Also fetch the previous block for comparison
    const prevBlockStart = new Date(Date.now() - blockDays * 2 * 24 * 60 * 60 * 1000).toISOString();

    console.log(`Block review: ${weeks} weeks for user ${user_id}`);

    // ── Athlete state ──
    const athleteState = await getOrBuildAthleteState(supabase, user_id);
    const athleteContext = stateToPromptContext(athleteState);

    // ── Parallel fetch ──
    const [logsResult, prevLogsResult, snapshotsResult, injuriesResult, profileResult, planResult] = await Promise.all([
      // This block's logs
      supabase
        .from("training_logs")
        .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, pace_segments, mood, cleaned_notes, workout_notes")
        .eq("user_id", user_id)
        .gte("workout_date", blockStart)
        .order("workout_date", { ascending: true }),

      // Previous block for comparison
      supabase
        .from("training_logs")
        .select("workout_date, workout_distance_miles, workout_duration_minutes, workout_type, pace_segments, mood")
        .eq("user_id", user_id)
        .gte("workout_date", prevBlockStart)
        .lt("workout_date", blockStart)
        .order("workout_date", { ascending: true }),

      // Fitness snapshots spanning both blocks
      supabase
        .from("fitness_snapshots")
        .select("created_at, predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds")
        .eq("user_id", user_id)
        .gte("created_at", prevBlockStart)
        .order("created_at", { ascending: true }),

      // Injuries during this block
      supabase
        .from("injuries")
        .select("body_area, side, severity, status, created_at")
        .eq("user_id", user_id)
        .gte("created_at", blockStart),

      // Profile
      supabase.from("athlete_profiles").select("profile_data").eq("user_id", user_id).single(),

      // Plan
      supabase.from("training_plans").select("name, target_race_distance, target_time_seconds, start_date, end_date").eq("user_id", user_id).eq("status", "active").limit(1),
    ]);

    const logs = logsResult.data || [];
    const prevLogs = prevLogsResult.data || [];
    const snapshots = snapshotsResult.data || [];
    const injuries = injuriesResult.data || [];
    const plan = planResult.data?.[0] || null;

    // ── Compute block stats ──
    const hardEfforts = ["interval", "tempo", "threshold", "race_pace", "speed"];

    function computeBlockStats(blockLogs: Record<string, unknown>[]) {
      const runs = blockLogs.filter((l) => ((l.workout_distance_miles as number) || 0) > 0);
      const totalMiles = runs.reduce((s, l) => s + ((l.workout_distance_miles as number) || 0), 0);
      const totalRuns = runs.length;

      let hardMinutes = 0;
      let qualitySessions = 0;
      const easyPaces: number[] = [];
      const hardPaces: number[] = [];

      for (const log of runs) {
        const segs = log.pace_segments as Array<Record<string, unknown>> | null;
        let isQuality = false;
        if (segs && segs.length > 0) {
          for (const seg of segs) {
            const pace = seg.pace_per_mile ? (seg.pace_per_mile as string).split(":").reduce((a: number, b: string, i: number) => a + (i === 0 ? parseInt(b) * 60 : parseInt(b)), 0) : 0;
            if (hardEfforts.includes(seg.effort as string)) {
              hardMinutes += (seg.duration_seconds as number) / 60;
              if (pace > 0) hardPaces.push(pace);
              isQuality = true;
            } else {
              if (pace > 0 && pace < 900) easyPaces.push(pace);
            }
          }
        }
        if (isQuality) qualitySessions++;
      }

      const moods = runs.map(l => l.mood as string).filter(Boolean);
      const positivePct = moods.length > 0 ? Math.round(moods.filter(m => m === "energized" || m === "positive").length / moods.length * 100) : 0;

      // Weekly volumes
      const weeklyMiles: number[] = [];
      const numWeeks = Math.ceil(runs.length > 0 ? (new Date(runs[runs.length - 1].workout_date as string).getTime() - new Date(runs[0].workout_date as string).getTime()) / (7 * 24 * 60 * 60 * 1000) + 1 : 1);
      for (let w = 0; w < Math.max(numWeeks, 1); w++) {
        const wStart = new Date(new Date(runs[0]?.workout_date as string || Date.now()).getTime() + w * 7 * 24 * 60 * 60 * 1000);
        const wEnd = new Date(wStart.getTime() + 7 * 24 * 60 * 60 * 1000);
        const wMiles = runs
          .filter(l => { const d = new Date(l.workout_date as string); return d >= wStart && d < wEnd; })
          .reduce((s, l) => s + ((l.workout_distance_miles as number) || 0), 0);
        weeklyMiles.push(Math.round(wMiles * 10) / 10);
      }

      return {
        totalMiles: Math.round(totalMiles * 10) / 10,
        totalRuns,
        avgWeekly: Math.round(totalMiles / Math.max(weeklyMiles.length, 1) * 10) / 10,
        peakWeek: weeklyMiles.length > 0 ? Math.max(...weeklyMiles) : 0,
        weeklyMiles,
        hardMinutes: Math.round(hardMinutes),
        qualitySessions,
        avgEasyPace: easyPaces.length > 0 ? fmtPace(easyPaces.reduce((a, b) => a + b, 0) / easyPaces.length) : "N/A",
        avgHardPace: hardPaces.length > 0 ? fmtPace(hardPaces.reduce((a, b) => a + b, 0) / hardPaces.length) : "N/A",
        positiveMoodPct: positivePct,
        longestRun: runs.length > 0 ? Math.max(...runs.map(l => (l.workout_distance_miles as number) || 0)) : 0,
      };
    }

    const blockStats = computeBlockStats(logs as Record<string, unknown>[]);
    const prevStats = prevLogs.length > 0 ? computeBlockStats(prevLogs as Record<string, unknown>[]) : null;

    // Fitness delta
    let fitnessDelta = "";
    if (snapshots.length >= 2) {
      const blockSnaps = snapshots.filter((s: Record<string, unknown>) => new Date(s.created_at as string) >= blockStartDate);
      const prevSnaps = snapshots.filter((s: Record<string, unknown>) => new Date(s.created_at as string) < blockStartDate);
      if (blockSnaps.length > 0 && prevSnaps.length > 0) {
        const latest = blockSnaps[blockSnaps.length - 1];
        const baseline = prevSnaps[prevSnaps.length - 1];
        const keys = ["predicted_5k_seconds", "predicted_10k_seconds", "predicted_half_seconds", "predicted_marathon_seconds"];
        const labels = ["5K", "10K", "Half", "Marathon"];
        const changes = keys.map((k, i) => {
          if (latest[k] && baseline[k]) {
            const diff = (baseline[k] as number) - (latest[k] as number);
            return `${labels[i]}: ${diff > 0 ? "improved" : "regressed"} ${Math.abs(Math.round(diff))}s (${fmtTime(latest[k] as number)})`;
          }
          return null;
        }).filter(Boolean);
        if (changes.length > 0) fitnessDelta = changes.join(", ");
      }
    }

    // ── AI prompt ──
    const injuriesLine = injuries.length > 0
      ? `Injuries: ${injuries.map((i: Record<string, unknown>) => `${i.body_area} (severity ${i.severity})`).join(", ")}`
      : "Clean block — no injuries";
    const fitnessDeltaLine = fitnessDelta ? `Fitness changes: ${fitnessDelta}` : "";
    const planLine = plan
      ? `Training plan: ${plan.name}, targeting ${plan.target_race_distance}${plan.target_time_seconds ? ` in ${fmtTime(plan.target_time_seconds)}` : ""}`
      : "No active training plan";
    const athleteContextBlock = athleteContext ? `\nATHLETE STATE:\n${athleteContext}` : "";
    const prevBlockBlock = prevStats
      ? `PREVIOUS BLOCK (for comparison):
Total: ${prevStats.totalMiles} miles, ${prevStats.totalRuns} runs (avg ${prevStats.avgWeekly}/week)
Quality: ${prevStats.qualitySessions} sessions, ${prevStats.hardMinutes} hard minutes
Easy: ${prevStats.avgEasyPace} | Hard: ${prevStats.avgHardPace}
Mood: ${prevStats.positiveMoodPct}% positive`
      : "No previous block data";

    const prompt = loadPrompt("block-review.v1", {
      weeks,
      totalMiles: blockStats.totalMiles,
      totalRuns: blockStats.totalRuns,
      avgWeekly: blockStats.avgWeekly,
      peakWeek: blockStats.peakWeek,
      weeklyMiles: blockStats.weeklyMiles.join(" → "),
      qualitySessions: blockStats.qualitySessions,
      hardMinutes: blockStats.hardMinutes,
      avgEasyPace: blockStats.avgEasyPace,
      avgHardPace: blockStats.avgHardPace,
      longestRun: blockStats.longestRun.toFixed(1),
      positiveMoodPct: blockStats.positiveMoodPct,
      injuriesLine,
      fitnessDeltaLine,
      planLine,
      athleteContextBlock,
      prevBlockBlock,
    });

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
        maxOutputTokens: 3000,
        temperature: 0.75,
        responseMimeType: "application/json",
      },
    });

    const result = await model.generateContent(prompt);
    const rawText = result.response.text().trim();

    let analysis: Record<string, unknown>;
    try {
      analysis = JSON.parse(rawText);
    } catch {
      const jsonMatch = rawText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        analysis = JSON.parse(jsonMatch[0]);
      } else {
        throw new Error("Failed to parse block review JSON");
      }
    }

    // Add computed data to the analysis
    analysis.block_stats = blockStats;
    analysis.previous_block_stats = prevStats;
    analysis.fitness_delta = fitnessDelta || "No snapshot data";
    analysis.block_period = {
      start: blockStartDate.toISOString().split("T")[0],
      end: new Date().toISOString().split("T")[0],
      weeks,
    };

    const summary = (analysis.one_line_summary as string) || `${weeks}-week block: ${blockStats.totalMiles}mi, grade ${analysis.block_grade}`;

    // ── Store insight ──
    const { error: insertError } = await supabase
      .from("ai_insights")
      .insert({
        user_id,
        insight_type: "block_review",
        trigger_source: "on_demand",
        title: `${weeks}-Week Block Review`,
        summary: summary.slice(0, 200),
        full_analysis: analysis,
        priority: "normal",
        expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      });

    if (insertError) console.error(`Failed to store block review: ${insertError.message}`);

    return new Response(
      JSON.stringify({ success: true, ...analysis }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Block review error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

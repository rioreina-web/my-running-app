/**
 * Post-Run Instant Analysis
 *
 * Triggers after a workout syncs (auto_sync or voice_log).
 * Analyzes the run in context: pace zones, recent load, training history.
 * Stores result in ai_insights table for the iOS app to display.
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
// Interfaces
// ============================================================================

interface PaceSegment {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string | null;
  avg_heart_rate?: number | null;
}

interface TrainingLog {
  id: string;
  user_id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  workout_pace_per_mile: string | null;
  pace_segments: PaceSegment[] | null;
  mood: string | null;
  notes: string | null;
  cleaned_notes: string | null;
  workout_notes: string | null;
  source: string | null;
}

// ============================================================================
// Pace zone utilities
// ============================================================================

function computePaceZones(snap: Record<string, number>): Record<string, number> | null {
  const marathonMi = 26.2188, halfMi = 13.1094, tenKMi = 6.2137, fiveKMi = 3.1069;

  const mp = snap.predicted_marathon_seconds ? snap.predicted_marathon_seconds / marathonMi : 0;
  const hm = snap.predicted_half_seconds ? snap.predicted_half_seconds / halfMi : 0;
  const tk = snap.predicted_10k_seconds ? snap.predicted_10k_seconds / tenKMi : 0;
  const fk = snap.predicted_5k_seconds ? snap.predicted_5k_seconds / fiveKMi : 0;

  if (!mp && !hm && !tk && !fk) return null;

  const marathon = mp || (hm ? hm * 1.06 : (tk ? tk * 1.15 : fk * 1.22));
  const half = hm || (mp ? mp * 0.943 : (tk ? tk * 1.08 : fk * 1.15));
  const tenK = tk || (hm ? hm * 0.925 : (fk ? fk * 1.06 : marathon * 0.87));
  const fiveK = fk || (tk ? tk * 0.943 : (hm ? hm * 0.87 : marathon * 0.82));

  return {
    easy: marathon + 90,
    marathon,
    halfMarathon: half,
    threshold: (tenK + half) / 2,
    tenK,
    fiveK,
  };
}

function labelPaceZone(paceSecsPerMile: number, zones: Record<string, number>): string {
  const tolerance = 8;
  const zoneDefs = [
    { name: "5K pace", pace: zones.fiveK },
    { name: "10K pace", pace: zones.tenK },
    { name: "threshold", pace: zones.threshold },
    { name: "HM pace", pace: zones.halfMarathon },
    { name: "marathon pace", pace: zones.marathon },
    { name: "easy pace", pace: zones.easy },
  ];

  if (paceSecsPerMile < zones.fiveK - tolerance) return "faster than 5K pace";
  for (const z of zoneDefs) {
    if (Math.abs(paceSecsPerMile - z.pace) <= tolerance) return z.name;
  }
  for (let i = 0; i < zoneDefs.length - 1; i++) {
    if (paceSecsPerMile > zoneDefs[i].pace && paceSecsPerMile < zoneDefs[i + 1].pace) {
      return `between ${zoneDefs[i].name} and ${zoneDefs[i + 1].name}`;
    }
  }
  return paceSecsPerMile > zones.easy + tolerance ? "recovery pace" : "easy pace";
}

function parsePace(p: string): number {
  const parts = p.split(":").map(Number);
  return parts.length === 2 ? parts[0] * 60 + parts[1] : 0;
}

function fmtPace(s: number): string {
  return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}/mi`;
}

// ============================================================================
// Main handler
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { training_log_id, user_id } = await req.json();

    if (!training_log_id || !user_id) {
      return new Response(
        JSON.stringify({ error: "training_log_id and user_id are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Post-run analysis for log ${training_log_id}, user ${user_id}`);

    // ── Athlete state ──
    const athleteState = await getOrBuildAthleteState(supabase, user_id);
    const athleteContext = stateToPromptContext(athleteState);

    // ── Parallel data fetch ──
    const [logResult, recentResult, snapshotResult, injuryResult, profileResult] = await Promise.all([
      // The workout that just synced
      supabase
        .from("training_logs")
        .select("*")
        .eq("id", training_log_id)
        .single(),

      // Last 14 days of training for context
      supabase
        .from("training_logs")
        .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, pace_segments, mood, cleaned_notes, workout_notes")
        .eq("user_id", user_id)
        .gte("workout_date", new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString())
        .neq("id", training_log_id)
        .order("workout_date", { ascending: false })
        .limit(20),

      // Latest fitness snapshot for pace zones
      supabase
        .from("fitness_snapshots")
        .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds")
        .eq("user_id", user_id)
        .order("created_at", { ascending: false })
        .limit(1),

      // Active injuries
      supabase
        .from("injuries")
        .select("body_area, side, severity, notes")
        .eq("user_id", user_id)
        .eq("status", "active")
        .limit(5),

      // Cached athlete profile
      supabase
        .from("athlete_profiles")
        .select("profile_data")
        .eq("user_id", user_id)
        .single(),
    ]);

    const log = logResult.data as TrainingLog | null;
    if (!log || !log.workout_distance_miles || log.workout_distance_miles <= 0) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "No distance data" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const recentLogs = (recentResult.data || []) as TrainingLog[];
    const snapshot = snapshotResult.data?.[0] || null;
    const injuries = injuryResult.data || [];
    const athleteProfile = profileResult.data?.profile_data || null;

    // ── Compute context ──

    // Pace zones
    const paceZones = snapshot ? computePaceZones(snapshot as Record<string, number>) : null;

    // This workout's key metrics
    const distance = log.workout_distance_miles;
    const duration = log.workout_duration_minutes || 0;
    const overallPace = duration > 0 && distance > 0 ? (duration * 60) / distance : 0;

    // Segment analysis
    const hardEfforts = ["interval", "tempo", "threshold", "race_pace", "speed"];
    let hardSegments: PaceSegment[] = [];
    let easySegments: PaceSegment[] = [];
    let workoutStructure = "";

    if (log.pace_segments && log.pace_segments.length > 0) {
      hardSegments = log.pace_segments.filter(s => hardEfforts.includes(s.effort));
      easySegments = log.pace_segments.filter(s => !hardEfforts.includes(s.effort));

      if (hardSegments.length > 0) {
        const splits = hardSegments.map(s => {
          const distLabel = s.distance_miles >= 0.9 ? `${s.distance_miles.toFixed(1)}mi` :
            Math.abs(s.distance_miles - 0.5) < 0.05 ? "800m" :
            Math.abs(s.distance_miles - 0.25) < 0.03 ? "400m" :
            `${Math.round(s.distance_miles * 1609)}m`;
          const paceLabel = s.pace_per_mile || "?";
          const zoneLabel = paceZones && s.pace_per_mile ? ` (${labelPaceZone(parsePace(s.pace_per_mile), paceZones)})` : "";
          return `${distLabel} @ ${paceLabel}${zoneLabel}`;
        });
        workoutStructure = `Hard segments: ${splits.join(", ")}`;
      }
    }

    // Recent load context
    const last7dMiles = recentLogs
      .filter(l => {
        const d = new Date(l.workout_date);
        return d.getTime() > Date.now() - 7 * 24 * 60 * 60 * 1000;
      })
      .reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);

    const last14dMiles = recentLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    const weeklyAvg = last14dMiles / 2;
    const thisWeekTotal = last7dMiles + distance;

    // Recent hard sessions
    const recentHardDays = recentLogs.filter(l => {
      if (l.pace_segments) return l.pace_segments.some(s => hardEfforts.includes(s.effort));
      return l.workout_type && ["interval", "tempo", "race"].includes(l.workout_type);
    }).length;

    const lastHardDate = recentLogs.find(l => {
      if (l.pace_segments) return l.pace_segments.some(s => hardEfforts.includes(s.effort));
      return l.workout_type && ["interval", "tempo", "race"].includes(l.workout_type);
    })?.workout_date;

    const daysSinceLastHard = lastHardDate
      ? Math.round((Date.now() - new Date(lastHardDate).getTime()) / (24 * 60 * 60 * 1000))
      : null;

    // ── Build AI prompt ──
    const dateStr = new Date(log.workout_date).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
    const isHard = hardSegments.length > 0;

    let paceRef = "";
    if (paceZones) {
      paceRef = `\nRunner's pace zones: Easy ${fmtPace(paceZones.easy)}, Marathon ${fmtPace(paceZones.marathon)}, HM ${fmtPace(paceZones.halfMarathon)}, Threshold ${fmtPace(paceZones.threshold)}, 10K ${fmtPace(paceZones.tenK)}, 5K ${fmtPace(paceZones.fiveK)}`;
    }

    let injuryNote = "";
    if (injuries.length > 0) {
      injuryNote = `\nActive injuries: ${injuries.map(i => `${i.body_area} (${i.side || "bilateral"}, severity ${i.severity}/10)`).join(", ")}`;
    }

    const prompt = `You're a running coach giving instant feedback after a workout. Be specific, casual, and brief — 3-5 sentences max. Reference actual paces and splits, not generalities. When pace zones are available, describe efforts in those terms (e.g. "right at 10K pace" or "a touch faster than threshold").

PACE DIRECTION: In running, LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. "Too fast" means a LOWER number than prescribed. "Too slow" means a HIGHER number. Running slower than easy pace on recovery days is good.

TODAY'S RUN (${dateStr}):
Distance: ${distance.toFixed(1)} miles
Duration: ${duration > 0 ? `${duration} min` : "unknown"}
Overall pace: ${overallPace > 0 ? fmtPace(overallPace) : "unknown"}
Type: ${log.workout_type || "untagged"}
Mood: ${log.mood || "not recorded"}
${workoutStructure ? `\n${workoutStructure}` : ""}
${log.workout_notes ? `Workout notes: ${log.workout_notes}` : ""}
${log.cleaned_notes ? `Runner's notes: ${log.cleaned_notes}` : ""}
${paceRef}${injuryNote}
${athleteContext ? `\nATHLETE STATE:\n${athleteContext}` : ""}

CONTEXT:
This week so far: ${thisWeekTotal.toFixed(1)} miles (2-week avg: ${weeklyAvg.toFixed(1)}/week)
Hard sessions in last 14 days: ${recentHardDays}
${daysSinceLastHard !== null ? `Days since last hard session: ${daysSinceLastHard}` : ""}
${recentLogs.length > 0 ? `Recent runs: ${recentLogs.slice(0, 5).map(l => {
  const d = new Date(l.workout_date);
  return `${d.getMonth() + 1}/${d.getDate()}: ${(l.workout_distance_miles || 0).toFixed(1)}mi ${l.workout_type || ""} ${l.mood ? `[${l.mood}]` : ""}`;
}).join(", ")}` : ""}

Write a brief, insightful analysis. Include:
1. What stands out about this specific run (pacing, effort, structure)
2. How it fits into the recent training context (load, recovery, progression)
3. One forward-looking note (what this means for the next session)

Keep it to 3-5 sentences. No headers, no bullet points. Write like a text from a coach who just looked at your watch data.`;

    // ── AI call ──
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      console.error("GEMINI_API_KEY not configured");
      return new Response(
        JSON.stringify({ error: "AI not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        maxOutputTokens: 1000,
        temperature: 0.85,
      },
    });

    const result = await model.generateContent(prompt);
    const analysis = result.response.text().trim();

    // ── Generate title and summary ──
    const title = isHard
      ? `${log.workout_type || "Workout"} — ${distance.toFixed(1)}mi`
      : `${distance.toFixed(1)}mi ${log.workout_type || "run"}`;

    const summary = analysis.split(".").slice(0, 2).join(".") + ".";

    // ── Store insight ──
    const { error: insertError } = await supabase
      .from("ai_insights")
      .insert({
        user_id: user_id,
        insight_type: "post_run_analysis",
        trigger_source: log.source === "voice_log" ? "voice_memo" : "workout_sync",
        title: title.charAt(0).toUpperCase() + title.slice(1),
        summary: summary.slice(0, 200),
        full_analysis: {
          analysis,
          run_date: log.workout_date,
          distance_miles: distance,
          duration_minutes: duration,
          overall_pace: overallPace > 0 ? fmtPace(overallPace) : null,
          workout_type: log.workout_type,
          is_quality_session: isHard,
          hard_segment_count: hardSegments.length,
          workout_structure: workoutStructure || null,
          week_miles_so_far: Math.round(thisWeekTotal * 10) / 10,
          weekly_average: Math.round(weeklyAvg * 10) / 10,
          mood: log.mood,
        },
        reference_id: training_log_id,
        priority: isHard ? "normal" : "low",
        expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(), // 7 days
      });

    if (insertError) {
      console.error(`Failed to store insight: ${insertError.message}`);
    } else {
      console.log(`Post-run analysis created for log ${training_log_id}`);
    }

    // Trigger injury early warning check (fire-and-forget)
    try {
      const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
      fetch(`${supabaseUrl}/functions/v1/injury-early-warning`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseServiceKey}`,
        },
        body: JSON.stringify({ user_id }),
      }).catch(err => console.error("Injury early warning trigger failed:", err));
      console.log("Triggered injury early warning for user", user_id);
    } catch (ewErr) {
      console.error("Error triggering injury early warning:", ewErr);
    }

    return new Response(
      JSON.stringify({ success: true, analysis: summary }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Post-run analysis error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

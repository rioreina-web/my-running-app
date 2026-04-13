/**
 * Adaptive Workout Designer
 *
 * Generates the next workout based on the runner's current state.
 * Replaces static training plans with intelligent, adaptive suggestions.
 * Stores the result in ai_insights with type 'adaptive_workout'.
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
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  pace_segments: PaceSegment[] | null;
  mood: string | null;
  notes: string | null;
}

interface PaceZones {
  easy: number;
  marathon: number;
  halfMarathon: number;
  threshold: number;
  tenK: number;
  fiveK: number;
}

// ============================================================================
// Pace zone utilities
// ============================================================================

function computePaceZones(snap: {
  predicted_marathon_seconds?: number;
  predicted_half_seconds?: number;
  predicted_10k_seconds?: number;
  predicted_5k_seconds?: number;
}): PaceZones | null {
  if (!snap.predicted_marathon_seconds && !snap.predicted_half_seconds &&
      !snap.predicted_10k_seconds && !snap.predicted_5k_seconds) {
    return null;
  }

  const marathonMi = 26.2188, halfMi = 13.1094, tenKMi = 6.2137, fiveKMi = 3.1069;

  const marathonPace = snap.predicted_marathon_seconds ? snap.predicted_marathon_seconds / marathonMi : 0;
  const halfPace = snap.predicted_half_seconds ? snap.predicted_half_seconds / halfMi : 0;
  const tenKPace = snap.predicted_10k_seconds ? snap.predicted_10k_seconds / tenKMi : 0;
  const fiveKPace = snap.predicted_5k_seconds ? snap.predicted_5k_seconds / fiveKMi : 0;

  const mp = marathonPace || (halfPace ? halfPace * 1.06 : (tenKPace ? tenKPace * 1.15 : fiveKPace * 1.22));
  const hm = halfPace || (marathonPace ? marathonPace * 0.943 : (tenKPace ? tenKPace * 1.08 : fiveKPace * 1.15));
  const tk = tenKPace || (halfPace ? halfPace * 0.925 : (fiveKPace ? fiveKPace * 1.06 : mp * 0.87));
  const fk = fiveKPace || (tenKPace ? tenKPace * 0.943 : (halfPace ? halfPace * 0.87 : mp * 0.82));

  return {
    easy: mp + 90,
    marathon: mp,
    halfMarathon: hm,
    threshold: (tk + hm) / 2,
    tenK: tk,
    fiveK: fk,
  };
}

function fmtPace(s: number): string {
  return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}/mi`;
}

// ============================================================================
// Load computation helpers
// ============================================================================

const HARD_EFFORTS = ["interval", "tempo", "threshold", "race_pace", "speed"];
const HARD_TYPES = ["interval", "tempo", "race", "intervals", "threshold", "fartlek"];

function isHardSession(log: TrainingLog): boolean {
  if (log.pace_segments && log.pace_segments.some(s => HARD_EFFORTS.includes(s.effort))) return true;
  if (log.workout_type && HARD_TYPES.includes(log.workout_type)) return true;
  return false;
}

function getStartOfWeek(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay(); // 0=Sun
  const diff = day === 0 ? 6 : day - 1; // Monday start
  d.setDate(d.getDate() - diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

function daysBetween(a: Date, b: Date): number {
  return Math.round(Math.abs(a.getTime() - b.getTime()) / (24 * 60 * 60 * 1000));
}

// ============================================================================
// Training phase detection
// ============================================================================

function detectTrainingPhase(plan: {
  start_date: string;
  end_date: string;
} | null): string | null {
  if (!plan) return null;

  const start = new Date(plan.start_date);
  const end = new Date(plan.end_date);
  const now = new Date();
  const totalWeeks = Math.max(1, Math.round((end.getTime() - start.getTime()) / (7 * 24 * 60 * 60 * 1000)));
  const currentWeek = Math.max(1, Math.round((now.getTime() - start.getTime()) / (7 * 24 * 60 * 60 * 1000)));
  const progress = currentWeek / totalWeeks;

  if (progress >= 0.9) return "taper";
  if (progress >= 0.6) return "peak";
  if (progress >= 0.3) return "build";
  return "base";
}

// ============================================================================
// Main handler
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id } = await req.json();

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "user_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Adaptive workout design for user ${user_id}`);

    const now = new Date();
    const fourteenDaysAgo = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000).toISOString();
    const threeDaysAgo = new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000).toISOString();

    // ── Athlete state (supplemental context for AI prompt) ──
    const athleteState = await getOrBuildAthleteState(supabase, user_id);
    const athleteContext = stateToPromptContext(athleteState);

    // ── Parallel data fetch ──
    const [
      logsResult,
      snapshotResult,
      injuriesResult,
      profileResult,
      plansResult,
      warningsResult,
      goalsResult,
    ] = await Promise.all([
      // Training logs for last 14 days
      supabase
        .from("training_logs")
        .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, pace_segments, mood, notes")
        .eq("user_id", user_id)
        .gte("workout_date", fourteenDaysAgo)
        .order("workout_date", { ascending: false })
        .limit(30),

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
        .select("body_area, side, severity, status, description, first_reported_at")
        .eq("user_id", user_id)
        .in("status", ["active", "monitoring"])
        .order("severity", { ascending: false })
        .limit(10),

      // Cached athlete profile
      supabase
        .from("athlete_profiles")
        .select("profile_data")
        .eq("user_id", user_id)
        .single(),

      // Active training plans
      supabase
        .from("training_plans")
        .select("name, target_race_distance, target_time_seconds, start_date, end_date, status")
        .eq("user_id", user_id)
        .eq("status", "active")
        .limit(1),

      // Recent injury warnings from AI
      supabase
        .from("ai_insights")
        .select("title, summary, full_analysis")
        .eq("user_id", user_id)
        .eq("insight_type", "injury_warning")
        .gte("created_at", threeDaysAgo)
        .order("created_at", { ascending: false })
        .limit(3),

      // Active user goals
      supabase
        .from("user_goals")
        .select("goal_title, target_date, goal_type, target_value")
        .eq("user_id", user_id)
        .eq("status", "active")
        .limit(5),
    ]);

    const logs = (logsResult.data || []) as TrainingLog[];
    const snapshot = snapshotResult.data?.[0] || null;
    const injuries = injuriesResult.data || [];
    const athleteProfile = profileResult.data?.profile_data || null;
    const activePlan = plansResult.data?.[0] || null;
    const injuryWarnings = warningsResult.data || [];
    const goals = goalsResult.data || [];

    // ── Compute pace zones ──
    const paceZones = snapshot ? computePaceZones(snapshot) : null;

    // ── This week's load ──
    const weekStart = getStartOfWeek(now);
    const thisWeekLogs = logs.filter(l => new Date(l.workout_date) >= weekStart);
    const thisWeekMiles = thisWeekLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    const thisWeekRuns = thisWeekLogs.length;
    const thisWeekHardSessions = thisWeekLogs.filter(isHardSession).length;

    // ── Recent load ──
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const last7dLogs = logs.filter(l => new Date(l.workout_date) >= sevenDaysAgo);
    const last7dMiles = last7dLogs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    const last14dMiles = logs.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    const weeklyAverage = last14dMiles / 2;

    // ── Last workout ──
    const lastWorkout = logs[0] || null;
    let lastWorkoutSummary = "No recent workouts";
    if (lastWorkout) {
      const daysSinceLast = daysBetween(now, new Date(lastWorkout.workout_date));
      const dist = lastWorkout.workout_distance_miles?.toFixed(1) || "?";
      const type = lastWorkout.workout_type || "run";
      const mood = lastWorkout.mood ? ` [mood: ${lastWorkout.mood}]` : "";
      lastWorkoutSummary = `${dist}mi ${type} ${daysSinceLast === 0 ? "today" : daysSinceLast === 1 ? "yesterday" : `${daysSinceLast} days ago`}${mood}`;
    }

    // ── Days since last hard session ──
    const lastHard = logs.find(isHardSession);
    const daysSinceLastHard = lastHard ? daysBetween(now, new Date(lastHard.workout_date)) : null;

    // ── Days since last rest day ──
    // Find the most recent day with no workout in the last 14 days
    let daysSinceRest: number | null = null;
    for (let i = 0; i < 14; i++) {
      const checkDate = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
      const dateStr = checkDate.toISOString().split("T")[0];
      const hasWorkout = logs.some(l => l.workout_date.startsWith(dateStr));
      if (!hasWorkout) {
        daysSinceRest = i;
        break;
      }
    }

    // ── Injury constraints ──
    let injuryContext = "";
    if (injuries.length > 0) {
      const lines = injuries.map((i: Record<string, unknown>) => {
        const sideLabel = i.side !== "unknown" ? `${i.side} ` : "";
        return `${sideLabel}${i.body_area} (severity: ${i.severity}/10, ${i.status})${i.description ? ` - ${i.description}` : ""}`;
      });
      injuryContext = `\nACTIVE INJURIES:\n- ${lines.join("\n- ")}`;
    }

    let warningContext = "";
    if (injuryWarnings.length > 0) {
      const warnings = injuryWarnings.map((w: Record<string, unknown>) => `${w.title}: ${w.summary}`);
      warningContext = `\nRECENT AI INJURY WARNINGS (last 3 days):\n- ${warnings.join("\n- ")}`;
    }

    // ── Training phase ──
    const trainingPhase = detectTrainingPhase(activePlan);

    // ── Build plan context ──
    let planContext = "";
    if (activePlan) {
      planContext = `\nACTIVE TRAINING PLAN: "${activePlan.name}"
Target race: ${activePlan.target_race_distance || "unspecified"}
Target time: ${activePlan.target_time_seconds ? `${Math.floor(activePlan.target_time_seconds / 3600)}h ${Math.floor((activePlan.target_time_seconds % 3600) / 60)}m` : "unspecified"}
Phase: ${trainingPhase || "unknown"} (${activePlan.start_date} to ${activePlan.end_date})`;
    }

    // ── Goals context ──
    let goalsContext = "";
    if (goals.length > 0) {
      const goalLines = goals.map((g: Record<string, unknown>) =>
        `${g.goal_title}${g.target_date ? ` (target: ${g.target_date})` : ""}`
      );
      goalsContext = `\nACTIVE GOALS:\n- ${goalLines.join("\n- ")}`;
    }

    // ── Athlete profile context ──
    let profileContext = "";
    if (athleteProfile) {
      const p = athleteProfile as Record<string, unknown>;
      if (p.summary) profileContext = `\nATHLETE PROFILE:\n${p.summary}`;
      else if (p.weekly_mileage_range) profileContext = `\nATHLETE: Typical weekly mileage ${p.weekly_mileage_range}`;
    }

    // ── Pace zones string ──
    let paceZoneStr = "Pace zones not available (no fitness snapshot). Do NOT invent paces — suggest effort-based workout instead (RPE scale).";
    if (paceZones) {
      paceZoneStr = `PACE ZONES (from fitness data — use these exact paces):
- Easy: ${fmtPace(paceZones.easy)}
- Marathon: ${fmtPace(paceZones.marathon)}
- Half Marathon: ${fmtPace(paceZones.halfMarathon)}
- Threshold: ${fmtPace(paceZones.threshold)}
- 10K: ${fmtPace(paceZones.tenK)}
- 5K: ${fmtPace(paceZones.fiveK)}`;
    }

    // ── Recent runs summary ──
    const recentRunsSummary = logs.slice(0, 7).map(l => {
      const d = new Date(l.workout_date);
      const dateLabel = `${d.getMonth() + 1}/${d.getDate()}`;
      const dist = (l.workout_distance_miles || 0).toFixed(1);
      const type = l.workout_type || "run";
      const hard = isHardSession(l) ? " [HARD]" : "";
      const mood = l.mood ? ` (${l.mood})` : "";
      return `${dateLabel}: ${dist}mi ${type}${hard}${mood}`;
    }).join("\n  ");

    // ── Fetch tomorrow's weather (Open-Meteo forecast, free, no key) ──
    let weatherContext = "";
    try {
      // Use Austin, TX as default — could be made dynamic from athlete profile
      const lat = 30.27; const lon = -97.74; // Austin
      const forecastRes = await fetch(
        `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America/Chicago&forecast_days=2`,
        { signal: AbortSignal.timeout(5000) }
      );
      if (forecastRes.ok) {
        const wx = await forecastRes.json();
        const d = wx.daily;
        if (d?.temperature_2m_max?.[1] != null) {
          const high = Math.round(d.temperature_2m_max[1]);
          const low = Math.round(d.temperature_2m_min[1]);
          const precip = d.precipitation_probability_max?.[1] ?? 0;
          const wind = Math.round(d.wind_speed_10m_max?.[1] ?? 0);
          weatherContext = `\nWEATHER TOMORROW: ${low}-${high}°F`;
          if (wind > 10) weatherContext += `, winds ${wind} mph`;
          if (precip > 30) weatherContext += `, ${precip}% rain chance`;
          // Heat adjustment guidance
          if (high > 75) {
            const slowSec = Math.round((high - 55) * 1.2);
            weatherContext += `\n⚠ HEAT: Slow all paces ~${slowSec}s/mi. Prioritize hydration. Consider shortening the workout or moving to early morning.`;
          }
          if (high < 35) {
            weatherContext += `\n❄ COLD: Extended warmup needed. Pace will feel harder initially — that's normal.`;
          }
        }
      }
    } catch { /* weather fetch is best-effort */ }

    // ── Build AI prompt ──
    const dayOfWeek = now.toLocaleDateString("en-US", { weekday: "long" });
    const tomorrowDate = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const tomorrowDay = tomorrowDate.toLocaleDateString("en-US", { weekday: "long" });

    const prompt = `You are an expert running coach designing a single workout. Generate ONE specific workout for tomorrow (${tomorrowDay}).
${weatherContext}

${paceZoneStr}

CURRENT LOAD:
- This week: ${thisWeekMiles.toFixed(1)} miles across ${thisWeekRuns} runs, ${thisWeekHardSessions} hard sessions
- Last 7 days: ${last7dMiles.toFixed(1)} miles
- Last 14 days: ${last14dMiles.toFixed(1)} miles
- 2-week weekly average: ${weeklyAverage.toFixed(1)} miles/week

LAST WORKOUT: ${lastWorkoutSummary}
Days since last hard session: ${daysSinceLastHard !== null ? daysSinceLastHard : "unknown"}
Days since last rest day: ${daysSinceRest !== null ? daysSinceRest : "unknown (ran every day in last 14 days)"}

RECENT RUNS:
  ${recentRunsSummary || "None"}
${injuryContext}${warningContext}${planContext}${goalsContext}${profileContext}

ATHLETE STATE SUMMARY:
${athleteContext}

PACE DIRECTION: LOWER pace number = FASTER. 5:00/mi is fast, 9:00/mi is slow. Running slower than prescribed easy pace is fine on recovery days.

INJURY HARD STOPS:
- If ANY active injury has severity >= 7: suggest rest day or cross-training ONLY. Do not prescribe any running workout.
- If ANY active injury has severity 5-6: suggest easy/recovery runs only. No tempo, intervals, long runs, or progression runs.
- If bone-related injury (shin, foot, hip, femur) at ANY severity: suggest rest or cross-training only until cleared by medical professional.

RULES:
1. ALL paces MUST come from the pace zones above. Do NOT invent or hardcode paces.
2. If no pace zones are available, describe the workout using RPE (1-10) and effort descriptions only.
3. If there are active injuries or recent injury warnings, modify the workout to avoid aggravating them. Explain the modification. Follow the INJURY HARD STOPS above — they override all other rules.
4. If the runner has had many hard sessions recently (3+ hard in 7 days) or no rest days in 5+ days, suggest easy/recovery.
5. If they've had several easy days in a row (3+ days since last hard session), they may be ready for quality work.
6. Consider the training phase: base = aerobic volume, build = introduce intensity, peak = race-specific, taper = reduce volume.
7. The workout should be appropriate for a ${tomorrowDay}.
8. Total distance should be consistent with their recent weekly average.

Respond with ONLY valid JSON (no markdown, no code fences) in this exact structure:
{
  "workout_type": "tempo" | "intervals" | "long_run" | "easy" | "recovery" | "progression" | "fartlek",
  "title": "Short descriptive title",
  "warmup": "Description with specific pace",
  "main_set": "Description with specific pace/paces",
  "cooldown": "Description with specific pace",
  "total_distance_miles": number,
  "estimated_duration_minutes": number,
  "target_paces": {"warmup": "X:XX", "main_set": "X:XX", "cooldown": "X:XX"},
  "intensity": "easy" | "moderate" | "moderate-hard" | "hard",
  "rationale": "Why this workout, referencing their current load and recent training",
  "alternative": "If legs are heavy: simpler alternative with pace"
}`;

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
        maxOutputTokens: 1500,
        temperature: 0.7,
        responseMimeType: "application/json",
        // @ts-ignore - disable thinking to get clean JSON output
        thinkingConfig: { thinkingBudget: 0 },
      },
    });

    console.log("Calling Gemini for adaptive workout...");
    const result = await model.generateContent(prompt);
    let rawText = result.response.text().trim();
    // Strip any markdown wrapping
    if (rawText.startsWith("```")) {
      rawText = rawText.replace(/^```json?\n?/, "").replace(/\n?```$/, "").trim();
    }

    // ── Parse AI response ──
    let workout: Record<string, unknown>;
    try {
      workout = JSON.parse(rawText);
    } catch {
      // Try extracting JSON from potential markdown wrapping
      const jsonMatch = rawText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        workout = JSON.parse(jsonMatch[0]);
      } else {
        console.error("Failed to parse AI response:", rawText.slice(0, 500));
        return new Response(
          JSON.stringify({ error: "Failed to parse workout suggestion" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ── Store in ai_insights ──
    const expiresAt = new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000).toISOString();
    const title = (workout.title as string) || "Suggested Workout";
    const summary = `${workout.workout_type}: ${workout.title} — ${workout.total_distance_miles}mi, ${workout.intensity}`;

    const { data: insightData, error: insertError } = await supabase
      .from("ai_insights")
      .insert({
        user_id,
        insight_type: "adaptive_workout",
        trigger_source: "adaptive_workout_designer",
        title,
        summary: summary.slice(0, 200),
        full_analysis: {
          workout,
          generated_for_date: tomorrowDate.toISOString().split("T")[0],
          context: {
            this_week_miles: Math.round(thisWeekMiles * 10) / 10,
            this_week_runs: thisWeekRuns,
            this_week_hard_sessions: thisWeekHardSessions,
            weekly_average: Math.round(weeklyAverage * 10) / 10,
            days_since_last_hard: daysSinceLastHard,
            days_since_rest: daysSinceRest,
            training_phase: trainingPhase,
            has_injuries: injuries.length > 0,
            has_pace_zones: !!paceZones,
          },
        },
        priority: "normal",
        expires_at: expiresAt,
      })
      .select("id")
      .single();

    if (insertError) {
      console.error(`Failed to store insight: ${insertError.message}`);
    } else {
      console.log(`Adaptive workout insight created: ${insightData?.id}`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        workout,
        insight_id: insightData?.id || null,
        generated_for: tomorrowDate.toISOString().split("T")[0],
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Adaptive workout error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

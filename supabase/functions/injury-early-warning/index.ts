/**
 * Injury Early Warning
 *
 * Analyzes multiple training signals to flag injury risk BEFORE it becomes
 * an injury. Looks at load spikes, intensity jumps, mood trends, pain
 * mentions, and existing injuries to compute a risk score (0-10).
 *
 * Only generates AI insight when risk_score >= 3. Runners train hard —
 * that's normal. We only flag patterns that are genuinely risky.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
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
  pace_segments: PaceSegment[] | null;
  mood: string | null;
  notes: string | null;
  cleaned_notes: string | null;
  workout_notes: string | null;
}

interface Injury {
  body_area: string;
  side: string | null;
  severity: number;
  notes: string | null;
  status: string;
}

interface RiskSignal {
  signal: string;
  level: "green" | "orange" | "red";
  detail: string;
  score_contribution: number;
}

// ============================================================================
// Constants
// ============================================================================

const HARD_EFFORTS = ["interval", "tempo", "threshold", "race_pace", "speed"];

const PAIN_KEYWORDS = [
  "hamstring", "calf", "shin", "knee", "achilles", "hip", "ankle",
  "foot", "plantar", "it band", "quad", "groin", "sore", "tight",
  "pain", "twinge", "niggle",
];

const NEGATIVE_MOODS = ["tired", "struggling"];

// ============================================================================
// Helpers
// ============================================================================

function daysAgo(n: number): string {
  return new Date(Date.now() - n * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function getHardMinutes(log: TrainingLog): number {
  if (!log.pace_segments) return 0;
  return log.pace_segments
    .filter(s => HARD_EFFORTS.includes(s.effort))
    .reduce((sum, s) => sum + (s.duration_seconds || 0) / 60, 0);
}

function isHardDay(log: TrainingLog): boolean {
  if (log.pace_segments?.some(s => HARD_EFFORTS.includes(s.effort))) return true;
  if (log.workout_type && ["interval", "tempo", "race"].includes(log.workout_type)) return true;
  return false;
}

function scanForPainMentions(text: string): string[] {
  const lower = text.toLowerCase();
  return PAIN_KEYWORDS.filter(kw => lower.includes(kw));
}

function splitIntoWeeks(logs: TrainingLog[], weeksBack: number): TrainingLog[][] {
  const weeks: TrainingLog[][] = [];
  const now = Date.now();
  for (let w = 0; w < weeksBack; w++) {
    const weekStart = now - (w + 1) * 7 * 24 * 60 * 60 * 1000;
    const weekEnd = now - w * 7 * 24 * 60 * 60 * 1000;
    weeks.push(
      logs.filter(l => {
        const t = new Date(l.workout_date).getTime();
        return t > weekStart && t <= weekEnd;
      })
    );
  }
  return weeks; // weeks[0] = most recent, weeks[3] = oldest
}

// ============================================================================
// Risk signal computation
// ============================================================================

function computeRiskSignals(
  logs: TrainingLog[],
  activeInjuries: Injury[],
): { signals: RiskSignal[]; riskScore: number } {
  const signals: RiskSignal[] = [];
  const weeks = splitIntoWeeks(logs, 4);

  // Weekly mileage
  const weekMiles = weeks.map(w =>
    w.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0)
  );
  const currentWeekMiles = weekMiles[0];
  const chronicWeeklyMiles = (weekMiles[0] + weekMiles[1] + weekMiles[2] + weekMiles[3]) / 4;

  // ── ACWR ──
  const acwr = chronicWeeklyMiles > 0 ? currentWeekMiles / chronicWeeklyMiles : 0;
  if (acwr > 1.5) {
    signals.push({
      signal: "ACWR",
      level: "red",
      detail: `Acute:Chronic ratio is ${acwr.toFixed(2)} — well above the 1.5 danger zone. ${currentWeekMiles.toFixed(1)} miles this week vs ${chronicWeeklyMiles.toFixed(1)} avg.`,
      score_contribution: 3,
    });
  } else if (acwr > 1.3) {
    signals.push({
      signal: "ACWR",
      level: "orange",
      detail: `Acute:Chronic ratio is ${acwr.toFixed(2)} — elevated above 1.3. ${currentWeekMiles.toFixed(1)} miles this week vs ${chronicWeeklyMiles.toFixed(1)} avg.`,
      score_contribution: 1.5,
    });
  }

  // ── Volume spike ──
  const previousWeekMiles = weekMiles[1];
  if (previousWeekMiles > 0) {
    const volumeJump = (currentWeekMiles - previousWeekMiles) / previousWeekMiles;
    if (volumeJump > 0.3) {
      const pct = Math.round(volumeJump * 100);
      signals.push({
        signal: "volume_spike",
        level: pct > 50 ? "red" : "orange",
        detail: `Mileage jumped ${pct}% week-over-week (${previousWeekMiles.toFixed(1)} → ${currentWeekMiles.toFixed(1)} miles).`,
        score_contribution: pct > 50 ? 2.5 : 1.5,
      });
    }
  }

  // ── Intensity spike ──
  const currentWeekHardMin = weeks[0].reduce((s, l) => s + getHardMinutes(l), 0);
  const previousWeekHardMin = weeks[1].reduce((s, l) => s + getHardMinutes(l), 0);
  if (previousWeekHardMin > 0) {
    const intensityJump = (currentWeekHardMin - previousWeekHardMin) / previousWeekHardMin;
    if (intensityJump > 0.5) {
      const pct = Math.round(intensityJump * 100);
      signals.push({
        signal: "intensity_spike",
        level: pct > 100 ? "red" : "orange",
        detail: `Hard minutes jumped ${pct}% week-over-week (${previousWeekHardMin.toFixed(0)} → ${currentWeekHardMin.toFixed(0)} min). Intensity can spike even when mileage looks flat.`,
        score_contribution: pct > 100 ? 2.5 : 1.5,
      });
    }
  } else if (currentWeekHardMin > 20) {
    // Going from zero hard minutes to a meaningful amount
    signals.push({
      signal: "intensity_spike",
      level: "orange",
      detail: `${currentWeekHardMin.toFixed(0)} hard minutes this week after no hard sessions last week.`,
      score_contribution: 1.5,
    });
  }

  // ── Back-to-back hard days ──
  const last14 = logs
    .filter(l => new Date(l.workout_date).getTime() > Date.now() - 14 * 24 * 60 * 60 * 1000)
    .sort((a, b) => a.workout_date.localeCompare(b.workout_date));

  let maxConsecutiveHard = 0;
  let currentStreak = 0;
  let prevDate: string | null = null;

  for (const log of last14) {
    if (!isHardDay(log)) {
      currentStreak = 0;
      prevDate = null;
      continue;
    }
    if (prevDate) {
      const daysBetween = Math.round(
        (new Date(log.workout_date).getTime() - new Date(prevDate).getTime()) / (24 * 60 * 60 * 1000)
      );
      if (daysBetween <= 1) {
        currentStreak++;
      } else {
        currentStreak = 1;
      }
    } else {
      currentStreak = 1;
    }
    maxConsecutiveHard = Math.max(maxConsecutiveHard, currentStreak);
    prevDate = log.workout_date;
  }

  if (maxConsecutiveHard >= 3) {
    signals.push({
      signal: "back_to_back_hard",
      level: "red",
      detail: `${maxConsecutiveHard} consecutive hard days. Bodies need easy days between hard efforts to absorb the training.`,
      score_contribution: 2.5,
    });
  } else if (maxConsecutiveHard >= 2) {
    signals.push({
      signal: "back_to_back_hard",
      level: "orange",
      detail: `2 consecutive hard days detected. An easy day between hard sessions helps absorb the training.`,
      score_contribution: 1,
    });
  }

  // ── Mood decline ──
  const last7dLogs = logs.filter(
    l => new Date(l.workout_date).getTime() > Date.now() - 7 * 24 * 60 * 60 * 1000
  );
  const negativeMoodCount = last7dLogs.filter(
    l => l.mood && NEGATIVE_MOODS.includes(l.mood.toLowerCase())
  ).length;

  if (negativeMoodCount >= 3) {
    signals.push({
      signal: "mood_decline",
      level: "orange",
      detail: `${negativeMoodCount} "tired" or "struggling" moods in the last 7 days. Cumulative fatigue often shows in mood before it shows in pace.`,
      score_contribution: 1.5,
    });
  }

  // ── Pain mentions ──
  const allPainMentions: { date: string; keywords: string[] }[] = [];
  for (const log of last7dLogs) {
    const textToScan = [log.cleaned_notes, log.workout_notes].filter(Boolean).join(" ");
    if (!textToScan) continue;
    const found = scanForPainMentions(textToScan);
    if (found.length > 0) {
      allPainMentions.push({ date: log.workout_date, keywords: found });
    }
  }

  if (allPainMentions.length > 0) {
    const allKeywords = [...new Set(allPainMentions.flatMap(p => p.keywords))];
    const mentionCount = allPainMentions.length;
    signals.push({
      signal: "pain_mentions",
      level: mentionCount >= 3 ? "red" : "orange",
      detail: `Pain/discomfort mentioned in ${mentionCount} of the last 7 days' notes: ${allKeywords.join(", ")}.`,
      score_contribution: mentionCount >= 3 ? 2.5 : 1.5,
    });
  }

  // ── Active injuries with high load ──
  // severity >= 5 with high load (ACWR > 1.3) OR severity >= 6 standalone → medical evaluation
  const highLoadInjuries = activeInjuries.filter(i => i.severity >= 5 && acwr > 1.3);
  const standaloneInjuries = activeInjuries.filter(i => i.severity >= 6 && !(i.severity >= 5 && acwr > 1.3));
  const flaggedInjuries = [...highLoadInjuries, ...standaloneInjuries];

  // Also flag bone-related injuries at ANY severity
  const BONE_AREAS = ["shin", "foot", "hip", "metatarsal", "tibia", "fibula", "femur", "heel", "navicular"];
  const boneInjuries = activeInjuries.filter(
    i => BONE_AREAS.some(b => i.body_area.toLowerCase().includes(b)) && !flaggedInjuries.includes(i)
  );
  const allFlaggedInjuries = [...flaggedInjuries, ...boneInjuries];

  if (allFlaggedInjuries.length > 0 && currentWeekMiles > 0) {
    const injuryList = allFlaggedInjuries
      .map(i => `${i.body_area}${i.side ? ` (${i.side})` : ""} severity ${i.severity}/10`)
      .join(", ");
    const isHighRisk = allFlaggedInjuries.some(i => i.severity >= 6) || boneInjuries.length > 0;
    signals.push({
      signal: "active_injury_load",
      level: isHighRisk ? "red" : "orange",
      detail: `Running on active injury: ${injuryList}. ${boneInjuries.length > 0 ? "Bone-related pain needs medical evaluation — stress fractures start as mild pain. " : ""}Training through moderate-to-severe injuries increases re-injury risk. Recommend medical evaluation.`,
      score_contribution: isHighRisk ? 2.5 : 1.5,
    });
  }

  // ── Compute total risk score (capped at 10) ──
  const rawScore = signals.reduce((sum, s) => sum + s.score_contribution, 0);
  const riskScore = Math.min(10, Math.round(rawScore * 10) / 10);

  return { signals, riskScore };
}

// ============================================================================
// Main handler
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id: bodyUserId } = await req.json();

    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId: user_id, isServiceRole } = auth;

    const rlBlocked = await enforceFeatureRateLimit(user_id, "injury_analysis", corsHeaders, { isServiceRole });
    if (rlBlocked) return rlBlocked;

    console.log(`Injury early warning check for user ${user_id}`);

    // ── Athlete state ──
    const athleteState = await getOrBuildAthleteState(supabase, user_id);
    const athleteContext = stateToPromptContext(athleteState);

    // ── Parallel data fetch ──
    const twentyEightDaysAgo = daysAgo(28);

    const [logsResult, injuriesResult, snapshotResult, profileResult] = await Promise.all([
      supabase
        .from("training_logs")
        .select("id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, pace_segments, mood, notes, cleaned_notes, workout_notes")
        .eq("user_id", user_id)
        .gte("workout_date", twentyEightDaysAgo)
        .order("workout_date", { ascending: false })
        .limit(100),

      supabase
        .from("injuries")
        .select("body_area, side, severity, notes, status")
        .eq("user_id", user_id)
        .eq("status", "active"),

      supabase
        .from("fitness_snapshots")
        .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds")
        .eq("user_id", user_id)
        .order("created_at", { ascending: false })
        .limit(1),

      supabase
        .from("athlete_profiles")
        .select("profile_data")
        .eq("user_id", user_id)
        .single(),
    ]);

    const logs = (logsResult.data || []) as TrainingLog[];
    const activeInjuries = (injuriesResult.data || []) as Injury[];
    const snapshot = snapshotResult.data?.[0] || null;
    const athleteProfile = profileResult.data?.profile_data || null;

    if (logs.length < 3) {
      console.log("Not enough training data for injury warning analysis");
      return new Response(
        JSON.stringify({ skipped: true, reason: "Insufficient training data (need at least 3 logs in 28 days)" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Compute risk signals ──
    const { signals, riskScore } = computeRiskSignals(logs, activeInjuries);

    console.log(`Risk score: ${riskScore}, signals: ${signals.length}`);

    // ── Exit early if risk is low ──
    if (riskScore < 3) {
      console.log("Risk score below threshold, no warning needed");
      return new Response(
        JSON.stringify({
          risk_score: riskScore,
          signals: signals.map(s => ({ signal: s.signal, level: s.level })),
          warning_generated: false,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── Build AI prompt ──
    const signalSummary = signals
      .map(s => `[${s.level.toUpperCase()}] ${s.signal}: ${s.detail}`)
      .join("\n");

    const weekMiles = splitIntoWeeks(logs, 4).map(w =>
      w.reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0)
    );

    let contextBlock = `TRAINING LOAD (last 4 weeks, most recent first):
Week 1: ${weekMiles[0].toFixed(1)} miles
Week 2: ${weekMiles[1].toFixed(1)} miles
Week 3: ${weekMiles[2].toFixed(1)} miles
Week 4: ${weekMiles[3].toFixed(1)} miles`;

    if (activeInjuries.length > 0) {
      contextBlock += `\n\nACTIVE INJURIES: ${activeInjuries.map(i => `${i.body_area}${i.side ? ` (${i.side})` : ""} — severity ${i.severity}/10${i.notes ? `: ${i.notes}` : ""}`).join("; ")}`;
    }

    if (athleteProfile) {
      const p = athleteProfile;
      const profileBits: string[] = [];
      if (p.weekly_mileage) profileBits.push(`typical weekly mileage: ${p.weekly_mileage}`);
      if (p.experience_level) profileBits.push(`experience: ${p.experience_level}`);
      if (p.injury_history) profileBits.push(`injury history: ${p.injury_history}`);
      if (profileBits.length > 0) {
        contextBlock += `\n\nATHLETE CONTEXT: ${profileBits.join(", ")}`;
      }
    }

    const prompt = loadPrompt("injury-early-warning.v1", {
      riskScore,
      signalSummary,
      contextBlock,
      athleteContextBlock: athleteContext ? `\nATHLETE STATE:\n${athleteContext}` : "",
    });

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
        maxOutputTokens: 800,
        temperature: 0.8,
      },
    });

    const result = await model.generateContent(prompt);
    const analysis = result.response.text().trim();

    // ── Determine priority ──
    const priority = riskScore >= 6 ? "high" : "normal";

    // ── Build title ──
    const topSignal = signals.sort((a, b) => b.score_contribution - a.score_contribution)[0];
    const titleMap: Record<string, string> = {
      ACWR: "Training load spike detected",
      volume_spike: "Mileage jump flagged",
      intensity_spike: "Intensity spike detected",
      back_to_back_hard: "Back-to-back hard days",
      mood_decline: "Fatigue pattern noticed",
      pain_mentions: "Pain signals in training notes",
      active_injury_load: "Training on active injury",
    };
    const title = titleMap[topSignal?.signal] || "Injury risk check";

    // ── Store insight ──
    const summary = analysis.split(".").slice(0, 2).join(".") + ".";

    const { error: insertError } = await supabase
      .from("ai_insights")
      .insert({
        user_id,
        insight_type: "injury_warning",
        trigger_source: "post_run_check",
        title,
        summary: summary.slice(0, 200),
        full_analysis: {
          analysis,
          risk_score: riskScore,
          signals: signals.map(s => ({
            signal: s.signal,
            level: s.level,
            detail: s.detail,
          })),
          weekly_mileage: weekMiles,
          active_injuries: activeInjuries.length,
        },
        priority,
        expires_at: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
      });

    if (insertError) {
      console.error(`Failed to store injury warning: ${insertError.message}`);
    } else {
      console.log(`Injury warning created: risk=${riskScore}, priority=${priority}`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        risk_score: riskScore,
        priority,
        signals: signals.map(s => ({ signal: s.signal, level: s.level })),
        warning_generated: true,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Injury early warning error:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

/**
 * Build Athlete Profile
 *
 * Aggregates up to 5 years of training history into a comprehensive,
 * recency-weighted athlete profile. The profile is cached in the
 * athlete_profiles table and rebuilt at most once per 24 hours.
 *
 * Usage:
 *   POST /build-athlete-profile
 *   Body: { "force_rebuild": false }  // optional, forces cache bypass
 *
 * Returns: { profile: AthleteProfile, cached: boolean }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import {
  buildAthleteProfile,
  buildAthleteProfileContext,
  type AthleteProfile,
} from "../_shared/athleteProfile.ts";
import { rebuildAthleteState } from "../_shared/athlete-state.ts";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    // Auth
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    // Parse request
    let forceRebuild = false;
    try {
      const body = await req.json();
      forceRebuild = body.force_rebuild === true;
    } catch {
      // No body or invalid JSON — use defaults
    }

    // Supabase admin client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── Check cache ──
    if (!forceRebuild) {
      const { data: cached } = await supabase
        .from("athlete_profiles")
        .select("profile_data, updated_at")
        .eq("user_id", userId)
        .single();

      if (cached) {
        const updatedAt = new Date(cached.updated_at);
        const hoursSinceUpdate = (Date.now() - updatedAt.getTime()) / (1000 * 60 * 60);

        if (hoursSinceUpdate < 24) {
          console.log(`Returning cached profile for ${userId} (${hoursSinceUpdate.toFixed(1)}h old)`);
          return new Response(
            JSON.stringify({
              profile: cached.profile_data,
              cached: true,
              processing_time: Date.now() - startTime,
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }
    }

    // ── Fetch all historical data (up to 5 years) ──
    const fiveYearsAgo = new Date();
    fiveYearsAgo.setFullYear(fiveYearsAgo.getFullYear() - 5);
    const fiveYearsAgoStr = fiveYearsAgo.toISOString();

    console.log(`Building athlete profile for ${userId} (fetching up to 5 years of data)`);

    const [
      logsResult,
      injuriesResult,
      snapshotsResult,
      formChecksResult,
      biomechanicsResult,
      goalsResult,
      plansResult,
    ] = await Promise.all([
      // Training logs — all historical data
      supabase
        .from("training_logs")
        .select("id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, mood, cleaned_notes, notes, coach_insight, workout_type")
        .eq("user_id", userId)
        .or(`workout_date.gte.${fiveYearsAgoStr},and(workout_date.is.null,created_at.gte.${fiveYearsAgoStr})`)
        .order("workout_date", { ascending: false, nullsFirst: false })
        .limit(2000), // ~5 years of daily training

      // All injuries
      supabase
        .from("injuries")
        .select("id, body_area, side, severity, status, onset_date, resolved_date, created_at, notes")
        .eq("user_id", userId)
        .order("created_at", { ascending: false }),

      // Fitness snapshots
      supabase
        .from("fitness_snapshots")
        .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds, confidence, created_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(50),

      // Form checks
      supabase
        .from("form_checks")
        .select("ai_analysis, ai_findings, created_at")
        .eq("user_id", userId)
        .eq("status", "completed")
        .order("created_at", { ascending: false })
        .limit(20),

      // Biomechanics analyses
      supabase
        .from("biomechanics_analyses")
        .select("overall_score, ai_analysis, created_at")
        .eq("user_id", userId)
        .eq("status", "completed")
        .order("created_at", { ascending: false })
        .limit(20),

      // Goals (all time)
      supabase
        .from("user_goals")
        .select("goal_title, target_date, status, created_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false }),

      // Training plans (all time)
      supabase
        .from("training_plans")
        .select("name, target_race_distance, target_time_seconds, start_date, end_date, status")
        .eq("user_id", userId)
        .order("created_at", { ascending: false }),
    ]);

    const logs = logsResult.data || [];
    const injuries = injuriesResult.data || [];
    const snapshots = snapshotsResult.data || [];
    const formChecks = formChecksResult.data || [];
    const biomechanicsData = biomechanicsResult.data || [];
    const goalsData = goalsResult.data || [];
    const plansData = plansResult.data || [];

    console.log(`Data fetched: ${logs.length} logs, ${injuries.length} injuries, ${snapshots.length} snapshots, ${formChecks.length} form checks, ${biomechanicsData.length} biomechanics, ${goalsData.length} goals, ${plansData.length} plans`);

    // ── Build profile ──
    const profile = buildAthleteProfile({
      logs,
      injuries,
      fitnessSnapshots: snapshots,
      formChecks,
      biomechanics: biomechanicsData,
      goals: goalsData,
      plans: plansData,
    });

    // ── Cache the profile ──
    await supabase
      .from("athlete_profiles")
      .upsert(
        {
          user_id: userId,
          profile_data: profile,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      );

    // ── Also rebuild the Dynamic Context Object (athlete_state) ──
    // This is the real-time state that all AI functions read from.
    const athleteState = await rebuildAthleteState(supabase, userId);
    console.log(`Profile + athlete state built for ${userId} in ${Date.now() - startTime}ms`);

    return new Response(
      JSON.stringify({
        profile,
        athlete_state: athleteState,
        cached: false,
        processing_time: Date.now() - startTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error building athlete profile:", error);
    return new Response(
      JSON.stringify({ error: "Failed to build athlete profile" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

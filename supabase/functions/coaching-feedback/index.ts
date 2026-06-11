/**
 * Coaching Feedback Edge Function
 *
 * Handles:
 * - POST /feedback — store thumbs up/down on a coaching message
 * - POST /adjustment — record a coaching adjustment to track
 * - POST /outcome — record a goal outcome (predicted vs actual)
 * - GET /negative — get recent negative feedback for prompt injection
 * - GET /pending — get unresolved coaching adjustments
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userId = user.id;
    const url = new URL(req.url);
    const path = url.pathname.split("/").pop();

    // ========================================================================
    // POST /feedback — Store thumbs up/down
    // ========================================================================
    if (req.method === "POST" && path === "feedback") {
      const body = await req.json();
      const { conversationId, messageId, rating, feedbackText, messageContent, queryComplexity, modelUsed } = body;

      if (!conversationId || ![-1, 1].includes(rating)) {
        return new Response(
          JSON.stringify({ error: "conversationId and rating (-1 or 1) required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data, error } = await supabase.from("coaching_feedback").insert({
        user_id: userId,
        conversation_id: conversationId,
        message_id: messageId || null,
        rating,
        feedback_text: feedbackText || null,
        message_content: messageContent ? messageContent.slice(0, 2000) : null,
        query_complexity: queryComplexity || null,
        model_used: modelUsed || null,
      }).select("id").single();

      if (error) {
        console.error("Error storing feedback:", error);
        return new Response(
          JSON.stringify({ error: "Failed to store feedback" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ success: true, id: data.id }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========================================================================
    // POST /adjustment — Record a coaching adjustment to track
    // ========================================================================
    if (req.method === "POST" && path === "adjustment") {
      const body = await req.json();
      const { weekStart, adjustmentType, targetWorkout, recommendation, source, sourceReferenceId } = body;

      if (!weekStart || !adjustmentType || !recommendation) {
        return new Response(
          JSON.stringify({ error: "weekStart, adjustmentType, and recommendation required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data, error } = await supabase.from("coaching_adjustments").insert({
        user_id: userId,
        week_start: weekStart,
        adjustment_type: adjustmentType,
        target_workout: targetWorkout || null,
        recommendation,
        source: source || "conversation",
        source_reference_id: sourceReferenceId || null,
      }).select("id").single();

      if (error) {
        console.error("Error storing adjustment:", error);
        return new Response(
          JSON.stringify({ error: "Failed to store adjustment" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ success: true, id: data.id }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========================================================================
    // POST /resolve — Mark an adjustment as followed/not followed with outcome
    // ========================================================================
    if (req.method === "POST" && path === "resolve") {
      const body = await req.json();
      const { adjustmentId, followed, outcomeNotes, outcomeMetrics } = body;

      if (!adjustmentId || followed === undefined) {
        return new Response(
          JSON.stringify({ error: "adjustmentId and followed (boolean) required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { error } = await supabase.from("coaching_adjustments").update({
        followed,
        outcome_notes: outcomeNotes || null,
        outcome_metrics: outcomeMetrics || null,
        resolved_at: new Date().toISOString(),
      }).eq("id", adjustmentId).eq("user_id", userId);

      if (error) {
        console.error("Error resolving adjustment:", error);
        return new Response(
          JSON.stringify({ error: "Failed to resolve adjustment" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ success: true }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========================================================================
    // POST /outcome — Record predicted vs actual race result
    // ========================================================================
    if (req.method === "POST" && path === "outcome") {
      const body = await req.json();
      const { goalId, raceDistance, predictedTimeSeconds, actualTimeSeconds, raceConditions, athleteNotes, predictionSource } = body;

      if (!raceDistance || !actualTimeSeconds) {
        return new Response(
          JSON.stringify({ error: "raceDistance and actualTimeSeconds required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data, error } = await supabase.from("goal_outcomes").insert({
        user_id: userId,
        goal_id: goalId || null,
        race_distance: raceDistance,
        predicted_time_seconds: predictedTimeSeconds || null,
        actual_time_seconds: actualTimeSeconds,
        race_conditions: raceConditions || null,
        athlete_notes: athleteNotes || null,
        prediction_source: predictionSource || "fitness_predictor",
      }).select("id, delta_seconds, delta_percentage").single();

      if (error) {
        console.error("Error storing outcome:", error);
        return new Response(
          JSON.stringify({ error: "Failed to store outcome" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ success: true, ...data }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========================================================================
    // GET /negative — Get recent negative feedback for prompt context
    // ========================================================================
    if (req.method === "GET" && path === "negative") {
      const { data, error } = await supabase.rpc("get_negative_feedback", {
        p_user_id: userId,
        p_limit: 5,
      });

      if (error) {
        console.error("Error fetching negative feedback:", error);
        return new Response(
          JSON.stringify({ error: "Failed to fetch feedback" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ feedback: data || [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ========================================================================
    // GET /pending — Get unresolved coaching adjustments
    // ========================================================================
    if (req.method === "GET" && path === "pending") {
      const { data, error } = await supabase.rpc("get_pending_adjustments", {
        p_user_id: userId,
      });

      if (error) {
        console.error("Error fetching pending adjustments:", error);
        return new Response(
          JSON.stringify({ error: "Failed to fetch adjustments" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ adjustments: data || [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Unknown endpoint. Use: feedback, adjustment, resolve, outcome, negative, pending" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error("Unexpected error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

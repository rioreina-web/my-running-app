/**
 * Process Check-In Voice Memo (v2 — optimized)
 *
 * Handles non-workout check-ins: fatigue, soreness, motivation, recovery.
 *
 * Optimizations over v1:
 *   1. Single Gemini call for transcription + analysis (was 2 serial calls)
 *   2. (RETIRED 2026-08-31) the 2.0-flash "for speed" swap — that model id
 *      errors now, and it failed every spoken check-in silently. Back on
 *      gemini-2.5-flash, in step with process-training-memo.
 *   3. Parallelized DB reads (mark-processing + fetch-user + fetch-context)
 *
 * Returns: mood, readiness, recommendation, plan_action, cleaned_notes
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { updateAthleteState } from "../_shared/athlete-state.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
import { requireServiceRole } from "../_shared/auth.ts";

/** The bearer token off the Authorization header, or "" when absent. */
function bearerToken(req: Request): string {
  const h = req.headers.get("Authorization") ?? "";
  return h.startsWith("Bearer ") ? h.slice("Bearer ".length).trim() : "";
}

/**
 * Service-role detection by CLAIM rather than string equality — see the call
 * site. Mirrors the helper in compute-workout-features / coaching-daily-read.
 */
function isServiceRoleJWT(token: string): boolean {
  try {
    if (!token) return false;
    const seg = token.split(".")[1];
    if (!seg) return false;
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/")
      .padEnd(Math.ceil(seg.length / 4) * 4, "=");
    const payload = JSON.parse(atob(b64)) as { role?: string; exp?: number };
    if (payload.role !== "service_role") return false;
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

const hardTypes = new Set(["tempo", "intervals", "long_run", "race", "progression"]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Claim-decode first, exact-match second (2026-08-31). The Vault copy of
    // the service key no longer string-equals this function's env copy, so
    // `requireServiceRole`'s timing-safe compare 401s every vault-keyed
    // dispatch — the same drift that hit parse-workout-structure,
    // compute-workout-features and coaching-daily-read. Safe because
    // verify_jwt is on: the gateway checked the signature before we see the
    // token. Without this a spoken check-in cannot be re-processed at all.
    const authBlocked = isServiceRoleJWT(bearerToken(req))
      ? null
      : requireServiceRole(req, corsHeaders);
    if (authBlocked) return authBlocked;

    const { record } = await req.json();
    if (!record?.id || !record?.audio_url) {
      return errorResponse("record.id and record.audio_url required", 400);
    }

    const today = new Date().toISOString().split("T")[0];

    // ── Step 1: Mark as processing + fetch user_id in parallel ────────
    const [, userRes] = await Promise.all([
      supabase
        .from("training_logs")
        .update({ processing_status: "processing" })
        .eq("id", record.id),
      supabase
        .from("training_logs")
        .select("user_id, mood")
        .eq("id", record.id)
        .single(),
    ]);
    const userId = userRes.data?.user_id;
    if (!userId) {
      return errorResponse(`training_log ${record.id} has no user_id`, 404);
    }
    // A mood already ON the row wins over extraction (2026-08-31). The Read
    // tab's check-in radio writes the athlete's own rating at insert time —
    // a tapped "tired" must not be replaced by the model's read of the
    // recording, and never by the "neutral" fallback below. Same rule as
    // process-training-memo.
    const declaredMood = (userRes.data?.mood as string | null) ?? null;

    // ── Step 2: Fetch context + download audio in parallel ────────────
    const audioUrl = new URL(record.audio_url);
    const bucketPrefix = "/storage/v1/object/public/training-memos/";
    const pathIndex = audioUrl.pathname.indexOf(bucketPrefix);
    const storagePath = pathIndex !== -1
      ? decodeURIComponent(audioUrl.pathname.slice(pathIndex + bucketPrefix.length))
      : audioUrl.pathname.split("/").pop();

    const [recentLogsRes, planRes, audioDownload] = await Promise.all([
      supabase
        .from("training_logs")
        .select("workout_date, workout_distance_miles, workout_type, mood, cleaned_notes")
        .eq("user_id", userId)
        .not("cleaned_notes", "is", null)
        .order("workout_date", { ascending: false })
        .limit(7),
      supabase
        .from("training_plans")
        .select("id")
        .eq("user_id", userId)
        .eq("status", "active")
        .limit(1)
        .maybeSingle(),
      supabase.storage.from("training-memos").download(storagePath!),
    ]);

    if (audioDownload.error) {
      throw new Error(`Failed to download audio: ${audioDownload.error.message}`);
    }

    // Fetch scheduled workouts (depends on planId)
    const planId = planRes.data?.id;
    const scheduledRes = planId
      ? await supabase
          .from("scheduled_workouts")
          .select("id, date, workout_type, workout_data, status")
          .eq("plan_id", planId)
          .gte("date", today)
          .eq("status", "scheduled")
          .order("date", { ascending: true })
          .limit(5)
      : { data: [] };

    const injuriesRes = await supabase
      .from("injuries")
      .select("body_area, severity, status")
      .eq("user_id", userId)
      .in("status", ["active", "monitoring"])
      .limit(5);

    // ── Step 3: Build context strings ─────────────────────────────────
    let recentContext = "";
    if (recentLogsRes.data?.length) {
      recentContext = "\n\nRECENT TRAINING (last 7 sessions):\n";
      for (const log of recentLogsRes.data) {
        const date = log.workout_date ? String(log.workout_date).split("T")[0] : "?";
        const dist = log.workout_distance_miles ? `${Number(log.workout_distance_miles).toFixed(1)}mi` : "";
        const type = log.workout_type || "";
        const mood = log.mood ? `[${log.mood}]` : "";
        recentContext += `- ${date}: ${type} ${dist} ${mood} — ${(log.cleaned_notes || "").slice(0, 80)}\n`;
      }
    }

    const todayWorkout = scheduledRes.data?.find((w: any) => w.date === today);
    const todayIsHard = todayWorkout && hardTypes.has(todayWorkout.workout_type);
    const todayWorkoutName = todayWorkout?.workout_data?.name || todayWorkout?.workout_type || null;
    const todayWorkoutId = todayWorkout?.id || null;

    let upcomingContext = "";
    if (scheduledRes.data?.length) {
      upcomingContext = "\n\nUPCOMING SCHEDULE:\n";
      for (const w of scheduledRes.data as any[]) {
        const name = w.workout_data?.name || w.workout_type;
        const isToday = w.date === today;
        upcomingContext += `- ${w.date}${isToday ? " (TODAY)" : ""}: ${name} [${w.workout_type}]\n`;
      }
    }

    let injuryContext = "";
    if (injuriesRes.data?.length) {
      injuryContext = "\n\nACTIVE INJURIES (be extra cautious with these areas):\n";
      for (const inj of injuriesRes.data) {
        injuryContext += `- ${inj.body_area} (${inj.status}, severity ${inj.severity}/10)\n`;
      }
    }

    let todayContext = "";
    if (todayWorkout) {
      todayContext = `\n\nTODAY'S PLANNED WORKOUT: ${todayWorkoutName} (${todayWorkout.workout_type})`;
      if (todayIsHard) {
        todayContext += "\nThis is a HARD session. If the athlete isn't ready, recommend a specific modification.";
      }
    }

    // ── Step 4: Single Gemini call — transcribe + analyze together ─────
    // This replaces two serial calls (Groq transcription → Gemini analysis)
    // with one multimodal Gemini call that does both at once.
    const audioArrayBuffer = await audioDownload.data.arrayBuffer();
    const fileName = storagePath!.split("/").pop() || "checkin.m4a";
    const mimeType = fileName.endsWith(".m4a") ? "audio/mp4" : "audio/mpeg";

    const uint8Array = new Uint8Array(audioArrayBuffer);
    let binary = "";
    const chunkSize = 8192;
    for (let i = 0; i < uint8Array.length; i += chunkSize) {
      const chunk = uint8Array.subarray(i, i + chunkSize);
      binary += String.fromCharCode(...chunk);
    }
    const base64Audio = btoa(binary);

    const model = genAI.getGenerativeModel({
      // gemini-2.5-flash, matching process-training-memo (2026-08-31). The
      // 2.0-flash id left here by the "speed" optimisation below now errors
      // outright: on 2026-08-31 a 9:44 voice memo transcribed fine through
      // the 2.5 memo path while a 10:40 voice CHECK-IN on the same account,
      // same minute, failed here — so every spoken check-in was landing as
      // `failed` with no transcript. Keep this id in step with the memo
      // path; they transcribe the same audio for the same athlete.
      model: "gemini-2.5-flash",
      generationConfig: {
        temperature: 0.4,
        // 4096, not 1500 (2026-08-31). 2.5-flash spends part of the output
        // budget on reasoning before it emits a token of answer, so the 1500
        // that sufficed for 2.0 truncated the JSON mid-string — the retry of
        // a real check-in died on "Unterminated string at position 214".
        // Transcript + analysis for a one-minute memo sits far under this.
        maxOutputTokens: 4096,
        responseMimeType: "application/json",
        // thinkingBudget 0 (2026-09-04): the reasoning the note above works
        // around is dynamic thinking, on by default for 2.5-flash — it cost
        // process-training-memo 10-13s per memo on the same model, and a
        // check-in is the same transcribe-and-extract task. Zeroing it is
        // what makes the 4096 ceiling comfortably sufficient rather than
        // merely usually sufficient. Cast: SDK has no thinkingConfig typing.
        thinkingConfig: { thinkingBudget: 0 },
      } as Record<string, unknown>,
    });

    const prompt = loadPrompt("process-check-in.v1", {
      recentContext,
      upcomingContext,
      todayContext,
      injuryContext,
    });

    const result = await model.generateContent([
      { text: prompt },
      { inlineData: { mimeType, data: base64Audio } },
    ]);
    const responseText = result.response.text();

    // Three strategies, matching process-training-memo's parseJsonResponse:
    // direct, fenced-code-block, then first-brace-to-last-brace. A check-in
    // that parses badly must not cost the athlete their recording.
    let analysis;
    try {
      analysis = JSON.parse(responseText);
    } catch {
      const cleaned = responseText.replace(/```json\s*/g, "").replace(/```/g, "").trim();
      try {
        analysis = JSON.parse(cleaned);
      } catch {
        const first = cleaned.indexOf("{");
        const last = cleaned.lastIndexOf("}");
        if (first === -1 || last <= first) {
          throw new Error(
            `Check-in analysis was not JSON (${responseText.length} chars): ` +
            responseText.slice(0, 120),
          );
        }
        analysis = JSON.parse(cleaned.substring(first, last + 1));
      }
    }

    const transcription = analysis.transcription || "";
    if (!transcription || transcription.length < 3) {
      throw new Error("Transcription failed — audio may be too short or unclear");
    }

    // ── Step 5: Save results ──────────────────────────────────────────
    const updatePayload: Record<string, unknown> = {
      cleaned_notes: analysis.cleaned_notes || "",
      // Athlete-declared mood wins over extraction — see declaredMood above.
      mood: declaredMood ?? (analysis.mood || "neutral"),
      coach_insight: analysis.recommendation || "",
      notes: transcription,
      processing_status: "completed",
      processing_error: null,
      extracted_data: {
        check_in: true,
        readiness_score: analysis.readiness_score,
        recommendation_type: analysis.recommendation_type,
        plan_action: analysis.plan_action || null,
        today_workout_id: todayWorkoutId,
        sleep_quality: analysis.sleep_quality,
        stress_level: analysis.stress_level,
        soreness_areas: analysis.soreness_areas,
        energy_level: analysis.energy_level,
      },
    };

    await supabase
      .from("training_logs")
      .update(updatePayload)
      .eq("id", record.id);

    // ── Step 5b: Update Athlete State (Dynamic Context Object) ────────
    // This is the central nervous system — other AI functions read this
    // instead of independently querying the same tables.
    if (userId) {
      await updateAthleteState(supabase, userId, {
        // Same preserve rule as the row update — the state must not carry a
        // model guess when the athlete rated themselves.
        last_mood: declaredMood ?? (analysis.mood || "neutral"),
        last_readiness_score: analysis.readiness_score ?? null,
        last_check_in_at: new Date().toISOString(),
        last_updated_by: "process-check-in",
      });
    }

    // ── Step 6: Auto-modify plan if readiness very low ────────────────
    let planModified = false;
    if (analysis.plan_action && todayWorkoutId && analysis.readiness_score <= 3) {
      const action = analysis.plan_action.action;
      if (action === "swap_to_easy" || action === "swap_to_recovery" || action === "skip") {
        const newType = action === "skip" ? "rest" : (analysis.plan_action.suggested_type || "easy");
        await supabase
          .from("scheduled_workouts")
          .update({
            workout_type: newType,
            workout_data: newType === "rest" ? null : { name: `${newType.charAt(0).toUpperCase() + newType.slice(1)} Run (modified from check-in)`, steps: [] },
            status: "modified",
            notes: `[Auto-modified] Readiness ${analysis.readiness_score}/10: ${analysis.plan_action.reason}`,
          })
          .eq("id", todayWorkoutId);
        planModified = true;
        console.log(`Auto-modified workout ${todayWorkoutId} to ${newType} (readiness ${analysis.readiness_score})`);
      }
    }

    // ── Step 7: Track soreness in injury system ───────────────────────
    if (analysis.soreness_areas?.length && userId) {
      // Fire all injury checks in parallel instead of sequential loop
      await Promise.all(analysis.soreness_areas.map(async (area: string) => {
        const { data: existing } = await supabase
          .from("injuries")
          .select("id")
          .eq("user_id", userId)
          .eq("body_area", area.toLowerCase())
          .in("status", ["active", "monitoring"])
          .limit(1);

        if (!existing?.length) {
          await supabase
            .from("injuries")
            .insert({
              user_id: userId,
              body_area: area.toLowerCase(),
              side: "unknown",
              severity: 2,
              status: "monitoring",
              source: "check_in",
              source_reference_id: record.id,
              source_text: `Check-in: ${analysis.cleaned_notes?.slice(0, 100) || "soreness reported"}`,
              first_reported_at: new Date().toISOString(),
            });
        }
      }));

      // ── Voice-to-Action: auto-trigger injury-early-warning ──
      // Soreness areas detected in a check-in → run injury risk assessment
      console.log(`[Voice-to-Action] Soreness detected (${analysis.soreness_areas.join(", ")}) — triggering injury-early-warning`);
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        await fetch(`${supabaseUrl}/functions/v1/injury-early-warning`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${serviceKey}`,
            apikey: serviceKey,
          },
          body: JSON.stringify({ user_id: userId }),
          signal: AbortSignal.timeout(15000),
        });
      } catch (warningError) {
        console.warn("[Voice-to-Action] Injury-early-warning failed (non-fatal):", warningError);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        id: record.id,
        // Mirror what was written — declared mood wins (see above).
        mood: declaredMood ?? analysis.mood,
        readiness_score: analysis.readiness_score,
        recommendation: analysis.recommendation,
        recommendation_type: analysis.recommendation_type,
        plan_action: analysis.plan_action || null,
        plan_modified: planModified,
        today_workout_id: todayWorkoutId,
        cleaned_notes: analysis.cleaned_notes,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Check-in processing error:", error);

    try {
      const { record } = await req.clone().json();
      if (record?.id) {
        await supabase
          .from("training_logs")
          .update({ processing_status: "failed", processing_error: String(error) })
          .eq("id", record.id);
      }
    } catch {}

    return errorResponse("Check-in processing failed: " + String(error), 500);
  }
});

function errorResponse(message: string, status: number): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

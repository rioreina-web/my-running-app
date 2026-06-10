/**
 * parse-workout-structure — Observer-layer AI pass.
 *
 * Takes raw per-second streams from a training_logs row and produces a structured
 * understanding: warmup / work_reps / recovery / cooldown, inferred pattern
 * (e.g. "8x800m @ 2:30"), equivalent race pace.
 *
 * POST body: { training_log_id: UUID }
 */
// NOTE(adaptive-plan-1.6): This function is a LOG PARSER (Observer layer), not
// a plan generator. Its output already uses M:SS pace strings — no
// pacePercentage in sight — so the Prompt 1.6 rewrite doesn't apply directly.
// If we later migrate the whole `parsed_structure` shape to integer
// seconds-per-mile for consistency with scheduled_workouts, do it in a
// dedicated follow-up, not as part of the plan-generation loop.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
interface Body {
  training_log_id: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  const rlBlocked = await enforceFeatureRateLimit(userId, "parse", corsHeaders);
  if (rlBlocked) return rlBlocked;

  try {
    const body = (await req.json()) as Body;
    if (!body?.training_log_id) {
      return json({ error: "training_log_id required" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1) Load the training_logs row — pull all 3 sources of truth:
    //    raw GPS streams, structured workout_notes, free-form voice memo / notes
    const { data: row, error: fetchErr } = await supabase
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, workout_duration_minutes, external_streams, notes, cleaned_notes, workout_notes, mood, source")
      .eq("id", body.training_log_id)
      .maybeSingle();

    if (fetchErr || !row) {
      return json({ error: fetchErr?.message ?? "training_log not found" }, 404);
    }

    // 2) Gather sources — at least one must exist
    const streamsBundle = row.external_streams as any;
    const streams = streamsBundle?.streams && typeof streamsBundle.streams === "object"
      ? streamsBundle.streams
      : null;
    const workoutNotes = (row.workout_notes as string | null)?.trim() || null;
    const voiceTranscript = (row.cleaned_notes as string | null)?.trim()
      ?? (row.notes as string | null)?.trim()
      ?? null;

    const haveStreams = streams !== null;
    const haveNotes = !!workoutNotes;
    const haveTranscript = !!voiceTranscript;

    if (!haveStreams && !haveNotes && !haveTranscript) {
      return json({ error: "no source data — workout has no streams, notes, or transcript" }, 422);
    }

    // Downsample streams when present (to ~180 points)
    const downsampled = haveStreams ? downsampleStreams(streams) : [];

    // 3) Prompt Gemini Flash
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) return json({ error: "GEMINI_API_KEY not set" }, 500);

    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        maxOutputTokens: 16000,
        temperature: 0.2,
        responseMimeType: "application/json",
        thinkingConfig: { thinkingBudget: 512 },
      },
    });

    const prompt = buildPrompt({
      distanceMiles: row.workout_distance_miles ?? 0,
      durationMinutes: row.workout_duration_minutes ?? 0,
      mood: (row.mood as string | null) ?? null,
      workoutNotes,
      voiceTranscript,
      timeline: downsampled,
      haveStreams,
    });

    const result = await model.generateContent(prompt);
    const text = result.response.text();

    let parsed: any;
    try {
      parsed = JSON.parse(text);
    } catch {
      return json({ error: "model returned invalid JSON", raw: text }, 502);
    }

    // 4) Validate minimum shape
    if (typeof parsed !== "object" || !parsed.type || !Array.isArray(parsed.blocks)) {
      return json({ error: "parsed output missing required fields", parsed }, 502);
    }

    parsed.parsed_at = new Date().toISOString();
    parsed.model = "gemini-2.5-flash";
    parsed.sources = [
      haveStreams ? "gps" : null,
      haveNotes ? "notes" : null,
      haveTranscript ? "voice_memo" : null,
    ].filter(Boolean);

    // 5) Write back
    const { error: updateErr } = await supabase
      .from("training_logs")
      .update({ parsed_structure: parsed })
      .eq("id", row.id);

    if (updateErr) {
      return json({ error: `update failed: ${updateErr.message}`, parsed }, 500);
    }

    return json({ ok: true, parsed }, 200);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("[parse-workout-structure]", msg);
    return json({ error: msg }, 500);
  }
});

// ── Helpers ──

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Downsample per-second streams to ~every 10s.
 * Returns a compact timeline: [{t, pace, hr, alt, dist, cad}, ...]
 */
function downsampleStreams(streams: Record<string, any>): Array<Record<string, number>> {
  const time = (streams.time as number[] | undefined) ?? [];
  const heartrate = (streams.heartrate as number[] | undefined) ?? [];
  const velocity = (streams.velocity_smooth as number[] | undefined) ?? [];
  const altitude = (streams.altitude as number[] | undefined) ?? [];
  const distance = (streams.distance as number[] | undefined) ?? [];
  const cadence = (streams.cadence as number[] | undefined) ?? [];

  const n = time.length || velocity.length || heartrate.length;
  if (n === 0) return [];

  const stride = Math.max(1, Math.floor(n / 180)); // cap at ~180 points
  const out: Array<Record<string, number>> = [];
  for (let i = 0; i < n; i += stride) {
    const speed = velocity[i];
    const paceSecPerMile = speed && speed > 0.2 ? Math.round(1609.34 / speed) : 0;
    out.push({
      t: time[i] ?? i,
      pace_s: paceSecPerMile,                       // 0 = stopped / invalid
      hr: Math.round(heartrate[i] ?? 0),
      alt: Math.round((altitude[i] ?? 0) * 10) / 10,
      dist_mi: distance[i] != null ? Math.round((distance[i] / 1609.34) * 100) / 100 : 0,
      cad: Math.round(cadence[i] ?? 0),
    });
  }
  return out;
}

function buildPrompt(input: {
  distanceMiles: number;
  durationMinutes: number;
  mood: string | null;
  workoutNotes: string | null;
  voiceTranscript: string | null;
  timeline: Array<Record<string, number>>;
  haveStreams: boolean;
}): string {
  const timelineStr = input.haveStreams
    ? input.timeline
        .map(
          (p) =>
            `${p.t}s d=${p.dist_mi}mi pace=${p.pace_s ? formatPace(p.pace_s) : "stopped"} hr=${p.hr || "-"}`
        )
        .join("\n")
    : "(no GPS stream available)";

  return loadPrompt("parse-workout-structure.v1", {
    distanceMiles: input.distanceMiles.toFixed(2),
    durationMinutes: input.durationMinutes.toFixed(1),
    moodLabel: input.mood ?? "(none)",
    workoutNotesBlock: input.workoutNotes ? `"${input.workoutNotes.slice(0, 1000)}"` : "(none)",
    voiceTranscriptBlock: input.voiceTranscript ? `"${input.voiceTranscript.slice(0, 2000)}"` : "(none)",
    timelineStr,
  });
}

function formatPace(secPerMile: number): string {
  const m = Math.floor(secPerMile / 60);
  const s = secPerMile % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

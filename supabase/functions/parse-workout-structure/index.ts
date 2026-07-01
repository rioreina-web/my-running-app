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
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { detectWorkBouts, boutsFromLaps, workBoutCount, formatWorkBouts, type WorkBout, type BoutOrRecovery, type LapInput } from "../_shared/shared/workBouts.ts";
import { isUserEdited } from "../_shared/structureOverride.ts";

import { corsHeaders } from "../_shared/cors.ts";
interface Body {
  training_log_id: string;
  /**
   * Required when called with the service-role key (server-to-server). The
   * app.settings/pg_net trigger path is unusable on Supabase (ALTER DATABASE
   * SET app.settings.* is permission-denied), so server flows — strava-sync on
   * every import, process-training-memo for voice-linked runs — invoke this
   * directly with the service role. See parse-workout-structure trigger notes.
   */
  user_id?: string;
  /**
   * Re-parse even when the athlete has hand-corrected the structure. Normally a
   * correction (`parsed_structure.edited_by_user === true`) is sacrosanct — a
   * Strava re-sync or a re-fire of this parser must never clobber it. The only
   * caller that sets force is the "restore auto-detected" path in
   * correct-workout-structure, where the athlete explicitly asked to discard
   * their edit and re-derive from the stream.
   */
  force?: boolean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body?.training_log_id) {
    return json({ error: "training_log_id required" }, 400);
  }

  // Accept a user JWT OR the service-role key (service callers must name user_id).
  const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
  if ("response" in auth) return auth.response;
  const { userId, isServiceRole } = auth;

  const rlBlocked = await enforceFeatureRateLimit(userId, "parse", corsHeaders, { isServiceRole });
  if (rlBlocked) return rlBlocked;

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1) Load the training_logs row — pull all 3 sources of truth:
    //    raw GPS streams, structured workout_notes, free-form voice memo / notes
    const { data: row, error: fetchErr } = await supabase
      .from("training_logs")
      .select("id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, external_streams, notes, cleaned_notes, workout_notes, mood, source, parsed_structure")
      .eq("id", body.training_log_id)
      .maybeSingle();

    if (fetchErr || !row) {
      return json({ error: fetchErr?.message ?? "training_log not found" }, 404);
    }

    // Ownership guard for user-JWT callers (IDOR). Service role may parse any row.
    if (!isServiceRole && (row as { user_id?: string }).user_id !== userId) {
      return json({ error: "not found" }, 404);
    }

    // A human correction is sacrosanct. If the athlete hand-edited this
    // workout's structure, never overwrite it — a Strava re-sync or a re-fire of
    // this parser must leave the correction intact. Only an explicit `force`
    // (the "restore auto-detected" path) re-derives from the stream.
    if (!body.force && isUserEdited(row.parsed_structure)) {
      return json({ ok: true, skipped: "user_edited", parsed: row.parsed_structure }, 200);
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

    // Recovery-segment the workout so the model gets pre-merged work bouts
    // (continuous efforts collapsed, reps split only on real recoveries) rather
    // than having to infer rep boundaries from a raw pace timeline.
    //
    // Prefer the athlete's OWN watch laps when they encode a real structure
    // (>= 2 recovery-bounded work bouts). A structured session records each rep
    // and recovery as its own lap — crisp distance + moving-time, no accel/decel
    // smear, no warmup jog merged into the first hard effort — so those
    // boundaries beat re-deriving them from the noisy per-second GPS trace. When
    // the laps DON'T encode a structure (steady run, or auto-lap-by-distance that
    // averages reps and recoveries together), they collapse to < 2 bouts and we
    // fall back to the GPS segmenter. See boutsFromLaps for the reliability gate.
    const rawLaps = Array.isArray(streamsBundle?.laps) ? (streamsBundle.laps as LapInput[]) : [];
    const lapBouts = rawLaps.length ? boutsFromLaps(rawLaps, streams ?? undefined).segments : [];
    const gpsBouts = haveStreams ? detectWorkBouts(streams).segments : [];
    const useLaps = workBoutCount(lapBouts) >= 2;
    const workBouts = useLaps ? lapBouts : gpsBouts;
    const geometrySource = useLaps ? "watch_laps" : gpsBouts.length ? "detectWorkBouts" : "model";
    const workBoutsBlock = formatWorkBouts(workBouts);

    // 3) Prompt Gemini Flash
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) return json({ error: "GEMINI_API_KEY not set" }, 500);

    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      // `thinkingConfig` is a valid Gemini 2.5 runtime field but is not yet
      // present in the @google/generative-ai 0.24.0 GenerationConfig typings,
      // so cast to satisfy the type checker without changing runtime behavior.
      generationConfig: {
        maxOutputTokens: 16000,
        temperature: 0.2,
        responseMimeType: "application/json",
        thinkingConfig: { thinkingBudget: 512 },
      } as Record<string, unknown>,
    });

    const prompt = buildPrompt({
      distanceMiles: row.workout_distance_miles ?? 0,
      durationMinutes: row.workout_duration_minutes ?? 0,
      mood: (row.mood as string | null) ?? null,
      workoutNotes,
      voiceTranscript,
      workBoutsBlock,
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

    // 4b) DETERMINISTIC GEOMETRY OVERRIDE.
    // The model is reliable for labels and intent, but NOT for numbers — it was
    // re-deriving per-rep distance/pace from the coarse ~10s timeline and
    // corrupting them (a measured 400m @ 4:30 came back as "500m @ 8:17"). The
    // work bouts from detectWorkBouts() are deterministic GPS truth, so use them
    // for the block geometry and the executed work totals. The model keeps only
    // the qualitative fields it's actually good at: type, intent_pattern, target
    // pace, rep labels, rest_format, subjective, equivalent_race_pace.
    if (workBouts.length) {
      parsed.blocks = blocksFromBouts(workBouts, streams);
      const work = workBouts.filter((s): s is WorkBout => s.kind === "work");
      const totalWorkM = work.reduce((a, b) => a + b.distance_m, 0);
      const totalWorkS = work.reduce((a, b) => a + b.duration_s, 0);
      parsed.work = parsed.work ?? {};
      parsed.work.reps = work.length;
      parsed.work.total_work_distance_mi = Math.round((totalWorkM / 1609.34) * 100) / 100;
      parsed.work.actual_pace_per_mile = totalWorkM > 0
        ? formatPace(Math.round(totalWorkS / (totalWorkM / 1609.34)))
        : (parsed.work.actual_pace_per_mile ?? null);
      // The model's execution_quality was judged against its own corrupted
      // paces; null it rather than assert a stale verdict. (A future pass can
      // recompute it from the deterministic actual-vs-target comparison.)
      if (parsed.work.execution_quality) parsed.work.execution_quality = null;
    }

    parsed.parsed_at = new Date().toISOString();
    parsed.model = "gemini-2.5-flash";
    parsed.geometry_source = geometrySource;
    parsed.sources = [
      haveStreams ? "gps" : null,
      workBouts.length ? "work_bouts" : null,
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
  workBoutsBlock: string;
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

  return loadPrompt("parse-workout-structure.v2", {
    distanceMiles: input.distanceMiles.toFixed(2),
    durationMinutes: input.durationMinutes.toFixed(1),
    moodLabel: input.mood ?? "(none)",
    workoutNotesBlock: input.workoutNotes ? `"${input.workoutNotes.slice(0, 1000)}"` : "(none)",
    voiceTranscriptBlock: input.voiceTranscript ? `"${input.voiceTranscript.slice(0, 2000)}"` : "(none)",
    workBoutsBlock: input.workBoutsBlock || "(no stream to segment)",
    timelineStr,
  });
}

function formatPace(secPerMile: number): string {
  const m = Math.floor(secPerMile / 60);
  const s = secPerMile % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * Build the canonical `blocks[]` straight from the deterministic work bouts —
 * one work_rep per bout, recoveries in between, in chronological order. Per-bout
 * HR is averaged from the raw heartrate stream over the bout's time window.
 * This is the geometry that gets stored, NOT the model's reconstruction.
 */
function blocksFromBouts(
  segments: BoutOrRecovery[],
  streams: Record<string, any> | null,
): Array<Record<string, unknown>> {
  const blocks: Array<Record<string, unknown>> = [];
  let lastEndS = 0;
  for (const s of segments) {
    if (s.kind === "work") {
      blocks.push({
        role: "work_rep",
        rep_num: s.index,
        distance_miles: Math.round((s.distance_m / 1609.34) * 100) / 100,
        duration_s: Math.round(s.duration_s),
        avg_pace_per_mile: s.avg_pace_per_mile,
        avg_hr: avgHrOverWindow(streams, s.start_s, s.end_s),
      });
      lastEndS = s.end_s;
    } else {
      // Recoveries carry no explicit window; reconstruct it from the previous
      // bout's end across the recovery's duration (segments are chronological).
      const startS = lastEndS;
      const endS = lastEndS + s.duration_s;
      // A recovery is its OWN segment with real distance + pace — a jog recovery
      // is easy running, not dead time. Keep its measured pace; only a standing
      // rest (no meaningful movement) gets "—". Never reduce a recovery to a
      // bare rest duration tacked onto the previous rep.
      const recMiles = s.distance_m / 1609.34;
      const isJog = s.style === "jog" && recMiles > 0.01 && s.duration_s > 0;
      blocks.push({
        role: "recovery",
        rep_num: null,
        distance_miles: Math.round(recMiles * 100) / 100,
        duration_s: Math.round(s.duration_s),
        avg_pace_per_mile: isJog ? formatPace(Math.round(s.duration_s / recMiles)) : "—",
        recovery_style: s.style, // "jog" | "standing"
        avg_hr: avgHrOverWindow(streams, startS, endS),
      });
      lastEndS = endS;
    }
  }
  return blocks;
}

function avgHrOverWindow(
  streams: Record<string, any> | null,
  startS: number,
  endS: number,
): number | null {
  if (!streams) return null;
  const time = (streams.time as number[] | undefined) ?? [];
  const hr = (streams.heartrate as number[] | undefined) ?? [];
  if (time.length === 0 || hr.length === 0) return null;
  let sum = 0, count = 0;
  const upTo = Math.min(time.length, hr.length);
  for (let i = 0; i < upTo; i++) {
    if (time[i] >= startS && time[i] <= endS && hr[i] > 0) {
      sum += hr[i];
      count++;
    }
  }
  return count > 0 ? Math.round(sum / count) : null;
}

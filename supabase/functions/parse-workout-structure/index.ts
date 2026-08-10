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
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { detectWorkBouts, boutsFromLaps, workBoutCount, formatWorkBouts, lapRoles, type WorkBout, type BoutOrRecovery, type LapInput } from "../_shared/shared/workBouts.ts";
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

/**
 * True when the token is a Supabase service-role JWT (by claim). Signature is
 * NOT checked here — the gateway already did that (verify_jwt = true, set for
 * this function in config.toml on 2026-08-10 precisely so this is safe).
 * Mirrors the helper in extract-rpe / drain-coach-insight-jobs /
 * drain-coachable-moment-jobs.
 *
 * DO NOT reuse this in a function whose verify_jwt is false — there the claim
 * would be unverified and anyone could mint `role: service_role` and parse any
 * athlete's workouts.
 */
function isServiceRoleJWT(token: string): boolean {
  try {
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

/**
 * Record WHY a parse failed onto its queue row.
 *
 * The dispatcher fires `net.http_post`, which is fire-and-forget — it cannot
 * see this function's response, so without this the only trace of a failure is
 * `attempts` climbing to 3 and the job sitting there mute. That is better than
 * today (where a failure leaves nothing at all) but still makes you guess.
 *
 * Best-effort by construction: a failure to write the bookkeeping must never
 * replace or mask the failure being reported.
 */
async function recordParseFailure(trainingLogId: string, message: string): Promise<void> {
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    await admin
      .from("workout_parse_jobs")
      .update({ last_error: message.slice(0, 500) })
      .eq("training_log_id", trainingLogId);
  } catch {
    // Swallowed deliberately — see above.
  }
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
  //
  // Service-role path decodes the role CLAIM rather than exact-matching
  // SUPABASE_SERVICE_ROLE_KEY. The Vault copy of the key — the one
  // dispatch_workout_parse sends — no longer string-equals this function's env
  // copy, even though both are validly signed, so the exact-match path in
  // requireAuthOrServiceRole 401s every dispatched job. Measured 2026-08-10:
  // 30 of 30 dispatches came back {"error":"Authentication required"} while the
  // cron itself reported success, because net.http_post cannot see the reply.
  // Same drift, and the same fix, as drain-* (2026-06-11) and extract-rpe
  // (2026-08-07).
  let userId: string;
  let isServiceRole: boolean;
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length).trim()
    : "";
  if (bearer && isServiceRoleJWT(bearer)) {
    if (!body.user_id) {
      return json({ error: "Service-role caller must specify user_id in body" }, 400);
    }
    userId = body.user_id;
    isServiceRole = true;
  } else {
    // User-JWT path (and its ownership check) unchanged.
    const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
    if ("response" in auth) return auth.response;
    ({ userId, isServiceRole } = auth);
  }

  const rlBlocked = await enforceFeatureRateLimit(userId, "parse", corsHeaders, { isServiceRole });
  if (rlBlocked) return rlBlocked;
  const monthlyCapped = await enforceMonthlyCap(userId, "parse", corsHeaders, { isServiceRole });
  if (monthlyCapped) return monthlyCapped;

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
      // Stamp before returning. Declining to re-parse IS a completed outcome,
      // so `dispatch_workout_parse` has to be able to retire this job — without
      // the stamp the row would be re-dispatched every 10 minutes until it
      // exhausted its three attempts, on every future stream write, forever.
      // Nothing about the athlete's structure changes here; only the "we have
      // considered this row as of now" marker moves.
      await supabase
        .from("training_logs")
        .update({ structure_parsed_at: new Date().toISOString() })
        .eq("id", row.id);
      return json({ ok: true, skipped: "user_edited", parsed: row.parsed_structure }, 200);
    }

    // 2) Gather sources — at least one must exist
    const streamsBundle = row.external_streams as any;
    const streams = streamsBundle?.streams && typeof streamsBundle.streams === "object"
      ? streamsBundle.streams
      : null;
    // Strip machine-generated boilerplate before the model sees it. strava-sync
    // writes "Distance: / Duration: / Pace: / Splits: 1mi @ 7:23, …" into
    // workout_notes — a RESTATEMENT of execution, already fully present in the
    // GPS timeline. The model reads those split paces and manufactures a
    // "[prescribed …]" from them. That text is never athlete intent, so remove
    // it; only genuinely athlete-typed lines survive.
    const workoutNotes = sanitizeAthleteNotes(row.workout_notes as string | null);
    const voiceTranscript = (row.cleaned_notes as string | null)?.trim()
      ?? (row.notes as string | null)?.trim()
      ?? null;

    const haveStreams = streams !== null;
    const haveNotes = !!workoutNotes;
    const haveTranscript = !!voiceTranscript;

    // A prescription can only come from the ATHLETE'S OWN words. For auto-synced
    // runs (strava/vital/healthkit) the `workout_notes` are machine-generated
    // ("Distance / Duration / Pace / Splits") — restating execution, never a
    // stated target. The model reads that text and manufactures a prescription
    // from it (e.g. an easy progression run became
    // "[prescribed 1mi @ 7:23, 1mi @ 7:00, …]", which are just the actual
    // splits). So intent is athlete-authored only when there is a voice
    // transcript, or the row itself is athlete-authored (voice_log/manual/check_in).
    const rowSource = (row.source as string | null) ?? "";
    const athleteAuthoredSource = ["voice_log", "manual", "check_in"].includes(rowSource);
    const haveAthleteIntent = haveTranscript || (haveNotes && athleteAuthoredSource);

    if (!haveStreams && !haveNotes && !haveTranscript) {
      await recordParseFailure(row.id as string, "no source data — no streams, notes, or transcript");
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
    const lapWork = workBoutCount(lapBouts);
    const gpsWork = workBoutCount(gpsBouts);
    // The athlete's watch laps ARE the workout: assemble the structure from them
    // whenever they yield a work bout. Consecutive same-effort laps are already
    // merged (three 1-mile tempo laps → one 3-mile bout; a rep flanked by jog
    // laps stays one rep), so a steady run auto-lapped by distance collapses to a
    // single bout rather than fake reps. We do NOT re-cut the run from the raw GPS
    // trace just because we can — that invents splits the athlete never ran.
    //
    // GPS segmentation is the FALLBACK, used only when:
    //   • there are no usable laps (a manual entry, or a device that recorded
    //     none), OR
    //   • the laps BLURRED a structured session — a watch auto-lapping by distance
    //     averages reps+recoveries into flat splits (collapsing to a single bout),
    //     while the GPS pass can still recover the real reps (>= 2 bouts). Then,
    //     and only then, GPS wins.
    const lapsBlurStructure = lapWork <= 1 && gpsWork >= 2;
    const useLaps = lapWork >= 1 && !lapsBlurStructure;
    const workBouts = useLaps ? lapBouts : gpsBouts;
    const geometrySource = useLaps ? "watch_laps" : gpsBouts.length ? "detectWorkBouts" : "model";
    const workBoutsBlock = formatWorkBouts(workBouts);

    // 3) Prompt Gemini Flash
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      await recordParseFailure(row.id as string, "GEMINI_API_KEY not set");
      return json({ error: "GEMINI_API_KEY not set" }, 500);
    }

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
      await recordParseFailure(row.id as string, "model returned invalid JSON");
      return json({ error: "model returned invalid JSON", raw: text }, 502);
    }

    // 4) Validate minimum shape
    if (typeof parsed !== "object" || !parsed.type || !Array.isArray(parsed.blocks)) {
      await recordParseFailure(row.id as string, "parsed output missing required fields");
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

    // 4c) DETERMINISTIC PRESCRIPTION GUARD.
    // The prompt forbids inventing a prescription, but the model still does it
    // when auto-sync notes restate the splits. Enforce in code: with no
    // athlete-authored intent there is NO prescription, so strip any
    // "[prescribed …]" the model appended and drop any target pace (a target can
    // only come from a stated prescription). See the "no AI hallucination" rule.
    if (!haveAthleteIntent) {
      if (typeof parsed.intent_pattern === "string") {
        const stripped = parsed.intent_pattern.replace(/\s*\[prescribed[^\]]*\]/gi, "").trim();
        parsed.intent_pattern = stripped.length ? stripped : null;
      }
      if (parsed.work && parsed.work.target_pace_per_mile != null) {
        parsed.work.target_pace_per_mile = null;
      }
      parsed.prescription_stripped = true;
    }

    // 4d) PER-LAP LABELS for the splits view — DESCRIPTIVE ONLY.
    // Tag every recorded lap (warmup / rep / recovery / cooldown) so the splits
    // chart can label each row while showing the watch's own numbers as-is. This
    // never merges, drops, or re-paces a split — it only names it. Keyed by
    // lap_index so the client joins 1:1 against running_workout_laps.
    if (rawLaps.length) {
      parsed.lap_roles = lapRoles(rawLaps);
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
    //
    // `structure_parsed_at` is the queue's completion signal (see
    // 20260810170000_wire_workout_structure_parse.sql). It is stamped on every
    // successful write INCLUDING the ones that correctly find no structure —
    // an easy 6-miler has none, and that is an answer, not a failure. Keeping
    // "parsed, nothing there" distinct from "never parsed" is what stops the
    // chat's fallback to average pace from being silent.
    //
    // It must be a real column and not read back out of `parsed_structure`:
    // `dispatch_workout_parse` retires jobs by comparing it to the job's
    // `created_at`, and that predicate has to be an index scan that cannot
    // fault on a malformed JSON timestamp.
    const { error: updateErr } = await supabase
      .from("training_logs")
      .update({
        parsed_structure: parsed,
        structure_parsed_at: parsed.parsed_at,
      })
      .eq("id", row.id);

    if (updateErr) {
      await recordParseFailure(row.id as string, `update failed: ${updateErr.message}`);
      return json({ error: `update failed: ${updateErr.message}`, parsed }, 500);
    }

    return json({ ok: true, parsed }, 200);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("[parse-workout-structure]", msg);
    if (body?.training_log_id) await recordParseFailure(body.training_log_id, msg);
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

/**
 * Drop auto-sync boilerplate lines from workout_notes, leaving only
 * athlete-authored text. strava-sync emits lines like "Distance: 4.0 miles",
 * "Duration: 29 min", "Pace: 7:02/mi", "Splits: 1.00 mi @ 7:23/mi, …", and
 * "(planned 8 miles)". Those restate execution the GPS timeline already carries
 * and are the source of fabricated prescriptions. Returns null when nothing
 * athlete-authored remains.
 */
function sanitizeAthleteNotes(raw: string | null): string | null {
  const text = raw?.trim();
  if (!text) return null;
  const MACHINE_LINE = /^\s*(distance|duration|pace|splits|elevation|avg\s*hr|calories)\s*:/i;
  const kept = text
    .split("\n")
    .filter((line) => line.trim() && !MACHINE_LINE.test(line))
    .join("\n")
    .trim();
  return kept.length ? kept : null;
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

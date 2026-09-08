/**
 * run-hr-trace Edge Function
 *
 * Per-minute heart-rate traces for a handful of runs, so the expanded week
 * chart can draw the SHAPE of an effort — the ramp, the reps, the recovery —
 * inside the day band at the hours it happened.
 *
 * WHY THIS IS NOT PART OF `trends-timeline`. The source is
 * `training_logs.external_streams->streams->heartrate`: one sample per second,
 * 3,599 of them for an hour's run, and the column as a whole runs 50-100 KB
 * per row. `trends-timeline` returns a 26-WEEK window — roughly 250 runs — so
 * folding traces into it would put the better part of a megabyte of numbers on
 * the wire to draw seven days. The performance audit of 2026-08-10 names
 * `external_streams` as the single largest cost in the app and says plainly:
 * never `select()` it. This endpoint is the narrow exception — it reads only
 * the two JSON paths it needs, for only the runs actually on screen.
 *
 * WHY PER MINUTE. A 60-minute run becomes 60 numbers instead of 3,600, which
 * is a 60× reduction for a curve that is drawn ~200pt wide. At that width a
 * per-second trace is drawing fifteen samples per point — it cannot be seen,
 * only paid for. A minute is also the grain a runner reads: nobody asks what
 * their heart rate was at 14:23, they ask what it did during the reps.
 *
 * MEAN, NOT LAST. Each bucket averages its samples rather than sampling one,
 * because a single reading lands anywhere in the beat-to-beat noise and a
 * decimated trace looks jagged in a way the effort was not.
 *
 * GAPS SURVIVE AS NULLS. A minute with no samples — a watch dropout, a paused
 * stretch — comes back `null` and the client breaks the line there. Bridging
 * it would draw a heart rate nobody measured.
 *
 * Request:  POST { log_ids: string[] }        (auth via user JWT)
 * Response: { traces: { [log_id]: { step_sec: 60, bpm: (number|null)[] } } }
 *
 * A run with no HR stream is simply absent from `traces` — the client already
 * has to handle "no trace for this run", so an empty entry would be a second
 * way of saying the same thing.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** One week of runs is under a dozen. The cap is a backstop, not a budget. */
const MAX_LOGS = 24;
const STEP_SEC = 60;
/** Physiologically possible on a running watch. Outside this is a sensor
 *  artifact — a dropout reading 0, or a cadence lock reading 220+ — and
 *  averaging it in drags the whole minute somewhere the athlete never was. */
const HR_MIN = 25;
const HR_MAX = 235;

interface Body {
  log_ids?: unknown;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Returns the user ID as a STRING, not a user object — see _shared/auth.ts.
  const userId = await getAuthenticatedUser(req);
  if (!userId) return unauthorizedResponse(corsHeaders);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const ids = Array.isArray(body.log_ids)
    ? body.log_ids.filter((v): v is string => typeof v === "string" && UUID_RE.test(v))
        .slice(0, MAX_LOGS)
    : [];
  if (ids.length === 0) return json({ traces: {} }, 200);

  const supabase = createClient(supabaseUrl, serviceKey);

  // ONLY the two paths. Selecting the column itself would pull GPS, cadence,
  // altitude, power and the lap array along with it — see the header.
  const { data, error } = await supabase
    .from("training_logs")
    .select("id, hr:external_streams->streams->heartrate, t:external_streams->streams->time")
    .eq("user_id", userId)           // scoped to the caller, not to the ids alone
    .in("id", ids);

  if (error) {
    console.error("[run-hr-trace] select failed:", error.message);
    return json({ error: "Could not read heart-rate streams" }, 500);
  }

  const traces: Record<string, { step_sec: number; bpm: (number | null)[] }> = {};

  for (const row of (data ?? []) as Array<Record<string, unknown>>) {
    const hr = row.hr, t = row.t;
    if (!Array.isArray(hr) || !Array.isArray(t) || hr.length === 0) continue;

    // The two arrays are parallel by construction; if a provider ever ships
    // them ragged, trust the shorter one rather than reading past its end.
    const n = Math.min(hr.length, t.length);
    const sums: number[] = [];
    const counts: number[] = [];

    for (let i = 0; i < n; i++) {
      const bpm = Number(hr[i]);
      const sec = Number(t[i]);
      if (!Number.isFinite(bpm) || !Number.isFinite(sec)) continue;
      if (bpm < HR_MIN || bpm > HR_MAX) continue;
      const b = Math.floor(sec / STEP_SEC);
      if (b < 0) continue;
      sums[b] = (sums[b] ?? 0) + bpm;
      counts[b] = (counts[b] ?? 0) + 1;
    }

    const buckets = counts.length;
    if (buckets === 0) continue;

    const bpmOut: (number | null)[] = [];
    for (let b = 0; b < buckets; b++) {
      const c = counts[b] ?? 0;
      bpmOut.push(c > 0 ? Math.round(sums[b] / c) : null);
    }
    // All-null is the same as no trace, and the client should not have to
    // discover that by walking the array.
    if (bpmOut.every((v) => v === null)) continue;

    traces[String(row.id)] = { step_sec: STEP_SEC, bpm: bpmOut };
  }

  return json({ traces }, 200);
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

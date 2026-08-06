/**
 * ingest-biometrics — the HealthKit write path into `daily_biometrics`.
 *
 * `daily_biometrics` is athlete-READ-ONLY by design (see
 * `20260804090000_daily_biometrics.sql`: "all writes go through the
 * service-role webhook"). That rule was written when Garmin-via-Junction was
 * the only imagined producer. Apple Health is a second producer, and it lives
 * on the device — so it needs a service-role seam rather than a client INSERT
 * policy. Widening RLS instead would have handed every athlete a write path to
 * a table the recovery ledger trusts. This function is that seam.
 *
 * ── The one thing to understand before touching this file ──────────────────
 *
 * **Apple's HRV is SDNN. Garmin's (via Junction) is RMSSD. They are different
 * metrics on different scales and MUST NEVER be pooled.** SDNN over a night
 * typically runs meaningfully higher than RMSSD for the same athlete, so a
 * history that silently switches producer mid-stream manufactures a step
 * change the Overnight factor would read as a real physiological shift.
 *
 * Two things keep that from happening:
 *
 *   1. The PK is `(user_id, date, source)`, and this function hard-codes
 *      `source = 'healthkit'`. A client cannot claim to be 'garmin' — the
 *      field is not read from the request. So the two producers can coexist
 *      on the same night without overwriting each other.
 *   2. `trends-timeline` pins ONE source for the whole window before it
 *      decorates any day, so a single ledger read never mixes the two.
 *
 * Given (1) and (2), storing SDNN in a column named `hrv_rmssd` is safe: the
 * column is the HRV *slot*, `source` is the metric discriminator. Renaming it
 * would be a migration on a table two producers and a shipped ledger already
 * read. The Overnight factor only ever compares an athlete to their OWN
 * 28-day baseline at 0.5x their own SD, so the absolute scale is never
 * meaningful — only the deviation is, and deviation is scale-free.
 *
 * ── What this function deliberately does NOT do ────────────────────────────
 *
 * No sleep score, no sleep efficiency, no stage breakdown, no Body Battery
 * equivalent. Those are Tier-0 in `recovery-trend-v2` §7.4 and were left out
 * of the schema on purpose: "capturing them invites someone to use them."
 * Apple exposes stage-level sleep and it is tempting. Don't.
 *
 * Auth: dual-mode (user JWT or service role) via requireAuthOrServiceRole.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(supabaseUrl, supabaseServiceKey);

/** This function writes exactly one source. Never taken from the request. */
const SOURCE = "healthkit";

/**
 * A night as the device measured it. Every metric is optional — Apple Watch
 * users routinely have resting HR on a night with no sleep record (the watch
 * was charging), and that night is still worth storing for the RHR series.
 */
interface NightInput {
  date?: unknown;
  hrv_sdnn?: unknown;
  resting_hr?: unknown;
  sleep_total_min?: unknown;
  hr_lowest?: unknown;
  respiratory_rate?: unknown;
  device_model?: unknown;
}

/** Batch ceiling. A 2-year first-run backfill is ~730 nights; chunk client-side. */
const MAX_NIGHTS = 400;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Physiological sanity gates. These reject sensor garbage, not unusual
 * athletes — the bounds are wide enough that a genuine outlier survives. A
 * value outside the gate becomes null (the night is still written for its
 * other metrics) rather than dropping the night entirely.
 */
function num(v: unknown, min: number, max: number): number | null {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  if (v < min || v > max) return null;
  return v;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { user_id?: string; nights?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
  if ("response" in auth) return auth.response;
  // `daily_biometrics.user_id` is TEXT holding a lowercase uuid. Swift's
  // `.uuidString` is UPPERCASE and silently matched nothing for two days once
  // already (the voice-memo auth bug) — normalise here so it cannot recur.
  const userId = auth.userId.toLowerCase();

  if (!Array.isArray(body.nights)) {
    return json({ error: "Body must contain a `nights` array" }, 400);
  }
  if (body.nights.length > MAX_NIGHTS) {
    return json(
      { error: `Too many nights in one call (max ${MAX_NIGHTS})`, received: body.nights.length },
      400,
    );
  }

  const now = new Date().toISOString();
  const rows: Record<string, unknown>[] = [];
  let skipped = 0;

  for (const raw of body.nights as NightInput[]) {
    const date = typeof raw?.date === "string" ? raw.date.slice(0, 10) : "";
    if (!DATE_RE.test(date)) {
      skipped++;
      continue;
    }

    const hrv = num(raw.hrv_sdnn, 1, 500);            // ms
    const restingHr = num(raw.resting_hr, 25, 120);   // bpm
    const hrLowest = num(raw.hr_lowest, 25, 120);     // bpm
    const sleepMin = num(raw.sleep_total_min, 0, 1440);
    const respRate = num(raw.respiratory_rate, 4, 40);

    // A night with nothing usable is not worth a row — writing it would put a
    // non-null date into the baseline windows with all-null metrics, which
    // reads as "we have coverage here" when we do not.
    if (hrv === null && restingHr === null && sleepMin === null) {
      skipped++;
      continue;
    }

    rows.push({
      user_id: userId,
      date,
      source: SOURCE,
      // SDNN in the HRV slot — see the header. `source` is the discriminator.
      hrv_rmssd: hrv,
      resting_hr: restingHr,
      hr_lowest: hrLowest,
      sleep_total_min: sleepMin === null ? null : Math.round(sleepMin),
      respiratory_rate: respRate,
      // Apple restates a night as more samples arrive (a nap logged later, a
      // watch that syncs at noon), so every write is final-wins for its date.
      sleep_state: "confirmed",
      device_model: typeof raw.device_model === "string" && raw.device_model
        ? raw.device_model.slice(0, 64)
        : "Apple Health",
      updated_at: now,
    });
  }

  if (rows.length === 0) {
    return json({ upserted: 0, skipped, source: SOURCE });
  }

  const { error } = await db
    .from("daily_biometrics")
    .upsert(rows, { onConflict: "user_id,date,source" });

  if (error) {
    console.error(`[ingest-biometrics] upsert failed for ${userId}: ${error.message}`);
    return json({ error: "Failed to store biometrics", detail: error.message }, 500);
  }

  return json({ upserted: rows.length, skipped, source: SOURCE });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

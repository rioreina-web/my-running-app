/**
 * vital-webhook -- receive Junction/Vital webhooks and ingest Garmin runs into
 * training_logs, with full parity to strava-sync:
 *   - per-second stream backfill into external_streams (Strava-shaped blob)
 *   - fire parse-workout-structure (interval/rep detection) once stream lands
 *   - fire fetch-workout-weather (conditions from the run's GPS) once stream lands
 *   - reconcileVoiceOrphan (fold in a voice memo recorded before the run)
 *
 * SECURITY: Svix signature (svix-id/svix-timestamp/svix-signature) vs
 * VITAL_WEBHOOK_SECRET (whsec_...). Junction sends no Supabase JWT -> deploy
 * with `--no-verify-jwt`. 5-minute replay window.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { pickBestOrphan, type OrphanCandidate } from "../_shared/voiceOrphanMatch.ts";
import { derivedLapsFromStream } from "../_shared/shared/workBouts.ts";

const WEBHOOK_SECRET = Deno.env.get("VITAL_WEBHOOK_SECRET") ?? "";
const VITAL_BASE = Deno.env.get("VITAL_BASE_URL") ?? "https://api.sandbox.us.junction.com/v2";
const VITAL_API_KEY = Deno.env.get("VITAL_API_KEY") ?? "";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

function res(status: number, body: unknown = { ok: true }): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
function timingSafeEqualStr(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
async function verifySvix(rawBody: string, h: Headers): Promise<boolean> {
  const id = h.get("svix-id"), ts = h.get("svix-timestamp"), sig = h.get("svix-signature");
  if (!id || !ts || !sig || !WEBHOOK_SECRET) return false;
  const now = Math.floor(Date.now() / 1000), tsn = Number(ts);
  if (!Number.isFinite(tsn) || Math.abs(now - tsn) > 300) return false;
  const b64 = WEBHOOK_SECRET.startsWith("whsec_") ? WEBHOOK_SECRET.slice(6) : WEBHOOK_SECRET;
  const keyBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${rawBody}`));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  for (const part of sig.split(" ")) { const [, s] = part.split(","); if (s && timingSafeEqualStr(s, expected)) return true; }
  return false;
}
async function vitalGet(path: string) {
  const r = await fetch(`${VITAL_BASE}${path}`, { headers: { "x-vital-api-key": VITAL_API_KEY, "Accept": "application/json" } });
  if (!r.ok) return null;
  try { return await r.json(); } catch { return null; }
}
function mean(a: unknown): number | null {
  if (!Array.isArray(a) || !a.length) return null;
  const n = a.filter((x) => typeof x === "number");
  return n.length ? (n as number[]).reduce((s, x) => s + x, 0) / n.length : null;
}
function toExternalStreams(w: Record<string, any>, s: Record<string, any> | null) {
  const src = w.source ?? {};
  const meta = {
    average_heartrate: w.average_hr ?? null, max_heartrate: w.max_hr ?? null,
    average_cadence: s ? mean(s.cadence) : null, average_watts: w.average_watts ?? null,
    max_watts: w.max_watts ?? null, calories: w.calories ?? null,
    total_elevation_gain: w.total_elevation_gain ?? null, device_name: src.app_id ?? "Garmin",
  };
  if (!s) return { source: "garmin", provider_id: w.provider_id ?? null, meta };
  const lat = Array.isArray(s.lat) ? s.lat : null, lng = Array.isArray(s.lng) ? s.lng : null;
  let latlng: number[][] | undefined;
  if (lat && lng) { const n = Math.min(lat.length, lng.length); latlng = []; for (let i = 0; i < n; i++) latlng.push([lat[i], lng[i]]); }
  const streams: Record<string, unknown> = {
    time: s.time, heartrate: s.heartrate, altitude: s.altitude, distance: s.distance,
    velocity_smooth: s.velocity_smooth, cadence: s.cadence, watts: s.power, temp: s.temperature,
  };
  if (latlng) streams.latlng = latlng;

  const blob: Record<string, unknown> = { source: "garmin", provider_id: w.provider_id ?? null, streams, meta };

  // Junction/Garmin delivers the per-second stream but NO native laps (unlike
  // Strava's `laps` array). Without them, every quality session's pace collapses
  // to the whole-workout average (a 6×mile @ 5:10 with jog recoveries reads
  // ~6:20). Derive rep-level laps from the stream — recovery-bounded, the same
  // detector the parser uses — and write them in the Strava lap shape, so the
  // existing `sync_workout_laps_from_streams` trigger + every lap-based surface
  // (key sessions, the pace ladder, quality volume) keep working. Prefer any
  // native laps the provider does supply. Additive: a run that doesn't segment
  // (steady/easy) simply gets no laps, exactly as before.
  const nativeLaps = Array.isArray(w.laps) ? w.laps : null;
  if (nativeLaps && nativeLaps.length) {
    blob.laps = nativeLaps;
  } else {
    const derived = derivedLapsFromStream({
      time: (s.time as number[]) ?? [],
      distance: (s.distance as number[]) ?? [],
      velocity_smooth: (s.velocity_smooth as number[]) ?? [],
      heartrate: (s.heartrate as number[]) ?? [],
    });
    if (derived.length) blob.laps = derived;
  }
  return blob;
}
// Fetch Vital stream, write external_streams onto the row. Returns true if written.
async function backfillStream(db: any, w: Record<string, any>, rowId?: string): Promise<boolean> {
  const s = await vitalGet(`/timeseries/workouts/${w.id}/stream`);
  const blob = toExternalStreams(w, s && typeof s === "object" ? s : null);
  if (!(blob as any).streams) return false;
  const q = db.from("training_logs").update({ external_streams: blob });
  await (rowId ? q.eq("id", rowId) : q.eq("vital_workout_id", String(w.id)));
  return true;
}
// Fold a voice memo recorded before this run into the run row (mirrors strava-sync).
async function reconcileVoiceOrphan(db: any, userId: string, runId: string, runDate: string, distMi: number) {
  try {
    const win = 4 * 60 * 60 * 1000, base = new Date(runDate).getTime();
    const lo = new Date(base - win).toISOString(), hi = new Date(base + win).toISOString();
    const { data, error } = await db.from("training_logs")
      .select("id, workout_date, workout_distance_miles")
      .eq("user_id", userId).is("external_streams", null).not("audio_url", "is", null)
      .is("vital_workout_id", null).neq("id", runId).gte("workout_date", lo).lte("workout_date", hi);
    if (error) { console.warn(`[vital-webhook] orphan lookup: ${error.message}`); return; }
    const orphan = pickBestOrphan({ workout_date: runDate, workout_distance_miles: distMi }, (data ?? []) as OrphanCandidate[]);
    if (!orphan) return;
    const { error: mErr } = await db.rpc("merge_voice_orphan_into_run", { p_orphan: orphan.id, p_run: runId });
    if (mErr) console.warn(`[vital-webhook] orphan merge failed: ${mErr.message}`);
    else console.log(`[vital-webhook] merged voice orphan ${orphan.id} -> ${runId}`);
  } catch (e) { console.warn(`[vital-webhook] reconcile threw: ${e instanceof Error ? e.message : String(e)}`); }
}
function fireFn(fn: string, trainingLogId: string, userId: string) {
  if (!supabaseUrl || !supabaseServiceKey) return;
  const p = fetch(`${supabaseUrl}/functions/v1/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${supabaseServiceKey}`, apikey: supabaseServiceKey },
    body: JSON.stringify({ training_log_id: trainingLogId, user_id: userId }),
  }).then((r) => { if (!r.ok) console.warn(`[vital-webhook] ${fn} ${r.status} for ${trainingLogId}`); })
    .catch((e) => console.warn(`[vital-webhook] ${fn} fetch failed: ${e}`));
  try { if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) { EdgeRuntime.waitUntil(p); return; } } catch { /* */ }
  void p;
}
function afterStream(rowId: string, userId: string) { fireFn("parse-workout-structure", rowId, userId); fireFn("fetch-workout-weather", rowId, userId); }
function toRow(userId: string, w: Record<string, any>) {
  const distanceMiles = Number(w.distance ?? 0) / 1609.34;
  const movingSec = Number(w.moving_time ?? (w.time_end && w.time_start ? (new Date(w.time_end).getTime() - new Date(w.time_start).getTime()) / 1000 : 0));
  return {
    user_id: userId, source: "garmin", vital_workout_id: String(w.id), workout_date: w.time_start,
    workout_distance_miles: distanceMiles, workout_duration_minutes: movingSec / 60,
    cleaned_notes: w.title ?? w.source?.name ?? "Garmin", processing_status: "completed",
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return res(405, { error: "POST only" });
  const rawBody = await req.text();
  if (!(await verifySvix(rawBody, req.headers))) return res(401, { error: "invalid signature" });
  let payload: any;
  try { payload = JSON.parse(rawBody); } catch { return res(400, { error: "bad json" }); }

  const eventType: string = payload.event_type ?? "";
  const db = createClient(supabaseUrl, supabaseServiceKey) as any;

  let userId: string | null = payload.client_user_id ?? null;
  if (!userId && payload.user_id) {
    const { data } = await db.from("vital_credentials").select("user_id").eq("vital_user_id", payload.user_id).maybeSingle();
    userId = (data?.user_id as string | undefined) ?? null;
  }

  if (eventType === "provider.connection.created") {
    if (userId) await db.from("vital_credentials").update({ connected_at: new Date().toISOString() }).eq("user_id", userId);
    return res(200);
  }

  // Stream ready for an already-ingested run -> backfill + fire structure/weather.
  if (eventType.endsWith("workout_stream.created")) {
    const d = payload.data; const items = Array.isArray(d) ? d : d ? [d] : [];
    for (const w of items) {
      if (!w?.id) continue;
      const { data: row } = await db.from("training_logs").select("id, user_id").eq("vital_workout_id", String(w.id)).maybeSingle();
      const wrote = await backfillStream(db, w, row?.id);
      if (wrote && row?.id) afterStream(row.id, row.user_id);
    }
    return res(200, { streamed: items.length });
  }

  const isWorkoutEvent = eventType.endsWith("workouts.created") || eventType.endsWith("workouts.updated");
  if (!isWorkoutEvent) return res(200, { ignored: eventType });
  if (!userId) return res(200, { ignored: "no user mapping", vitalUserId: payload.user_id });

  const d = payload.data;
  const workouts: Record<string, any>[] = Array.isArray(d) ? d : Array.isArray(d?.workouts) ? d.workouts : d ? [d] : [];

  let imported = 0, skipped = 0;
  for (const w of workouts) {
    if (w?.sport?.slug && w.sport.slug !== "running") { skipped++; continue; }
    const key = String(w.id);
    const { data: existing } = await db.from("training_logs").select("id").eq("vital_workout_id", key).maybeSingle();
    if (existing) {
      const wrote = await backfillStream(db, w, existing.id);
      if (wrote) afterStream(existing.id, userId);
      skipped++; continue;
    }
    const { data: inserted, error } = await db.from("training_logs").insert(toRow(userId, w)).select("id").single();
    if (error) { console.error(`[vital-webhook] insert failed ${key}: ${error.message}`); return res(500, { error: error.message }); }
    imported++;
    const rowId = inserted.id as string;
    const dist = Number(w.distance ?? 0) / 1609.34;
    await reconcileVoiceOrphan(db, userId, rowId, w.time_start, dist);
    const wrote = await backfillStream(db, w, rowId);
    if (wrote) afterStream(rowId, userId);
  }
  return res(200, { imported, skipped });
});

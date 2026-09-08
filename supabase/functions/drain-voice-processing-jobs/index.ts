/**
 * Drain Voice-Processing Jobs (W3.3)
 *
 * Cron-driven worker that pulls a batch of queued jobs from
 * `voice_processing_jobs`, calls `process-training-memo` or
 * `process-check-in` for each (by job.kind), and manages retries /
 * status / backoff. Mirrors `drain-coach-insight-jobs`; sized smaller
 * because voice processing (transcription + LLM) runs ~10-60s per job.
 *
 * Auth: service-role only.
 *
 * Body (optional):
 *   { batch?: number }   // default 10
 *
 * Response:
 *   { claimed, completed, retrying, failed, elapsed_ms }
 *
 * Sizing:
 *   - Default batch 10, parallelism 3, every-minute cron.
 *   - Steady-state ~10 memos/min — far above expected voice-log rate
 *     at 1k users (~0.5/min). Burst recovery is minutes-scale.
 *   - Stale `in_progress` rows (worker hit its wall-clock budget) are
 *     re-queued by the claim RPC itself after 10 minutes.
 *
 * Backoff: 2^attempt × 30s, capped at 30 min.
 *
 * Payload contract: both downstream functions take
 *   { record: { id, user_id, audio_url } }
 * — user_id is REQUIRED by process-training-memo's service-role auth
 * gate (requireAuthOrServiceRole). The pre-outbox trigger omitted it;
 * this worker is the fix.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
import { isProviderExhaustedText } from "../_shared/provider-errors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 10;
const MAX_BATCH = 50;
const PARALLELISM = 3;
const BACKOFF_BASE_SECONDS = 30;
const BACKOFF_MAX_SECONDS = 30 * 60;
/** Flat wait while the model provider is unfunded/over quota. Matches the
 *  Retry-After that process-training-memo sends on 503. Provider outages run
 *  minutes-to-hours, so the normal 30s exponential ramp is far too eager. */
const PROVIDER_OUTAGE_BACKOFF_SECONDS = 15 * 60;

interface ClaimedJob {
  id: number;
  training_log_id: string;
  user_id: string;
  // "note" = a typed manual note: no audio, process-training-memo takes the
  // text branch (transcription = the row's `notes`).
  kind: "memo" | "check_in" | "note";
  audio_url: string | null;
  attempts: number;
  max_attempts: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // --- Auth: service-role only ---
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "Authentication required" }, 401);
  }
  const token = authHeader.slice("Bearer ".length).trim();
  // Confirm a service-role token by decoding the role claim. The gateway has
  // already verified the JWT signature (verify_jwt = true in config.toml), so
  // we only read the claim. Robust to service-key / Vault drift — unlike the
  // exact-key match against SUPABASE_SERVICE_ROLE_KEY that 403'd these drains
  // when the function-env key and the Vault copy diverged (2026-06-11).
  if (!isServiceRoleJWT(token)) {
    return jsonResponse({ error: "Service role required" }, 403);
  }

  const startedAt = Date.now();

  try {
    const body = await req.json().catch(() => ({}));
    const requestedBatch = (body as { batch?: unknown }).batch;
    const batch =
      typeof requestedBatch === "number" && Number.isFinite(requestedBatch)
        ? Math.max(1, Math.min(MAX_BATCH, Math.floor(requestedBatch)))
        : DEFAULT_BATCH;

    const { data: claimed, error: claimErr } = await admin.rpc(
      "claim_voice_processing_jobs",
      { batch_size: batch },
    );

    if (claimErr) {
      console.error("claim failed:", claimErr.message);
      return jsonResponse({ error: claimErr.message }, 500);
    }

    const jobs = (claimed ?? []) as ClaimedJob[];
    if (jobs.length === 0) {
      return jsonResponse({
        claimed: 0,
        completed: 0,
        retrying: 0,
        failed: 0,
        elapsed_ms: Date.now() - startedAt,
      });
    }

    const counters = { completed: 0, retrying: 0, failed: 0 };
    const queue = jobs.slice();

    async function worker(): Promise<void> {
      while (true) {
        const job = queue.shift();
        if (!job) return;
        await processJob(job, counters);
      }
    }

    await Promise.all(
      Array.from({ length: Math.min(PARALLELISM, jobs.length) }, () => worker()),
    );

    return jsonResponse({
      claimed: jobs.length,
      ...counters,
      elapsed_ms: Date.now() - startedAt,
    });
  } catch (err) {
    console.error("drain-voice-processing-jobs error:", err);
    return jsonResponse({ error: String(err) }, 500);
  }
});

interface CallResult {
  kind: "ok" | "err";
  retryable: boolean;
  /** The upstream model provider is out of credit/quota. Retryable, but the
   *  attempt must NOT be counted — see processJob. */
  providerExhausted?: boolean;
  error?: string;
}

interface Counters {
  completed: number;
  retrying: number;
  failed: number;
}

async function processJob(job: ClaimedJob, counters: Counters): Promise<void> {
  const result = await callProcessor(job);

  if (result.kind === "ok") {
    await admin
      .from("voice_processing_jobs")
      .update({ status: "completed", completed_at: new Date().toISOString() })
      .eq("id", job.id);
    counters.completed++;
    return;
  }

  // ── An upstream billing outage must not spend this job's retry budget. ──
  // (2026-08-13) Gemini's prepay credits ran dry and every memo recorded in
  // that window died: three attempts at 30s/60s backoff burned in three
  // minutes, then `failed` forever, with a "tap to try again" the athlete
  // could not act on. The outage lasted ~7 hours. Nothing about that is the
  // job's fault, so we hand the attempt back (the claim RPC already
  // incremented it) and wait out the outage on a flat 15-minute backoff
  // instead of an exponential one that starts far too fast.
  //
  // This retries indefinitely while the provider is down — deliberately. The
  // failure mode being fixed is silent permanent data loss; an outage that
  // never ends is an ops problem a queue cannot solve, and the cost is
  // bounded (one fail-fast call per job per 15 min, under the LLM budget
  // guard). The row stays visible in the queue the whole time.
  if (result.providerExhausted) {
    await admin
      .from("voice_processing_jobs")
      .update({
        status: "queued",
        attempts: Math.max(0, job.attempts - 1),
        next_retry_at: new Date(Date.now() + PROVIDER_OUTAGE_BACKOFF_SECONDS * 1000).toISOString(),
        last_error: (result.error ?? "").slice(0, 500),
      })
      .eq("id", job.id);
    console.warn(
      `[drain-voice] job ${job.id}: provider unavailable, attempt not counted ` +
        `(attempts stays ${Math.max(0, job.attempts - 1)}/${job.max_attempts})`,
    );
    counters.retrying++;
    return;
  }

  // `attempts` was already incremented by the claim RPC.
  const exhausted = job.attempts >= job.max_attempts;
  if (exhausted || !result.retryable) {
    await admin
      .from("voice_processing_jobs")
      .update({
        status: "failed",
        last_error: (result.error ?? "").slice(0, 500),
      })
      .eq("id", job.id);
    // Make the failure athlete-visible via the existing status column —
    // iOS shows a retry affordance off processing_status='failed'.
    await admin
      .from("training_logs")
      .update({
        processing_status: "failed",
        processing_error: `voice outbox: ${(result.error ?? "exhausted retries").slice(0, 200)}`,
      })
      .eq("id", job.training_log_id);
    counters.failed++;
    return;
  }

  const backoffSec = Math.min(
    BACKOFF_BASE_SECONDS * Math.pow(2, Math.max(0, job.attempts - 1)),
    BACKOFF_MAX_SECONDS,
  );
  const nextRetryAt = new Date(Date.now() + backoffSec * 1000).toISOString();

  await admin
    .from("voice_processing_jobs")
    .update({
      status: "queued",
      next_retry_at: nextRetryAt,
      last_error: (result.error ?? "").slice(0, 500),
    })
    .eq("id", job.id);
  counters.retrying++;
}

async function callProcessor(job: ClaimedJob): Promise<CallResult> {
  const fn = job.kind === "check_in" ? "process-check-in" : "process-training-memo";
  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/${fn}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${supabaseServiceKey}`,
        apikey: supabaseServiceKey,
      },
      body: JSON.stringify({
        record: {
          id: job.training_log_id,
          user_id: job.user_id,
          audio_url: job.audio_url,
        },
      }),
    });

    if (res.ok) {
      return { kind: "ok", retryable: false };
    }

    const text = await res.text().catch(() => "");

    // 503 + a provider-exhaustion body = the model provider is out of
    // credit. Retryable, but uncounted (see processJob). The text check is
    // the belt-and-braces half: it still fires if an older, not-yet-
    // redeployed process-training-memo answers 500 with the raw provider
    // error in the body — which is exactly the shape that stranded memos on
    // 2026-08-13, and a real risk given this repo's deploy-drift history.
    if (isProviderExhaustedText(text)) {
      return {
        kind: "err",
        retryable: true,
        providerExhausted: true,
        error: `${fn} HTTP ${res.status}: ${text.slice(0, 200)}`,
      };
    }

    // 409 = "already processing": with the client now direct-invoking
    // process-training-memo on insert (2026-08-04), the drain routinely races
    // an in-flight run. That's a healthy state, not a failure — retry with
    // backoff, and the next attempt hits the "already processed" 200
    // short-circuit and completes the job. Marking it failed here would
    // clobber processing_status on a memo that's actively being processed.
    // Otherwise: 429 + 5xx retry, remaining 4xx don't.
    const retryable = res.status === 409 || res.status === 429 || res.status >= 500;
    return {
      kind: "err",
      retryable,
      error: `${fn} HTTP ${res.status}: ${text.slice(0, 200)}`,
    };
  } catch (err) {
    return { kind: "err", retryable: true, error: `network: ${String(err)}` };
  }
}

/** True if `token` is a non-expired service-role JWT. Signature is already
 *  verified by the gateway (verify_jwt = true); we only read the claims.
 *  Mirrors rebuild-athlete-state's auth so a future key rotation can never
 *  silently 403 the drain pipeline again. */
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

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

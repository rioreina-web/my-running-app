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

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 10;
const MAX_BATCH = 50;
const PARALLELISM = 3;
const BACKOFF_BASE_SECONDS = 30;
const BACKOFF_MAX_SECONDS = 30 * 60;

interface ClaimedJob {
  id: number;
  training_log_id: string;
  user_id: string;
  kind: "memo" | "check_in";
  audio_url: string;
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
  if (!constantTimeEq(token, supabaseServiceKey)) {
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
    // 409/processing-races and "already processed" shapes come back as
    // 2xx from the processors; anything else: 429 + 5xx retry, 4xx don't.
    const retryable = res.status === 429 || res.status >= 500;
    return {
      kind: "err",
      retryable,
      error: `${fn} HTTP ${res.status}: ${text.slice(0, 200)}`,
    };
  } catch (err) {
    return { kind: "err", retryable: true, error: `network: ${String(err)}` };
  }
}

function constantTimeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

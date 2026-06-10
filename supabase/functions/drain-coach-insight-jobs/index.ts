/**
 * Drain Coach-Insight Jobs
 *
 * Cron-driven worker that pulls a batch of queued jobs from
 * `coach_insight_jobs`, calls `generate-workout-insight` for each, and
 * manages retries / status / backoff.
 *
 * Auth: service-role only. Cron job (and operator dry-runs) call this
 * with the service-role JWT.
 *
 * Body (optional):
 *   { batch?: number }   // default 20
 *
 * Response:
 *   {
 *     claimed: number,       // jobs we claimed this tick
 *     completed: number,     // jobs that finished (success)
 *     retrying: number,      // jobs that failed but will retry
 *     failed: number,        // jobs that exhausted retries
 *     elapsed_ms: number
 *   }
 *
 * Sizing:
 *   - Default batch = 40 jobs/invocation.
 *   - Up to 10 jobs processed in parallel (Gemini fan-out cap).
 *   - 30s edge-fn budget → ~10s for 40 jobs at 3s/job avg with 10-wide
 *     concurrency. Plenty of margin.
 *   - Cron schedule = every minute (see migration 20260508170000).
 *   - Steady-state throughput ≈ 40/min = 57k/day. Well above 10k-user
 *     baseline (~5-7k inserts/day). Burst recovery is hours-scale by
 *     design — coach_insight is enrichment, not blocking.
 *
 * Backoff:
 *   2^attempt × 30s, capped at 30 min.
 *   attempt 1 fails → retry in 30s
 *   attempt 2 fails → retry in 60s
 *   attempt 3 fails → retry in 120s, then marked failed (max_attempts=3)
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { corsHeaders } from "../_shared/cors.ts";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(supabaseUrl, supabaseServiceKey);

const DEFAULT_BATCH = 40;
const MAX_BATCH = 200;
const PARALLELISM = 10;
const BACKOFF_BASE_SECONDS = 30;
const BACKOFF_MAX_SECONDS = 30 * 60;

interface ClaimedJob {
  id: number;
  training_log_id: string;
  user_id: string;
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

    // --- Atomic claim ---
    // FOR UPDATE SKIP LOCKED guarantees concurrent worker invocations
    // can't double-claim the same job. The CTE pattern lets us run the
    // claim and the update in one round-trip.
    const { data: claimed, error: claimErr } = await admin.rpc(
      "claim_coach_insight_jobs",
      { batch_size: batch }
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

    // --- Process jobs with bounded parallelism ---
    // Sequential processing under-throughputs (~10/invocation @ 3s/job
    // before the 30s edge-fn ceiling). 10-wide parallel keeps Gemini
    // fan-out under 200/min (well below the 1k RPM tier) while pushing
    // batch-of-40 through in ~12s.
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
      Array.from({ length: Math.min(PARALLELISM, jobs.length) }, () => worker())
    );

    return jsonResponse({
      claimed: jobs.length,
      ...counters,
      elapsed_ms: Date.now() - startedAt,
    });
  } catch (err) {
    console.error("drain-coach-insight-jobs error:", err);
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

/**
 * Process one claimed job: call generate-workout-insight, update the
 * outbox + training_logs based on the result. Bumps the right counter.
 */
async function processJob(job: ClaimedJob, counters: Counters): Promise<void> {
  const result = await callGenerateInsight(job.training_log_id);

  if (result.kind === "ok") {
    await admin
      .from("coach_insight_jobs")
      .update({ status: "completed", completed_at: new Date().toISOString() })
      .eq("id", job.id);
    counters.completed++;
    return;
  }

  // Failure. Decide retry vs. give up.
  // `attempts` was already incremented by the claim RPC, so the value
  // we have here reflects the count INCLUDING this attempt.
  const exhausted = job.attempts >= job.max_attempts;
  if (exhausted || !result.retryable) {
    await admin
      .from("coach_insight_jobs")
      .update({
        status: "failed",
        last_error: (result.error ?? "").slice(0, 500),
      })
      .eq("id", job.id);
    await admin
      .from("training_logs")
      .update({ coach_insight_status: "failed" })
      .eq("id", job.training_log_id)
      .is("coach_insight", null);
    counters.failed++;
    return;
  }

  // Retryable: requeue with exponential backoff.
  const backoffSec = Math.min(
    BACKOFF_BASE_SECONDS * Math.pow(2, Math.max(0, job.attempts - 1)),
    BACKOFF_MAX_SECONDS
  );
  const nextRetryAt = new Date(Date.now() + backoffSec * 1000).toISOString();
  await admin
    .from("coach_insight_jobs")
    .update({
      status: "queued",
      next_retry_at: nextRetryAt,
      last_error: (result.error ?? "").slice(0, 500),
    })
    .eq("id", job.id);
  counters.retrying++;
}

async function callGenerateInsight(trainingLogId: string): Promise<CallResult> {
  try {
    const res = await fetch(
      `${supabaseUrl}/functions/v1/generate-workout-insight`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseServiceKey}`,
          apikey: supabaseServiceKey,
        },
        body: JSON.stringify({ training_log_id: trainingLogId }),
      }
    );

    if (res.ok) {
      return { kind: "ok", retryable: false };
    }

    const text = await res.text().catch(() => "");

    // 429 (rate limit) and 502 (Gemini upstream) are retryable.
    // 5xx in general is retryable.
    // 4xx other than 429 means our input is broken — don't retry forever.
    const retryable = res.status === 429 || res.status >= 500;
    return {
      kind: "err",
      retryable,
      error: `HTTP ${res.status}: ${text.slice(0, 200)}`,
    };
  } catch (err) {
    // Network / timeout — assume retryable.
    return {
      kind: "err",
      retryable: true,
      error: `network: ${String(err)}`,
    };
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

function jsonResponse(
  body: Record<string, unknown>,
  status = 200
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

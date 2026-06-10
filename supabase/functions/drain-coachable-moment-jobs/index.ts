/**
 * Drain Coachable-Moment Jobs
 *
 * Cron-driven worker that pulls a batch of queued jobs from
 * `coachable_moment_jobs`, calls `evaluate-coachable-moment` for each,
 * and manages retries / status / backoff. Mirrors
 * `drain-coach-insight-jobs` — same shape, different downstream call.
 *
 * Auth: service-role only.
 *
 * Body (optional):
 *   { batch?: number }   // default 40
 *
 * Response:
 *   {
 *     claimed: number,        // jobs we claimed this tick
 *     completed: number,      // jobs that finished (success)
 *     retrying: number,       // failed but will retry
 *     failed: number,         // exhausted retries
 *     re_armed_by_trigger: number, // CAS detected a fresh trigger fire
 *     elapsed_ms: number
 *   }
 *
 * Sizing:
 *   - Default batch = 40 athletes/invocation.
 *   - Up to 10 evaluator calls in parallel.
 *   - 30s edge-fn budget → plenty of margin.
 *   - Cron = every minute.
 *
 * Backoff:
 *   2^attempt × 30s, capped at 30 min. Same shape as drain-coach-insight-jobs.
 *
 * Stale `in_progress` recovery:
 *   If the worker crashes mid-batch, rows are stranded in 'in_progress'.
 *   The drainer's claim RPC won't touch them (only picks status='queued').
 *   A follow-up migration adds a "stale in_progress reset" sweep — for now,
 *   manually reset with:
 *     UPDATE coachable_moment_jobs
 *        SET status='queued', next_retry_at=NOW()
 *      WHERE status='in_progress' AND last_attempted_at < NOW() - INTERVAL '5 min';
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

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
  athlete_user_id: string;
  attempts: number;
  max_attempts: number;
  /// Version flag from the claim — last_enqueued_at at the moment of
  /// claim. Worker's completion writes only if this still matches,
  /// detecting "trigger fired during processing → leave queued".
  version: string;
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
      "claim_coachable_moment_jobs",
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
        re_armed_by_trigger: 0,
        elapsed_ms: Date.now() - startedAt,
      });
    }

    const counters = { completed: 0, retrying: 0, failed: 0, re_armed_by_trigger: 0 };
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
    console.error("drain-coachable-moment-jobs error:", err);
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
  re_armed_by_trigger: number;
}

/**
 * Process one claimed job: call evaluate-coachable-moment, then CAS-
 * complete the outbox row only if the trigger hasn't re-armed it during
 * processing.
 */
async function processJob(job: ClaimedJob, counters: Counters): Promise<void> {
  const result = await callEvaluator(job.athlete_user_id);

  if (result.kind === "ok") {
    // CAS completion: only flip to 'completed' if no trigger fired
    // during processing. If the trigger bumped last_enqueued_at, our
    // WHERE clause misses zero rows and the row stays in 'in_progress';
    // the stale-recovery sweep (or a future drain tick) reclaims it.
    //
    // Actually — we want the row to go to 'queued' so the NEXT drain
    // tick claims it. Do that explicitly when the CAS misses.
    const { data: updated } = await admin
      .from("coachable_moment_jobs")
      .update({
        status: "completed",
        completed_at: new Date().toISOString(),
      })
      .eq("athlete_user_id", job.athlete_user_id)
      .eq("last_enqueued_at", job.version)
      .select("athlete_user_id");

    if (updated && updated.length > 0) {
      counters.completed++;
    } else {
      // Trigger fired during processing. Leave the row alone — its
      // status is already 'queued' (the trigger set it) and the next
      // drain tick will pick it up.
      counters.re_armed_by_trigger++;
    }
    return;
  }

  // Failure path. `attempts` was already incremented by the claim RPC,
  // so this reflects "attempts including this one".
  const exhausted = job.attempts >= job.max_attempts;
  if (exhausted || !result.retryable) {
    await admin
      .from("coachable_moment_jobs")
      .update({
        status: "failed",
        last_error: (result.error ?? "").slice(0, 500),
      })
      .eq("athlete_user_id", job.athlete_user_id);
    counters.failed++;
    return;
  }

  const backoffSec = Math.min(
    BACKOFF_BASE_SECONDS * Math.pow(2, Math.max(0, job.attempts - 1)),
    BACKOFF_MAX_SECONDS,
  );
  const nextRetryAt = new Date(Date.now() + backoffSec * 1000).toISOString();

  await admin
    .from("coachable_moment_jobs")
    .update({
      status: "queued",
      next_retry_at: nextRetryAt,
      last_error: (result.error ?? "").slice(0, 500),
    })
    .eq("athlete_user_id", job.athlete_user_id);
  counters.retrying++;
}

async function callEvaluator(athleteUserId: string): Promise<CallResult> {
  try {
    const res = await fetch(
      `${supabaseUrl}/functions/v1/evaluate-coachable-moment`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supabaseServiceKey}`,
          apikey: supabaseServiceKey,
        },
        body: JSON.stringify({ athlete_user_id: athleteUserId }),
      },
    );

    if (res.ok) {
      return { kind: "ok", retryable: false };
    }

    const text = await res.text().catch(() => "");

    // 429 (rate limit) and 5xx are retryable.
    // 4xx other than 429 means our input is broken — don't retry forever.
    const retryable = res.status === 429 || res.status >= 500;
    return {
      kind: "err",
      retryable,
      error: `HTTP ${res.status}: ${text.slice(0, 200)}`,
    };
  } catch (err) {
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
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Edge-function error tracking (beta-audit item #16, 2026-07-16).
 *
 * Sentry was wired for web, iOS, and ml-service — but not edge functions,
 * the core coaching backend. When a beta user hit a failure in
 * coaching-agent / process-training-memo / shift-day, the only signal was
 * Supabase console logs nobody watches.
 *
 * Usage — inside an existing top-level catch:
 *
 *   } catch (error) {
 *     captureException(error, { fn: "coaching-agent", userId });
 *     await flushSentry();
 *     return ...500...;
 *   }
 *
 * Or wrap a whole handler (for functions without a top-level catch):
 *
 *   Deno.serve(withSentry("upload-voice-memo", handler));
 *
 * Fail-soft by design: no SENTRY_DSN secret → everything is a no-op except
 * the console.error, which always fires. Set the secret with
 * `supabase secrets set SENTRY_DSN=<backend-project-dsn>` (use a separate
 * Sentry project from the iOS app so release health doesn't mix).
 */

import * as Sentry from "npm:@sentry/deno@10.64.0";

let initialized = false;

function ensureInit(): boolean {
  const dsn = Deno.env.get("SENTRY_DSN");
  if (!dsn) return false;
  if (!initialized) {
    Sentry.init({
      dsn,
      environment: Deno.env.get("DENO_DEPLOYMENT_ID") ? "production" : "development",
      // Errors only — no perf tracing in short-lived edge isolates.
      tracesSampleRate: 0,
    });
    initialized = true;
  }
  return true;
}

/**
 * Report an error with context. `fn` becomes a searchable tag; `userId`
 * (when present) attaches the affected athlete. Always console.errors so
 * Supabase logs keep working even without a DSN.
 */
export function captureException(
  error: unknown,
  context: { fn: string; userId?: string | null } & Record<string, unknown>,
): void {
  console.error(`[${context.fn}] captured error:`, error);
  if (!ensureInit()) return;
  try {
    Sentry.withScope((scope) => {
      scope.setTag("function", context.fn);
      if (typeof context.userId === "string" && context.userId.length > 0) {
        scope.setUser({ id: context.userId });
      }
      const { fn: _fn, userId: _uid, ...rest } = context;
      if (Object.keys(rest).length > 0) scope.setContext("edge", rest);
      Sentry.captureException(error);
    });
  } catch (reportErr) {
    // Error tracking must never take the function down with it.
    console.error("[sentry] captureException failed:", reportErr);
  }
}

/**
 * Flush pending events before the isolate freezes. Bounded; never throws;
 * instant no-op when Sentry isn't configured.
 */
export async function flushSentry(timeoutMs = 2000): Promise<void> {
  if (!initialized) return;
  try {
    await Sentry.flush(timeoutMs);
  } catch {
    // Never block or fail the response over telemetry.
  }
}

/**
 * Wrap a Deno.serve handler so uncaught throws are captured, flushed, and
 * turned into a JSON 500 instead of an opaque runtime error.
 */
export function withSentry(
  fnName: string,
  handler: (req: Request) => Promise<Response> | Response,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    try {
      return await handler(req);
    } catch (error) {
      captureException(error, { fn: fnName, method: req.method });
      await flushSentry();
      return new Response(
        JSON.stringify({ error: "Internal error" }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
  };
}

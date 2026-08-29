import { NextResponse } from "next/server";
import { z } from "zod";

import { enforceRateLimit } from "@/lib/rate-limit";

/**
 * Beta invite requests from the public /beta page.
 *
 * Deliberately storage-free: no table, no migration, no RLS surface. The
 * request is validated here and forwarded to whatever list tool is wired up
 * via BETA_INVITE_WEBHOOK_URL (ConvertKit, MailerLite, a Zap, an inbox
 * relay). If nothing is configured the route says so plainly and the form
 * falls back to email, rather than silently swallowing a signup.
 */

const RequestSchema = z.object({
  email: z.string().trim().email().max(254),
  race: z.string().trim().max(200).optional().default(""),
  recent: z.string().trim().max(200).optional().default(""),
  mileage: z
    .enum(["under-20", "20-40", "40-60", "60-plus"])
    .optional()
    .default("20-40"),
  coaching: z
    .enum(["self-coached", "have-a-coach", "i-coach"])
    .optional()
    .default("self-coached"),
});

function clientKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  const ip = forwarded?.split(",")[0]?.trim() || "unknown";
  return `${ip}:beta-invite`;
}

export async function POST(request: Request) {
  const rateLimited = await enforceRateLimit(clientKey(request), 5, 600_000);
  if (rateLimited) return rateLimited;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const parsed = RequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid_request", issues: parsed.error.flatten().fieldErrors },
      { status: 400 },
    );
  }

  const webhook = process.env.BETA_INVITE_WEBHOOK_URL;
  if (!webhook) {
    // Honest 503 — the UI shows the email fallback rather than pretending
    // the request landed somewhere.
    return NextResponse.json({ error: "not_configured" }, { status: 503 });
  }

  try {
    const res = await fetch(webhook, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...parsed.data,
        source: "web/beta",
        requested_at: new Date().toISOString(),
      }),
    });

    if (!res.ok) {
      return NextResponse.json({ error: "upstream_failed" }, { status: 502 });
    }
  } catch {
    return NextResponse.json({ error: "upstream_failed" }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}

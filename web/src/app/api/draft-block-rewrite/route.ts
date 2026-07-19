import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enforceRateLimit } from "@/lib/rate-limit";
import { SUPABASE_SERVICE_ROLE_KEY } from "@/lib/env.server";
import { z } from "zod";

// Coach asks the AI to DRAFT a mid-block rewrite of an athlete's live plan
// (R5 assisted rewrite, Phase E). This route authenticates the coach,
// resolves their coach_profiles.id, and forwards to the `draft-block-rewrite`
// edge function with the service-role key — the same trust boundary as
// /api/rewrite-block → rewrite-block.
//
// PROPOSAL ONLY. The edge function never writes to scheduled_workouts or
// plan_adjustments; the coach reviews the returned diff, stages accepted
// changes into the live-plan editor, and applies through the EXISTING
// /api/rewrite-block path (which owns validation, race-week confirm, and
// the audit ledger). AI advises, never acts.

const workoutSchema = z.object({
  scheduledWorkoutId: z.string().uuid(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date must be YYYY-MM-DD"),
  weekNumber: z.number().int().positive(),
  dayOfWeek: z.number().int().min(1).max(7),
  workoutType: z.string().min(1),
  name: z.string().max(200).optional(),
  miles: z.number().nonnegative().optional(),
});

const draftBlockSchema = z.object({
  athleteUserId: z.string().min(1, "athleteUserId is required"),
  planId: z.string().uuid("Invalid plan ID"),
  weekRange: z.object({
    fromWeek: z.number().int().positive(),
    toWeek: z.number().int().positive(),
  }).refine((r) => r.toWeek >= r.fromWeek, {
    message: "toWeek must be >= fromWeek",
  }),
  workouts: z.array(workoutSchema).min(1, "The block has no workouts to draft against"),
  request: z.string().min(1, "Describe the change you want").max(600),
});

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  // Per-coach burst guard; the once-per-athlete-per-day budget lives in the
  // edge function (draft_rewrite bucket, keyed on the athlete).
  const rateLimited = await enforceRateLimit(`${user.id}:draft-block-rewrite`, 5, 60_000);
  if (rateLimited) return rateLimited;

  // Resolve the caller's coach profile — only a coach may draft a rewrite.
  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!coachProfile) {
    return NextResponse.json({ error: "Not a coach" }, { status: 403 });
  }

  const parsed = draftBlockSchema.safeParse(await request.json());
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten().fieldErrors },
      { status: 400 },
    );
  }
  const b = parsed.data;

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/draft-block-rewrite`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        apikey: SUPABASE_SERVICE_ROLE_KEY,
      },
      body: JSON.stringify({
        coachId: coachProfile.id,
        athleteUserId: b.athleteUserId,
        planId: b.planId,
        weekRange: b.weekRange,
        workouts: b.workouts,
        request: b.request,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      // Pass through structured rejection signals (draft_validation_failed
      // violations, 429 budget) so the panel can render them.
      return NextResponse.json(
        {
          error: data.error || "Draft failed",
          code: data.code,
          violations: data.violations,
          resetAt: data.resetAt,
        },
        { status: res.status },
      );
    }
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json(
      { error: "Failed to draft the rewrite", details: String(err) },
      { status: 500 },
    );
  }
}

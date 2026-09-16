import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enforceRateLimit } from "@/lib/rate-limit";
import { serviceRoleKey } from "@/lib/env.server";
import { z } from "zod";

// Coach applies a manual mid-block rewrite to an athlete's LIVE plan (R5,
// Phase B). This route authenticates the coach, resolves their
// coach_profiles.id, and forwards to the `rewrite-block` edge function with
// the service-role key — the same trust boundary as assign-plan →
// subscribe-to-plan. The edge function re-verifies ownership; identity is
// never taken from the client.

const changeSchema = z.object({
  scheduledWorkoutId: z.string().uuid().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date must be YYYY-MM-DD"),
  weekNumber: z.number().int().positive(),
  workoutType: z.string().min(1, "workoutType is required"),
  workoutData: z.unknown().optional(),
  notes: z.string().max(2000).nullable().optional(),
});

const rewriteBlockSchema = z.object({
  athleteUserId: z.string().min(1, "athleteUserId is required"),
  planId: z.string().uuid("Invalid plan ID"),
  weekRange: z.object({
    fromWeek: z.number().int().positive(),
    toWeek: z.number().int().positive(),
  }).refine((r) => r.toWeek >= r.fromWeek, {
    message: "toWeek must be >= fromWeek",
  }),
  changes: z.array(changeSchema).min(1, "At least one change is required"),
  reasonCode: z.enum([
    "sickness",
    "injury_niggle",
    "race_change",
    "life_event",
    "performance",
    "other",
  ]),
  reasonText: z.string().max(280).optional(),
  confirmRaceWeek: z.boolean().optional(),
});

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rateLimited = await enforceRateLimit(`${user.id}:rewrite-block`, 20, 60_000);
  if (rateLimited) return rateLimited;

  // Resolve the caller's coach profile — only a coach may rewrite a plan.
  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!coachProfile) {
    return NextResponse.json({ error: "Not a coach" }, { status: 403 });
  }

  const parsed = rewriteBlockSchema.safeParse(await request.json());
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten().fieldErrors },
      { status: 400 },
    );
  }
  const b = parsed.data;

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/rewrite-block`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${serviceRoleKey()}`,
        apikey: serviceRoleKey(),
      },
      body: JSON.stringify({
        coachId: coachProfile.id,
        athleteUserId: b.athleteUserId,
        planId: b.planId,
        weekRange: b.weekRange,
        changes: b.changes,
        reasonCode: b.reasonCode,
        reasonText: b.reasonText ?? null,
        confirmRaceWeek: b.confirmRaceWeek ?? false,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      // Pass through the race-week confirm signal so the UI can prompt.
      return NextResponse.json(
        { error: data.error || "Rewrite failed", code: data.code },
        { status: res.status },
      );
    }
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json(
      { error: "Failed to rewrite block", details: String(err) },
      { status: 500 },
    );
  }
}

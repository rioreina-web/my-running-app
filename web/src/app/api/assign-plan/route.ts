import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enforceRateLimit } from "@/lib/rate-limit";
import { z } from "zod";

const assignPlanSchema = z.object({
  planTemplateId: z.string().uuid("Invalid plan template ID"),
  athleteUserId: z.string().uuid("Invalid athlete user ID"),
  startDate: z.string().min(1, "Start date is required"),
  raceDate: z.string().nullable().optional(),
});

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rateLimited = await enforceRateLimit(`${user.id}:assign-plan`, 10, 60_000);
  if (rateLimited) return rateLimited;

  const parsed = assignPlanSchema.safeParse(await request.json());
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid input", details: parsed.error.flatten().fieldErrors }, { status: 400 });
  }
  const { planTemplateId, athleteUserId, startDate, raceDate } = parsed.data;

  // Forward the coach's OWN session token (same pattern as shift-day). The
  // edge function authorizes on the JWT subject: it verifies the caller is
  // the athlete or a coach with an active relationship to them. The previous
  // service-role bearer had no `sub`, so the function rejected every call —
  // and had it accepted the key, this route would have let any signed-in
  // user assign plans to any athlete, because nothing here checks that.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/subscribe-to-plan`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({
        planTemplateId,
        athleteUserId,
        startDate,
        raceDate: raceDate || null,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json({ error: data.error || "Assignment failed" }, { status: res.status });
    }

    return NextResponse.json(data);
  } catch (err) {
    console.error("[assign-plan] upstream call failed:", err);
    return NextResponse.json({ error: "Failed to assign plan" }, { status: 500 });
  }
}

import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enforceRateLimit } from "@/lib/rate-limit";
import { SUPABASE_SERVICE_ROLE_KEY } from "@/lib/env.server";
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

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/subscribe-to-plan`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        apikey: SUPABASE_SERVICE_ROLE_KEY,
      },
      body: JSON.stringify({
        planTemplateId,
        athleteUserId,
        startDate,
        raceDate: raceDate || null,
        assignedBy: user.id,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json({ error: data.error || "Assignment failed" }, { status: res.status });
    }

    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json({ error: "Failed to assign plan", details: String(err) }, { status: 500 });
  }
}

import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { fetchVitalStream } from "@/lib/vital";
import { enforceRateLimit } from "@/lib/rate-limit";
import { z } from "zod";

const querySchema = z.object({
  id: z.string().min(1, "Workout ID is required"),
});

export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rateLimited = await enforceRateLimit(`${user.id}:vital-stream`, 60, 60_000);
  if (rateLimited) return rateLimited;

  const parsed = querySchema.safeParse({ id: request.nextUrl.searchParams.get("id") });
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid input", details: parsed.error.flatten().fieldErrors }, { status: 400 });
  }
  const workoutId = parsed.data.id;

  // Ownership check: the workout ID must map to a training_logs row owned by
  // the caller. Without this, any authenticated user could pass another
  // athlete's vital_workout_id and pull their per-second GPS (home address)
  // + heart rate via the shared server-side Vital key. RLS on training_logs
  // already scopes this select to the caller; the explicit user_id filter is
  // defense in depth.
  const { data: ownedWorkout, error: ownershipError } = await supabase
    .from("training_logs")
    .select("id")
    .eq("vital_workout_id", workoutId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (ownershipError) {
    return NextResponse.json({ error: "Failed to verify workout" }, { status: 500 });
  }
  if (!ownedWorkout) {
    // 404, not 403 — don't confirm the ID exists for someone else.
    return NextResponse.json({ error: "Workout not found" }, { status: 404 });
  }

  const data = await fetchVitalStream(workoutId);
  if (!data) {
    return NextResponse.json({ error: "Failed to fetch data" }, { status: 500 });
  }

  return NextResponse.json(data);
}

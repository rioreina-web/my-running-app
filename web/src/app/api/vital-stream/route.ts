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

  const data = await fetchVitalStream(workoutId);
  if (!data) {
    return NextResponse.json({ error: "Failed to fetch data" }, { status: 500 });
  }

  return NextResponse.json(data);
}

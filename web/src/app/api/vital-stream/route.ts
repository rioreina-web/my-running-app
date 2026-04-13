import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { fetchVitalStream } from "@/lib/vital";
import { checkRateLimit } from "@/lib/rate-limit";

export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rl = checkRateLimit(`${user.id}:vital-stream`, 30, 60_000);
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const workoutId = request.nextUrl.searchParams.get("id");
  if (!workoutId) {
    return NextResponse.json({ error: "Missing workout id" }, { status: 400 });
  }

  const data = await fetchVitalStream(workoutId);
  if (!data) {
    return NextResponse.json({ error: "Failed to fetch data" }, { status: 500 });
  }

  return NextResponse.json(data);
}

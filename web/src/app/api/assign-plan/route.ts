import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { checkRateLimit } from "@/lib/rate-limit";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rl = checkRateLimit(`${user.id}:assign-plan`, 10, 60_000);
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const { planTemplateId, athleteUserId, startDate, raceDate } = await request.json();

  if (!planTemplateId || !athleteUserId || !startDate) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/subscribe-to-plan`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        apikey: SUPABASE_ANON_KEY,
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

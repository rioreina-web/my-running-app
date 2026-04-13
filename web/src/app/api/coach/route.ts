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

  const rl = checkRateLimit(`${user.id}:coach`, 20, 60_000);
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const body = await request.json();
  const { message, conversationId } = body;

  if (!message) {
    return NextResponse.json({ error: "Message required" }, { status: 400 });
  }

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/coaching-agent`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        apikey: SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        userId: user.id,
        message,
        conversationId: conversationId || undefined,
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      return NextResponse.json(
        { error: `Edge function error: ${res.status}`, details: text },
        { status: res.status }
      );
    }

    const data = await res.json();
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json(
      { error: "Failed to reach coaching agent", details: String(err) },
      { status: 500 }
    );
  }
}

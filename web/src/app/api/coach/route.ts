import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enforceRateLimit } from "@/lib/rate-limit";
import { SUPABASE_SERVICE_ROLE_KEY } from "@/lib/env.server";
import { z } from "zod";

const coachSchema = z.object({
  message: z.string().min(1, "Message is required").max(2000, "Message too long"),
  conversationId: z.string().uuid().optional(),
});

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rateLimited = await enforceRateLimit(`${user.id}:coach`, 20, 60_000);
  if (rateLimited) return rateLimited;

  const parsed = coachSchema.safeParse(await request.json());
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid input", details: parsed.error.flatten().fieldErrors }, { status: 400 });
  }
  const { message, conversationId } = parsed.data;

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/coaching-agent`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        apikey: SUPABASE_SERVICE_ROLE_KEY,
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

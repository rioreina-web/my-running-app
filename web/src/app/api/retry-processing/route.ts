import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { enforceRateLimit } from "@/lib/rate-limit";
import { SUPABASE_SERVICE_ROLE_KEY } from "@/lib/env.server";
import { z } from "zod";

const retrySchema = z.object({
  logId: z.string().uuid("Invalid log ID"),
});

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const rateLimited = await enforceRateLimit(`${user.id}:retry-processing`, 5, 60_000);
  if (rateLimited) return rateLimited;

  const parsed = retrySchema.safeParse(await request.json());
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid input", details: parsed.error.flatten().fieldErrors }, { status: 400 });
  }
  const { logId } = parsed.data;

  // Get the training log to find the audio URL
  const { data: log, error: fetchError } = await supabase
    .from("training_logs")
    .select("id, audio_url, user_id")
    .eq("id", logId)
    .eq("user_id", user.id)
    .single();

  if (fetchError || !log?.audio_url) {
    return NextResponse.json({ error: "Log not found or no audio" }, { status: 404 });
  }

  // Reset processing status
  await supabase
    .from("training_logs")
    .update({ processing_status: "pending", processing_error: null, processing_attempts: 0 })
    .eq("id", logId);

  // Trigger reprocessing
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/process-training-memo`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        apikey: SUPABASE_SERVICE_ROLE_KEY,
      },
      body: JSON.stringify({
        type: "INSERT",
        table: "training_logs",
        schema: "public",
        record: { id: log.id, audio_url: log.audio_url },
      }),
    });

    const data = await res.json();
    return NextResponse.json(data);
  } catch (err) {
    return NextResponse.json({ error: "Processing failed", details: String(err) }, { status: 500 });
  }
}

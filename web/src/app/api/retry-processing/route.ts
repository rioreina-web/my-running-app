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

  const rl = checkRateLimit(`${user.id}:retry-processing`, 10, 60_000);
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const { logId } = await request.json();
  if (!logId) {
    return NextResponse.json({ error: "Missing logId" }, { status: 400 });
  }

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
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        apikey: SUPABASE_ANON_KEY,
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

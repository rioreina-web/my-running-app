"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Coach lifecycle actions for a coachable_moment. The DB trigger
// `set_coachable_moment_handled_at` stamps `handled_at` automatically when
// `status` leaves `'open'`, and RLS gates updates to the coach who owns
// the moment, so these actions are intentionally thin.

async function transitionStatus(
  momentId: string,
  next: "handled" | "dismissed"
): Promise<{ ok: true } | { ok: false; error: string }> {
  const supabase = await createClient();
  const { error } = await supabase
    .from("coachable_moments")
    .update({ status: next })
    .eq("id", momentId)
    .eq("status", "open"); // idempotent — only fires the lifecycle trigger once
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

export async function handleMomentAction(momentId: string, athleteId: string) {
  const result = await transitionStatus(momentId, "handled");
  if (result.ok) revalidatePath(`/coach-portal/athletes/${athleteId}`);
  return result;
}

export async function dismissMomentAction(momentId: string, athleteId: string) {
  const result = await transitionStatus(momentId, "dismissed");
  if (result.ok) revalidatePath(`/coach-portal/athletes/${athleteId}`);
  return result;
}

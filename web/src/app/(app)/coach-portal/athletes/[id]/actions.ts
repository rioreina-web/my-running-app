"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

// Mirror the DB CHECK constraints (20260716140000) so the UI and server agree.
const NAME_MAX = 80;
const BIO_MAX = 600;

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

/**
 * Save an athlete's profile (display name + bio) to athlete_settings.
 *
 * Security: athlete_settings has no coach write policy (owner + service_role
 * only), so the write goes through the service-role admin client. That means
 * this action MUST gate access itself — it verifies the caller is a coach who
 * owns a plan the athlete is actively subscribed to, exactly the gate the
 * detail page uses, before touching the row. Never widen this without keeping
 * the gate.
 */
export async function updateAthleteProfileAction(
  athleteId: string,
  input: { displayName: string; bio: string }
): Promise<{ ok: true } | { ok: false; error: string }> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: "Not signed in." };

  // 1. Caller must be a coach.
  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!coachProfile) return { ok: false, error: "Coach profile not found." };

  // 2. Coach must own an active subscription with this athlete (same gate as
  //    the page — scoped through plan_templates.coach_id via RLS).
  const { data: gateRow } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id)")
    .eq("athlete_user_id", athleteId)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachProfile.id)
    .limit(1)
    .maybeSingle();
  if (!gateRow) return { ok: false, error: "You do not coach this athlete." };

  // 3. Normalize input. Empty string clears the field (stored as NULL).
  const displayName = input.displayName.trim().slice(0, NAME_MAX) || null;
  const bio = input.bio.trim().slice(0, BIO_MAX) || null;

  // 4. Upsert on the athlete's settings row (user_id is UNIQUE). Only the
  //    profile fields are written — timezone/location and other settings on
  //    the row are left untouched. Service-role client bypasses RLS, so the
  //    explicit user_id scope above is what keeps this to one athlete.
  const admin = createAdminClient();
  const { error } = await admin
    .from("athlete_settings")
    .upsert(
      { user_id: athleteId, display_name: displayName, bio },
      { onConflict: "user_id" }
    );
  if (error) return { ok: false, error: error.message };

  // Refresh both the detail page and the roster so the name updates everywhere.
  revalidatePath(`/coach-portal/athletes/${athleteId}`);
  revalidatePath("/coach-portal/athletes");
  return { ok: true };
}

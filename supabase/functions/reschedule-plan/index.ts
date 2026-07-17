import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

import { corsHeaders } from "../_shared/cors.ts";
// ── Workout Library (same source of truth as generate-training-plan) ──

const WORKOUT_CODES_BY_DAY = `
=== TUESDAY (Speed/Quality) ===
Fartlek 105%: RSS_1 8x3' | RSS_2 6x6' | RSS_3 12x2' | RSS_4 10x3' | RSS_4b 10x3'/3' | FARTLEK 8x3'/2'
Track 110%: RSPS_1 12x400m | RSPS_2 8x800m | RSPS_3 3x4x800m | RSPS_4 12x600m | RSPS_5 8x1km | RSPS_6 5xmi | RSPS_7 6x1200m | RSPS_8 3x4x800m@108%
Speed 105-107%: RSS_5 10x800m@107% | RSS_6 10x1km@107% | RSS_7 6xmi@107% | RSS_8 3x2mi@106% | RSS_9 12x1km@106% | RSS_10 8xmi@105% | RSS_14 3x2mi@105% | RSS_15 2x4mi@105% | RSS_16 6xmi@105% | RSS_17 4xmi@105% | RSS_18 2x3mi@105%
Tempo/Cutdown: RSS_11 3/2/1mi cutdown | RSS_12 2x3mi@104%
Progression: RSS_13 7mi 97>105% | RSS_19 7mi 97>103% | GE_7 1hr 80>90% | GE_8 90min 80>90%
Hill/Speed 115%: GS_1 12x200m | GS_2 12x300m | GS_3 10x400m | GS_4 12x400m | GS_5 hill sprints 10s | GS_7 hill sprints 15s

=== THURSDAY (Moderate — restricted set) ===
ONLY use: GE_1 10mi@85% | GE_2 12mi@85% | BE_1 10mi@80% | BE_2 12mi@80% | GE_7 1hr progression | GS_5 hill sprints | GS_7 hill sprints

=== SATURDAY (Long Run) ===
Easy 80%: BE_1 10mi | BE_2 12mi | BE_3 15mi | BE_4 18mi | BE_5 20mi | BE_6 22mi | BE_7 24mi | BE_8 2hr hills
Moderate 85%: GE_1 10mi | GE_2 12mi | GE_3 15mi | GE_4 18mi | GE_5 20mi | GE_6 22mi
Progression: GE_7 1hr | GE_8 90min | GE_9 2hr | GE_10 20mi 80>90%
Steady 90%: RSE_1 8mi | RSE_2 10mi | RSE_3 12mi | RSE_4 15mi | RSE_5 18mi | RSE_6 20mi prog 85>92%
Alternation 90%: RSE_7 10x1km | RSE_8 8x1mi | RSE_9 20mi 85>95% | RSE_10 15mi@90-95%
Race-Specific 95%: RCE_1 10mi | RCE_2 12mi | RCE_3 15mi | RCE_4 18mi 90>95% | RCE_5 4x3mi | RCE_6 4x4mi | RCE_7 5x3mi | RCE_8 15k/10k/5k
MP 100%: RP_1 10mi | RP_2 12mi | RP_3 10x1mi | RP_4 5x2mi | RP_5 6x2mi | RP_6 4x3mi | RP_7 5x3mi | RP_8 2x5mi | RP_9 3x5mi | RP_10 2x6mi

=== SPECIAL ===
EASY: Easy Run (70-75%)
REST: Rest Day
STRIDES: Easy Run + 4-6x100m strides (115%)
RACE: Race Day (DO NOT MOVE)
`;

// ── Coach AI guidance (Phase 2) ─────────────────────────────────
//
// Hard rules / guidelines / silent note the coach attached to the plan. Read
// server-side with the service role and NEVER accepted from the client — the
// athlete who triggers a reschedule can't read plan_templates under RLS, and
// guidance must stay authoritative. Best-effort: any failure (or the column
// not existing yet, pre-migration) resolves to "" so a reschedule never breaks.

interface CoachRule {
  on?: boolean;
  strength?: "hard" | "guide";
  text?: string;
}

/** Format the stored { rules, note } envelope into the prompt block. Returns
 *  "" when there's nothing to say (the v2 template reads fine either way). */
function formatCoachGuidance(raw: unknown): string {
  if (!raw || typeof raw !== "object") return "";
  const g = raw as { rules?: unknown; note?: unknown };
  const rules: CoachRule[] = Array.isArray(g.rules) ? (g.rules as CoachRule[]) : [];
  const active = rules.filter(
    (r) => r && r.on !== false && typeof r.text === "string" && r.text.trim().length > 0,
  );
  const hard = active.filter((r) => r.strength !== "guide");
  const guides = active.filter((r) => r.strength === "guide");
  const note = typeof g.note === "string" ? g.note.trim() : "";

  if (hard.length === 0 && guides.length === 0 && note === "") return "";

  const lines: string[] = ["COACH GUIDANCE (set by this athlete's coach for this plan):"];
  for (const r of hard) lines.push(`- MUST: ${r.text!.trim()}`);
  for (const r of guides) lines.push(`- Prefer: ${r.text!.trim()}`);
  if (note) lines.push(`Silent context (never quote or reference to the athlete): ${note}`);
  return lines.join("\n") + "\n\n";
}

async function loadCoachGuidance(userId: string): Promise<string> {
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return "";
    const admin = createClient(url, key);

    const { data: sub } = await admin
      .from("athlete_plan_subscriptions")
      .select("plan_template_id")
      .eq("athlete_user_id", userId)
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const templateId = (sub as { plan_template_id?: string } | null)?.plan_template_id;
    if (!templateId) return "";

    const { data: tmpl, error } = await admin
      .from("plan_templates")
      .select("coach_ai_guidance")
      .eq("id", templateId)
      .maybeSingle();
    if (error || !tmpl) return "";

    return formatCoachGuidance((tmpl as { coach_ai_guidance?: unknown }).coach_ai_guidance);
  } catch (_e) {
    return "";
  }
}

// ── Handler ─────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) return unauthorizedResponse(corsHeaders);

    const rlBlocked = await enforceFeatureRateLimit(userId, "reschedule", corsHeaders);
    if (rlBlocked) return rlBlocked;

    const body = await req.json();
    const { scope, reason, reasonCategory, plan, workouts, recentHistory } = body;

    if (!scope || !plan || !workouts?.length) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: scope, plan, workouts" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Build the user prompt with full context
    const userPrompt = buildUserPrompt(scope, reason, reasonCategory, plan, workouts, recentHistory);

    // Resolve the coach's guidance for this athlete's active plan and fold it
    // into the v2 system prompt (empty string when there's none).
    const coachGuidance = await loadCoachGuidance(userId);
    const systemPrompt = loadPrompt("reschedule-plan.v2", {
      workoutCodesByDay: WORKOUT_CODES_BY_DAY,
      coachGuidance,
    });

    // Call Gemini
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    const result = await model.generateContent({
      contents: [
        { role: "user", parts: [{ text: systemPrompt }] },
        { role: "model", parts: [{ text: "I understand. I'm ready to reschedule training plans. Send me the athlete's current schedule and the reason for rescheduling." }] },
        { role: "user", parts: [{ text: userPrompt }] },
      ],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 4096,
      },
    });

    const responseText = result.response.text();

    // Parse the reschedule data
    const rescheduleData = extractRescheduleData(responseText);
    const message = getConversationalMessage(responseText);

    if (!rescheduleData) {
      return new Response(
        JSON.stringify({
          success: false,
          message: message || "I couldn't generate a reschedule. Could you provide more details about what you need?",
          changes: [],
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message,
        changes: rescheduleData.changes || [],
        summary: rescheduleData.summary || "",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Reschedule error:", error);
    return new Response(
      JSON.stringify({ error: "Failed to reschedule. Please try again.", details: String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// ── Build User Prompt ───────────────────────────────────────────

function buildUserPrompt(
  scope: string,
  reason: string,
  reasonCategory: string,
  plan: Record<string, unknown>,
  workouts: Array<Record<string, unknown>>,
  recentHistory?: Array<Record<string, unknown>>
): string {
  const lines: string[] = [];

  lines.push(`RESCHEDULE REQUEST`);
  lines.push(`Scope: ${scope}`);
  lines.push(`Reason category: ${reasonCategory}`);
  lines.push(`Athlete's explanation: "${reason}"`);
  lines.push(``);

  lines.push(`PLAN OVERVIEW`);
  lines.push(`Name: ${plan.name}`);
  lines.push(`Target: ${plan.targetRaceDistance}`);
  lines.push(`Goal time: ${plan.targetTimeSeconds ? formatTime(plan.targetTimeSeconds as number) : "none"}`);
  lines.push(`Start: ${plan.startDate}, End: ${plan.endDate}`);
  lines.push(`Total weeks: ${plan.totalWeeks}, Current week: ${plan.currentWeek}`);
  lines.push(``);

  // Recent history
  if (recentHistory?.length) {
    lines.push(`RECENT TRAINING (last 14 days):`);
    for (const h of recentHistory) {
      const dist = h.distanceMiles ? ` (${(h.distanceMiles as number).toFixed(1)}mi)` : "";
      lines.push(`  ${h.date} — ${h.workoutType} [${h.status}]${dist}`);
    }
    lines.push(``);
  }

  // Current schedule
  lines.push(`CURRENT SCHEDULE (workouts in scope):`);
  const dayNames = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  for (const w of workouts) {
    const day = dayNames[w.dayOfWeek as number] || "?";
    const code = w.workoutCode || w.workoutType;
    const dist = w.totalDistanceMiles ? ` ${(w.totalDistanceMiles as number).toFixed(1)}mi` : "";
    const name = w.workoutName ? ` — ${w.workoutName}` : "";
    lines.push(`  Wk${w.weekNumber} ${day} ${w.date} | ${code}${name}${dist} [${w.status}]`);
  }
  lines.push(``);

  lines.push(`Reschedule the ${scope === "day" ? "single day" : scope === "week" ? "this week's workouts" : "remaining scheduled workouts"} based on the reason above. Only output CHANGED workouts.`);

  return lines.join("\n");
}

// ── Helpers ─────────────────────────────────────────────────────

function extractRescheduleData(text: string): Record<string, unknown> | null {
  const s = text.indexOf("<<<RESCHEDULE>>>");
  const e = text.indexOf("<<<END_RESCHEDULE>>>");
  if (s === -1 || e === -1 || e <= s) return null;

  let json = text.substring(s + "<<<RESCHEDULE>>>".length, e).trim();
  const cb = json.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (cb) json = cb[1].trim();

  try {
    return JSON.parse(json);
  } catch {
    // Try fixing common JSON issues
    try {
      json = json.replace(/,\s*}/g, "}").replace(/,\s*]/g, "]");
      return JSON.parse(json);
    } catch {
      console.error("Failed to parse reschedule JSON:", json.substring(0, 200));
    }
  }
  return null;
}

function getConversationalMessage(text: string): string {
  const s = text.indexOf("<<<RESCHEDULE>>>");
  const e = text.indexOf("<<<END_RESCHEDULE>>>");
  if (s !== -1 && e !== -1) {
    return (text.substring(0, s).trim() + " " + text.substring(e + "<<<END_RESCHEDULE>>>".length).trim()).trim();
  }
  return text;
}

function formatTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * draft-block-rewrite — AI-drafted PROPOSAL for a coach mid-block rewrite.
 *
 * Phase E of outputs/adaptive-coach-plan-builder-spec-2026-07-03.md (R5
 * assisted rewrite). Deliberately a SEPARATE function from the apply path:
 * `rewrite-block` writes, this one only proposes. It never touches
 * `scheduled_workouts` or `plan_adjustments` — the coach reviews the diff in
 * the live-plan editor, stages accepted changes into the editor state, and
 * the EXISTING /api/rewrite-block → rewrite-block path applies them with its
 * validation, race-week confirm, and per-week audit rows. AI advises, never
 * acts.
 *
 * Engine (decision 2026-07-03): constrained library, extending the
 * reschedule-plan closed-selection PATTERN — a closed candidate library
 * (DRAFT_CANDIDATE_LIBRARY below, the coach-portal analogue of
 * WORKOUT_CODES_BY_DAY) plus 'KEEP' and 'REST'. The model selects codes; it
 * never generates workouts. reschedule-plan itself (a golden eval family) is
 * untouched.
 *
 * Contract: POST with the service-role key (called only from the trusted
 * Next.js API route /api/draft-block-rewrite, which authenticates the coach
 * and resolves coachId first — same trust boundary as rewrite-block).
 *
 *   body {
 *     coachId: uuid,                // coach_profiles.id (resolved server-side)
 *     athleteUserId: string,
 *     planId: uuid,
 *     weekRange: { fromWeek: int, toWeek: int },
 *     workouts: Array<{             // the coach's current view of the block
 *       scheduledWorkoutId: uuid,   // verified against the plan server-side
 *       date: "YYYY-MM-DD",
 *       weekNumber: int,
 *       dayOfWeek: int,             // 1=Mon..7=Sun
 *       workoutType: string,
 *       name?: string,
 *       miles?: number
 *     }>,
 *     request: string               // coach's natural-language ask, <= 600 chars
 *   }
 *   200 { ok:true, message, summary, weeks:[...], days:[...] }   — the proposal
 *   400 { error }              — validation / shape problems
 *   401 { error }              — missing/invalid service-role auth
 *   403 { error }              — coach does not own this athlete's plan
 *   422 { error, code:"draft_validation_failed", violations:[...] }
 *                              — the MODEL's draft broke a hard constraint
 *                                (unknown code, mileage out of range,
 *                                race-week touch). Rejected, never surfaced
 *                                as an applyable diff.
 *   429 { error }              — once-per-athlete-per-day draft budget spent
 *   500 { error }
 *
 * Hard validation (all violations reject with 422 — no partial proposals):
 *   1. Every proposed day maps to a known library code or 'KEEP'.
 *   2. Every proposed date is one of the scheduled dates supplied (and each
 *      supplied workout id is verified to belong to the plan).
 *   3. Post-draft week mileage stays inside plan_templates.
 *      weekly_mileage_targets for that week, when targets exist (±0.5 mi
 *      rounding tolerance).
 *   4. Race-week days (within 6 days of plan end_date, or type 'race') are
 *      untouched — mirrored from rewrite-block's guard but as a REJECTION,
 *      not a confirm, unless the coach's request explicitly targets the race
 *      week ("race week", "taper", "final week", ...).
 *
 * Rate limit: once per ATHLETE per day (draft_rewrite bucket, free tier=1),
 * mirroring reschedule-plan's enforceFeatureRateLimit mechanism. Keyed on the
 * athlete so two coaches can't double-spend one athlete's draft budget.
 */
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";

// ── Closed candidate library ─────────────────────────────────────────────
//
// The coach-portal analogue of reschedule-plan's WORKOUT_CODES_BY_DAY, in
// the 10-zone workout-type vocabulary the live-plan editor already speaks
// (CLAUDE.md "Workout labels are pace-zone labels"). `miles` is the
// approximate TOTAL for the day (quality sessions include warmup/cooldown)
// and is what the weekly-mileage validation sums. Keep the formatted block
// in `formatCandidateLibrary()` and the eval cassettes' `candidateLibrary`
// var in sync with this map.

interface Candidate {
  workoutType: string;
  name: string;
  miles: number;
}

export const DRAFT_CANDIDATE_LIBRARY: Record<string, Candidate> = {
  REST: { workoutType: "rest", name: "Rest", miles: 0 },
  XT_45: { workoutType: "cross_train", name: "Cross-train 45 min", miles: 0 },
  // Recovery / easy
  REC_3: { workoutType: "recovery", name: "Recovery 3 mi", miles: 3 },
  REC_4: { workoutType: "recovery", name: "Recovery 4 mi", miles: 4 },
  EZ_3: { workoutType: "easy", name: "Easy 3 mi", miles: 3 },
  EZ_4: { workoutType: "easy", name: "Easy 4 mi", miles: 4 },
  EZ_5: { workoutType: "easy", name: "Easy 5 mi", miles: 5 },
  EZ_6: { workoutType: "easy", name: "Easy 6 mi", miles: 6 },
  EZ_8: { workoutType: "easy", name: "Easy 8 mi", miles: 8 },
  EZ_10: { workoutType: "easy", name: "Easy 10 mi", miles: 10 },
  STR_5: { workoutType: "easy", name: "Easy 5 mi + 4-6×100m strides", miles: 5 },
  // Moderate / steady aerobic
  MOD_5: { workoutType: "moderate", name: "Moderate 5 mi", miles: 5 },
  MOD_6: { workoutType: "moderate", name: "Moderate 6 mi", miles: 6 },
  MOD_8: { workoutType: "moderate", name: "Moderate 8 mi", miles: 8 },
  STY_5: { workoutType: "steady", name: "Steady 5 mi", miles: 5 },
  STY_6: { workoutType: "steady", name: "Steady 6 mi", miles: 6 },
  STY_8: { workoutType: "steady", name: "Steady 8 mi", miles: 8 },
  // Long runs
  LONG_10: { workoutType: "long_run", name: "Long 10 mi", miles: 10 },
  LONG_12: { workoutType: "long_run", name: "Long 12 mi", miles: 12 },
  LONG_14: { workoutType: "long_run", name: "Long 14 mi", miles: 14 },
  LONG_16: { workoutType: "long_run", name: "Long 16 mi", miles: 16 },
  LONG_18: { workoutType: "long_run", name: "Long 18 mi", miles: 18 },
  LONG_20: { workoutType: "long_run", name: "Long 20 mi", miles: 20 },
  LONGWO_12: { workoutType: "long_wo", name: "Long 12 mi w/ work", miles: 12 },
  LONGWO_14: { workoutType: "long_wo", name: "Long 14 mi w/ work", miles: 14 },
  LONGWO_16: { workoutType: "long_wo", name: "Long 16 mi w/ work", miles: 16 },
  // Race-pace (totals include ~2 mi warmup/cooldown)
  MP_5: { workoutType: "mp", name: "MP 5 mi", miles: 7 },
  MP_6: { workoutType: "mp", name: "MP 6 mi", miles: 8 },
  MP_7: { workoutType: "mp", name: "MP 7 mi", miles: 9 },
  MP_8: { workoutType: "mp", name: "MP 8 mi", miles: 10 },
  HMP_4: { workoutType: "hmp", name: "HMP 4 mi", miles: 6 },
  HMP_5: { workoutType: "hmp", name: "HMP 5 mi", miles: 7 },
  HMP_6: { workoutType: "hmp", name: "HMP 6 mi", miles: 8 },
  LT_3: { workoutType: "lt", name: "LT 3 mi", miles: 5 },
  LT_4: { workoutType: "lt", name: "LT 4 mi", miles: 6 },
  LT_5: { workoutType: "lt", name: "LT 5 mi", miles: 7 },
  LT_6: { workoutType: "lt", name: "LT 6 mi", miles: 8 },
  TENK_5X1K: { workoutType: "10k", name: "10K 5×1km", miles: 6 },
  TENK_6X1K: { workoutType: "10k", name: "10K 6×1km", miles: 7 },
  FIVEK_5X1K: { workoutType: "5k", name: "5K 5×1km", miles: 6 },
  FIVEK_6X800: { workoutType: "5k", name: "5K 6×800", miles: 6 },
  THREEK_4X800: { workoutType: "3k", name: "3K 4×800", miles: 5 },
  THREEK_8X400: { workoutType: "3k", name: "3K 8×400", miles: 5 },
  MILE_8X400: { workoutType: "mile", name: "Mile 8×400", miles: 5 },
};

export function formatCandidateLibrary(): string {
  return `KEEP — leave the day exactly as scheduled (unlisted days are kept anyway)
REST — full rest day (0 mi)
XT_45 — 45 min cross-training, 0 running miles (not counted in running-fitness math)

Recovery/Easy: REC_3 (3mi) | REC_4 (4mi) | EZ_3 | EZ_4 | EZ_5 | EZ_6 | EZ_8 | EZ_10 | STR_5 (easy 5mi + 4-6×100m strides)
Moderate/Steady: MOD_5 | MOD_6 | MOD_8 | STY_5 | STY_6 | STY_8
Long runs: LONG_10 | LONG_12 | LONG_14 | LONG_16 | LONG_18 | LONG_20 (easy-moderate long) | LONGWO_12 | LONGWO_14 | LONGWO_16 (long with embedded quality)
Marathon pace: MP_5 (~7mi total) | MP_6 (~8) | MP_7 (~9) | MP_8 (~10)
Half-marathon pace: HMP_4 (~6) | HMP_5 (~7) | HMP_6 (~8)
Threshold: LT_3 (~5) | LT_4 (~6) | LT_5 (~7) | LT_6 (~8)
10K pace: TENK_5X1K (~6) | TENK_6X1K (~7)
5K pace: FIVEK_5X1K (~6) | FIVEK_6X800 (~6)
3K pace: THREEK_4X800 (~5) | THREEK_8X400 (~5)
Mile pace: MILE_8X400 (~5)`;
}

// ── Request/response shapes ──────────────────────────────────────────────

interface DraftWorkoutInput {
  scheduledWorkoutId?: string;
  date?: string;
  weekNumber?: number;
  dayOfWeek?: number;
  workoutType?: string;
  name?: string;
  miles?: number;
}

interface DraftBlockBody {
  coachId?: string;
  athleteUserId?: string;
  planId?: string;
  weekRange?: { fromWeek?: number; toWeek?: number };
  workouts?: DraftWorkoutInput[];
  request?: string;
}

interface ModelDay {
  date?: string;
  code?: string;
  reason?: string;
}

interface ModelDraft {
  days?: ModelDay[];
  weekReasons?: Array<{ weekNumber?: number; reason?: string }>;
  summary?: string;
}

interface DaySnapshot {
  workoutType: string;
  name: string | null;
  miles: number | null;
}

interface ProposalDay {
  scheduledWorkoutId: string;
  date: string;
  weekNumber: number;
  dayOfWeek: number;
  changed: boolean;
  code: string | null; // library code when changed
  reason: string | null;
  before: DaySnapshot;
  after: DaySnapshot;
}

const DAY_NAMES = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// The coach must EXPLICITLY target the race week for the AI to touch it —
// otherwise touching it is a hard rejection (rewrite-block's confirm guard,
// tightened to a rejection for the AI path).
const RACE_WEEK_INTENT = /\b(race\s*week|race\s*day|taper|final\s+week|last\s+week)\b/i;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function parseLocalDate(s: string): Date {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return new Date(NaN);
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

function raceWeekStartOf(endDate: string | null): string | null {
  if (!endDate) return null;
  const d = parseLocalDate(endDate);
  if (isNaN(d.getTime())) return null;
  d.setDate(d.getDate() - 6);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** Parse plan_templates.weekly_mileage_targets — same tolerant shape as
 * subscribe-to-plan's buildWeekTargets (ramp-tool {targetMilesMin/Max} or
 * legacy single {targetMiles}). Local copy on purpose: subscribe-to-plan
 * doesn't export it and importing across function dirs is off-pattern. */
function parseWeekTargets(raw: unknown): Map<number, { min: number; max: number }> {
  const out = new Map<number, { min: number; max: number }>();
  if (!Array.isArray(raw)) return out;
  for (const entry of raw as Array<Record<string, unknown>>) {
    const wk = entry?.weekNumber;
    if (typeof wk !== "number") continue;
    const min = typeof entry?.targetMilesMin === "number" ? entry.targetMilesMin
      : typeof entry?.targetMiles === "number" ? entry.targetMiles : null;
    const max = typeof entry?.targetMilesMax === "number" ? entry.targetMilesMax
      : typeof entry?.targetMiles === "number" ? entry.targetMiles : null;
    if (min === null || max === null || max <= 0) continue;
    out.set(wk, { min, max });
  }
  return out;
}

function extractDraft(text: string): ModelDraft | null {
  const s = text.indexOf("<<<DRAFT>>>");
  const e = text.indexOf("<<<END_DRAFT>>>");
  if (s === -1 || e === -1 || e <= s) return null;
  let raw = text.substring(s + "<<<DRAFT>>>".length, e).trim();
  const cb = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (cb) raw = cb[1].trim();
  try {
    return JSON.parse(raw) as ModelDraft;
  } catch {
    try {
      raw = raw.replace(/,\s*}/g, "}").replace(/,\s*]/g, "]");
      return JSON.parse(raw) as ModelDraft;
    } catch {
      console.error("draft-block-rewrite: failed to parse draft JSON:", raw.substring(0, 200));
      return null;
    }
  }
}

function proseAround(text: string): string {
  const s = text.indexOf("<<<DRAFT>>>");
  const e = text.indexOf("<<<END_DRAFT>>>");
  if (s !== -1 && e !== -1) {
    return (text.substring(0, s).trim() + " " + text.substring(e + "<<<END_DRAFT>>>".length).trim()).trim();
  }
  return text.trim();
}

// ── Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // Service-role only — the API route authenticates the coach first
  // (same trust boundary as rewrite-block).
  const authFail = requireServiceRole(req, corsHeaders);
  if (authFail) return authFail;

  let body: DraftBlockBody;
  try {
    body = (await req.json()) as DraftBlockBody;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { coachId, athleteUserId, planId } = body;
  const fromWeek = body.weekRange?.fromWeek;
  const toWeek = body.weekRange?.toWeek;
  const request = typeof body.request === "string" ? body.request.trim().slice(0, 600) : "";

  if (!coachId || !athleteUserId || !planId) {
    return json({ error: "Missing required fields: coachId, athleteUserId, planId" }, 400);
  }
  if (
    typeof fromWeek !== "number" || typeof toWeek !== "number" ||
    fromWeek < 1 || toWeek < fromWeek
  ) {
    return json({ error: "weekRange must be { fromWeek, toWeek } with 1 <= fromWeek <= toWeek" }, 400);
  }
  if (request.length === 0) {
    return json({ error: "request (the coach's plain-language ask) is required" }, 400);
  }
  if (!Array.isArray(body.workouts) || body.workouts.length === 0) {
    return json({ error: "workouts must be a non-empty array (the current scheduled block)" }, 400);
  }

  // ── Validate workout shapes; index by date ────────────────────────────
  const byDate = new Map<string, Required<Pick<DraftWorkoutInput, "scheduledWorkoutId" | "date" | "weekNumber" | "dayOfWeek" | "workoutType">> & { name: string | null; miles: number | null }>();
  for (const [i, w] of body.workouts.entries()) {
    if (!w.scheduledWorkoutId || typeof w.scheduledWorkoutId !== "string") {
      return json({ error: `workouts[${i}].scheduledWorkoutId is required` }, 400);
    }
    if (!w.date || !/^\d{4}-\d{2}-\d{2}$/.test(w.date)) {
      return json({ error: `workouts[${i}].date must be YYYY-MM-DD` }, 400);
    }
    if (typeof w.weekNumber !== "number" || w.weekNumber < fromWeek || w.weekNumber > toWeek) {
      return json({ error: `workouts[${i}].weekNumber must fall within weekRange` }, 400);
    }
    if (typeof w.dayOfWeek !== "number" || w.dayOfWeek < 1 || w.dayOfWeek > 7) {
      return json({ error: `workouts[${i}].dayOfWeek must be 1..7 (Mon..Sun)` }, 400);
    }
    if (typeof w.workoutType !== "string" || w.workoutType.length === 0) {
      return json({ error: `workouts[${i}].workoutType is required` }, 400);
    }
    if (byDate.has(w.date)) {
      // Doubles (two sessions on one date) make the date→day mapping
      // ambiguous for the model; those days must be edited manually.
      return json({ error: `workouts contains two entries for ${w.date} — days with doubles must be edited manually` }, 400);
    }
    byDate.set(w.date, {
      scheduledWorkoutId: w.scheduledWorkoutId,
      date: w.date,
      weekNumber: w.weekNumber,
      dayOfWeek: w.dayOfWeek,
      workoutType: w.workoutType,
      name: typeof w.name === "string" && w.name.length > 0 ? w.name : null,
      miles: typeof w.miles === "number" && isFinite(w.miles) && w.miles >= 0 ? w.miles : null,
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Load the plan + verify ownership (mirrors rewrite-block) ──────────
  const { data: plan, error: planErr } = await supabase
    .from("training_plans")
    .select("id, user_id, coach_id, start_date, end_date")
    .eq("id", planId)
    .maybeSingle<{ id: string; user_id: string; coach_id: string | null; start_date: string | null; end_date: string | null }>();

  if (planErr) {
    console.error("draft-block-rewrite: plan lookup failed", planErr);
    return json({ error: "Database error" }, 500);
  }
  if (!plan) return json({ error: "Plan not found" }, 404);
  if (plan.user_id !== athleteUserId) {
    return json({ error: "planId does not belong to athleteUserId" }, 400);
  }

  // Ownership: directly coach-owned, OR the coach owns the plan template the
  // athlete is actively subscribed to. The subscription row also carries the
  // weekly mileage targets used for validation, so fetch it either way.
  const { data: sub } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id, weekly_mileage_targets)")
    .eq("athlete_user_id", athleteUserId)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachId)
    .limit(1)
    .maybeSingle();

  const ownsPlan = plan.coach_id === coachId || Boolean(sub);
  if (!ownsPlan) {
    return json({ error: "You do not coach this athlete's plan" }, 403);
  }

  // ── Verify every supplied workout id belongs to this plan ─────────────
  const ids = [...byDate.values()].map((w) => w.scheduledWorkoutId);
  const { data: dbRows, error: rowsErr } = await supabase
    .from("scheduled_workouts")
    .select("id, plan_id, date")
    .in("id", ids);
  if (rowsErr) {
    console.error("draft-block-rewrite: workout verification failed", rowsErr);
    return json({ error: "Database error" }, 500);
  }
  const dbById = new Map((dbRows ?? []).map((r: { id: string; plan_id: string | null; date: string }) => [r.id, r]));
  for (const w of byDate.values()) {
    const row = dbById.get(w.scheduledWorkoutId);
    if (!row || row.plan_id !== planId || row.date !== w.date) {
      return json({ error: `scheduledWorkoutId ${w.scheduledWorkoutId} is not on this plan (or its date changed — reload the editor)` }, 400);
    }
  }

  // ── Rate limit: once per ATHLETE per day ───────────────────────────────
  // Mirrors reschedule-plan's enforceFeatureRateLimit mechanism. Keyed on
  // the athlete (not the coach) and isServiceRole is deliberately NOT
  // passed, so the trusted-route caller still pays the athlete's budget.
  const rlBlocked = await enforceFeatureRateLimit(athleteUserId, "draft_rewrite", corsHeaders);
  if (rlBlocked) return rlBlocked;

  // ── Build prompts ──────────────────────────────────────────────────────
  const templateRaw = (sub as { plan_template?: { weekly_mileage_targets?: unknown } } | null)?.plan_template;
  const weekTargets = parseWeekTargets(templateRaw?.weekly_mileage_targets);

  const targetLines: string[] = [];
  for (let wk = fromWeek; wk <= toWeek; wk++) {
    const t = weekTargets.get(wk);
    if (t) targetLines.push(`Week ${wk}: ${t.min}–${t.max} mi (hard range — stay inside it)`);
  }
  const mileageTargets = targetLines.length > 0
    ? targetLines.join("\n")
    : "No weekly mileage targets are set for these weeks.";

  const systemPrompt = loadPrompt("draft-block-rewrite.v1", {
    candidateLibrary: formatCandidateLibrary(),
    mileageTargets,
  });

  const raceWeekStart = raceWeekStartOf(plan.end_date);
  const lines: string[] = [];
  lines.push("BLOCK REWRITE REQUEST (from the coach)");
  lines.push(`Coach's request: "${request}"`);
  lines.push(`Week range in scope: W${fromWeek}–W${toWeek}`);
  if (plan.end_date && raceWeekStart) {
    lines.push(`Race day: ${plan.end_date} (race week begins ${raceWeekStart} — do not change days on or after it)`);
  }
  lines.push("");
  lines.push("CURRENT SCHEDULED BLOCK:");
  const weeksInScope = [...new Set([...byDate.values()].map((w) => w.weekNumber))].sort((a, b) => a - b);
  for (const wk of weeksInScope) {
    const days = [...byDate.values()].filter((w) => w.weekNumber === wk).sort((a, b) => a.date.localeCompare(b.date));
    let total = 0;
    for (const d of days) {
      total += d.miles ?? 0;
      const mi = d.miles != null ? ` ${d.miles}mi` : "";
      const nm = d.name ? ` — ${d.name}` : "";
      lines.push(`  Wk${wk} ${DAY_NAMES[d.dayOfWeek]} ${d.date} | ${d.workoutType}${nm}${mi}`);
    }
    const t = weekTargets.get(wk);
    lines.push(`  Week ${wk} total: ${Math.round(total * 10) / 10} mi${t ? ` (target ${t.min}–${t.max} mi)` : ""}`);
  }
  lines.push("");
  lines.push("Draft the block rewrite. Only list days that change.");
  const userPrompt = lines.join("\n");

  // ── Call Gemini (same pattern as reschedule-plan) ──────────────────────
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "GEMINI_API_KEY not configured" }, 500);

  let responseText: string;
  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
    const result = await model.generateContent({
      contents: [
        { role: "user", parts: [{ text: systemPrompt }] },
        { role: "model", parts: [{ text: "Understood. I draft block-rewrite proposals for the coach to review — selection from the candidate library only, never applied automatically. Send the current block and the coach's request." }] },
        { role: "user", parts: [{ text: userPrompt }] },
      ],
      generationConfig: { temperature: 0.2, maxOutputTokens: 4096 },
    });
    responseText = result.response.text();
  } catch (error) {
    console.error("draft-block-rewrite: model call failed", error);
    return json({ error: "The draft could not be generated. Please try again." }, 500);
  }

  const draft = extractDraft(responseText);
  const message = proseAround(responseText);
  if (!draft || !Array.isArray(draft.days)) {
    // Model declined or emitted no parseable draft — surface the prose so
    // the coach sees WHY, but there is no diff to review.
    return json({ ok: true, message: message || "No draft could be produced for that request.", summary: "", weeks: [], days: [] }, 200);
  }

  // ── Hard validation of the model output ────────────────────────────────
  const violations: Array<{ code: string; detail: string }> = [];
  const changedByDate = new Map<string, { candidate: Candidate; code: string; reason: string | null }>();
  const requestTargetsRaceWeek = RACE_WEEK_INTENT.test(request);

  for (const d of draft.days) {
    const date = typeof d.date === "string" ? d.date : "";
    const code = typeof d.code === "string" ? d.code.toUpperCase() : "";
    if (!byDate.has(date)) {
      violations.push({ code: "unknown_date", detail: `Proposed a change on ${date || "(missing date)"}, which is not in the scheduled block.` });
      continue;
    }
    if (changedByDate.has(date)) {
      violations.push({ code: "duplicate_date", detail: `Proposed two changes for ${date}.` });
      continue;
    }
    if (code === "KEEP") continue;
    const candidate = DRAFT_CANDIDATE_LIBRARY[code];
    if (!candidate) {
      violations.push({ code: "unknown_code", detail: `"${d.code}" on ${date} is not in the candidate library.` });
      continue;
    }
    changedByDate.set(date, {
      candidate,
      code,
      reason: typeof d.reason === "string" && d.reason.trim().length > 0 ? d.reason.trim().slice(0, 200) : null,
    });
  }

  // Race-week guard — REJECTION, not confirm (unless explicitly targeted).
  if (!requestTargetsRaceWeek) {
    for (const [date, change] of changedByDate) {
      const before = byDate.get(date)!;
      const inRaceWeek = raceWeekStart && plan.end_date && date >= raceWeekStart && date <= plan.end_date;
      if (inRaceWeek || before.workoutType === "race" || change.candidate.workoutType === "race") {
        violations.push({
          code: "race_week_violation",
          detail: `Proposed changing ${date}, which is ${before.workoutType === "race" ? "race day" : "in the race week"}. The AI draft may not touch the race week unless the request explicitly targets it.`,
        });
      }
    }
  }

  // Weekly mileage bounds (only when targets exist for the week).
  for (const wk of weeksInScope) {
    const t = weekTargets.get(wk);
    if (!t) continue;
    const days = [...byDate.values()].filter((w) => w.weekNumber === wk);
    let total = 0;
    for (const d of days) {
      const change = changedByDate.get(d.date);
      total += change ? change.candidate.miles : (d.miles ?? 0);
    }
    total = Math.round(total * 10) / 10;
    if (total > t.max + 0.5 || total < t.min - 0.5) {
      violations.push({
        code: "mileage_out_of_range",
        detail: `Week ${wk} lands at ${total} mi after the draft; the plan's target for that week is ${t.min}–${t.max} mi.`,
      });
    }
  }

  if (violations.length > 0) {
    console.warn("draft-block-rewrite: draft rejected", violations);
    return json(
      {
        error: "The drafted rewrite broke a plan constraint and was rejected. Nothing was changed — try rephrasing the request.",
        code: "draft_validation_failed",
        violations,
      },
      422,
    );
  }

  // ── Build the proposal (per-day before/after diff) ─────────────────────
  const days: ProposalDay[] = [...byDate.values()]
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((w) => {
      const change = changedByDate.get(w.date);
      const before: DaySnapshot = { workoutType: w.workoutType, name: w.name, miles: w.miles };
      if (!change) {
        return {
          scheduledWorkoutId: w.scheduledWorkoutId,
          date: w.date,
          weekNumber: w.weekNumber,
          dayOfWeek: w.dayOfWeek,
          changed: false,
          code: null,
          reason: null,
          before,
          after: before,
        };
      }
      const { candidate, code, reason } = change;
      const after: DaySnapshot = {
        workoutType: candidate.workoutType,
        name: candidate.workoutType === "rest" ? null : candidate.name,
        miles: candidate.miles > 0 ? candidate.miles : null,
      };
      const isSame = after.workoutType === before.workoutType &&
        (after.miles ?? null) === (before.miles ?? null) &&
        (after.name ?? null) === (before.name ?? null);
      return {
        scheduledWorkoutId: w.scheduledWorkoutId,
        date: w.date,
        weekNumber: w.weekNumber,
        dayOfWeek: w.dayOfWeek,
        changed: !isSame,
        code: isSame ? null : code,
        reason: isSame ? null : reason,
        before,
        after: isSame ? before : after,
      };
    });

  const weekReasonByNum = new Map<number, string>();
  for (const wr of draft.weekReasons ?? []) {
    if (typeof wr?.weekNumber === "number" && typeof wr?.reason === "string" && wr.reason.trim()) {
      weekReasonByNum.set(wr.weekNumber, wr.reason.trim().slice(0, 200));
    }
  }
  const weeks = weeksInScope.map((wk) => {
    const wkDays = days.filter((d) => d.weekNumber === wk);
    const beforeTotal = Math.round(wkDays.reduce((s, d) => s + (d.before.miles ?? 0), 0) * 10) / 10;
    const afterTotal = Math.round(wkDays.reduce((s, d) => s + (d.after.miles ?? 0), 0) * 10) / 10;
    const t = weekTargets.get(wk) ?? null;
    return {
      weekNumber: wk,
      reason: weekReasonByNum.get(wk) ?? null,
      changedCount: wkDays.filter((d) => d.changed).length,
      mileageBefore: beforeTotal,
      mileageAfter: afterTotal,
      target: t,
    };
  });

  return json(
    {
      ok: true,
      message,
      summary: typeof draft.summary === "string" ? draft.summary.trim().slice(0, 280) : "",
      weeks,
      days,
    },
    200,
  );
});

// NOTE(adaptive-plan-1.6): This file now emits seconds-per-mile paces and
// resolves any `pace_reference` against the caller's AthletePaceProfile
// before returning planData. `pacePercentage` is still accepted as a legacy
// input for one release, but the primary output shape is the new one.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import {
  validateLength,
  validationErrorResponse,
  internalErrorResponse,
} from "../_shared/validation.ts";
import {
  getOrBuildPaceProfile,
  resolveSteps,
  type ResolvablePaceStep,
} from "../_shared/resolve-pace.ts";

import { corsHeaders } from "../_shared/cors.ts";

// ── Interfaces ──────────────────────────────────────────────────

interface Attachment {
  fileName: string;
  fileType: "image" | "pdf" | "text";
  base64Data?: string;
  storageUrl?: string;
}

interface PlanBuilderRequest {
  message: string;
  conversationId?: string;
  attachments?: Attachment[];
}

interface ImportedStep {
  stepType: string;
  durationType: string;
  durationValue: number;
  // New (preferred) fields — emitted by LLM or resolved server-side.
  target_pace_seconds_per_mile?: number | null;
  target_pace_seconds_high?: number | null;
  pace_reference?: string | null; // 'easy' | 'marathon' | 'half' | '10K' | '5K' | 'mile'
  resolved_from_snapshot_id?: string | null;
  resolved_at?: string | null;
  // Legacy fields — kept one release for back-compat during roll-forward.
  pacePercentage?: number | null;
  paceSecondsPerKm?: number | null;
  paceSecondsPerKmHigh?: number | null;
  notes: string | null;
  order?: number;
}

interface ImportedDay {
  date: string;
  dayOfWeek: number;
  dayName?: string;
  weekNumber: number;
  workoutType: string;
  name: string;
  description: string;
  totalDistanceMiles: number | null;
  estimatedDurationMinutes: number | null;
  steps: ImportedStep[];
  // Two-lane metadata (set by tagWorkoutSources)
  source?: "coach_locked" | "athlete_drag" | "easy_fill";
  isMovable?: boolean;
}

interface QualityTemplate {
  weekNumber: number;
  purpose: string;
  workoutType: string;
  workoutData: Record<string, unknown> | null;
  targetPacePercentage: number | null;
  targetDistanceMiles: number | null;
  targetDurationMinutes: number | null;
  priorityRank: number;
  suggestedDayOfWeek: number | null; // 0=Mon..6=Sun
}

interface PlanData {
  plan: {
    name: string;
    startDate: string;
    endDate: string;
    targetRaceDistance?: string | null;
    targetTimeSeconds?: number | null;
  };
  workouts: ImportedDay[];
  qualityTemplates?: QualityTemplate[];
}

// ── System Prompt ───────────────────────────────────────────────

const SYSTEM_PROMPT = `You are an expert running coach assistant helping build a personalized training plan.

CORE PHILOSOPHY: Be efficient. Don't ask questions you can infer. Generate the plan as quickly as possible.

WHEN THE USER PROVIDES AN EXISTING PLAN (upload, text, or description):
- Extract the workouts directly. The plan already has mileage, structure, and schedule.
- Only ask for what's genuinely missing: start date (if not stated) and duration/end date.
- Do NOT ask for current weekly mileage — the plan itself defines the mileage.
- Do NOT ask for experience level — the plan itself reflects the appropriate level.
- Confirm what you extracted briefly, then generate immediately.

WHEN BUILDING FROM SCRATCH:
- Ask only what you truly need in ONE round of questions (not multiple rounds):
  - When does the plan start and end? (or race date)
  - How many days per week can they run?
  - What's their approximate current weekly mileage?
  - Are they training for a specific race? (optional — they might just want a general plan)
- If they mention a race, ask for goal time. If no race, skip it entirely.
- Then generate the plan. Don't keep asking follow-up questions.

NOT EVERY PLAN HAS A RACE:
- Plans can be for general fitness, base building, maintenance, or just staying in shape.
- If there's no race target, set targetRaceDistance to "general" and targetTimeSeconds to 0.
- For general plans, use effort-based paces (e.g. "easy effort", "moderate effort") in step notes.
- Pace fields can all be null for effort-based plans.

PACE OUTPUT — USE SECONDS PER MILE OR A NAMED REFERENCE. NEVER PERCENTAGES:
- Output paces on each step as ONE of the following:
  * target_pace_seconds_per_mile: integer seconds per mile (e.g., 385 for 6:25/mi).
    Use this when the user's source text specifies an exact pace.
  * pace_reference: one of 'easy' | 'marathon' | 'half' | '10K' | '5K' | 'mile'.
    Use this when the user's source text describes intensity by race distance
    (the server resolves it against the athlete's pace profile).
- If both are set, the explicit seconds wins; pace_reference becomes a display label.
- Do NOT output pacePercentage — it is a legacy field and will be ignored.
- Map common phrasing:
    easy / conversational / aerobic   → pace_reference: "easy"
    steady / moderate / marathon pace → pace_reference: "marathon"
    tempo / threshold / HMP           → pace_reference: "half"
    10K pace                          → pace_reference: "10K"
    5K pace / VO2max                  → pace_reference: "5K"
    mile pace / speed / strides       → pace_reference: "mile"
- If the athlete has no goal and the plan is pure effort, leave both fields null.

WORKOUT TYPES: rest, easy, tempo, intervals, long_run, recovery, progression, strides, race
STEP TYPES: warmup, active, rest, recovery, cooldown
DURATION TYPES: distance_miles, distance_meters, time_seconds

WHEN READY TO OUTPUT THE FINAL PLAN:
Write a brief natural summary, then include the structured data:

<<<PLAN>>>
{
  "plan": {
    "name": "Plan Name",
    "startDate": "2026-03-02",
    "endDate": "2026-06-21",
    "targetRaceDistance": "marathon",
    "targetTimeSeconds": 12600
  },
  "workouts": [
    {
      "date": "2026-03-02",
      "dayOfWeek": 1,
      "weekNumber": 1,
      "workoutType": "easy",
      "name": "Easy Run",
      "description": "Relaxed aerobic run",
      "totalDistanceMiles": 5.0,
      "estimatedDurationMinutes": 47,
      "steps": [
        {
          "stepType": "active",
          "durationType": "distance_miles",
          "durationValue": 5.0,
          "pace_reference": "easy",
          "notes": "Easy conversational pace"
        }
      ]
    }
  ]
}
<<<END_PLAN>>>

RULES:
- The workouts array must include EVERY day from startDate to endDate (no gaps).
- Rest days: workoutType "rest", name "Rest Day", empty steps array.
- dayOfWeek: 1 = Monday, 7 = Sunday.
- targetRaceDistance: "5k", "10k", "half_marathon", "marathon", "ultra", or "general".
- targetTimeSeconds: goal time in seconds, or 0 if no race goal.
- Dates in YYYY-MM-DD format. weekNumber starts at 1, increments each Monday.
- For plans with many weeks, you MUST include all days. Do not truncate or abbreviate.

DISTANCE ROUNDING (easy runs only):
- Easy runs (workoutType "easy"): totalDistanceMiles MUST be a whole integer
  (e.g., 5, 6, 8, 10). Never 5.5, 9.5, 4.5. Runners say "10 mile easy,"
  not "9.5 mile easy."
- Every other workout type (recovery, long_run, tempo, intervals,
  progression, race, strides) may carry fractional distances. Long runs
  especially — coaches routinely prescribe 13.1, 16, 20, etc.
- Step durationValue in easy workouts follows the same rule (whole miles).
- When distributing weekly mileage across easy days, prefer uneven whole-mile
  distributions (e.g., 8 + 10 + 12 = 30) over half-mile splits.`;

// ── Helpers ─────────────────────────────────────────────────────

function extractPlanData(text: string): PlanData | null {
  const startMarker = "<<<PLAN>>>";
  const endMarker = "<<<END_PLAN>>>";

  const startIdx = text.indexOf(startMarker);
  const endIdx = text.indexOf(endMarker);

  if (startIdx === -1 || endIdx === -1 || endIdx <= startIdx) {
    return null;
  }

  const jsonStr = text.substring(startIdx + startMarker.length, endIdx).trim();

  try {
    return JSON.parse(jsonStr) as PlanData;
  } catch {
    // Try extracting from code block within markers
    const codeBlockMatch = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlockMatch) {
      try {
        return JSON.parse(codeBlockMatch[1].trim()) as PlanData;
      } catch {
        /* continue */
      }
    }

    // Try finding first { to last }
    const firstBrace = jsonStr.indexOf("{");
    const lastBrace = jsonStr.lastIndexOf("}");
    if (firstBrace !== -1 && lastBrace > firstBrace) {
      try {
        return JSON.parse(
          jsonStr.substring(firstBrace, lastBrace + 1)
        ) as PlanData;
      } catch {
        /* continue */
      }
    }
  }

  return null;
}

function getConversationalMessage(text: string): string {
  // Remove the plan JSON from the message for display
  const startMarker = "<<<PLAN>>>";
  const endMarker = "<<<END_PLAN>>>";
  const startIdx = text.indexOf(startMarker);
  const endIdx = text.indexOf(endMarker);

  if (startIdx !== -1 && endIdx !== -1) {
    return (
      text.substring(0, startIdx).trim() +
      text.substring(endIdx + endMarker.length).trim()
    );
  }
  return text;
}

function validatePlanData(data: PlanData): string | null {
  if (!data.plan) return "Missing plan metadata";
  if (!data.plan.name) return "Missing plan name";
  if (!data.plan.startDate) return "Missing start date";
  if (!data.plan.endDate) return "Missing end date";
  // targetRaceDistance and targetTimeSeconds are optional (general/base plans)
  if (!data.workouts || !Array.isArray(data.workouts))
    return "Missing workouts array";
  if (data.workouts.length === 0) return "Workouts array is empty";
  return null;
}

// Easy runs are prescribed in whole miles. "10 mile easy" reads correct;
// "9.5 mile easy" does not. Long runs, intervals, tempo, and recovery can
// carry fractional distances (coach may prescribe 13.1, 6×800m math lands
// on 6.98, 3.5mi shakeout, etc.).
const WHOLE_MILE_WORKOUT_TYPES = new Set(["easy"]);

function roundDistanceIfWhole(workoutType: string, miles: number | null | undefined): number | null {
  if (miles == null) return null;
  if (!WHOLE_MILE_WORKOUT_TYPES.has(workoutType)) return miles;
  return Math.round(miles);
}

function normalizeWorkouts(workouts: ImportedDay[]): ImportedDay[] {
  return workouts.map((day) => ({
    date: day.date,
    dayOfWeek: day.dayOfWeek,
    dayName:
      day.dayName ||
      [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ][day.dayOfWeek - 1],
    weekNumber: day.weekNumber,
    workoutType: day.workoutType || "rest",
    name: day.name || "Rest Day",
    description: day.description || "",
    totalDistanceMiles: roundDistanceIfWhole(day.workoutType || "rest", day.totalDistanceMiles ?? null),
    estimatedDurationMinutes: day.estimatedDurationMinutes ?? null,
    steps: (day.steps || []).map((step, idx) => ({
      stepType: step.stepType || "active",
      durationType: step.durationType || "distance_miles",
      durationValue: normalizeStepDistance(
        day.workoutType || "rest",
        step.stepType || "active",
        step.durationType || "distance_miles",
        step.durationValue || 0,
      ),
      target_pace_seconds_per_mile: step.target_pace_seconds_per_mile ?? null,
      target_pace_seconds_high: step.target_pace_seconds_high ?? null,
      pace_reference: step.pace_reference ?? null,
      resolved_from_snapshot_id: step.resolved_from_snapshot_id ?? null,
      resolved_at: step.resolved_at ?? null,
      // Legacy fields preserved in JSONB for one release.
      pacePercentage: step.pacePercentage ?? null,
      paceSecondsPerKm: step.paceSecondsPerKm ?? null,
      paceSecondsPerKmHigh: step.paceSecondsPerKmHigh ?? null,
      notes: step.notes ?? null,
      order: step.order ?? idx,
    })),
  }));
}

// For easy/recovery/long_run: any distance-mile step rounds to whole miles.
// Intervals/tempo: leave as-is (800m reps, mile splits are prescribed precisely).
function normalizeStepDistance(
  workoutType: string,
  _stepType: string,
  durationType: string,
  value: number,
): number {
  if (durationType !== "distance_miles") return value;
  if (!WHOLE_MILE_WORKOUT_TYPES.has(workoutType)) return value;
  return Math.round(value);
}

const QUALITY_TYPES = new Set(["tempo", "intervals", "long_run", "race", "progression"]);

/**
 * Extract quality session templates from the dated workout list.
 * Quality workouts (tempo, intervals, long_run, race, progression) become
 * pool templates; their dates become suggestions, not locks.
 */
function extractQualityTemplates(workouts: ImportedDay[]): QualityTemplate[] {
  const quality = workouts.filter((w) => QUALITY_TYPES.has(w.workoutType));

  // Group by week and assign priority ranks
  const byWeek = new Map<number, ImportedDay[]>();
  for (const w of quality) {
    const existing = byWeek.get(w.weekNumber) || [];
    existing.push(w);
    byWeek.set(w.weekNumber, existing);
  }

  const templates: QualityTemplate[] = [];
  for (const [weekNum, weekWorkouts] of byWeek) {
    // Sort by importance: long_run/race first, then intervals, then tempo
    const sorted = weekWorkouts.sort((a, b) => {
      const order: Record<string, number> = {
        long_run: 1, race: 1, intervals: 2, tempo: 3, progression: 4,
      };
      return (order[a.workoutType] ?? 5) - (order[b.workoutType] ?? 5);
    });

    for (let i = 0; i < sorted.length; i++) {
      const w = sorted[i];
      const purposeMap: Record<string, string> = {
        tempo: "threshold development",
        intervals: "speed development",
        long_run: "long run",
        progression: "progressive endurance",
        race: "race",
      };

      // Extract pace percentage from first active step
      let pacePercentage: number | null = null;
      const activeStep = w.steps.find((s) => s.stepType === "active");
      if (activeStep?.pacePercentage) pacePercentage = activeStep.pacePercentage;

      templates.push({
        weekNumber: weekNum,
        purpose: purposeMap[w.workoutType] || w.workoutType,
        workoutType: w.workoutType,
        workoutData: {
          name: w.name,
          description: w.description,
          steps: w.steps,
          totalDistanceMiles: w.totalDistanceMiles,
          estimatedDurationMinutes: w.estimatedDurationMinutes,
        },
        targetPacePercentage: pacePercentage,
        targetDistanceMiles: w.totalDistanceMiles,
        targetDurationMinutes: w.estimatedDurationMinutes,
        priorityRank: i + 1,
        suggestedDayOfWeek: w.dayOfWeek > 0 ? w.dayOfWeek - 1 : null, // 1-indexed → 0-indexed
      });
    }
  }

  return templates;
}

/**
 * Tag each workout with source metadata for the two-lane model.
 */
function tagWorkoutSources(workouts: ImportedDay[]): ImportedDay[] {
  return workouts.map((w) => ({
    ...w,
    source: QUALITY_TYPES.has(w.workoutType) ? "coach_locked" : "easy_fill",
    isMovable: QUALITY_TYPES.has(w.workoutType), // quality sessions can be moved
  }));
}

// ── Main Handler ────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Auth
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    // Rate limiting
    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "plan_builder");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({
            error: "Rate limit exceeded",
            remaining: 0,
            resetAt: rateLimit.resetAt.toISOString(),
          }),
          {
            status: 429,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    // Parse request
    const body: PlanBuilderRequest = await req.json();

    if (!body.message || body.message.trim().length === 0) {
      return validationErrorResponse("Message is required", corsHeaders);
    }

    const lengthErr = validateLength(body.message, "message", 5000);
    if (lengthErr) return validationErrorResponse(lengthErr, corsHeaders);

    // Set up Supabase client for conversation storage
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Load existing conversation
    let existingMessages: Array<{
      role: string;
      content: string;
      timestamp: string;
    }> = [];
    if (body.conversationId) {
      const { data } = await supabase
        .from("conversations")
        .select("messages")
        .eq("id", body.conversationId)
        .single();

      if (data?.messages) {
        existingMessages = data.messages;
      }
    }

    // Build Gemini prompt parts
    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.0-flash",
      generationConfig: {
        maxOutputTokens: 65536,
        temperature: 0.4,
      },
      systemInstruction: SYSTEM_PROMPT,
    });

    // Build conversation history for Gemini
    const history = existingMessages.map((msg) => ({
      role: msg.role === "user" ? "user" : ("model" as const),
      parts: [{ text: msg.content }],
    }));

    // Build current message parts (text + attachments)
    const currentParts: Array<{ text: string } | { inlineData: { mimeType: string; data: string } }> = [];

    // Add attachment content
    if (body.attachments && body.attachments.length > 0) {
      for (const attachment of body.attachments) {
        if (attachment.base64Data) {
          if (attachment.fileType === "image") {
            // Use Gemini multimodal for images
            currentParts.push({
              inlineData: {
                mimeType: "image/jpeg",
                data: attachment.base64Data,
              },
            });
          } else if (
            attachment.fileType === "text" ||
            attachment.fileType === "pdf"
          ) {
            // Decode text content and include inline
            try {
              const decoded = atob(attachment.base64Data);
              currentParts.push({
                text: `[UPLOADED FILE: ${attachment.fileName}]\n${decoded}\n[END FILE]`,
              });
            } catch {
              currentParts.push({
                text: `[UPLOADED FILE: ${attachment.fileName} - could not decode content]`,
              });
            }
          }
        } else if (attachment.storageUrl) {
          // Fetch content from storage
          try {
            const resp = await fetch(attachment.storageUrl);
            if (attachment.fileType === "image") {
              const buffer = await resp.arrayBuffer();
              const base64 = btoa(
                String.fromCharCode(...new Uint8Array(buffer))
              );
              currentParts.push({
                inlineData: { mimeType: "image/jpeg", data: base64 },
              });
            } else {
              const text = await resp.text();
              currentParts.push({
                text: `[UPLOADED FILE: ${attachment.fileName}]\n${text}\n[END FILE]`,
              });
            }
          } catch {
            currentParts.push({
              text: `[UPLOADED FILE: ${attachment.fileName} - could not fetch content]`,
            });
          }
        }
      }
    }

    // Add the user's text message
    currentParts.push({ text: body.message });

    // Call Gemini with conversation history
    const chat = model.startChat({ history });
    const result = await chat.sendMessage(currentParts);
    const responseText = result.response.text();

    // Check if the response contains a plan
    const planData = extractPlanData(responseText);
    const conversationalMessage = getConversationalMessage(responseText);

    // Save conversation
    const now = new Date().toISOString();
    const newMessages = [
      ...existingMessages,
      { role: "user", content: body.message, timestamp: now },
      {
        role: "assistant",
        content: conversationalMessage,
        timestamp: now,
      },
    ];

    let conversationId = body.conversationId;
    if (conversationId) {
      await supabase
        .from("conversations")
        .update({ messages: newMessages, updated_at: now })
        .eq("id", conversationId);
    } else {
      const { data: convData } = await supabase
        .from("conversations")
        .insert({ messages: newMessages })
        .select("id")
        .single();

      conversationId = convData?.id;
    }

    // Build response
    const response: Record<string, unknown> = {
      type: planData ? "plan" : "question",
      message: conversationalMessage,
      conversationId,
    };

    if (planData) {
      const validationError = validatePlanData(planData);
      if (validationError) {
        // Plan was malformed — treat as a question and ask for clarification
        response.type = "question";
        response.message =
          conversationalMessage ||
          "I had trouble structuring the plan. Let me try again — could you confirm the key details?";
      } else {
        planData.workouts = tagWorkoutSources(normalizeWorkouts(planData.workouts));
        // Resolve every step's target pace against the athlete's profile so
        // downstream consumers never have to fall back to percentages or
        // "N/A" strings. Silently skips users with no profile yet.
        const paceProfile = await getOrBuildPaceProfile(supabase, userId);
        planData.workouts = planData.workouts.map((day) => ({
          ...day,
          // ResolvablePaceStep is an `interface` carrying an index signature
          // ([key: string]: unknown) with every field optional; ImportedStep is
          // an `interface` with no index signature and four REQUIRED keys
          // (stepType, durationType, durationValue, notes). Interfaces get no
          // implicit index signature, so neither type is assignable to the
          // other and both directions have to route through `unknown`.
          //
          // Safe at runtime: resolveStepPace spreads the input step and only
          // rewrites pace fields, so ImportedStep's required keys survive
          // untouched. A generic <T extends ResolvablePaceStep> would express
          // this properly, but ImportedStep cannot satisfy that constraint
          // while it is an interface — and this function is a cut product
          // pending deletion (CUT_FUNCTIONS_PENDING_DELETION), so the cast is
          // the right amount of effort. Deleting the directory retires it.
          steps: resolveSteps(
            day.steps as unknown as ResolvablePaceStep[],
            paceProfile,
          ) as unknown as ImportedStep[],
        }));
        planData.qualityTemplates = extractQualityTemplates(planData.workouts);
        response.planData = planData;
      }
    }

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Custom plan builder error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

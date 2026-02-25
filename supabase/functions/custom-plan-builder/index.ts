import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import {
  validateLength,
  validationErrorResponse,
  internalErrorResponse,
} from "../_shared/validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
  pacePercentage: number | null;
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
- pacePercentage can be null for effort-based plans without a race pace reference.

PACE RULES (only when a race goal exists — pacePercentage is % of goal race pace):
- 65-70% = recovery/easy
- 70-75% = easy/aerobic
- 80-85% = steady/moderate
- 85-90% = tempo/threshold
- 95-100% = race pace
- 100-105% = VO2max / 5K pace
- 105-115% = speed/sprint
- null = effort-based (no specific pace target)

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
          "pacePercentage": 70,
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
- For plans with many weeks, you MUST include all days. Do not truncate or abbreviate.`;

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
    totalDistanceMiles: day.totalDistanceMiles ?? null,
    estimatedDurationMinutes: day.estimatedDurationMinutes ?? null,
    steps: (day.steps || []).map((step, idx) => ({
      stepType: step.stepType || "active",
      durationType: step.durationType || "distance_miles",
      durationValue: step.durationValue || 0,
      pacePercentage: step.pacePercentage ?? null,
      notes: step.notes ?? null,
      order: step.order ?? idx,
    })),
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
        planData.workouts = normalizeWorkouts(planData.workouts);
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

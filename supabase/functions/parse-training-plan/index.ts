import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateLength, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";

import { corsHeaders } from "../_shared/cors.ts";

interface ParseRequest {
  text?: string;
  imageBase64?: string;
  imageMimeType?: string;
  fileBase64?: string;
  fileType?: string;
  // Optional context from user's existing plan
  goalTimeSeconds?: number;
  raceDistance?: string;
  // Answers to clarifying questions from a previous parse
  clarificationAnswers?: { id: string; answer: string }[];
}

function repairTruncatedJson(text: string): string {
  // Try to fix truncated JSON by closing open brackets/braces
  let s = text.trim();
  // Remove trailing commas before we close
  s = s.replace(/,\s*$/, "");

  // Count open vs close brackets
  let braces = 0, brackets = 0;
  let inString = false, escaped = false;
  for (const ch of s) {
    if (escaped) { escaped = false; continue; }
    if (ch === "\\") { escaped = true; continue; }
    if (ch === '"') { inString = !inString; continue; }
    if (inString) continue;
    if (ch === "{") braces++;
    else if (ch === "}") braces--;
    else if (ch === "[") brackets++;
    else if (ch === "]") brackets--;
  }
  // If we're inside a string, close it
  if (inString) s += '"';
  // Remove any trailing partial key-value (e.g., `"key": "partial`)
  s = s.replace(/,\s*"[^"]*"?\s*:?\s*"?[^"]*$/, "");
  // Close open brackets and braces
  for (let i = 0; i < brackets; i++) s += "]";
  for (let i = 0; i < braces; i++) s += "}";
  return s;
}

function parseJsonResponse(text: string, wasTruncated = false): unknown {
  try { return JSON.parse(text); } catch { /* continue */ }

  const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    try { return JSON.parse(codeBlockMatch[1].trim()); } catch { /* continue */ }
  }

  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    try { return JSON.parse(text.substring(firstBrace, lastBrace + 1)); } catch { /* continue */ }
  }

  // If truncated, try to repair by closing open brackets/braces
  if (wasTruncated && firstBrace !== -1) {
    const partial = text.substring(firstBrace);
    const repaired = repairTruncatedJson(partial);
    console.log("Attempting truncation repair...");
    try { return JSON.parse(repaired); } catch (e: any) {
      console.error("Repair failed:", e?.message);
    }
  }

  throw new Error("Could not parse AI response as JSON");
}

function buildPrompt(goalTimeSeconds?: number, raceDistance?: string, clarificationAnswers?: { id: string; answer: string }[]): string {
  const raceContext = goalTimeSeconds
    ? `The athlete is training for a ${raceDistance || "marathon"} with a goal time of ${Math.floor(goalTimeSeconds / 3600)}:${String(Math.floor((goalTimeSeconds % 3600) / 60)).padStart(2, "0")}:${String(goalTimeSeconds % 60).padStart(2, "0")}.`
    : "No specific race goal is set. Use reasonable pacePercentage defaults for a recreational runner.";

  let clarificationContext = "";
  if (clarificationAnswers && clarificationAnswers.length > 0) {
    clarificationContext = "\n\nThe user answered these clarifying questions about the training:\n";
    for (const a of clarificationAnswers) {
      clarificationContext += `- ${a.id}: ${a.answer}\n`;
    }
    clarificationContext += "\nUse these answers to produce an accurate parse. Do NOT return any clarifications this time.\n";
  }

  return `You are an expert running coach assistant. Parse the following training plan into structured multi-week workout data.

${raceContext}${clarificationContext}

RULES:
- Parse ALL weeks found in the input. If no "Week" label exists, treat the entire input as Week 1
- Each week must have all 7 days (Monday=1 through Sunday=7)
- Days not mentioned should be "rest" days
- Keep distances in their ORIGINAL units. Use "distance_km" for kilometers, "distance_miles" for miles, "distance_meters" for meters
- For rest days: workoutType="rest", name="Rest Day", steps=[]
- If a workout says "tempo" or "threshold" without specifying warmup/cooldown, assume warmup + tempo portion + cooldown
- If intervals are listed without warmup/cooldown, assume warmup + intervals + cooldown
- When distances are given as ranges (e.g., "35 - 40 km", "3-5 km"), use the MIDPOINT of the range

PACE DATA:
- pacePercentage is relative to goal race pace (100% = race pace):
  65-70% = recovery/easy, 70-75% = easy/aerobic, 80-85% = steady/moderate
  85-90% = tempo/threshold, 95-100% = race pace, 100-105% = VO2max/5K, 105-115% = speed/sprint
- ALSO provide actual pace values when the training plan specifies them:
  * paceSecondsPerKm: pace in total seconds per km (fast/low end). e.g., 3:06/km = 186, 4:30/km = 270
  * paceSecondsPerKmHigh: pace in seconds per km (slow/high end for ranges). null if no range given.
  * For named paces without specific values (e.g., "easy", "tempo"), set paceSecondsPerKm to null and rely on pacePercentage
  * For specific pace values (e.g., "3:06-3:10/km", "at 5:30 pace", "at 3'30 pace"), ALWAYS set paceSecondsPerKm
- "marathon pace" or "MP" = 100% pacePercentage
- "easy" = 70% pacePercentage
- "recovery" = 65% pacePercentage
- "steady" or "moderate" = 80% pacePercentage
- "threshold" or "tempo" = 88% pacePercentage
- "5K pace" or "VO2max" = 103% pacePercentage
- "sprint" or "fast strides" or "max speed" = 110-115% pacePercentage

DOUBLES (TWO RUNS IN ONE DAY):
- Many training plans include "doubles" — two separate runs in a single day (e.g., "AM: 1hr easy / PM: 1hr10 at marathon pace")
- When a day has two separate sessions, create TWO entries for that dayOfWeek with different "session" numbers:
  * First run: "session": 1 (e.g., morning run)
  * Second run: "session": 2 (e.g., afternoon/evening run)
- The name should distinguish them, e.g., "AM Easy Run" and "PM Marathon Pace Run"
- Each session gets its own steps, totalDistanceMiles, and estimatedDurationMinutes
- If a day has three sessions (rare but possible, e.g., easy + workout + sprints), use session 1, 2, 3
- The dayOfWeek value is the SAME for both entries — only session differs
- Look for patterns like: "2x1hr", "AM/PM", slashes separating runs, "+" joining different sessions, or multiple distinct efforts listed for one day
- IMPORTANT: When workouts are listed on separate lines under the same day name, each line is a separate session. Example:
  "Mon\n1 hr easy\n1 hr easy" → TWO sessions: session 1 = "AM Easy Run" (1hr), session 2 = "PM Easy Run" (1hr)
  "Thu\n1 hr easy\n1 hr 10 min at 3'30 pace" → TWO sessions: session 1 = easy, session 2 = pace work
  "Fri\n1 hr 10 min at 3'30 pace\n50 min easy + 10 x 100m sprint" → TWO sessions: session 1 = pace, session 2 = easy + sprints

TIME-BASED WORKOUTS → DISTANCE ESTIMATION:
- When a workout is given as a duration (e.g., "1 hr easy", "2hr30 easy", "50 min recovery"), you MUST estimate the distance in miles
- Use the athlete's goal pace context to estimate:
  * Easy/recovery pace: ~70% of race pace speed → roughly 8:30-9:30/mi for a 3:00-3:30 marathoner, 9:30-10:30/mi for a 4:00 marathoner
  * Marathon pace: ~100% → roughly 6:52/mi for 3:00, 8:00/mi for 3:30, 9:09/mi for 4:00
  * Tempo: ~88% → roughly 6:30-7:00/mi for a sub-3:00 marathoner
- Formula: distance = duration_minutes / pace_per_mile_minutes
- For "1 hr easy" with a 3:00 marathon goal: ~60/8.75 ≈ 6.9 miles → output ~7.0 mi
- For "2hr30 easy" with a 3:00 marathon goal: ~150/8.75 ≈ 17.1 miles → output ~17.0 mi
- ALWAYS provide totalDistanceMiles even for time-based workouts — estimate it
- For time-based steps, use durationType="time_seconds" and durationValue=total_seconds

PACE NOTATION:
- "3'30" or "3'30\"" or "3'30 pace" or "3:30/km" = 3 minutes 30 seconds per kilometer (common in metric countries)
  → "at 3'30 pace" means running at 3:30 per km → paceSecondsPerKm = 210
- "X'YY" or "X'YY pace" nearly always means per-km pace unless explicitly stated as per-mile
- Watch for variations: "3'30", "3'30\"", "3'30 \"pace", "3:30/km" — all mean the same thing
- For pace ranges like "3:06-3:10/km": paceSecondsPerKm=186 (fast end), paceSecondsPerKmHigh=190 (slow end)
- When converting per-mile pace to per-km: divide by 1.60934 (e.g., 7:00/mi = 420s/mi = 261s/km)

WORKOUT TYPE CLASSIFICATION:
- "easy": Standard easy/aerobic run. Single pace, no hard efforts.
- "recovery": Very easy, short recovery jog (typically ≤45min or ≤5mi)
- "long_run": Longest run of the week OR runs ≥90min OR labeled as "long run". Easy long runs are still "long_run".
- "tempo": Contains sustained threshold/tempo effort (e.g., tempo blocks, marathon pace sustained segments)
- "intervals": Contains repeated hard efforts with recovery (e.g., 8x800m, 5x1km, repeat sets)
- "progression": Starts easy and gets faster over the run, or contains sections at progressively faster paces
- "strides": Easy run plus short accelerations/strides at the end
- "race": Race day or time trial
- For complex workouts with multiple pace zones (e.g., "35-40km with sections at marathon pace and threshold"), classify by the PRIMARY hard effort type
- A workout titled "Extensive Long Run With Variations" or "Extensive - Intensive long running" that includes multiple pace changes is a "long_run" type
- A workout titled like "Doubles - AM Easy / PM Workout" → classify each session separately
- "hilly progressive running" or "progressive run" = "progression" type
- Easy run + sprints at the end (e.g., "50 min easy + 10 x 100m sprint") = "strides" type

WORKOUT NAMING:
- Give each workout a clear, descriptive name that a runner would recognize
- Use the original training plan's terminology when available (e.g., "Extensive Long Run With Variations", "Marathon Pace Tempo", "Recovery Double")
- For doubles: include AM/PM or Session 1/2 distinction
- Examples: "Easy Run", "AM Easy Run", "PM Marathon Pace Run", "Extensive Long Run With Variations", "Interval Session - 8x800m", "Progressive Long Run", "Recovery Jog + Sprints"

INPUT FORMAT RECOGNITION:
- Training plans may come in many formats. Be flexible in parsing:
  * "Week 1: Mon: 5mi easy, Tue: intervals..." — labeled weeks with inline days
  * "Mon\n1 hr easy\nTue\n8x800m..." — day names on separate lines, workouts on following lines
  * "Monday - 5mi easy\nTuesday - tempo run..." — day names with dashes
  * Day abbreviations: Mon, Tue, Wed, Thu, Fri, Sat, Sun (case-insensitive)
- If the input has NO week labels, treat the entire input as Week 1
- If a day has multiple lines of workouts below it (before the next day name), each line is typically a separate session (double)
- "1 hr easy" means a 1-hour easy run. "1 hr 10 min" means 70 minutes. "2 hr 30 min" means 150 minutes
- Descriptions in parentheses like "(Extensive - Intensive long running)" are workout descriptors/names, not separate workouts
- "warm up" as a standalone workout before a main workout on the same day = that's a warmup step, NOT a separate session

METADATA EXTRACTION:
- "planName": Extract or infer a name for the plan (e.g., "Pfitzinger 18/55 Marathon Plan", "Hal Higdon Intermediate 1"). Use null if you cannot determine a name.
- "detectedMeta.raceDistance": One of "marathon", "half_marathon", "10k", "5k", "mile" — or null if not clear
- "detectedMeta.goalTime": In "HH:MM:SS" format if mentioned — or null if not mentioned
- "detectedMeta.startDate": In "YYYY-MM-DD" format if mentioned — or null if not mentioned
- "missingFields": List any fields from ["planName", "raceDistance", "goalTime", "startDate"] that you could NOT detect

CLARIFICATION RULES:
- If something is AMBIGUOUS in the training content, add a clarification question
- Examples of things that might be ambiguous:
  * Are distances in miles or kilometers?
  * Does "5K" mean a 5K race or a 5K-pace workout?
  * What are the easy day distances if not specified?
  * Are there warmup/cooldown included or separate?
  * What day does the training week start on?
  * Is a listed time (e.g., "30 min") for the whole run or just the hard portion?
- Only ask about GENUINELY ambiguous things — don't ask if the training is already clear
- Maximum 3 clarification questions
- If the user already provided clarification answers, do NOT ask more questions — just parse accurately

OUTPUT FORMAT - respond ONLY with this JSON, no other text:
{
  "totalWeeks": 16,
  "planName": "Boston Marathon 18-Week Plan",
  "detectedMeta": {
    "raceDistance": "marathon|half_marathon|10k|5k|mile|null if not detected",
    "goalTime": "HH:MM:SS or null if not detected",
    "startDate": "YYYY-MM-DD or null if not detected"
  },
  "missingFields": ["planName", "raceDistance", "goalTime", "startDate"],
  "clarifications": [
    {
      "id": "units",
      "question": "Are the distances in miles or kilometers?",
      "options": ["Miles", "Kilometers"]
    }
  ],
  "weeks": [
    {
      "weekNumber": 1,
      "label": "Week 1",
      "totalDistanceMiles": 35.0,
      "days": [
        {
          "dayOfWeek": 1,
          "dayName": "Monday",
          "session": 1,
          "workoutType": "easy|tempo|intervals|long_run|recovery|rest|strides|progression",
          "name": "Easy Run",
          "description": "Relaxed aerobic run",
          "totalDistanceMiles": 5.0,
          "estimatedDurationMinutes": 45,
          "steps": [
            {
              "stepType": "warmup|active|rest|recovery|cooldown",
              "durationType": "distance_km|distance_miles|distance_meters|time_seconds",
              "durationValue": 5.0,
              "pacePercentage": 70,
              "paceSecondsPerKm": null,
              "paceSecondsPerKmHigh": null,
              "notes": "Easy pace"
            }
          ]
        },
        {
          "dayOfWeek": 1,
          "dayName": "Monday",
          "session": 2,
          "workoutType": "easy",
          "name": "PM Easy Run",
          "description": "Second easy run of the day",
          "totalDistanceMiles": 5.0,
          "estimatedDurationMinutes": 45,
          "steps": [
            {
              "stepType": "active",
              "durationType": "distance_miles",
              "durationValue": 5.0,
              "pacePercentage": 70,
              "notes": "Easy pace"
            }
          ]
        }
      ]
    }
  ]
}

STEP TYPES:
- "warmup": warm-up jog before main workout
- "active": main work (tempo miles, interval reps, easy run)
- "rest": standing/walking rest between intervals
- "recovery": jog recovery between intervals
- "cooldown": cool-down jog after workout

Now parse this training plan:`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "parse");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const body: ParseRequest = await req.json();

    if (!body.text && !body.imageBase64 && !body.fileBase64) {
      return new Response(
        JSON.stringify({ error: "Provide text, imageBase64, or fileBase64" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (body.text) {
      const lengthErr = validateLength(body.text, "text", 50000);
      if (lengthErr) return validationErrorResponse(lengthErr, corsHeaders);
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const isMultimodal = !!(body.imageBase64 || body.fileBase64);
    const generationConfig: any = {
      maxOutputTokens: 65536,
      temperature: 0.2,
      // Disable thinking mode — we just need fast structured output
      thinkingConfig: { thinkingBudget: 0 },
    };
    // Only use JSON response mode for text-only requests;
    // multimodal (image/PDF) inputs can fail with responseMimeType set
    if (!isMultimodal) {
      generationConfig.responseMimeType = "application/json";
    }
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig,
    });

    const prompt = buildPrompt(body.goalTimeSeconds, body.raceDistance, body.clarificationAnswers);

    // Build content parts for Gemini (multimodal)
    const parts: any[] = [{ text: prompt }];

    if (body.text) {
      parts.push({ text: `\n\n${body.text}` });
    }

    if (body.imageBase64) {
      parts.push({
        inlineData: {
          mimeType: body.imageMimeType || "image/jpeg",
          data: body.imageBase64,
        },
      });
      if (!body.text) {
        parts.push({ text: "\n\n[The training plan is in the image above. Extract all weeks and workouts you can see.]" });
      }
    }

    if (body.fileBase64 && body.fileType) {
      if (body.fileType === "application/pdf") {
        parts.push({
          inlineData: {
            mimeType: "application/pdf",
            data: body.fileBase64,
          },
        });
        parts.push({ text: "\n\n[The training plan is in the PDF above. Extract all weeks and workouts.]" });
      } else {
        try {
          const decoded = atob(body.fileBase64);
          parts.push({ text: `\n\nFile content (${body.fileType}):\n${decoded}` });
        } catch {
          parts.push({ text: `\n\n[File provided as base64 with type ${body.fileType}]` });
        }
      }
    }

    console.log(`Parsing training plan: text=${!!body.text}, image=${!!body.imageBase64}, file=${!!body.fileBase64}, hasClarifications=${!!body.clarificationAnswers?.length}`);

    let result;
    try {
      result = await model.generateContent(parts);
    } catch (genError: any) {
      console.error("Gemini API error:", genError?.message || genError);
      const msg = genError?.message || "";
      if (msg.includes("SAFETY") || msg.includes("blocked")) {
        return new Response(
          JSON.stringify({ error: "Content was blocked by safety filters. Try rephrasing your input." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      return new Response(
        JSON.stringify({ error: "AI service error. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const finishReason = result.response.candidates?.[0]?.finishReason;
    const wasTruncated = finishReason === "MAX_TOKENS";
    if (wasTruncated) {
      console.warn("Response truncated — hit max output tokens");
    }
    if (finishReason === "SAFETY") {
      return new Response(
        JSON.stringify({ error: "Content was filtered by safety settings. Try rephrasing." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const responseText = result.response.text();
    console.log(`Gemini response: ${responseText.length} chars, finishReason=${finishReason}`);

    let parsed: any;
    try {
      parsed = parseJsonResponse(responseText, wasTruncated);
    } catch (parseErr) {
      console.error("JSON parse failed. First 500 chars:", responseText.substring(0, 500));
      console.error("Last 200 chars:", responseText.substring(responseText.length - 200));
      const userMsg = wasTruncated
        ? "The plan is very long and the response was cut off. Try pasting fewer weeks at a time."
        : "Could not parse AI response. Please try again or simplify your input.";
      return new Response(
        JSON.stringify({ error: userMsg }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!parsed.weeks || !Array.isArray(parsed.weeks)) {
      console.error("Missing weeks array. Keys:", Object.keys(parsed));
      return new Response(
        JSON.stringify({ error: "AI response missing 'weeks' array. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Normalize weeks
    const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    const weeks = parsed.weeks.map((week: any) => {
      const days = (week.days || []).map((day: any) => ({
        dayOfWeek: day.dayOfWeek,
        dayName: day.dayName || dayNames[(day.dayOfWeek || 1) - 1],
        session: day.session ?? 1,
        workoutType: day.workoutType || "rest",
        name: day.name || "Rest Day",
        description: day.description || "",
        totalDistanceMiles: day.totalDistanceMiles ?? null,
        estimatedDurationMinutes: day.estimatedDurationMinutes ?? null,
        steps: (day.steps || []).map((step: any, idx: number) => ({
          stepType: step.stepType || "active",
          durationType: step.durationType || "distance_miles",
          durationValue: step.durationValue || 0,
          pacePercentage: step.pacePercentage ?? null,
          paceSecondsPerKm: step.paceSecondsPerKm ?? null,
          paceSecondsPerKmHigh: step.paceSecondsPerKmHigh ?? null,
          notes: step.notes ?? null,
          order: idx,
        })),
      }));

      // Fill in missing days with rest (only if NO entry exists for that day)
      for (let d = 1; d <= 7; d++) {
        if (!days.find((day: any) => day.dayOfWeek === d)) {
          days.push({
            dayOfWeek: d,
            dayName: dayNames[d - 1],
            session: 1,
            workoutType: "rest",
            name: "Rest Day",
            description: "Recovery day",
            totalDistanceMiles: null,
            estimatedDurationMinutes: null,
            steps: [],
          });
        }
      }
      // Sort by dayOfWeek first, then session
      days.sort((a: any, b: any) => a.dayOfWeek - b.dayOfWeek || (a.session || 1) - (b.session || 1));

      return {
        weekNumber: week.weekNumber,
        label: week.label || `Week ${week.weekNumber}`,
        totalDistanceMiles: week.totalDistanceMiles ?? days.reduce((sum: number, d: any) => sum + (d.totalDistanceMiles || 0), 0),
        days,
      };
    });

    weeks.sort((a: any, b: any) => a.weekNumber - b.weekNumber);

    // Extract clarifications (only if user hasn't already answered)
    const clarifications = (!body.clarificationAnswers?.length && Array.isArray(parsed.clarifications))
      ? parsed.clarifications.filter((c: any) => c.question && c.id).slice(0, 3)
      : [];

    // Extract detected metadata
    const detectedMeta = parsed.detectedMeta ?? null;
    const planName = parsed.planName ?? null;

    // Determine which fields are missing / couldn't be detected
    const missingFields: string[] = [];
    if (!planName) missingFields.push("planName");
    if (!detectedMeta?.raceDistance) missingFields.push("raceDistance");
    if (!detectedMeta?.goalTime) missingFields.push("goalTime");
    if (!detectedMeta?.startDate) missingFields.push("startDate");

    console.log(`Parsed ${weeks.length} weeks, ${clarifications.length} clarifications, missing: [${missingFields.join(", ")}]`);

    return new Response(
      JSON.stringify({
        totalWeeks: weeks.length,
        planName,
        detectedMeta,
        missingFields,
        clarifications,
        weeks,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Parse training plan error:", error?.message || error);
    const msg = error?.message || "";
    if (msg.includes("Could not parse") || msg.includes("JSON")) {
      return new Response(
        JSON.stringify({ error: "Could not parse the AI response. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    return internalErrorResponse(corsHeaders);
  }
});

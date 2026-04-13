import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateLength, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";

import { corsHeaders } from "../_shared/cors.ts";

interface ParseRequest {
  text: string;
  goalTimeSeconds?: number;
  raceDistance?: string;
  currentPhase?: string;
}

interface ImportedStep {
  stepType: string;
  durationType: string;
  durationValue: number;
  pacePercentage: number | null;
  paceSecondsPerKm: number | null;
  paceSecondsPerKmHigh: number | null;
  notes: string | null;
}

interface ImportedDay {
  dayOfWeek: number;
  dayName: string;
  workoutType: string;
  name: string;
  description: string;
  totalDistanceMiles: number | null;
  estimatedDurationMinutes: number | null;
  steps: ImportedStep[];
}

function parseJsonResponse(text: string): unknown {
  // Strategy 1: Direct parse
  try {
    return JSON.parse(text);
  } catch { /* continue */ }

  // Strategy 2: Extract from markdown code block
  const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    try {
      return JSON.parse(codeBlockMatch[1].trim());
    } catch { /* continue */ }
  }

  // Strategy 3: Find first { to last }
  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    try {
      return JSON.parse(text.substring(firstBrace, lastBrace + 1));
    } catch { /* continue */ }
  }

  throw new Error("Could not parse AI response as JSON");
}

function buildPrompt(text: string, goalTimeSeconds?: number, raceDistance?: string, currentPhase?: string): string {
  const raceContext = goalTimeSeconds
    ? `The athlete is training for a ${raceDistance || "marathon"} with a goal time of ${Math.floor(goalTimeSeconds / 3600)}:${String(Math.floor((goalTimeSeconds % 3600) / 60)).padStart(2, "0")}:${String(goalTimeSeconds % 60).padStart(2, "0")}. They are in the "${currentPhase || "support"}" phase.`
    : "No specific race goal provided. Use reasonable defaults for a recreational runner.";

  return `You are a running coach assistant. Parse the following training week description into structured workout data.

${raceContext}

IMPORTANT RULES:
- All days Monday through Sunday (dayOfWeek 1-7) MUST be included in the output
- Days not mentioned in the text should be inferred as "rest" days
- Keep distances in their ORIGINAL units. Use "distance_km" for kilometers, "distance_miles" for miles, "distance_meters" for meters
- For rest days, set workoutType to "rest", name to "Rest Day", steps to empty array

DOUBLES (TWO RUNS IN ONE DAY):
- When a day has two separate sessions (e.g., "AM: 1hr easy / PM: tempo"), create TWO entries for that dayOfWeek with different "session" numbers:
  * First run: "session": 1
  * Second run: "session": 2
- The dayOfWeek is the SAME for both entries — only session differs
- Each session gets its own steps, totalDistanceMiles, and estimatedDurationMinutes
- Look for patterns like: "2x1hr", "AM/PM", slashes separating runs, "+" joining different sessions
- If a day has multiple lines of workouts, each line is a separate session
- For single-session days, set "session": 1

PACE DATA:
- pacePercentage is relative to goal race pace (100% = race pace). Common values:
  - 65-70% = recovery/easy
  - 70-75% = easy/aerobic
  - 80-85% = steady/moderate
  - 85-90% = tempo/threshold
  - 95-100% = race pace
  - 100-105% = VO2max/5K pace
  - 105-115% = speed/sprint
- ALSO provide actual pace values when the training plan specifies them:
  * paceSecondsPerKm: pace in total seconds per km (fast/low end). e.g., 3:06/km = 186
  * paceSecondsPerKmHigh: pace in seconds per km (slow/high end for ranges). null if no range.
  * For named paces without specific values (e.g., "easy", "tempo"), set paceSecondsPerKm to null
  * For specific pace values (e.g., "3:06-3:10/km", "at 5:30 pace"), ALWAYS set paceSecondsPerKm
- For pace ranges like "3:06-3:10/km": paceSecondsPerKm=186, paceSecondsPerKmHigh=190
- "X'YY" or "X'YY pace" nearly always means per-km pace unless explicitly stated as per-mile

OUTPUT FORMAT - respond ONLY with this JSON structure, no other text:
{
  "days": [
    {
      "dayOfWeek": 1,
      "dayName": "Monday",
      "session": 1,
      "workoutType": "easy|tempo|intervals|long_run|recovery|rest|strides|progression",
      "name": "Human-readable workout name",
      "description": "Brief description of the workout",
      "totalDistanceMiles": 5.0,
      "estimatedDurationMinutes": 45,
      "steps": [
        {
          "stepType": "warmup|active|rest|recovery|cooldown",
          "durationType": "distance_km|distance_miles|distance_meters|time_seconds",
          "durationValue": 2.0,
          "pacePercentage": 70,
          "paceSecondsPerKm": null,
          "paceSecondsPerKmHigh": null,
          "notes": "Easy warm-up"
        }
      ]
    }
  ]
}

STEP TYPE GUIDE:
- "warmup": warm-up jog before the main workout
- "active": the main work portion (tempo miles, interval reps, easy run miles)
- "rest": standing/walking rest between intervals
- "recovery": jog recovery between intervals
- "cooldown": cool-down jog after workout

EXAMPLE 1 - Simple week:
Input: "Mon easy 5mi, Tue 6mi tempo, Wed off, Thu 5mi easy + strides, Fri rest, Sat 16mi long, Sun 4mi recovery"
Output:
{
  "days": [
    {"dayOfWeek":1,"dayName":"Monday","workoutType":"easy","name":"Easy Run","description":"Relaxed aerobic run","totalDistanceMiles":5.0,"estimatedDurationMinutes":47,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":5.0,"pacePercentage":70,"notes":"Easy conversational pace"}]},
    {"dayOfWeek":2,"dayName":"Tuesday","workoutType":"tempo","name":"Tempo Run","description":"Sustained tempo effort","totalDistanceMiles":10.0,"estimatedDurationMinutes":75,"steps":[{"stepType":"warmup","durationType":"distance_miles","durationValue":2.0,"pacePercentage":70,"notes":"Easy warm-up"},{"stepType":"active","durationType":"distance_miles","durationValue":6.0,"pacePercentage":88,"notes":"Tempo effort"},{"stepType":"cooldown","durationType":"distance_miles","durationValue":2.0,"pacePercentage":65,"notes":"Easy cool-down"}]},
    {"dayOfWeek":3,"dayName":"Wednesday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":4,"dayName":"Thursday","workoutType":"strides","name":"Easy + 6x100m Strides","description":"Easy run with strides for leg speed","totalDistanceMiles":5.5,"estimatedDurationMinutes":50,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":5.0,"pacePercentage":70,"notes":"Easy run"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 1"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 2"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 3"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 4"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 5"},{"stepType":"recovery","durationType":"distance_meters","durationValue":100,"pacePercentage":null,"notes":"Walk back"},{"stepType":"active","durationType":"distance_meters","durationValue":100,"pacePercentage":110,"notes":"Stride 6"}]},
    {"dayOfWeek":5,"dayName":"Friday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":6,"dayName":"Saturday","workoutType":"long_run","name":"Long Run","description":"Endurance builder","totalDistanceMiles":16.0,"estimatedDurationMinutes":144,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":16.0,"pacePercentage":75,"notes":"Easy long run pace"}]},
    {"dayOfWeek":7,"dayName":"Sunday","workoutType":"recovery","name":"Recovery Run","description":"Very easy recovery jog","totalDistanceMiles":4.0,"estimatedDurationMinutes":40,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":4.0,"pacePercentage":65,"notes":"Super easy recovery"}]}
  ]
}

EXAMPLE 2 - Complex week with intervals:
Input: "Tuesday: 2mi WU, 8x800m at 5K pace with 400m jog, 2mi CD. Saturday: 20mi long run, last 6 at marathon pace"
Output:
{
  "days": [
    {"dayOfWeek":1,"dayName":"Monday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":2,"dayName":"Tuesday","workoutType":"intervals","name":"8x800m at 5K Pace","description":"VO2max intervals with jog recovery","totalDistanceMiles":10.0,"estimatedDurationMinutes":75,"steps":[{"stepType":"warmup","durationType":"distance_miles","durationValue":2.0,"pacePercentage":70,"notes":"Easy warm-up"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 1 at 5K pace"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 2"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 3"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 4"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 5"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 6"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 7"},{"stepType":"recovery","durationType":"distance_meters","durationValue":400,"pacePercentage":65,"notes":"Jog recovery"},{"stepType":"active","durationType":"distance_meters","durationValue":800,"pacePercentage":105,"notes":"800m rep 8 - last one!"},{"stepType":"cooldown","durationType":"distance_miles","durationValue":2.0,"pacePercentage":65,"notes":"Easy cool-down"}]},
    {"dayOfWeek":3,"dayName":"Wednesday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":4,"dayName":"Thursday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":5,"dayName":"Friday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]},
    {"dayOfWeek":6,"dayName":"Saturday","workoutType":"long_run","name":"Long Run w/ MP Finish","description":"Long run finishing at marathon pace","totalDistanceMiles":20.0,"estimatedDurationMinutes":160,"steps":[{"stepType":"active","durationType":"distance_miles","durationValue":14.0,"pacePercentage":75,"notes":"Easy long run pace"},{"stepType":"active","durationType":"distance_miles","durationValue":6.0,"pacePercentage":100,"notes":"Marathon pace finish"}]},
    {"dayOfWeek":7,"dayName":"Sunday","workoutType":"rest","name":"Rest Day","description":"Recovery day","totalDistanceMiles":null,"estimatedDurationMinutes":null,"steps":[]}
  ]
}

Now parse this training week:
${text}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify authenticated user from JWT
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    // Rate limiting
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

    if (!body.text || body.text.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Text is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const lengthErr = validateLength(body.text, "text", 5000);
    if (lengthErr) return validationErrorResponse(lengthErr, corsHeaders);

    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;
    const genAI = new GoogleGenerativeAI(geminiKey);
    const model = genAI.getGenerativeModel({
      model: "gemini-2.5-flash",
      generationConfig: {
        maxOutputTokens: 16384,
        temperature: 0.3,
        responseMimeType: "application/json",
        thinkingConfig: { thinkingBudget: 0 },
      },
    });

    const prompt = buildPrompt(body.text, body.goalTimeSeconds, body.raceDistance, body.currentPhase);

    let result;
    try {
      result = await model.generateContent(prompt);
    } catch (genError: any) {
      console.error("Gemini API error:", genError?.message || genError);
      return new Response(
        JSON.stringify({ error: "AI service error. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const responseText = result.response.text();

    let parsed: any;
    try {
      parsed = parseJsonResponse(responseText);
    } catch {
      console.error("JSON parse failed. First 300 chars:", responseText.substring(0, 300));
      return new Response(
        JSON.stringify({ error: "Could not parse AI response. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!parsed.days || !Array.isArray(parsed.days)) {
      return new Response(
        JSON.stringify({ error: "AI response missing 'days' array" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate and normalize
    const days = parsed.days.map((day: any) => ({
      dayOfWeek: day.dayOfWeek,
      dayName: day.dayName || ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day.dayOfWeek - 1],
      session: day.session ?? 1,
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
        paceSecondsPerKm: step.paceSecondsPerKm ?? null,
        paceSecondsPerKmHigh: step.paceSecondsPerKmHigh ?? null,
        notes: step.notes ?? null,
        order: idx,
      })),
    }));

    // Ensure all 7 days present (only add rest if NO entry exists for that day)
    for (let d = 1; d <= 7; d++) {
      if (!days.find((day: any) => day.dayOfWeek === d)) {
        const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
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

    days.sort((a: any, b: any) => a.dayOfWeek - b.dayOfWeek || (a.session || 1) - (b.session || 1));

    return new Response(
      JSON.stringify({ days }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Parse training week error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

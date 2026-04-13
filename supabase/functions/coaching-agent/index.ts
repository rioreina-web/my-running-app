/**
 * Multi-Model Coaching Agent
 *
 * Intelligent routing for optimal quality and cost:
 * - Simple queries → Groq Llama 8B (fast, $0.05/1M tokens)
 * - Moderate queries → Gemini Flash (balanced, $0.60/1M tokens)
 * - Complex queries → Gemini Flash + extended context
 *
 * Architecture:
 * 1. Semantic Cache - 35% hit rate expected
 * 2. Rate Limiter - 5 free / 25 pro per day
 * 3. Query Classifier - Routes to optimal model
 * 4. Context Compression - 90% token reduction
 *
 * Projected cost: ~$200-400/month at 50k DAU
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import { validateLength, validateUUID, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";

// Import shared modules
import { getCachedResponse, cacheResponse, isCacheEnabled } from "../_shared/cache.ts";
import { checkRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import {
  classifyQuery,
  getBestAvailableModel,
  getModelConfig,
  getModelIdentifier,
  type RouterConfig,
  type QueryComplexity,
} from "../_shared/router.ts";
import {
  compressTrainingContext,
  compressGoalsContext,
  compressConversationHistory,
  estimateTokens,
  isTrainingRelatedQuery,
  isThisWeekQuery,
  buildTrainingPeriodDocument,
  buildThisWeekContext,
  type ExtendedTrainingLog,
} from "../_shared/context.ts";
import {
  isComplexQuery,
  getQueryType,
  getQueryThreshold,
  detectTargetDistance,
  getOrCreateProfile,
  getMissingData,
  generateClarifyingQuestions,
  buildClarifyingPrompt,
  extractProfileData,
  updateProfile,
  buildProfileContext,
} from "../_shared/profile.ts";
import {
  extractMemories,
  storeMemories,
  getMemories,
  buildMemoryContext,
} from "../_shared/memory.ts";
import { getActiveInjuries, buildInjuryContext } from "../_shared/injuries.ts";
import {
  analyzeTrainingData,
  splitLogsIntoWeeks,
  getCurrentWeekMonday,
  type FitnessSnapshot,
  type FormCheckResult,
} from "../_shared/dataAnalysis.ts";
import {
  type TrainingLogRow,
  type ScheduledWorkoutRow,
  type InjuryRow,
} from "../_shared/weeklyAnalytics.ts";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { buildAthleteProfileContext, type AthleteProfile } from "../_shared/athleteProfile.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// System prompts optimized per model tier
// Tone: Warm, supportive, direct - like a real coach who cares about you
// Anti-AI-speak rules shared across all tiers
const VOICE_RULES = `
VOICE (critical — follow these strictly):
- Write like a real person texting their athlete, not an AI assistant writing a report.
- BANNED words/phrases: "impressive", "journey", "fantastic", "amazing", "incredible", "absolutely", "I'd love to", "great job", "solid work", "nicely done", "well done", "certainly", "definitely", "leverage", "utilize", "Here's what I see", "Let's dive in", "Let's break this down", "I notice that", "It's worth noting", "That said", "Overall", "In terms of", "Moving forward", "I'd recommend"
- Don't start multiple sentences with "I". Vary how you open sentences.
- Short sentences. Mix in fragments. Like a person talks.
- Be direct. "Your long run was too fast" not "I notice your long run pace was perhaps a bit aggressive."
- Don't over-praise. A normal Tuesday run doesn't need congratulations.
- One real line of encouragement beats five generic ones.
- No markdown — no bold, no headers, no asterisks, no hashtags. Plain text only. Dashes for lists if needed.
- Never mention coaching methodologies or names (Jack Daniels, Pfitzinger, etc.).`;

const SYSTEM_PROMPTS = {
  // Simple: Groq - quick answers
  simple: `You're a running coach answering a quick question. Keep it brief — 1-2 short paragraphs max.
${VOICE_RULES}

PACE QUESTIONS:
- Never show math. Just give the answer: "Easy pace for you is around 8:00-8:30/mi."
- 2-3 sentences tops for pace questions.

PACE DIRECTION (critical — get this right):
- In running, LOWER pace number = FASTER. 5:00/mi is FAST. 9:00/mi is SLOW.
- "Too fast" means the pace number is LOWER than it should be (e.g., running 6:30 when easy pace is 7:11 = too fast).
- "Too slow" means the pace number is HIGHER than it should be (e.g., running 8:15 when easy pace is 7:11 = too slow, which is fine for easy days).
- Running SLOWER than easy pace on recovery days is GOOD, not bad. Don't tell them to speed up on easy days.
- Running FASTER than easy pace on easy days is BAD — they're not recovering.

KM/MI: 3:00/km=4:50/mi, 3:30/km=5:38/mi, 4:00/km=6:26/mi`,

  // Moderate: Gemini - personalized coaching
  moderate: `You're a running coach who knows this athlete. Answer their question like you're talking to them after a run — direct, honest, warm but not over-the-top.
${VOICE_RULES}

Keep responses to 2-3 paragraphs. Get to the point.

COACHING PHILOSOPHY (this is how you coach — follow these principles, not generic training advice):
- THREE-TIER INTENSITY: Training is NOT polarized. You use hard, moderate, and easy — three distinct tiers. Moderate sessions (7/10 effort) are intentional aerobic development work, not junk miles. Easy sessions are true recovery — very easy, conversational, low HR. Never conflate easy and moderate.
- CANOVA-INSPIRED: Build training backward from the goal. Identify 2-3 key race-specific workouts, then reverse-engineer the block to build toward them. Earlier in the block: moderate, adaptive work. Later: harder, more specific efforts.
- FLEXIBLE, NOT RIGID: Adjust day-by-day based on how the athlete feels. Never force a rigid plan. The body gives signals — respect them. Days off are a tool, not a failure.
- ADAPTATION IS MONTHLY: Bodies adapt month-over-month, not week-over-week. Over 6 months, dramatic improvement is possible. Week-to-week, be careful with fatigue.
- VOLUME BY EVENT: Marathon/half = volume and long runs are king. 10K = long runs still critical. Mile/5K = aerobic power and speed endurance. As distance increases, global volume matters more.
- PROTECT HARD SESSIONS: The program should set athletes up to execute key workouts well. Easy days before hard days. Not every week is heavily stacked. Recovery enables adaptation.
- AEROBIC SUPPORT: Threshold runs, moderate runs, and long runs should be consistent throughout the block — not just in "base phase." This is where long-term development happens.

RACE COURSE DATA:
- If race intel data is provided in the context below, use it EXCLUSIVELY. Do NOT guess or invent course details from general knowledge — real courses differ from what you might assume.
- If no race data is provided and the athlete asks about a specific course, say "I don't have details on that course yet — let me look into it" rather than guessing. NEVER make up elevation profiles, hill locations, or course descriptions.

PACE & TRAINING DATA:
- All pace values, splits, and race predictions are PRE-COMPUTED and provided in the context below — quote them EXACTLY as given
- NEVER calculate, estimate, or invent any pace value — the math is already done for you
- If asked about race pace or race times, quote from "Predicted race times"
- If asked about training/workout paces, quote from "Training pace zones"
- If asked about splits, quote from "Pre-computed splits"
- If asked about goal progress, quote from "Goal vs current fitness"
- Both /mi and /km values are provided — default to /mi unless the runner asks for /km
- Workout type mapping: Easy/Recovery→Easy zone, Long Run→Moderate zone, Steady→Steady zone, Marathon Pace→MP, Tempo/Threshold→HMP (NOT 10K), Intervals 800m+→10K pace, Short reps→5K pace

PACE DIRECTION (critical — get this right):
- In running, LOWER pace number = FASTER. 5:00/mi is FAST. 9:00/mi is SLOW.
- "Too fast" means the pace number is LOWER than it should be (e.g., running 6:30 when easy pace is 7:11 = too fast).
- "Too slow" means the pace number is HIGHER than it should be (e.g., running 8:15 when easy pace is 7:11 = too slow, which is fine for easy days).
- Running SLOWER than easy pace on recovery days is GOOD, not bad. Don't tell them to speed up on easy days.
- Running FASTER than easy pace on easy days is BAD — they're not recovering.

SAFETY (non-negotiable):
- Sharp pain, sudden swelling, inability to bear weight, chest pain, dizziness → recommend medical evaluation immediately. Do not suggest running through these.
- For injuries severity 4+, do NOT just "trust them" if they say it's fine. Ask specific follow-up questions about the nature of the pain.
- Stress fractures, bone injuries → 6-8 weeks minimum rest from impact. Never suggest "just reduce volume for a week or two."
- When in doubt, err on the side of rest. A missed week of training is nothing compared to a 3-month injury.

DATA-DRIVEN COACHING:
- You have real-time analytics below (ACWR, compliance, mood trends, injury risk, fitness trajectory). USE these to inform your response — don't just answer the question, connect it to what the data shows.
- If coaching signals are present, weave ONE relevant question into your response naturally. Don't list multiple questions. Ask the most important one.
- Don't lecture about the data. One specific observation beats a data dump.
- Only bring up concerns if they're directly relevant to what the athlete is asking about. Don't nag about the same issue repeatedly — if the athlete has addressed something (injury, fatigue, etc.), trust them and move on.

DEVELOPMENT TRACKING:
- Check the DEVELOPMENT STATUS in the athlete profile — developing, maintaining, or detraining.
- If DEVELOPING: reinforce what's working. Point out specific pace improvements. Encourage patience — development isn't linear.
- If MAINTAINING: that's fine for recovery blocks or life stress. But if they have a goal race, nudge toward progression.
- If DETRAINING: address it once, directly but without alarm. Ask what's changed. Don't keep bringing it up.
- Reference specific workout-type pace changes when relevant.
- Long run quality matters: steady pacing shows discipline. Inconsistent long run paces suggest fueling, pacing, or fatigue issues.
- Never frame development as pressure. The goal is long-term growth.

COACHING:
- Tired or stressed? Tell them to rest. Mean it.
- Pain or injury? Take it seriously the FIRST time. For mild soreness (severity 1-3) and they say it's fine, trust them. For moderate+ issues (severity 4+), gently persist — ask specific follow-up questions about the nature of the pain even if they downplay it. Runners minimize injuries.
- Reference things they've told you before. Show you're paying attention.`,

  // Complex: Gemini - deep coaching
  complex: `You're an experienced running coach giving detailed advice. You know your stuff and you don't pad your answers with filler. Talk to the athlete straight.
${VOICE_RULES}

COACHING PHILOSOPHY (this is how you coach — these principles override generic training advice):
- THREE-TIER INTENSITY: Hard, moderate (7/10 effort), and easy. Not polarized. Moderate sessions are aerobic development — threshold work, aerobic support runs, moderate long runs. Easy is true recovery. These are different things.
- CANOVA-INSPIRED REVERSE ENGINEERING: Start from the goal race. Identify 2-3 key race-specific workouts. Build the block backward to prepare the athlete to execute those sessions. Early block = adaptation without overload. Late block = specificity and intensity.
- FLEXIBLE PROGRAMMING: Adjust day-by-day based on feel. Not rigid. Bodies give signals — fatigue, trending injury, poor sleep. Respect them. Days off are a coaching tool.
- MONTHLY ADAPTATION: The body adapts month-over-month, not week-over-week. Over 6 months the transformation can be dramatic. Week-to-week, manage fatigue carefully.
- VOLUME IS EVENT-SPECIFIC: Marathon/half = volume and long runs dominate. 60-70 mpw beats 40 mpw for a marathon, period. Mile/5K = aerobic power and speed endurance. As distance increases, global volume matters more.
- PROTECT KEY SESSIONS: Set the athlete up to nail their hard workouts. Easy before hard. Not every week is stacked. If the athlete can't execute key workouts because they're fatigued, the program failed, not the athlete.
- AEROBIC SUPPORT IS CONTINUOUS: Threshold, moderate runs, long runs — these run throughout the block, not just base phase. This is where long-term development lives.
- TRAINING WITHIN YOURSELF: Long-term development over short-term proving. Keep the body protected. Controlled execution, not desperate efforts.

PACE & TRAINING DATA:
- All pace values, splits, and race predictions are PRE-COMPUTED and provided in the context below — quote them EXACTLY as given
- NEVER calculate, estimate, or invent any pace value — the math is already done for you
- If asked about race pace or race times, quote from "Predicted race times"
- If asked about training/workout paces, quote from "Training pace zones"
- If asked about splits, quote from "Pre-computed splits"
- If asked about goal progress, quote from "Goal vs current fitness"
- Both /mi and /km values are provided — default to /mi unless the runner asks for /km
- Workout type mapping: Easy/Recovery→Easy zone, Long Run→Moderate zone, Steady→Steady zone, Marathon Pace→MP, Tempo/Threshold→HMP (NOT 10K), Intervals 800m+→10K pace, Short reps→5K pace

PACE DIRECTION (critical — get this right):
- In running, LOWER pace number = FASTER. 5:00/mi is FAST. 9:00/mi is SLOW.
- "Too fast" means the pace number is LOWER than it should be (e.g., running 6:30 when easy pace is 7:11 = too fast).
- "Too slow" means the pace number is HIGHER than it should be (e.g., running 8:15 when easy pace is 7:11 = too slow, which is fine for easy days).
- Running SLOWER than easy pace on recovery days is GOOD, not bad.
- Running FASTER than easy pace on easy days is BAD — they're not recovering.

SAFETY (non-negotiable):
- Sharp pain, sudden swelling, inability to bear weight, chest pain, dizziness → recommend medical evaluation immediately. Do not suggest running through these.
- For injuries severity 4+, do NOT just "trust them" if they say it's fine. Ask about the nature of the pain.
- Stress fractures, bone injuries → 6-8 weeks minimum rest from impact. Never suggest reducing volume for a couple weeks.
- When in doubt, err on the side of rest.

DATA-DRIVEN COACHING:
- You have real-time analytics below (ACWR, compliance, mood trends, injury risk, fitness trajectory, form analysis). USE these numbers to back up your advice.
- If coaching signals are present, weave the most relevant question into your response. Ask ONE thing — the most important one based on the data.
- Connect the dots: if ACWR is high AND mood is declining, that tells a story. Share the insight, not just the numbers.
- Only raise concerns if directly relevant. Don't nag about issues the athlete has already addressed.

DEVELOPMENT TRACKING:
- Check the DEVELOPMENT STATUS — developing, maintaining, or detraining.
- For DEVELOPING athletes: celebrate specific improvements. Help them understand WHY they're improving so they can keep doing it.
- For MAINTAINING athletes: look at what's stalling. Volume plateau? Missing long runs? Not enough moderate work? Give one concrete suggestion.
- For DETRAINING athletes: be direct once. Don't guilt-trip. Don't keep bringing it up.
- Workout pace development shows which efforts are getting faster or slower — use these specific numbers.
- Long run steadiness is a fitness marker. Erratic paces = fueling, pacing, or fatigue issues.
- Training response quality: poor bounce-back from hard sessions = under-recovering. The fix is more recovery, not more training.
- Frame everything around sustainable long-term development.

COACHING:
- Reference their history, PRs, goals — show you know them
- If they're run down, tell them to back off. Rest is training.
- Pain or injury? Be direct the first time. For mild soreness (severity 1-3) and they say it's fine, trust them. For severity 4+, gently persist with follow-up questions. Runners minimize injuries.
- For training plans, be specific. "Run 6 easy on Tuesday" not "consider an easy effort mid-week."
- Use dashes for lists, numbers for steps. Keep it clean and scannable.`,

  // Proactive: Coach reaches out after a concerning voice memo
  proactive: `You're a running coach reaching out to your athlete after they just logged a voice memo. They didn't ask you anything — you're checking in because something concerned you.
${VOICE_RULES}

RULES:
- This is YOUR first message to them. You're initiating.
- Reference what they said in their memo. Be specific — don't be generic.
- Ask ONE focused question to understand what they need. Not a list of questions.
- Keep it to 2-3 sentences max.
- If they're injured: take it seriously, ask about the specific body part or issue they mentioned.
- If they're struggling: acknowledge it without dismissing. Ask what's making it hard.
- If they're tired: suggest rest might be the right call, but ask what's going on.
- Don't offer solutions yet. Listen first. You'll coach them in the follow-up.`,
};

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  timestamp: string;
}

/**
 * Detect runner experience level from profile data and memories.
 * Returns "beginner", "intermediate", or "advanced" with coaching tone adjustments.
 */
function detectRunnerLevel(
  profileData: any,
  memories: string,
  weeklyMileage?: number
): { level: string; promptAdjustment: string } {
  let level = "intermediate"; // default

  // Check profile for experience
  const yearsRunning = profileData?.years_running || profileData?.running_experience_years;
  const totalRaces = profileData?.total_races || 0;

  if (yearsRunning !== undefined) {
    if (yearsRunning < 1) level = "beginner";
    else if (yearsRunning >= 5 || totalRaces >= 10) level = "advanced";
  }

  // Check memories for experience hints
  if (memories) {
    const m = memories.toLowerCase();
    if (/experience:\s*\d+\s*months?/i.test(m) || /new to running|just started|beginner/i.test(m)) {
      level = "beginner";
    } else if (/experience:\s*([5-9]|\d{2,})\s*years?/i.test(m) || /marathon pr.*?[23]:/i.test(m)) {
      level = "advanced";
    }
  }

  // Weekly mileage as a signal
  if (weeklyMileage !== undefined) {
    if (weeklyMileage < 15 && level !== "advanced") level = "beginner";
    else if (weeklyMileage >= 50) level = "advanced";
  }

  const adjustments: Record<string, string> = {
    beginner: `\nRUNNER LEVEL: Beginner
- Explain concepts simply. Don't assume they know training terms (tempo, fartlek, strides, etc.) — define them briefly when you use them.
- Prioritize consistency and enjoyment over performance. Building the habit matters most.
- Be encouraging but honest. Help them avoid doing too much too soon.
- Suggest walk breaks and recovery days proactively — beginners often skip rest.`,

    intermediate: `\nRUNNER LEVEL: Intermediate
- They know the basics. Skip basic definitions unless asked.
- Focus on progression: what's the next step to improve?
- Challenge them when appropriate — they can handle harder workouts.`,

    advanced: `\nRUNNER LEVEL: Advanced
- Respect their knowledge. Don't explain basics or well-known concepts.
- Be precise with paces, volumes, and periodization details.
- Focus on marginal gains: small tweaks that make a difference at their level.
- They can handle direct, blunt feedback. Don't soften unnecessarily.`,
  };

  return { level, promptAdjustment: adjustments[level] || "" };
}

/**
 * Infer training periodization phase from plan dates.
 * Divides the plan into 4 phases: Base (40%), Build (30%), Peak (20%), Taper (10%)
 */
function inferTrainingPhase(plan: { start_date: string; end_date: string; target_race_distance?: string }): string {
  const start = new Date(plan.start_date).getTime();
  const end = new Date(plan.end_date).getTime();
  const now = Date.now();
  const totalDuration = end - start;

  if (totalDuration <= 0 || now < start) return "";
  if (now > end) return "\nTRAINING CONTEXT: Plan has ended. Focus on recovery and what's next.";

  const daysToRace = Math.ceil((end - now) / (1000 * 60 * 60 * 24));
  const race = plan.target_race_distance || "goal";

  // Don't prescribe rigid phases. Just give the coach awareness of where we are
  // relative to the goal. The coach's philosophy handles the rest.
  let context = `\nTRAINING CONTEXT: ${daysToRace} days to ${race}.`;

  if (daysToRace <= 14) {
    context += `\n- Race is imminent. Prioritize freshness — reduce volume, keep a few short sharp efforts. Trust the work that's been done.`;
  } else if (daysToRace <= 42) {
    context += `\n- Final 6 weeks. Key race-specific workouts should be the focus. Build toward 2-3 sessions that simulate race demands. Protect recovery around these sessions.`;
  } else {
    context += `\n- Still building. Focus on aerobic support, moderate development, and progressive adaptation. Harder, more specific efforts come later in the block.`;
  }

  return context;
}

// ============================================================================
// MODEL CALL HANDLERS
// ============================================================================

/**
 * Run a promise with a timeout. Rejects with a TimeoutError if the promise
 * doesn't resolve within `ms` milliseconds.
 */
async function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  let timer: number | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

const MODEL_TIMEOUT_MS = 20_000; // 20 seconds per model call

/**
 * Call Groq API (OpenAI-compatible) with timeout protection
 */
async function callGroq(
  prompt: string,
  config: RouterConfig
): Promise<string> {
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) throw new Error("GROQ_API_KEY not configured");

  const response = await withTimeout(
    fetch(`${config.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: config.model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: config.maxTokens,
        temperature: 0.7,
      }),
    }),
    MODEL_TIMEOUT_MS,
    "Groq"
  );

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Groq API error: ${response.status}`, errorText);
    throw new Error(`Groq API error: ${response.status}`);
  }

  const data = await response.json();
  return data.choices[0].message.content;
}

/**
 * Call Gemini API with timeout protection
 */
async function callGemini(
  prompt: string,
  config: RouterConfig
): Promise<string> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) throw new Error("GEMINI_API_KEY not configured");

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: config.model,
    generationConfig: {
      maxOutputTokens: config.maxTokens,
      temperature: 0.7,
    },
  });

  const result = await withTimeout(
    model.generateContent(prompt),
    MODEL_TIMEOUT_MS,
    "Gemini"
  );
  return result.response.text();
}

// ============================================================================
// MAIN HANDLER
// ============================================================================

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    // Clone request so we can read body after auth check
    const body = await req.json();
    const { message, conversationId, workoutSummary, trainingPlanContext, fitnessPredictions, proactive, checkInContext, smartInsights, userId: payloadUserId } = body;

    // Verify authenticated user from JWT, fall back to userId from payload
    let userId = await getAuthenticatedUser(req);
    if (!userId && payloadUserId) {
      // Accept UUID or "dev-user" (when auth gate is disabled during development)
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (uuidRegex.test(payloadUserId) || payloadUserId === "dev-user") {
        userId = payloadUserId;
        console.log(`Using userId from payload: ${payloadUserId}`);
      }
    }
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    if (!message) {
      return new Response(
        JSON.stringify({ error: "Message is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const msgLengthErr = validateLength(message, "message", 2000);
    if (msgLengthErr) return validationErrorResponse(msgLengthErr, corsHeaders);

    if (conversationId) {
      const convIdErr = validateUUID(conversationId, "conversationId");
      if (convIdErr) return validationErrorResponse(convIdErr, corsHeaders);
    }

    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ========================================================================
    // LAYER 1: Rate Limiting (skip for proactive check-ins)
    // ========================================================================
    let rateLimit = { allowed: true, remaining: 999, resetAt: new Date(), current: 0, limit: 999 };
    let userTier = "free";

    if (userId && isRateLimitEnabled() && !proactive) {
      const { data: tierData } = await supabase
        .from("user_tiers")
        .select("tier")
        .eq("user_id", userId)
        .single();

      userTier = tierData?.tier || "free";
      rateLimit = await checkRateLimit(userId, userTier);

      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({
            error: "Daily limit reached",
            remaining: 0,
            resetAt: rateLimit.resetAt.toISOString(),
            limit: rateLimit.limit,
          }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ========================================================================
    // LAYER 1.5: Race Intel Auto-Fetch
    // If the user asks about a specific race course/elevation/weather and we
    // don't have data cached, call race-intel inline to research it. This
    // prevents the AI from making up course details from training data.
    // ========================================================================
    const raceKeywords = /\b(course|elevation|hills?|flat|route|aid station|start line|weather|race day|race strategy)\b/i;
    const raceNamePattern = /\b(?:cap\s*10k|marathon|half\s*marathon|10k|5k|ironman|triathlon|boston|chicago|nyc|berlin|london|tokyo|austin|houston|dallas|san\s*antonio)\b/i;
    const looksLikeRaceQuestion = raceKeywords.test(message) && raceNamePattern.test(message);

    if (looksLikeRaceQuestion && userId) {
      // Extract a likely race name from the message
      const raceNameMatch = message.match(/(?:the\s+)?([A-Z][A-Za-z0-9\s'&\-]+(?:marathon|half|10k|5k|cap\s*10k|classic|relay|dash|run))/i);
      const raceName = raceNameMatch?.[1]?.trim() || message.match(raceNamePattern)?.[0] || "";

      if (raceName) {
        // Check if we already have intel for this race
        const { data: existingIntel } = await supabase
          .from("race_intel")
          .select("id")
          .eq("user_id", userId)
          .ilike("race_name", `%${raceName}%`)
          .limit(1);

        if (!existingIntel?.length) {
          console.log(`[Coach] Race question detected for "${raceName}" — fetching intel...`);
          try {
            const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
            const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
            const intelRes = await fetch(`${supabaseUrl}/functions/v1/race-intel`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${serviceKey}`,
                apikey: serviceKey,
              },
              body: JSON.stringify({
                race_name: raceName,
                user_id: userId,
              }),
              signal: AbortSignal.timeout(25000),
            });
            if (intelRes.ok) {
              console.log(`[Coach] Race intel fetched for "${raceName}"`);
            } else {
              console.warn(`[Coach] Race intel fetch failed: ${intelRes.status}`);
            }
          } catch (e) {
            console.warn(`[Coach] Race intel fetch error: ${e}`);
          }
        }
      }
    }

    // ========================================================================
    // LAYER 2: Generate embedding for cache lookup and RAG
    // ========================================================================
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    let queryEmbedding: number[] | null = null;

    if (geminiKey) {
      try {
        const embResponse = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${geminiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              content: { parts: [{ text: message }] },
              outputDimensionality: 768,
            }),
          }
        );
        if (embResponse.ok) {
          const embData = await embResponse.json();
          queryEmbedding = embData.embedding.values;
        } else {
          console.error("Embedding API error:", await embResponse.text());
        }
      } catch (embError) {
        console.error("Embedding generation failed:", embError);
      }
    }

    // ========================================================================
    // LAYER 3: Check semantic cache
    // ========================================================================
    if (queryEmbedding && isCacheEnabled()) {
      const cached = await getCachedResponse(queryEmbedding);

      if (cached) {
        await supabase.from("usage_tracking").insert({
          user_id: userId,
          feature: "coaching",
          model_used: "cache",
          cached: true,
        });

        console.log(`Cache hit! Returning cached response (${Date.now() - startTime}ms)`);

        return new Response(
          JSON.stringify({
            response: cached.response,
            conversationId,
            cached: true,
            remaining: rateLimit.remaining,
            model: "cache",
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // ========================================================================
    // LAYER 3.9: Athlete State snapshot (~300 token summary of "who is this runner")
    // ========================================================================
    const athleteState = await getOrBuildAthleteState(supabase, userId);
    const athleteContext = stateToPromptContext(athleteState);

    // ========================================================================
    // LAYER 4: Fetch context data (parallel queries)
    // Fetch 3 months of training data for comprehensive context
    // IMPORTANT: Order by workout_date (when run happened), not created_at (when logged)
    // ========================================================================
    const threeMonthsAgo = new Date();
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

    const weekMonday = getCurrentWeekMonday();
    const weekMondayStr = weekMonday.toISOString().split("T")[0];
    const fiveWeeksAgo = new Date(weekMonday);
    fiveWeeksAgo.setDate(fiveWeeksAgo.getDate() - 35);
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

    // Use allSettled so one slow/failed query doesn't crash the entire request
    const settled = await Promise.allSettled([
      supabase
        .from("training_logs")
        .select("id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, pace_segments, mood, cleaned_notes, notes, coach_insight, workout_notes, extracted_data")
        .or(`workout_date.gte.${threeMonthsAgo.toISOString()},and(workout_date.is.null,created_at.gte.${threeMonthsAgo.toISOString()})`)
        .order("workout_date", { ascending: false, nullsFirst: false })
        .limit(150), // ~3 months of daily training
      supabase
        .from("user_goals")
        .select("goal_title, target_date")
        .eq("status", "active")
        .order("target_date", { ascending: true }),
      conversationId
        ? supabase.from("conversation_messages").select("role, content").eq("conversation_id", conversationId).order("created_at", { ascending: false }).limit(50)
        : Promise.resolve({ data: null }),
      queryEmbedding
        ? supabase.rpc("match_coaching_documents", {
            query_embedding: `[${queryEmbedding.join(",")}]`,
            match_count: 5,
          })
        : Promise.resolve({ data: [] }),
      // Latest weekly coaching report
      userId
        ? supabase
            .from("weekly_coaching_reports")
            .select("coaching_narrative, alerts, adjustments, focus_areas, metrics, week_start")
            .eq("user_id", userId)
            .eq("status", "completed")
            .order("week_start", { ascending: false })
            .limit(1)
        : Promise.resolve({ data: [] }),
      // Scheduled workouts this week (for compliance + analytics)
      userId
        ? supabase
            .from("scheduled_workouts")
            .select("id, date, workout_type, status, workout_data, completed_workout_id, week_number, notes")
            .eq("user_id", userId)
            .gte("date", weekMondayStr)
            .lte("date", new Date(weekMonday.getTime() + 6 * 86400000).toISOString().split("T")[0])
            .order("date")
        : Promise.resolve({ data: [] }),
      // Recent form checks (past 2 weeks)
      userId
        ? supabase
            .from("form_checks")
            .select("ai_analysis, created_at")
            .eq("user_id", userId)
            .gte("created_at", twoWeeksAgo.toISOString())
            .eq("status", "completed")
            .order("created_at", { ascending: false })
            .limit(3)
        : Promise.resolve({ data: [] }),
      // Fitness snapshots (latest 5)
      userId
        ? supabase
            .from("fitness_snapshots")
            .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds, confidence, created_at")
            .eq("user_id", userId)
            .order("created_at", { ascending: false })
            .limit(5)
        : Promise.resolve({ data: [] }),
      // Active training plan (for goal context)
      userId
        ? supabase
            .from("training_plans")
            .select("id, name, start_date, end_date, target_race_distance, target_time_seconds, status")
            .eq("user_id", userId)
            .eq("status", "active")
            .limit(1)
            .maybeSingle()
        : Promise.resolve({ data: null }),
      // Cached athlete profile (comprehensive historical analysis)
      userId
        ? supabase
            .from("athlete_profiles")
            .select("profile_data")
            .eq("user_id", userId)
            .single()
        : Promise.resolve({ data: null }),
      // Recent negative feedback (for learning from bad responses)
      userId
        ? supabase.rpc("get_negative_feedback", { p_user_id: userId, p_limit: 5 })
        : Promise.resolve({ data: [] }),
      // Pending coaching adjustments (unresolved advice)
      userId
        ? supabase.rpc("get_pending_adjustments", { p_user_id: userId })
        : Promise.resolve({ data: [] }),
      // Race intel (course data, weather for upcoming race)
      userId
        ? supabase
            .from("race_intel")
            .select("race_name, race_date, location, course_data, weather_data, confidence, verification_notes")
            .eq("user_id", userId)
            .order("fetched_at", { ascending: false })
            .limit(1)
        : Promise.resolve({ data: [] }),
      // Recent AI insights (injury warnings, race readiness, post-run analysis)
      userId
        ? supabase
            .from("ai_insights")
            .select("insight_type, title, summary, priority, created_at")
            .eq("user_id", userId)
            .order("created_at", { ascending: false })
            .limit(5)
        : Promise.resolve({ data: [] }),
    ]);

    // Extract results — use empty defaults for any query that failed
    const extract = <T>(index: number, fallback: T): T => {
      const r = settled[index];
      return r.status === "fulfilled" ? (r.value as any)?.data ?? fallback : fallback;
    };
    const logsResult = { data: extract<any[]>(0, []) };
    const goalsResult = { data: extract<any[]>(1, []) };
    const conversationResult = { data: extract<any[]>(2, []) };
    const docsResult = { data: extract<any[]>(3, []) };
    const weeklyReportResult = { data: extract<any[]>(4, []) };
    const scheduledResult = { data: extract<any[]>(5, []) };
    const formChecksResult = { data: extract<any[]>(6, []) };
    const fitnessSnapshotsResult = { data: extract<any[]>(7, []) };
    const activePlanResult = { data: extract<any>(8, null) };
    const athleteProfileResult = { data: extract<any>(9, null) };
    const negativeFeedbackResult = { data: extract<any[]>(10, []) };
    const pendingAdjustmentsResult = { data: extract<any[]>(11, []) };
    const raceIntelResult = { data: extract<any[]>(12, []) };
    const aiInsightsResult = { data: extract<any[]>(13, []) };

    // Log any failed queries for debugging
    settled.forEach((r, i) => {
      if (r.status === "rejected") {
        console.warn(`Context query ${i} failed: ${r.reason?.message || r.reason}`);
      }
    });

    const hasTrainingData = (logsResult.data?.length || 0) > 0;
    const hasGoals = (goalsResult.data?.length || 0) > 0;
    // Conversation fetched DESC with limit 50 — reverse to chronological order
    const existingMessages: Array<{ role: string; content: string }> = (conversationResult.data || []).reverse();

    // Build weekly coaching report context — include full narrative + adjustments + metrics
    let weeklyReportContext = "";
    const latestReport = weeklyReportResult.data?.[0];
    if (latestReport) {
      const narrative = (latestReport.coaching_narrative as string) || "";
      const activeAlerts = (latestReport.alerts as Array<{ severity: string; title: string }> || [])
        .filter((a) => a.severity !== "green")
        .map((a) => `[${a.severity}] ${a.title}`)
        .join(", ");
      const focusAreas = (latestReport.focus_areas as string[])?.join(", ") || "";
      const adjustments = (latestReport.adjustments as string[]) || [];
      const metrics = latestReport.metrics as Record<string, any> | null;

      let reportParts = [`\n\nWeekly Coaching Report (week of ${latestReport.week_start}):`];
      // Include full narrative for moderate/complex, truncated for simple
      reportParts.push(narrative.slice(0, 1200));
      if (activeAlerts) reportParts.push(`Active alerts: ${activeAlerts}`);
      if (focusAreas) reportParts.push(`Focus areas: ${focusAreas}`);
      if (adjustments.length > 0) reportParts.push(`Recommended adjustments: ${adjustments.join("; ")}`);
      if (metrics) {
        const metricLines: string[] = [];
        if (metrics.total_miles != null) metricLines.push(`Weekly miles: ${metrics.total_miles}`);
        if (metrics.total_runs != null) metricLines.push(`Runs: ${metrics.total_runs}`);
        if (metrics.avg_pace) metricLines.push(`Avg pace: ${metrics.avg_pace}`);
        if (metrics.compliance_pct != null) metricLines.push(`Plan compliance: ${metrics.compliance_pct}%`);
        if (metricLines.length > 0) reportParts.push(`Metrics: ${metricLines.join(", ")}`);
      }
      weeklyReportContext = reportParts.join("\n");
    }

    // ========================================================================
    // LAYER 4.25: Retrieve persistent memories and active injuries
    // ========================================================================
    let memoriesContext = "";
    let injuryContext = "";
    let activeInjuries: Awaited<ReturnType<typeof getActiveInjuries>> = [];
    if (userId) {
      try {
        const [userMemories, userInjuries] = await Promise.all([
          getMemories(supabase, userId),
          getActiveInjuries(supabase, userId),
        ]);
        memoriesContext = buildMemoryContext(userMemories);
        activeInjuries = userInjuries;
        injuryContext = buildInjuryContext(userInjuries);
        if (memoriesContext) {
          console.log(`Retrieved ${userMemories.length} memories for user context`);
        }
        if (injuryContext) {
          console.log(`Retrieved ${userInjuries.length} active injuries for context`);
        }
      } catch (memError) {
        console.error("Error fetching memories/injuries:", memError);
      }
    }

    // ========================================================================
    // LAYER 4.27: Feedback learning + pending adjustments context
    // ========================================================================
    let feedbackContext = "";
    const negativeFeedback = negativeFeedbackResult.data || [];
    if (negativeFeedback.length > 0 && !isCoachInsightRequest) {
      const feedbackLines = negativeFeedback
        .filter((f: any) => f.message_content)
        .slice(0, 3)
        .map((f: any) => {
          const snippet = f.message_content.slice(0, 150);
          const reason = f.feedback_text ? ` (Reason: ${f.feedback_text.slice(0, 80)})` : "";
          return `- "${snippet}..."${reason}`;
        });
      if (feedbackLines.length > 0) {
        feedbackContext = `\n\nIMPORTANT - This athlete previously found these types of responses unhelpful:\n${feedbackLines.join("\n")}\nAvoid similar patterns. Adjust your approach.`;
      }
    }

    let pendingAdjustmentsContext = "";
    const pendingAdj = pendingAdjustmentsResult.data || [];
    if (pendingAdj.length > 0 && !isCoachInsightRequest) {
      const adjLines = pendingAdj.slice(0, 5).map((a: any) =>
        `- [${a.adjustment_type}] ${a.recommendation}${a.target_workout ? ` (for: ${a.target_workout})` : ""}`
      );
      pendingAdjustmentsContext = `\n\nRecent coaching adjustments (check if followed):\n${adjLines.join("\n")}`;
    }

    // ========================================================================
    // LAYER 4.28: Race Intel (course data, weather, logistics)
    // ========================================================================
    let raceIntelContext = "";
    const raceIntel = raceIntelResult.data?.[0];
    if (raceIntel) {
      const course = raceIntel.course_data as Record<string, any> | null;
      const weather = raceIntel.weather_data as Record<string, any> | null;
      const parts: string[] = [`\n\nUpcoming Race: ${raceIntel.race_name}${raceIntel.race_date ? ` (${raceIntel.race_date})` : ""}${raceIntel.location ? ` — ${raceIntel.location}` : ""}`];

      if (course) {
        if (course.course_description) parts.push(`Course: ${course.course_description}`);
        if (course.elevation_gain_ft) parts.push(`Elevation: +${course.elevation_gain_ft}ft${course.elevation_loss_ft ? ` / -${course.elevation_loss_ft}ft` : ""}`);
        if (course.key_hills?.length > 0) parts.push(`Key hills: ${course.key_hills.map((h: any) => `mile ${h.mile}: ${h.description}`).join("; ")}`);
        if (course.surface) parts.push(`Surface: ${course.surface}`);
        if (course.start_time) parts.push(`Start: ${course.start_time}`);
        if (course.notable_features?.length > 0) parts.push(`Notable: ${course.notable_features.join(", ")}`);
        if (course.aid_station_details) parts.push(`Aid stations: ${course.aid_station_details}`);
      }
      if (weather?.conditions_summary) parts.push(`Weather (historical avg): ${weather.conditions_summary}`);
      if (raceIntel.confidence !== "high" && raceIntel.verification_notes) {
        parts.push(`Note: ${raceIntel.verification_notes}`);
      }

      raceIntelContext = parts.join("\n");
      console.log(`Race intel loaded for ${raceIntel.race_name} (confidence: ${raceIntel.confidence})`);
    }

    // ========================================================================
    // LAYER 4.29: AI Insights cross-reference (injury warnings, race readiness, etc.)
    // ========================================================================
    let aiInsightsContext = "";
    const recentInsights = aiInsightsResult.data || [];
    if (recentInsights.length > 0) {
      aiInsightsContext = "\n\nRecent AI Insights (from other analyses — reference these when relevant):\n";
      for (const insight of recentInsights) {
        const age = Math.round((Date.now() - new Date(insight.created_at).getTime()) / (1000 * 60 * 60));
        const ageLabel = age < 24 ? `${age}h ago` : `${Math.round(age / 24)}d ago`;
        const priority = insight.priority ? ` [${insight.priority}]` : "";
        aiInsightsContext += `- ${insight.insight_type.replace(/_/g, " ")}${priority} (${ageLabel}): ${(insight.summary || insight.title || "").slice(0, 150)}\n`;
      }
      aiInsightsContext += "If the athlete asks about injury risk, race readiness, or training block progress, reference the relevant insight above.\n";
    }

    // ========================================================================
    // LAYER 4.3: Real-time data analysis (ACWR, compliance, signals)
    // ========================================================================
    let analyticsContext = "";
    if (userId) {
      try {
        // Split training logs into this week + previous weeks for ACWR
        const allLogs = (logsResult.data || []) as TrainingLogRow[];
        const thisWeekLogs = allLogs.filter((l) => {
          if (!l.workout_date) return false;
          return l.workout_date >= weekMondayStr;
        });
        const olderLogs = allLogs.filter((l) => {
          if (!l.workout_date) return false;
          return l.workout_date < weekMondayStr && l.workout_date >= fiveWeeksAgo.toISOString().split("T")[0];
        });
        const previousWeeksLogs = splitLogsIntoWeeks(olderLogs, weekMonday);

        // Goal context for analysis
        const plan = activePlanResult.data;
        const goalDaysRemaining = plan?.end_date
          ? Math.ceil((new Date(plan.end_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24))
          : null;

        const analysis = analyzeTrainingData({
          thisWeekLogs: thisWeekLogs as TrainingLogRow[],
          previousWeeksLogs,
          scheduledThisWeek: (scheduledResult.data || []) as ScheduledWorkoutRow[],
          activeInjuries: activeInjuries as unknown as InjuryRow[],
          formChecks: (formChecksResult.data || []) as FormCheckResult[],
          fitnessSnapshots: (fitnessSnapshotsResult.data || []) as FitnessSnapshot[],
          goalDaysRemaining,
          targetTimeSeconds: plan?.target_time_seconds || null,
          targetDistance: plan?.target_race_distance || null,
          includeSignals: smartInsights !== false,
        });

        analyticsContext = analysis.context;
        if (analysis.signals.length > 0) {
          console.log(`Generated ${analysis.signals.length} coaching signals (${analysis.signals.filter(s => s.priority === "high").length} high priority)`);
        }
      } catch (analyticsError) {
        console.error("Error computing real-time analytics:", analyticsError);
      }
    }

    // ========================================================================
    // LAYER 4.35: Athlete Profile (comprehensive historical context)
    // ========================================================================
    let athleteProfileContext = "";
    if (athleteProfileResult.data?.profile_data) {
      try {
        athleteProfileContext = buildAthleteProfileContext(athleteProfileResult.data.profile_data as AthleteProfile);
        if (athleteProfileContext) {
          console.log(`Loaded athlete profile context (~${estimateTokens(athleteProfileContext)} tokens)`);
        }
      } catch (profileError) {
        console.error("Error building athlete profile context:", profileError);
      }
    }

    // ========================================================================
    // LAYER 4.38: Runner experience level detection
    // ========================================================================
    let runnerLevelContext = "";
    if (userId) {
      const profileForLevel = athleteProfileResult.data?.profile_data || {};
      const { level, promptAdjustment } = detectRunnerLevel(
        profileForLevel,
        memoriesContext,
        profileForLevel?.avg_weekly_mileage || profileForLevel?.weekly_mileage,
      );
      runnerLevelContext = promptAdjustment;
      if (level !== "intermediate") {
        console.log(`Runner level detected: ${level}`);
      }
    }

    // ========================================================================
    // LAYER 4.4: Periodization awareness from active training plan
    // ========================================================================
    let periodizationContext = "";
    const activePlan = activePlanResult.data;
    if (activePlan?.start_date && activePlan?.end_date) {
      periodizationContext = inferTrainingPhase({
        start_date: activePlan.start_date,
        end_date: activePlan.end_date,
        target_race_distance: activePlan.target_race_distance,
      });
      if (periodizationContext) {
        console.log(`Periodization phase detected for plan "${activePlan.name}"`);
      }
    }

    // ========================================================================
    // LAYER 4.5: User Profile & Conversational Data Gathering
    // ========================================================================
    let userProfile = null;
    let profileContext = "";

    if (userId) {
      // Get or create user profile
      userProfile = await getOrCreateProfile(supabase, userId);

      // Extract any profile data from this message and store it
      const extractedData = extractProfileData(message);
      if (Object.keys(extractedData).length > 0) {
        await updateProfile(supabase, userId, extractedData);
        // Refresh profile with new data
        userProfile = { ...userProfile, ...extractedData };
        console.log("Extracted and stored profile data:", Object.keys(extractedData));
      }

      // Check if this is a complex query that might need clarification
      if (isComplexQuery(message)) {
        const queryType = getQueryType(message);
        const targetDistance = detectTargetDistance(message);
        const missingData = getMissingData(userProfile, queryType, targetDistance);

        // Get the threshold for this query type (pace_advice = 1, training_plan = 2, etc.)
        const threshold = getQueryThreshold(queryType);
        console.log(`Complex query detected: type=${queryType}, distance=${targetDistance}, missing=${missingData.length} fields, threshold=${threshold}`);

        // If we're missing critical data AND this is a new conversation (not a follow-up answer)
        // Use query-specific threshold: pace questions need data to answer, training plans can tolerate more missing
        const isLikelyAnswer = existingMessages.length > 0 &&
          existingMessages[existingMessages.length - 1]?.role === "assistant" &&
          (message.length < 100 || /^\d|^yes|^no|^about|^around|^i |^my /i.test(message));

        if (missingData.length >= threshold && !isLikelyAnswer) {
          const questions = generateClarifyingQuestions(missingData, 3);
          const clarifyingResponse = buildClarifyingPrompt(message, questions, userProfile);

          // Save conversation with the clarifying questions
          let finalConversationId = conversationId;
          if (!finalConversationId) {
            const { data: newConv } = await supabase
              .from("conversations")
              .insert({ user_id: userId, updated_at: new Date().toISOString() })
              .select("id")
              .single();
            finalConversationId = newConv?.id;
          } else {
            await supabase
              .from("conversations")
              .update({ updated_at: new Date().toISOString() })
              .eq("id", finalConversationId);
          }
          if (finalConversationId) {
            await supabase.from("conversation_messages").insert([
              { conversation_id: finalConversationId, user_id: userId, role: "user", content: message },
              { conversation_id: finalConversationId, user_id: userId, role: "assistant", content: clarifyingResponse },
            ]);
          }

          console.log(`Asking ${questions.length} clarifying questions`);

          return new Response(
            JSON.stringify({
              response: clarifyingResponse,
              conversationId: finalConversationId,
              model: "clarifying",
              needsMoreInfo: true,
              missingFields: missingData,
              remaining: rateLimit.remaining,
              processingTime: Date.now() - startTime,
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      // Build profile context for the AI prompt (with structured injury data)
      profileContext = buildProfileContext(userProfile, activeInjuries);
    }

    // ========================================================================
    // LAYER 5: Classify query and get best available model
    // ========================================================================
    let complexity: QueryComplexity;
    let config: RouterConfig;

    if (proactive && checkInContext) {
      // Proactive check-ins always use moderate tier for empathy
      const result = getBestAvailableModel("moderate");
      complexity = result.complexity;
      config = result.config;
      console.log(`Proactive check-in routed to ${complexity} tier (${config.provider}/${config.model})`);
    } else {
      const preferredComplexity = classifyQuery(message, {
        hasTrainingData,
        hasGoals,
        conversationLength: existingMessages.length,
      });
      const result = getBestAvailableModel(preferredComplexity);
      complexity = result.complexity;
      config = result.config;
      console.log(`Query routed to ${complexity} tier (${config.provider}/${config.model})`);
    }

    // ========================================================================
    // LAYER 6: Build context-aware prompt
    // ========================================================================
    const isTrainingQuery = proactive ? true : isTrainingRelatedQuery(message);
    const isThisWeek = proactive ? false : isThisWeekQuery(message);
    const isCoachInsightRequest = !proactive && message.includes("[COACH INSIGHT REQUEST");

    // For coach insight requests, skip extra context - workout details are in the message
    // For simple queries, use compressed context. For moderate/complex, use full training document
    // For "this week" queries, add focused this-week context at the top
    let trainingContext = "";
    let thisWeekContext = "";

    if (!isCoachInsightRequest) {
      // Always build "this week" context for this-week queries
      if (isThisWeek) {
        thisWeekContext = buildThisWeekContext((logsResult.data || []) as ExtendedTrainingLog[]);
      }

      if (complexity === "simple") {
        // Simple queries: minimal compressed context
        trainingContext = compressTrainingContext(logsResult.data || []);
      } else {
        // Moderate/Complex queries: full training period document (3 months)
        trainingContext = buildTrainingPeriodDocument(
          (logsResult.data || []) as ExtendedTrainingLog[],
          3 // 3 months of data
        );
      }

      // Prepend this week context if it's a this-week query
      if (thisWeekContext) {
        trainingContext = thisWeekContext + "\n\n" + trainingContext;
      }
    }

    const goalsContext = isCoachInsightRequest ? "" : compressGoalsContext(goalsResult.data || [], isTrainingQuery);
    // Include full conversation history for continuity (up to 12 messages, 600 chars each)
    const conversationContext = isCoachInsightRequest ? "" : compressConversationHistory(existingMessages);

    console.log(`Query analysis: training-related=${isTrainingQuery}, thisWeek=${isThisWeek}, hasGoals=${hasGoals}, isCoachInsight=${isCoachInsightRequest}, proactive=${!!proactive}, complexity=${complexity}`);

    // Add relevant docs for ALL queries (skip for coach insight and proactive)
    // Even simple questions benefit from grounded knowledge
    let docsContext = "";
    if (!isCoachInsightRequest && !proactive && docsResult.data && docsResult.data.length > 0) {
      const maxDocs = complexity === "simple" ? 3 : 5;
      const maxChars = complexity === "simple" ? 800 : 1500;
      docsContext = "\n\nRelevant coaching knowledge:\n";
      docsResult.data.slice(0, maxDocs).forEach((doc: any) => {
        docsContext += `${doc.title}: ${doc.content.slice(0, maxChars)}\n\n`;
      });
    }

    // Build the full prompt
    let fullPrompt: string;

    if (proactive && checkInContext) {
      // Proactive check-in: coach reaches out after concerning voice memo
      const { mood, cleanedNotes, coachInsight } = checkInContext;
      const hkContext = workoutSummary ? `\n\nRecent workouts:\n${workoutSummary}` : "";
      const planContext = trainingPlanContext ? `\n\nTraining Plan:\n${trainingPlanContext}` : "";
      fullPrompt = `${SYSTEM_PROMPTS.proactive}${runnerLevelContext}

${athleteContext}

${trainingContext}${athleteProfileContext}${analyticsContext}${periodizationContext}${memoriesContext}${injuryContext}${raceIntelContext}${aiInsightsContext}${profileContext}${planContext}${hkContext}

Athlete's voice memo summary: ${cleanedNotes || "No details available"}
Detected mood: ${mood}
${coachInsight ? `Your initial take: ${coachInsight}` : ""}

Open the conversation:`;
    } else if (isCoachInsightRequest) {
      // Check if goals should be included (harder efforts - look for [GOALS] tag)
      const includeGoals = message.includes("[GOALS]") && hasGoals;
      const goalsHint = includeGoals && goalsResult.data && goalsResult.data.length > 0
        ? `\nRunner's upcoming goal: ${goalsResult.data[0].goal_title} (${Math.ceil((new Date(goalsResult.data[0].target_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24))} days away)`
        : "";

      // Coach insight: thoughtful feedback on a single workout
      fullPrompt = `Give quick feedback on this workout. 4-5 sentences, plain text, no markdown.

Talk like a real coach — not an AI. No "impressive", "journey", "fantastic", "great job", "solid work" or any generic praise. Be specific about what you see in the workout. Short sentences. Be direct.

If they're tired, say rest up. If something hurts, tell them to take it seriously. Don't sugarcoat, don't over-praise. One honest observation is worth more than five compliments.

Never mention coaching frameworks or names (Daniels, etc.).${goalsHint}

${message}

Coach:`;
    } else if (complexity === "simple") {
      // Simple queries: include athlete profile + docs so answers are personalized and grounded
      const systemPrompt = SYSTEM_PROMPTS[complexity as keyof typeof SYSTEM_PROMPTS];
      const simpleContext = [athleteContext, runnerLevelContext, athleteProfileContext, memoriesContext, injuryContext, docsContext].filter(Boolean).join("");
      fullPrompt = `${systemPrompt}
${simpleContext ? `\n${simpleContext}\n` : ""}
Question: ${message}

Answer:`;
    } else {
      // Moderate/Complex: include full context + profile + memories + injuries
      const systemPrompt = SYSTEM_PROMPTS[complexity as keyof typeof SYSTEM_PROMPTS];
      const hkContext = workoutSummary ? `\n\nRecent HealthKit workouts (from Apple Watch / GPS watch):\n${workoutSummary}` : "";
      const planContext = trainingPlanContext ? `\n\nActive Training Plan:\n${trainingPlanContext}` : "";
      const predContext = fitnessPredictions ? `\n\nFitness Predictions:\n${fitnessPredictions}` : "";
      fullPrompt = `${systemPrompt}${runnerLevelContext}

${athleteContext}

${trainingContext}${athleteProfileContext}${analyticsContext}${periodizationContext}${planContext}${predContext}${goalsContext}${memoriesContext}${injuryContext}${raceIntelContext}${aiInsightsContext}${weeklyReportContext}${profileContext}${hkContext}${conversationContext}${docsContext}${feedbackContext}${pendingAdjustmentsContext}

Runner's question: ${message}

Coach:`;
    }

    // Token budget enforcement — truncate prompt if it exceeds model limits
    const MAX_PROMPT_TOKENS: Record<string, number> = {
      simple: 4_000,
      moderate: 30_000,
      complex: 90_000,
    };
    const tokenBudget = MAX_PROMPT_TOKENS[complexity] || 30_000;
    let inputTokens = estimateTokens(fullPrompt);

    if (inputTokens > tokenBudget) {
      console.warn(`Prompt exceeds budget: ${inputTokens} > ${tokenBudget} tokens — truncating`);
      // Truncate to fit within budget (rough: 4 chars per token)
      const maxChars = tokenBudget * 4;
      fullPrompt = fullPrompt.slice(0, maxChars) + "\n\n[Context truncated to fit model limits]\n\nRunner's question: " + message + "\n\nCoach:";
      inputTokens = estimateTokens(fullPrompt);
    }
    console.log(`Prompt built: ~${inputTokens} tokens for ${complexity} query`);

    // ========================================================================
    // LAYER 7: Call the appropriate model (with fallback)
    // ========================================================================
    let coachResponse: string;
    let actualProvider = config.provider;

    // Retry wrapper: tries a model call, waits 2s, retries once before giving up
    async function withRetry<T>(fn: () => Promise<T>, label: string): Promise<T> {
      try {
        return await fn();
      } catch (firstError: any) {
        console.warn(`${label} attempt 1 failed: ${firstError?.message || firstError}`);
        await new Promise((r) => setTimeout(r, 2000));
        return await fn();
      }
    }

    try {
      if (config.provider === "groq") {
        console.log("Calling Groq Llama for simple query...");
        coachResponse = await withRetry(() => callGroq(fullPrompt, config), "Groq");
      } else {
        // Try Gemini first, fall back to Groq on rate limit or timeout
        try {
          console.log("Calling Gemini for coaching query...");
          coachResponse = await withRetry(() => callGemini(fullPrompt, config), "Gemini");
        } catch (geminiError: any) {
          const errorMessage = geminiError?.message || String(geminiError);
          console.log(`Gemini failed after retry (${errorMessage}), falling back to Groq...`);
          actualProvider = "groq";
          const groqConfig = getModelConfig("simple");
          coachResponse = await withRetry(() => callGroq(fullPrompt, groqConfig), "Groq-fallback");
        }
      }
    } catch (modelError: any) {
      // Both models failed after retries — return a graceful degradation response
      console.error("All model providers failed after retries:", modelError?.message || String(modelError));
      actualProvider = "fallback";
      coachResponse = "I'm having trouble connecting to my AI backend right now. " +
        "This is temporary — please try again in a minute. " +
        "In the meantime, your training data is safe and I'll have a full analysis ready when I'm back online.";
    }

    const outputTokens = estimateTokens(coachResponse);

    // ========================================================================
    // LAYER 8: Cache the response for future queries (skip for proactive)
    // ========================================================================
    if (!proactive && queryEmbedding && isCacheEnabled()) {
      await cacheResponse(queryEmbedding, message, coachResponse, complexity);
    }

    // ========================================================================
    // LAYER 9: Save conversation and log usage
    // ========================================================================
    // For proactive check-ins, only save the assistant message (no fake user message)
    const proactiveMessages = [
      { role: "assistant", content: coachResponse, timestamp: new Date().toISOString(), proactive: true },
    ];
    const normalMessages = [
      { role: "user", content: message, timestamp: new Date().toISOString() },
      { role: "assistant", content: coachResponse, timestamp: new Date().toISOString() },
    ];
    const newMessages = proactive ? proactiveMessages : normalMessages;

    // Save messages to normalized table
    let convIdForSave = conversationId;
    if (!convIdForSave) {
      const { data: newConv } = await supabase
        .from("conversations")
        .insert({ user_id: userId, updated_at: new Date().toISOString() })
        .select("id")
        .single();
      convIdForSave = newConv?.id;
    } else {
      await supabase
        .from("conversations")
        .update({ updated_at: new Date().toISOString() })
        .eq("id", convIdForSave);
    }

    const messageRows = newMessages.map((msg: any) => ({
      conversation_id: convIdForSave,
      user_id: userId,
      role: msg.role,
      content: msg.content,
      proactive: msg.proactive || false,
    }));

    // Insert messages and capture the assistant message ID for feedback
    let assistantMessageId: string | null = null;
    const [convResult, _usageResult] = await Promise.all([
      convIdForSave
        ? supabase.from("conversation_messages").insert(messageRows).select("id, role").then((res) => {
            const assistantRow = res.data?.find((m: any) => m.role === "assistant");
            assistantMessageId = assistantRow?.id || null;
            return { data: { id: convIdForSave } };
          })
        : Promise.resolve({ data: null }),
      supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: proactive ? "coaching_proactive" : "coaching",
        model_used: getModelIdentifier(complexity),
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        cached: false,
      }),
    ]);

    const finalConversationId = conversationId || convResult.data?.id;

    // ========================================================================
    // LAYER 9.5: Extract and store memories for future sessions
    // ========================================================================
    if (userId) {
      try {
        const newMemories = extractMemories(message, coachResponse);
        if (newMemories.length > 0) {
          await storeMemories(supabase, userId, newMemories, finalConversationId);
          console.log(`Extracted and stored ${newMemories.length} new memories`);
        }
      } catch (memError) {
        console.error("Error storing memories:", memError);
        // Don't fail the request if memory storage fails
      }
    }
    const processingTime = Date.now() - startTime;

    console.log(
      `Response generated in ${processingTime}ms using ${config.provider}/${config.model} (${complexity})`
    );

    return new Response(
      JSON.stringify({
        response: coachResponse,
        conversationId: finalConversationId,
        messageId: assistantMessageId,
        model: complexity,
        provider: config.provider,
        cached: false,
        remaining: proactive ? rateLimit.remaining : rateLimit.remaining - 1,
        proactive: proactive || false,
        feedbackEnabled: !isCoachInsightRequest,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    console.error("Coaching agent error:", error);
    return new Response(
      JSON.stringify({ error: `Internal error: ${error?.message || String(error)}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

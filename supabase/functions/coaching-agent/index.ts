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

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// System prompts optimized per model tier
// Tone: Warm, supportive, direct - like a real coach who cares about you
const SYSTEM_PROMPTS = {
  // Simple: Groq - quick, supportive answers
  simple: `You are Coach - a friendly, supportive running coach. Talk like a real coach would: warm, direct, and encouraging.

TONE:
- Be like a supportive friend who happens to know a lot about running
- Keep it simple and clear - no jargon or complexity
- Be encouraging but honest
- 1-2 short paragraphs max

PACE QUESTIONS:
- Never show math or calculations
- Just give the answer directly: "For you, easy pace would be around 8:00-8:30/mi"
- Keep pace answers to 2-3 sentences

KM/MI: 3:00/km=4:50/mi, 3:30/km=5:38/mi, 4:00/km=6:26/mi

FORMAT: Plain text only, no markdown. Use dashes for lists if needed.`,

  // Moderate: Gemini - personalized coaching
  moderate: `You are Coach - a supportive, knowledgeable running coach who genuinely cares about helping runners improve. Talk like a real coach: warm, direct, and encouraging.

TONE:
- Be like a supportive friend who's also an expert coach
- Speak naturally and conversationally - avoid sounding robotic or formal
- Be encouraging and positive, but also honest when needed
- Keep responses focused and helpful (2-3 paragraphs max)

PACE & TRAINING DATA:
- All pace values, splits, and race predictions are PRE-COMPUTED and provided in the context below — quote them EXACTLY as given
- NEVER calculate, estimate, or invent any pace value — the math is already done for you
- If asked about race pace or race times, quote from "Predicted race times"
- If asked about training/workout paces, quote from "Training pace zones"
- If asked about splits, quote from "Pre-computed splits"
- If asked about goal progress, quote from "Goal vs current fitness"
- Both /mi and /km values are provided — default to /mi unless the runner asks for /km
- Workout type mapping: Easy/Recovery→Easy zone, Long Run→Moderate zone, Steady→Steady zone, Marathon Pace→MP, Tempo/Threshold→HMP (NOT 10K), Intervals 800m+→10K pace, Short reps→5K pace

COACHING APPROACH:
- If they're tired or stressed, encourage rest - it's part of training
- If they mention pain or injury, take it seriously and recommend backing off
- Remember what they've told you and reference it naturally
- Celebrate their progress and hard work

FORMAT: Write in plain conversational text. No markdown bold or headers. Use dashes for short lists only.`,

  // Complex: Gemini - deep coaching for training plans and analysis
  complex: `You are Coach - an experienced, supportive running coach who helps runners reach their goals. Talk like a real coach: warm, knowledgeable, and direct.

TONE:
- Be like a trusted mentor who knows their stuff
- Speak naturally - conversational, not formal or robotic
- Be encouraging and supportive throughout
- Give clear, actionable advice they can actually follow

PACE & TRAINING DATA:
- All pace values, splits, and race predictions are PRE-COMPUTED and provided in the context below — quote them EXACTLY as given
- NEVER calculate, estimate, or invent any pace value — the math is already done for you
- If asked about race pace or race times, quote from "Predicted race times"
- If asked about training/workout paces, quote from "Training pace zones"
- If asked about splits, quote from "Pre-computed splits"
- If asked about goal progress, quote from "Goal vs current fitness"
- Both /mi and /km values are provided — default to /mi unless the runner asks for /km
- Workout type mapping: Easy/Recovery→Easy zone, Long Run→Moderate zone, Steady→Steady zone, Marathon Pace→MP, Tempo/Threshold→HMP (NOT 10K), Intervals 800m+→10K pace, Short reps→5K pace

COACHING APPROACH:
- Remember what they've shared (PRs, goals, injuries) and use it naturally
- If they're fatigued, fully support taking rest - it's productive, not weakness
- For any injury or pain, acknowledge it seriously and recommend backing off early
- Reaffirm their hard work and progress, even when things are tough
- For training plans, be specific but not overwhelming

FORMAT:
- Write in clear, conversational prose
- No markdown bold or headers
- Use dashes for bullet points, numbers for steps
- Keep it readable and well-organized`,
};

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  timestamp: string;
}

// ============================================================================
// MODEL CALL HANDLERS
// ============================================================================

/**
 * Call Groq API (OpenAI-compatible)
 */
async function callGroq(
  prompt: string,
  config: RouterConfig
): Promise<string> {
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) throw new Error("GROQ_API_KEY not configured");

  const response = await fetch(`${config.baseUrl}/chat/completions`, {
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
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Groq API error: ${response.status}`, errorText);
    throw new Error(`Groq API error: ${response.status}`);
  }

  const data = await response.json();
  return data.choices[0].message.content;
}

/**
 * Call Gemini API
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

  const result = await model.generateContent(prompt);
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
    // Verify authenticated user from JWT
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    const { message, conversationId, workoutSummary, trainingPlanContext, fitnessPredictions } = await req.json();

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
    // LAYER 1: Rate Limiting
    // ========================================================================
    let rateLimit = { allowed: true, remaining: 999, resetAt: new Date(), current: 0, limit: 999 };
    let userTier = "free";

    if (userId && isRateLimitEnabled()) {
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
    // LAYER 4: Fetch context data (parallel queries)
    // Fetch 3 months of training data for comprehensive context
    // IMPORTANT: Order by workout_date (when run happened), not created_at (when logged)
    // ========================================================================
    const threeMonthsAgo = new Date();
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

    const [logsResult, goalsResult, conversationResult, docsResult] = await Promise.all([
      supabase
        .from("training_logs")
        .select("id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, mood, cleaned_notes, notes, coach_insight")
        .or(`workout_date.gte.${threeMonthsAgo.toISOString()},and(workout_date.is.null,created_at.gte.${threeMonthsAgo.toISOString()})`)
        .order("workout_date", { ascending: false, nullsFirst: false })
        .limit(150), // ~3 months of daily training
      supabase
        .from("user_goals")
        .select("goal_title, target_date")
        .eq("status", "active")
        .order("target_date", { ascending: true }),
      conversationId
        ? supabase.from("conversations").select("messages").eq("id", conversationId).single()
        : Promise.resolve({ data: null }),
      queryEmbedding
        ? supabase.rpc("match_coaching_documents", {
            query_embedding: `[${queryEmbedding.join(",")}]`,
            match_count: 2,
          })
        : Promise.resolve({ data: [] }),
    ]);

    const hasTrainingData = (logsResult.data?.length || 0) > 0;
    const hasGoals = (goalsResult.data?.length || 0) > 0;
    const existingMessages = conversationResult.data?.messages || [];

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
          const conversationUpdate = conversationId
            ? supabase
                .from("conversations")
                .update({
                  messages: [
                    ...existingMessages,
                    { role: "user", content: message, timestamp: new Date().toISOString() },
                    { role: "assistant", content: clarifyingResponse, timestamp: new Date().toISOString() },
                  ],
                  updated_at: new Date().toISOString(),
                })
                .eq("id", conversationId)
            : supabase
                .from("conversations")
                .insert({
                  messages: [
                    { role: "user", content: message, timestamp: new Date().toISOString() },
                    { role: "assistant", content: clarifyingResponse, timestamp: new Date().toISOString() },
                  ],
                })
                .select("id")
                .single();

          const convResult = await conversationUpdate;
          const finalConversationId = conversationId || convResult.data?.id;

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
    const preferredComplexity = classifyQuery(message, {
      hasTrainingData,
      hasGoals,
      conversationLength: existingMessages.length,
    });

    const { complexity, config } = getBestAvailableModel(preferredComplexity);
    console.log(`Query routed to ${complexity} tier (${config.provider}/${config.model})`);

    // ========================================================================
    // LAYER 6: Build context-aware prompt
    // ========================================================================
    const systemPrompt = SYSTEM_PROMPTS[complexity];
    const isTrainingQuery = isTrainingRelatedQuery(message);
    const isThisWeek = isThisWeekQuery(message);
    const isCoachInsightRequest = message.includes("[COACH INSIGHT REQUEST");

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

    console.log(`Query analysis: training-related=${isTrainingQuery}, thisWeek=${isThisWeek}, hasGoals=${hasGoals}, isCoachInsight=${isCoachInsightRequest}, complexity=${complexity}`);

    // Add relevant docs for moderate/complex queries (skip for coach insight)
    let docsContext = "";
    if (!isCoachInsightRequest && complexity !== "simple" && docsResult.data && docsResult.data.length > 0) {
      docsContext = "\n\nRelevant coaching knowledge:\n";
      docsResult.data.slice(0, 2).forEach((doc: any) => {
        docsContext += `${doc.title}: ${doc.content.slice(0, 300)}...\n`;
      });
    }

    // Build the full prompt
    let fullPrompt: string;

    if (isCoachInsightRequest) {
      // Check if goals should be included (harder efforts - look for [GOALS] tag)
      const includeGoals = message.includes("[GOALS]") && hasGoals;
      const goalsHint = includeGoals && goalsResult.data && goalsResult.data.length > 0
        ? `\nRunner's upcoming goal: ${goalsResult.data[0].goal_title} (${Math.ceil((new Date(goalsResult.data[0].target_date).getTime() - Date.now()) / (1000 * 60 * 60 * 24))} days away)`
        : "";

      // Coach insight: thoughtful feedback on a single workout
      fullPrompt = `You are Coach, giving thoughtful feedback on a workout.

IMPORTANT: Never mention specific coaching methodologies, frameworks, or coach names (e.g., Canova, VDOT, Jack Daniels) in your response. Just apply the principles naturally.

Philosophy to apply:
- Encourage running relaxed and within yourself, even on hard efforts
- Value mobility and active recovery
- If the athlete mentions fatigue or stress, support rest with positive reinforcement
- If any injury or pain is mentioned, acknowledge it seriously and recommend rest/catching it early
- Be understanding and positive - reaffirm they are working hard and moving toward their goals

Write 4-5 sentences in plain conversational text. No markdown, no bold, no headers - just natural, supportive coaching feedback.${goalsHint}

${message}

Coach:`;
    } else if (complexity === "simple") {
      // Simple queries: minimal context for speed
      fullPrompt = `${systemPrompt}

Question: ${message}

Answer:`;
    } else {
      // Moderate/Complex: include full context + profile + memories + injuries
      const hkContext = workoutSummary ? `\n\nRecent HealthKit workouts (from Apple Watch / GPS watch):\n${workoutSummary}` : "";
      const planContext = trainingPlanContext ? `\n\nActive Training Plan:\n${trainingPlanContext}` : "";
      const predContext = fitnessPredictions ? `\n\nFitness Predictions:\n${fitnessPredictions}` : "";
      fullPrompt = `${systemPrompt}

${trainingContext}${planContext}${predContext}${goalsContext}${memoriesContext}${injuryContext}${profileContext}${hkContext}${conversationContext}${docsContext}

Runner's question: ${message}

Coach:`;
    }

    const inputTokens = estimateTokens(fullPrompt);
    console.log(`Prompt built: ~${inputTokens} tokens for ${complexity} query`);

    // ========================================================================
    // LAYER 7: Call the appropriate model (with fallback)
    // ========================================================================
    let coachResponse: string;
    let actualProvider = config.provider;

    if (config.provider === "groq") {
      console.log("Calling Groq Llama for simple query...");
      coachResponse = await callGroq(fullPrompt, config);
    } else {
      // Try Gemini first, fall back to Groq on rate limit
      try {
        console.log("Calling Gemini for coaching query...");
        coachResponse = await callGemini(fullPrompt, config);
      } catch (geminiError: any) {
        const errorMessage = geminiError?.message || String(geminiError);
        if (errorMessage.includes("429") || errorMessage.includes("Resource exhausted")) {
          console.log("Gemini rate limited, falling back to Groq...");
          actualProvider = "groq";
          const groqConfig = getModelConfig("simple");
          coachResponse = await callGroq(fullPrompt, groqConfig);
        } else {
          throw geminiError;
        }
      }
    }

    const outputTokens = estimateTokens(coachResponse);

    // ========================================================================
    // LAYER 8: Cache the response for future queries
    // ========================================================================
    if (queryEmbedding && isCacheEnabled()) {
      await cacheResponse(queryEmbedding, message, coachResponse, complexity);
    }

    // ========================================================================
    // LAYER 9: Save conversation and log usage
    // ========================================================================
    const conversationUpdate = conversationId
      ? supabase
          .from("conversations")
          .update({
            messages: [
              ...existingMessages,
              { role: "user", content: message, timestamp: new Date().toISOString() },
              { role: "assistant", content: coachResponse, timestamp: new Date().toISOString() },
            ],
            updated_at: new Date().toISOString(),
          })
          .eq("id", conversationId)
      : supabase
          .from("conversations")
          .insert({
            messages: [
              { role: "user", content: message, timestamp: new Date().toISOString() },
              { role: "assistant", content: coachResponse, timestamp: new Date().toISOString() },
            ],
          })
          .select("id")
          .single();

    const [convResult, _usageResult] = await Promise.all([
      conversationUpdate,
      supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: "coaching",
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
        model: complexity,
        provider: config.provider,
        cached: false,
        remaining: rateLimit.remaining - 1,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Coaching agent error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

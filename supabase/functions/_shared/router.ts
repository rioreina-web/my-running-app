/**
 * Multi-Model Query Router
 *
 * Routes queries to the optimal model based on complexity:
 * - Simple (60%): Groq Llama 3.1 8B - fast, cheap ($0.05/1M tokens)
 * - Moderate (30%): Gemini Flash - balanced ($0.60/1M tokens)
 * - Complex (10%): Gemini Flash + high tokens - best reasoning
 *
 * Cost savings: ~40% reduction vs single-model approach
 */

export type QueryComplexity = "simple" | "moderate" | "complex";

export interface RouterConfig {
  model: string;
  provider: "groq" | "gemini";
  baseUrl: string;
  apiKeyEnv: string;
  maxTokens: number;
  costPer1kTokens: number;
}

// Multi-model configuration
const MODEL_CONFIG: Record<QueryComplexity, RouterConfig> = {
  // Simple: Groq Llama - fastest, cheapest
  // Best for: definitions, general knowledge, quick facts
  simple: {
    model: "llama-3.1-8b-instant",
    provider: "groq",
    baseUrl: "https://api.groq.com/openai/v1",
    apiKeyEnv: "GROQ_API_KEY",
    maxTokens: 400,
    costPer1kTokens: 0.00005, // $0.05/1M tokens
  },

  // Moderate: Gemini Flash - balanced quality/cost
  // Best for: personalized advice, recommendations, coaching
  moderate: {
    model: "gemini-2.5-flash",
    provider: "gemini",
    baseUrl: "https://generativelanguage.googleapis.com/v1beta",
    apiKeyEnv: "GEMINI_API_KEY",
    // 2.5 Flash consumes thinking tokens before writing output — bump budget
    // so full coaching responses aren't truncated mid-sentence.
    maxTokens: 2000,
    costPer1kTokens: 0.0006, // $0.60/1M tokens
  },

  // Complex: Gemini Flash with extended context
  // Best for: training plans, analysis, multi-step reasoning
  complex: {
    model: "gemini-2.5-flash",
    provider: "gemini",
    baseUrl: "https://generativelanguage.googleapis.com/v1beta",
    apiKeyEnv: "GEMINI_API_KEY",
    maxTokens: 3000,
    costPer1kTokens: 0.0006,
  },
};

// ============================================================================
// QUERY CLASSIFICATION PATTERNS
// ============================================================================

// Complex: Requires deep reasoning, analysis, or multi-step planning
const COMPLEX_PATTERNS = [
  // Training plan creation
  /training plan/i,
  /build.*plan/i,
  /create.*program/i,
  /design.*schedule/i,
  /periodization/i,
  /macro.?cycle/i,
  /meso.?cycle/i,

  // Analysis and diagnostics
  /analyze my/i,
  /pattern in my/i,
  /what.*(wrong|issue|problem)/i,
  /why (am|do|did|have) i/i,
  /diagnose/i,
  /root cause/i,

  // Performance optimization
  /over.?train/i,
  /under.?train/i,
  /injury (prevention|pattern|risk)/i,
  /compare my/i,
  /trend in my/i,
  /progress(ion)? (analysis|review)/i,

  // Race preparation
  /prepare for.*race/i,
  /taper(ing)?/i,
  /peak(ing)?.*race/i,
  /race strategy/i,
  /pacing strategy/i,

  // Complex coaching
  /what should my.*look like/i,
  /how (can|do) i improve/i,
  /optimize my/i,
  /breakthrough/i,
];

// Moderate: Needs user context and personalized advice
const MODERATE_PATTERNS = [
  // Personalized queries
  /my (run|training|workout|week|month|pace|heart rate)/i,
  /should i/i,
  /can i/i,
  /this week/i,
  /today('s)?/i,

  // Feedback and recommendations
  /how (did|was|is) my/i,
  /recommend/i,
  /suggest/i,
  /adjust/i,
  /modify/i,

  // Context-dependent
  /based on my/i,
  /for my (goal|race|training)/i,
  /given my/i,
  /considering my/i,

  // Progress checks
  /how am i doing/i,
  /am i (ready|prepared|on track)/i,
  /feedback on/i,
  /rate my/i,
  /review my/i,
];

// Simple: General knowledge, definitions, quick answers
// (Anything that doesn't match above patterns)
const SIMPLE_PATTERNS = [
  /what is (a |an |the )?/i,
  /what are /i,
  /define /i,
  /explain /i,
  /tell me about /i,
  /how does.*work/i,
  /difference between/i,
  /benefits of/i,
  /best (way|practice)/i,
  /tips for/i,
  /general/i,
];

export interface ClassificationContext {
  hasTrainingData: boolean;
  hasGoals: boolean;
  conversationLength: number;
}

/**
 * Classify query complexity to determine optimal model
 */
export function classifyQuery(
  query: string,
  context: ClassificationContext
): QueryComplexity {
  const q = query.toLowerCase().trim();

  // 1. Check for complex patterns (highest priority)
  if (COMPLEX_PATTERNS.some((pattern) => pattern.test(q))) {
    console.log("Query classified as COMPLEX (pattern match)");
    return "complex";
  }

  // 2. Check for moderate patterns
  if (MODERATE_PATTERNS.some((pattern) => pattern.test(q))) {
    console.log("Query classified as MODERATE (pattern match)");
    return "moderate";
  }

  // 3. Personalized questions with user data → moderate
  if (
    context.hasTrainingData &&
    (q.includes("my") || q.includes("i ") || q.includes("i'm") || q.includes("me"))
  ) {
    console.log("Query classified as MODERATE (personalized + has data)");
    return "moderate";
  }

  // 4. Long conversation → moderate (needs context)
  if (context.conversationLength > 4) {
    console.log("Query classified as MODERATE (conversation context)");
    return "moderate";
  }

  // 5. Check for explicit simple patterns
  if (SIMPLE_PATTERNS.some((pattern) => pattern.test(q))) {
    console.log("Query classified as SIMPLE (knowledge query)");
    return "simple";
  }

  // 6. Short queries without personalization → simple
  if (q.length < 50 && !q.includes("my") && !q.includes("i ")) {
    console.log("Query classified as SIMPLE (short generic query)");
    return "simple";
  }

  // Default to moderate for safety
  console.log("Query classified as MODERATE (default)");
  return "moderate";
}

/**
 * Get model configuration for complexity level
 */
export function getModelConfig(complexity: QueryComplexity): RouterConfig {
  return MODEL_CONFIG[complexity];
}

/**
 * Check if a provider is available
 */
export function isProviderAvailable(provider: "groq" | "gemini"): boolean {
  if (provider === "groq") {
    return !!Deno.env.get("GROQ_API_KEY");
  }
  return !!Deno.env.get("GEMINI_API_KEY");
}

/**
 * Get best available model with fallback logic
 */
export function getBestAvailableModel(
  preferredComplexity: QueryComplexity
): { complexity: QueryComplexity; config: RouterConfig } {
  const config = getModelConfig(preferredComplexity);

  // Check if preferred provider is available
  if (isProviderAvailable(config.provider)) {
    return { complexity: preferredComplexity, config };
  }

  // Fallback logic
  if (preferredComplexity === "simple" && !isProviderAvailable("groq")) {
    // Groq unavailable, fall back to Gemini for simple queries
    console.log("Groq unavailable, falling back to Gemini for simple query");
    if (isProviderAvailable("gemini")) {
      return {
        complexity: "moderate",
        config: getModelConfig("moderate"),
      };
    }
  }

  if (
    (preferredComplexity === "moderate" || preferredComplexity === "complex") &&
    !isProviderAvailable("gemini")
  ) {
    // Gemini unavailable, fall back to Groq
    console.log("Gemini unavailable, falling back to Groq");
    if (isProviderAvailable("groq")) {
      return {
        complexity: "simple",
        config: getModelConfig("simple"),
      };
    }
  }

  // No providers available
  throw new Error(
    "No AI providers configured. Set GROQ_API_KEY and/or GEMINI_API_KEY"
  );
}

/**
 * Format model identifier for logging/tracking
 */
export function getModelIdentifier(complexity: QueryComplexity): string {
  const config = MODEL_CONFIG[complexity];
  return `${complexity}-${config.provider}-${config.model}`;
}

/**
 * Get cost estimate for a query
 */
export function estimateCost(
  complexity: QueryComplexity,
  inputTokens: number,
  outputTokens: number
): number {
  const config = MODEL_CONFIG[complexity];
  return ((inputTokens + outputTokens) / 1000) * config.costPer1kTokens;
}

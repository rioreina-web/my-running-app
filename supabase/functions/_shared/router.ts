/**
 * Multi-Model Query Router
 *
 * Routes queries to the optimal model based on complexity:
 * - Simple (60%): Groq (opt-in, see GROQ_SIMPLE_MODEL) else Gemini Flash
 * - Moderate (30%): Gemini Flash - balanced ($0.60/1M tokens)
 * - Complex (10%): Gemini Flash + high tokens - best reasoning
 *
 * The simple tier is Gemini by default. Groq is a cost optimisation the
 * deployment opts into by setting GROQ_SIMPLE_MODEL to a model ID the
 * account can actually call — Groq retires model IDs on its own schedule,
 * and a hard-coded one is a silent outage waiting to happen. On
 * 2026-09-08 `llama-3.1-8b-instant` started returning
 * `404 model_not_found` in prod, which took the whole simple tier (~60%
 * of coach questions) down: every one of them fell through to the
 * "I'm having trouble connecting to my AI backend" message.
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

const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta";
const GROQ_BASE_URL = "https://api.groq.com/openai/v1";

/**
 * Groq model ID for the simple tier, or null when Groq is not opted in.
 * Read per-call (not captured at module load) so flipping the secret in
 * the Supabase dashboard takes effect on the next cold start without a
 * redeploy.
 */
function groqSimpleModel(): string | null {
  const model = Deno.env.get("GROQ_SIMPLE_MODEL")?.trim();
  return model ? model : null;
}

// Multi-model configuration
const MODEL_CONFIG: Record<QueryComplexity, RouterConfig> = {
  // Simple: default Gemini Flash. Overridden by the Groq config below
  // when GROQ_SIMPLE_MODEL is set — see getModelConfig().
  // Best for: definitions, general knowledge, quick facts
  simple: {
    model: "gemini-2.5-flash",
    provider: "gemini",
    baseUrl: GEMINI_BASE_URL,
    apiKeyEnv: "GEMINI_API_KEY",
    // 1000, not the 400 this tier used on Groq: 2.5 Flash spends thinking
    // tokens inside the same budget, so a 400 cap can be consumed entirely
    // by thinking and return an empty answer. Same reasoning as moderate.
    maxTokens: 1000,
    costPer1kTokens: 0.0006,
  },

  // Moderate: Gemini Flash - balanced quality/cost
  // Best for: personalized advice, recommendations, coaching
  moderate: {
    model: "gemini-2.5-flash",
    provider: "gemini",
    baseUrl: GEMINI_BASE_URL,
    apiKeyEnv: "GEMINI_API_KEY",
    // C.6 (2026-06-10): cap lowered 2000 → 1000. Most coach responses run
    // 300-600 output tokens; the cap is the worst-case cost bound, not a
    // target. NOT the 800 from TASKS.md: 2.5 Flash spends thinking tokens
    // inside this same budget (see the truncation incident that drove the
    // original bump), so 800 risked mid-sentence cuts. Callers should log
    // via noteTruncationIfCapped() and we raise only if eval scores suffer.
    maxTokens: 1000,
    costPer1kTokens: 0.0006, // $0.60/1M tokens
  },

  // Complex: Gemini Flash with extended context
  // Best for: training plans, analysis, multi-step reasoning
  complex: {
    model: "gemini-2.5-flash",
    provider: "gemini",
    baseUrl: GEMINI_BASE_URL,
    apiKeyEnv: "GEMINI_API_KEY",
    // C.6 (2026-06-10): 3000 → 2000 (thinking-token headroom; see above).
    maxTokens: 2000,
    costPer1kTokens: 0.0006,
  },
};

/**
 * C.6 — call this with the provider's finish reason after a completion.
 * Logs a grep-able marker when a response hit the output-token cap, so
 * cap-induced truncation is visible in function logs before anyone
 * raises a limit. (Sentry isn't wired in edge functions; the marker
 * string is the counter. Search logs for "prompt_response_truncated".)
 */
export function noteTruncationIfCapped(
  finishReason: string | null | undefined,
  context: { fn: string; complexity?: string },
): void {
  const r = (finishReason ?? "").toUpperCase();
  if (r === "MAX_TOKENS" || r === "LENGTH") {
    console.error(
      `[prompt_response_truncated] fn=${context.fn} complexity=${context.complexity ?? "?"} finish=${r}`,
    );
  }
}

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
  if (complexity === "simple") {
    const groqModel = groqSimpleModel();
    if (groqModel) {
      return {
        model: groqModel,
        provider: "groq",
        baseUrl: GROQ_BASE_URL,
        apiKeyEnv: "GROQ_API_KEY",
        maxTokens: 400,
        costPer1kTokens: 0.00005, // $0.05/1M tokens
      };
    }
  }
  return MODEL_CONFIG[complexity];
}

/**
 * The config to try when `config` fails — the *other* provider, so one
 * provider being down (bad key, retired model, quota exhausted) degrades
 * latency instead of costing the runner their answer.
 *
 * Returns null when there is nothing left to try: the other provider has
 * no key configured, or both tiers already resolve to the same provider.
 */
export function getFallbackConfig(config: RouterConfig): RouterConfig | null {
  if (config.provider === "groq") {
    // Groq only ever backs the simple tier, and moderate is the cheapest
    // Gemini config — with enough output budget for 2.5 Flash's thinking.
    if (!isProviderAvailable("gemini")) return null;
    return MODEL_CONFIG.moderate;
  }

  // Gemini failed. Groq is only usable if the deployment opted in.
  const groqModel = groqSimpleModel();
  if (!groqModel || !isProviderAvailable("groq")) return null;
  return {
    model: groqModel,
    provider: "groq",
    baseUrl: GROQ_BASE_URL,
    apiKeyEnv: "GROQ_API_KEY",
    // Roomier than the simple tier's 400: this is standing in for a
    // moderate/complex answer, which is longer than a quick fact.
    maxTokens: 800,
    costPer1kTokens: 0.00005,
  };
}

/**
 * True when an error from a model provider is worth retrying — a timeout,
 * a network blip, a 429, a 5xx. A 404 for a retired model or a 401 for a
 * bad key returns false: retrying those just burns two seconds before
 * failing the same way, when the right move is to fail over immediately.
 */
export function isRetryableModelError(error: unknown): boolean {
  const status = modelErrorStatus(error);
  if (status === null) return true; // timeout / network / unknown — retry
  if (status === 408 || status === 429) return true;
  return status >= 500;
}

/** HTTP status carried by a provider error, if we can recover one. */
function modelErrorStatus(error: unknown): number | null {
  const withStatus = error as { status?: unknown } | null;
  if (typeof withStatus?.status === "number") return withStatus.status;
  // The Gemini SDK only puts the status in the message text.
  const match = String((error as { message?: string })?.message ?? error)
    .match(/\b(4\d\d|5\d\d)\b/);
  return match ? Number(match[1]) : null;
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
 * Get best available model with fallback logic.
 *
 * This picks between providers on *configuration* (is a key set?). The
 * runtime failure case — a key that exists but the call fails — is
 * handled by the caller retrying with `getFallbackConfig()`.
 */
export function getBestAvailableModel(
  preferredComplexity: QueryComplexity
): { complexity: QueryComplexity; config: RouterConfig } {
  const config = getModelConfig(preferredComplexity);

  // Check if preferred provider is available
  if (isProviderAvailable(config.provider)) {
    return { complexity: preferredComplexity, config };
  }

  const fallback = getFallbackConfig(config);
  if (fallback) {
    console.log(
      `${config.provider} unavailable, falling back to ${fallback.provider} for ${preferredComplexity} query`,
    );
    // The tier keeps its name — it still describes how much context the
    // query earns. Only the model serving it changed.
    return { complexity: preferredComplexity, config: fallback };
  }

  // No providers available
  throw new Error(
    "No AI providers configured. Set GEMINI_API_KEY (and optionally GROQ_API_KEY + GROQ_SIMPLE_MODEL)"
  );
}

/**
 * Format model identifier for logging/tracking
 */
export function getModelIdentifier(
  complexity: QueryComplexity,
  config: RouterConfig = getModelConfig(complexity),
): string {
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
  const config = getModelConfig(complexity);
  return ((inputTokens + outputTokens) / 1000) * config.costPer1kTokens;
}

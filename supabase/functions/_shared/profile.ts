/**
 * User Profile Management
 *
 * Handles:
 * - Fetching user profiles
 * - Detecting missing data for complex queries
 * - Generating clarifying questions
 * - Extracting and storing profile data from conversations
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface UserProfile {
  id?: string;
  user_id: string;
  current_weekly_mileage?: number;
  peak_weekly_mileage?: number;
  years_running?: number;
  pr_5k_seconds?: number;
  pr_10k_seconds?: number;
  pr_half_seconds?: number;
  pr_marathon_seconds?: number;
  easy_pace_per_mile?: string;
  tempo_pace_per_mile?: string;
  injury_history?: any[];
  current_injuries?: any[];
  preferred_run_days?: string[];
  long_run_day?: string;
  cross_training?: string[];
  data_completeness?: number;
}

// Queries that typically need more user context
const COMPLEX_QUERY_PATTERNS = [
  /build.*plan/i,
  /create.*plan/i,
  /training plan/i,
  /marathon plan/i,
  /half.?marathon plan/i,
  /prepare.*for.*(race|marathon|half|5k|10k)/i,
  /qualify.*for/i,
  /bq|boston qualify/i,
  /what pace should i/i,
  /goal pace/i,
  /target time/i,
  /predict.*time/i,
  /how fast (can|should|could) i/i,
  /am i ready for/i,
  /can i run.*(sub|under)/i,
];

// Data fields needed for different query types
// Priority order matters - most important fields first
const QUERY_DATA_REQUIREMENTS: Record<string, string[]> = {
  training_plan: [
    "current_weekly_mileage",
    "relevant_pr",
    "peak_weekly_mileage",
    "injury_status",
  ],
  race_prediction: ["relevant_pr", "current_weekly_mileage"],
  pace_advice: ["relevant_pr"], // PR is CRITICAL for pace advice - can't give meaningful pace without it
  qualification: ["relevant_pr", "current_weekly_mileage", "years_running"],
};

// Minimum missing fields before asking questions (per query type)
// Lower threshold = more likely to ask questions
const QUERY_THRESHOLD: Record<string, number> = {
  training_plan: 2,    // Ask if missing 2+ fields
  race_prediction: 1,  // Ask if missing ANY field - need data to predict
  pace_advice: 1,      // Ask if missing ANY field - can't guess pace without PR
  qualification: 2,    // Ask if missing 2+ fields
};

// Questions to ask for missing data
// These should sound natural and conversational
const CLARIFYING_QUESTIONS: Record<string, string> = {
  current_weekly_mileage:
    "What's your current weekly mileage? (e.g., 25-30 miles per week)",
  peak_weekly_mileage:
    "What's the highest weekly mileage you've comfortably handled in the past?",
  years_running: "How long have you been running consistently?",
  pr_marathon: "What's your marathon PR (or most recent marathon time)?",
  pr_half: "What's your half marathon PR (or most recent half time)?",
  pr_5k: "What's your 5K PR or a recent 5K time?",
  pr_10k: "What's your 10K PR or a recent 10K time? Even a time trial or hard tempo effort at that distance helps.",
  relevant_pr: "What's a recent race time at any distance? This helps me estimate appropriate paces for you.",
  injury_status:
    "Any current injuries or areas of concern I should know about?",
  recent_race: "What was your most recent race result (any distance)?",
  easy_pace_per_mile: "What's your typical easy/conversational run pace?",
  goal_race: "Do you have a specific goal race you're targeting?",
  available_days: "How many days per week can you realistically train?",
};

/**
 * Check if a query is complex enough to need clarifying questions
 */
export function isComplexQuery(query: string): boolean {
  return COMPLEX_QUERY_PATTERNS.some((pattern) => pattern.test(query));
}

/**
 * Get the threshold for asking clarifying questions based on query type
 */
export function getQueryThreshold(queryType: string): number {
  return QUERY_THRESHOLD[queryType] ?? 2;
}

/**
 * Determine what type of complex query this is
 */
export function getQueryType(query: string): string {
  const q = query.toLowerCase();

  if (/plan|schedule|program|training/i.test(q)) return "training_plan";
  if (/predict|estimate|target|goal time/i.test(q)) return "race_prediction";
  if (/pace|speed/i.test(q)) return "pace_advice";
  if (/qualify|bq|boston/i.test(q)) return "qualification";

  return "training_plan"; // default
}

/**
 * Detect which race distance the query is about
 */
export function detectTargetDistance(query: string): string | null {
  const q = query.toLowerCase();

  if (/marathon|26\.2|26 mile/i.test(q) && !/half/i.test(q)) return "marathon";
  if (/half.?marathon|13\.1|half/i.test(q)) return "half";
  if (/10k|10 k|10km/i.test(q)) return "10k";
  if (/5k|5 k|5km/i.test(q)) return "5k";

  return null;
}

/**
 * Get or create user profile
 */
export async function getOrCreateProfile(
  supabase: SupabaseClient,
  userId: string
): Promise<UserProfile> {
  // Try to fetch existing profile
  const { data: existing } = await supabase
    .from("user_profiles")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (existing) return existing;

  // Create new profile
  const { data: newProfile } = await supabase
    .from("user_profiles")
    .insert({ user_id: userId })
    .select()
    .single();

  return newProfile || { user_id: userId };
}

/**
 * Check if the user has ANY usable PR for pace estimation
 * Returns true if we have at least one PR we can use for calculations
 */
function hasAnyUsablePR(profile: UserProfile): boolean {
  return !!(
    profile.pr_5k_seconds ||
    profile.pr_10k_seconds ||
    profile.pr_half_seconds ||
    profile.pr_marathon_seconds
  );
}

/**
 * Check if the user has a PR at or near the target distance
 * For example, if asking about 10K pace:
 * - Best: has 10K PR
 * - Acceptable: has 5K or half PR (can extrapolate)
 * - Not acceptable: only has marathon PR (too different)
 */
function hasRelevantPR(profile: UserProfile, targetDistance: string | null): boolean {
  if (!targetDistance) {
    // No specific distance - any PR is fine
    return hasAnyUsablePR(profile);
  }

  switch (targetDistance) {
    case "5k":
      // For 5K: need 5K PR or 10K PR to extrapolate
      return !!(profile.pr_5k_seconds || profile.pr_10k_seconds);
    case "10k":
      // For 10K: need 10K, 5K, or half PR
      return !!(profile.pr_10k_seconds || profile.pr_5k_seconds || profile.pr_half_seconds);
    case "half":
      // For half: need half, 10K, or marathon PR
      return !!(profile.pr_half_seconds || profile.pr_10k_seconds || profile.pr_marathon_seconds);
    case "marathon":
      // For marathon: need marathon or half PR
      return !!(profile.pr_marathon_seconds || profile.pr_half_seconds);
    default:
      return hasAnyUsablePR(profile);
  }
}

/**
 * Get the best PR field to ask for based on target distance
 */
function getBestPRToAsk(targetDistance: string | null): string {
  switch (targetDistance) {
    case "5k":
      return "pr_5k";
    case "10k":
      return "pr_10k";
    case "half":
      return "pr_half";
    case "marathon":
      return "pr_marathon";
    default:
      return "relevant_pr";
  }
}

/**
 * Check what data is missing for a query type
 */
export function getMissingData(
  profile: UserProfile,
  queryType: string,
  targetDistance: string | null
): string[] {
  const requirements = QUERY_DATA_REQUIREMENTS[queryType] || [];
  const missing: string[] = [];

  for (const req of requirements) {
    if (req === "relevant_pr") {
      // Check if we have a usable PR for this distance
      if (!hasRelevantPR(profile, targetDistance)) {
        // Ask for the specific PR they need
        missing.push(getBestPRToAsk(targetDistance));
      }
    } else if (req === "current_weekly_mileage" && !profile.current_weekly_mileage) {
      missing.push("current_weekly_mileage");
    } else if (req === "peak_weekly_mileage" && !profile.peak_weekly_mileage) {
      missing.push("peak_weekly_mileage");
    } else if (req === "injury_status") {
      // Always good to ask about injuries for training plans if not recently updated
      if (!profile.current_injuries || profile.current_injuries.length === 0) {
        missing.push("injury_status");
      }
    } else if (req === "years_running" && !profile.years_running) {
      missing.push("years_running");
    } else if (req === "easy_pace_per_mile" && !profile.easy_pace_per_mile) {
      missing.push("easy_pace_per_mile");
    }
  }

  return missing;
}

/**
 * Generate clarifying questions for missing data
 * Returns up to 2-3 questions at a time to not overwhelm
 */
export function generateClarifyingQuestions(
  missingData: string[],
  maxQuestions: number = 3
): string[] {
  const questions: string[] = [];

  for (const field of missingData.slice(0, maxQuestions)) {
    const question = CLARIFYING_QUESTIONS[field];
    if (question) {
      questions.push(question);
    }
  }

  return questions;
}

/**
 * Build a prompt that asks clarifying questions
 */
export function buildClarifyingPrompt(
  originalQuery: string,
  questions: string[],
  profile: UserProfile
): string {
  // Build context from what we already know
  const knownParts: string[] = [];
  if (profile.current_weekly_mileage) {
    knownParts.push(`you're running about ${profile.current_weekly_mileage} miles per week`);
  }
  if (profile.pr_marathon_seconds) {
    knownParts.push(`your marathon PR is ${formatTime(profile.pr_marathon_seconds)}`);
  }
  if (profile.pr_half_seconds) {
    knownParts.push(`your half PR is ${formatTime(profile.pr_half_seconds)}`);
  }
  if (profile.pr_10k_seconds) {
    knownParts.push(`your 10K PR is ${formatTime(profile.pr_10k_seconds)}`);
  }
  if (profile.pr_5k_seconds) {
    knownParts.push(`your 5K PR is ${formatTime(profile.pr_5k_seconds)}`);
  }

  let knownContext = "";
  if (knownParts.length > 0) {
    knownContext = `I know ${knownParts.join(", ")}. `;
  }

  // Check if this is a pace-related question
  const isPaceQuestion = /pace|goal|target|predict|how fast/i.test(originalQuery);

  const intro = isPaceQuestion
    ? `To give you an accurate pace recommendation, I need a bit more info. ${knownContext}`
    : `I'd love to help with that! ${knownContext}To give you the best advice, I have a few quick questions:`;

  // For single questions, make it more conversational
  if (questions.length === 1) {
    return `${intro.replace("a few quick questions:", "")}

${questions[0]}`;
  }

  const questionList = questions
    .map((q, i) => `${i + 1}. ${q}`)
    .join("\n");

  return `${intro}

${questionList}

Once I have this, I can give you a much more accurate and personalized answer.`;
}

/**
 * Extract profile data from a user message
 * Returns updates to apply to the profile
 */
export function extractProfileData(
  message: string,
  conversationContext?: string
): Partial<UserProfile> {
  const updates: Partial<UserProfile> = {};
  const m = message.toLowerCase();

  // Extract weekly mileage
  const mileageMatch = message.match(
    /(\d+)[\s-]*(?:to|-)?\s*(\d+)?\s*(?:miles?|mi)\s*(?:per|a|\/)\s*week/i
  ) || message.match(/(?:running|run|do|averaging?)\s*(?:about|around)?\s*(\d+)[\s-]*(?:to|-)?\s*(\d+)?\s*(?:miles?|mi)/i);

  if (mileageMatch) {
    const low = parseInt(mileageMatch[1]);
    const high = mileageMatch[2] ? parseInt(mileageMatch[2]) : low;
    updates.current_weekly_mileage = (low + high) / 2;
  }

  // Extract PRs - marathon
  const marathonMatch = message.match(
    /(?:marathon|26\.2).*?(\d):(\d{2})(?::(\d{2}))?/i
  ) || message.match(/(\d):(\d{2})(?::(\d{2}))?\s*(?:marathon|for the marathon)/i);

  if (marathonMatch) {
    const hours = parseInt(marathonMatch[1]);
    const minutes = parseInt(marathonMatch[2]);
    const seconds = marathonMatch[3] ? parseInt(marathonMatch[3]) : 0;
    updates.pr_marathon_seconds = hours * 3600 + minutes * 60 + seconds;
  }

  // Extract PRs - half marathon
  const halfMatch = message.match(
    /(?:half|13\.1).*?(\d):(\d{2})(?::(\d{2}))?/i
  ) || message.match(/(\d):(\d{2})(?::(\d{2}))?\s*(?:half|for the half)/i);

  if (halfMatch && !marathonMatch) {
    const hours = parseInt(halfMatch[1]);
    const minutes = parseInt(halfMatch[2]);
    const seconds = halfMatch[3] ? parseInt(halfMatch[3]) : 0;
    updates.pr_half_seconds = hours * 3600 + minutes * 60 + seconds;
  }

  // Extract injuries
  const injuryKeywords = [
    "calf",
    "hamstring",
    "quad",
    "knee",
    "ankle",
    "achilles",
    "shin",
    "hip",
    "it band",
    "plantar",
    "foot",
    "back",
  ];

  for (const injury of injuryKeywords) {
    if (m.includes(injury)) {
      const side = m.includes("left") ? "left" : m.includes("right") ? "right" : "unknown";
      const status = m.includes("recovered") || m.includes("healed")
        ? "resolved"
        : "active";

      updates.current_injuries = [
        {
          area: injury,
          side: side,
          status: status,
          noted_at: new Date().toISOString(),
        },
      ];
      break;
    }
  }

  // Extract years running
  const yearsMatch = message.match(
    /(?:been running|running for|started running)\s*(?:about|around|for)?\s*(\d+)\s*(?:years?|yrs?)/i
  ) || message.match(/(\d+)\s*(?:years?|yrs?)\s*(?:of running|running)/i);

  if (yearsMatch) {
    updates.years_running = parseInt(yearsMatch[1]);
  }

  // Extract pace
  const paceMatch = message.match(
    /(?:easy|recovery)\s*(?:pace|run).*?(\d{1,2}):(\d{2})/i
  ) || message.match(/(\d{1,2}):(\d{2})\s*(?:per mile|\/mi)?\s*(?:for easy|easy pace)/i);

  if (paceMatch) {
    updates.easy_pace_per_mile = `${paceMatch[1]}:${paceMatch[2]}`;
  }

  return updates;
}

/**
 * Update user profile with extracted data
 */
export async function updateProfile(
  supabase: SupabaseClient,
  userId: string,
  updates: Partial<UserProfile>
): Promise<void> {
  if (Object.keys(updates).length === 0) return;

  // Handle injury array merging
  if (updates.current_injuries) {
    const { data: existing } = await supabase
      .from("user_profiles")
      .select("current_injuries")
      .eq("user_id", userId)
      .single();

    if (existing?.current_injuries) {
      updates.current_injuries = [
        ...existing.current_injuries,
        ...updates.current_injuries,
      ];
    }
  }

  await supabase
    .from("user_profiles")
    .upsert(
      { user_id: userId, ...updates },
      { onConflict: "user_id" }
    );

  console.log(`Profile updated for ${userId}:`, Object.keys(updates));
}

/**
 * Format seconds to time string (H:MM:SS or M:SS)
 */
function formatTime(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  }
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

/**
 * Build profile context for the AI prompt
 */
export function buildProfileContext(profile: UserProfile): string {
  const parts: string[] = [];

  if (profile.current_weekly_mileage) {
    parts.push(`Current weekly mileage: ${profile.current_weekly_mileage} miles`);
  }
  if (profile.peak_weekly_mileage) {
    parts.push(`Peak weekly mileage: ${profile.peak_weekly_mileage} miles`);
  }
  if (profile.years_running) {
    parts.push(`Running experience: ${profile.years_running} years`);
  }
  if (profile.pr_marathon_seconds) {
    parts.push(`Marathon PR: ${formatTime(profile.pr_marathon_seconds)}`);
  }
  if (profile.pr_half_seconds) {
    parts.push(`Half marathon PR: ${formatTime(profile.pr_half_seconds)}`);
  }
  if (profile.pr_10k_seconds) {
    parts.push(`10K PR: ${formatTime(profile.pr_10k_seconds)}`);
  }
  if (profile.pr_5k_seconds) {
    parts.push(`5K PR: ${formatTime(profile.pr_5k_seconds)}`);
  }
  if (profile.easy_pace_per_mile) {
    parts.push(`Easy pace: ${profile.easy_pace_per_mile}/mi`);
  }
  if (profile.current_injuries && profile.current_injuries.length > 0) {
    const injuries = profile.current_injuries
      .map((i: any) => `${i.side} ${i.area} (${i.status})`)
      .join(", ");
    parts.push(`Current injuries: ${injuries}`);
  }

  if (parts.length === 0) return "";

  return `\nRunner's profile:\n- ${parts.join("\n- ")}`;
}

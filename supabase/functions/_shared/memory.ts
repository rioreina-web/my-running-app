/**
 * User Memory Management
 *
 * Extracts important facts from conversations and stores them
 * for cross-session recall. Memories persist indefinitely unless
 * they have an expiration (e.g., temporary injuries).
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { detectInjury, upsertInjury } from "./injuries.ts";

export interface UserMemory {
  id?: string;
  user_id: string;
  category: string;
  content: string;
  source_conversation_id?: string;
  extracted_from?: string;
  importance?: number;
  expires_at?: string;
  created_at?: string;
}

// Categories for organizing memories
export const MEMORY_CATEGORIES = {
  PR: "pr",              // Personal records
  INJURY: "injury",      // Current/past injuries
  GOAL: "goal",          // Running goals
  PREFERENCE: "preference", // Training preferences
  TRAINING: "training",  // Training history/patterns
  RACE: "race",          // Race history
  PERSONAL: "personal",  // Personal info (name, etc.)
  AGREEMENT: "agreement", // Coaching agreements ("let's focus on...", "we agreed to...")
  CONTEXT: "context",     // Life context affecting training (stress, travel, sleep)
};

/**
 * Extract memorable facts from a message
 * Returns an array of memories to store
 */
export function extractMemories(
  message: string,
  assistantResponse: string,
  conversationContext?: string
): Partial<UserMemory>[] {
  const memories: Partial<UserMemory>[] = [];
  const m = message.toLowerCase();
  const fullContext = `${message} ${assistantResponse} ${conversationContext || ""}`.toLowerCase();

  // Extract PRs
  const prPatterns = [
    { regex: /(?:my|ran|pr|personal record).*?marathon.*?(\d):(\d{2}):?(\d{2})?/i, distance: "marathon" },
    { regex: /(\d):(\d{2}):?(\d{2})?\s*(?:marathon|26\.2)/i, distance: "marathon" },
    { regex: /(?:my|ran|pr|personal record).*?half.*?(\d):(\d{2}):?(\d{2})?/i, distance: "half marathon" },
    { regex: /(\d):(\d{2}):?(\d{2})?\s*(?:half|13\.1)/i, distance: "half marathon" },
    { regex: /(?:my|ran|pr|personal record).*?10k.*?(\d{2}):(\d{2})/i, distance: "10K" },
    { regex: /(\d{2}):(\d{2})\s*(?:10k|10 k)/i, distance: "10K" },
    { regex: /(?:my|ran|pr|personal record).*?5k.*?(\d{2}):(\d{2})/i, distance: "5K" },
    { regex: /(\d{2}):(\d{2})\s*(?:5k|5 k)/i, distance: "5K" },
  ];

  for (const { regex, distance } of prPatterns) {
    const match = message.match(regex);
    if (match) {
      const timeStr = match[3]
        ? `${match[1]}:${match[2]}:${match[3]}`
        : `${match[1]}:${match[2]}`;
      memories.push({
        category: MEMORY_CATEGORIES.PR,
        content: `${distance} PR: ${timeStr}`,
        importance: 8,
        extracted_from: message.slice(0, 200),
      });
      break; // Only extract one PR per message
    }
  }

  // Extract current injuries
  const injuryKeywords = [
    "calf", "hamstring", "quad", "knee", "ankle", "achilles",
    "shin", "hip", "it band", "plantar", "foot", "back", "glute"
  ];

  const injuryIndicators = [
    /hurt/i, /pain/i, /injured/i, /sore/i, /tight/i, /strain/i,
    /pulled/i, /torn/i, /inflammation/i, /tendinitis/i
  ];

  for (const injury of injuryKeywords) {
    if (m.includes(injury) && injuryIndicators.some(p => p.test(m))) {
      const side = m.includes("left") ? "left " : m.includes("right") ? "right " : "";
      const isHealed = /healed|recovered|better|gone|resolved/i.test(m);

      if (!isHealed) {
        memories.push({
          category: MEMORY_CATEGORIES.INJURY,
          content: `Current issue: ${side}${injury}`,
          importance: 9,
          expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(), // 30 days
          extracted_from: message.slice(0, 200),
        });
      }
      break;
    }
  }

  // Extract weekly mileage
  const mileageMatch = message.match(
    /(\d{1,3})\s*(?:to|-)\s*(\d{1,3})?\s*(?:miles?|mi)\s*(?:per|a|\/)\s*week/i
  ) || message.match(
    /(?:run|running|average|averaging)\s*(?:about|around)?\s*(\d{1,3})\s*(?:miles?|mi)/i
  );

  if (mileageMatch) {
    const miles = mileageMatch[2]
      ? Math.round((parseInt(mileageMatch[1]) + parseInt(mileageMatch[2])) / 2)
      : parseInt(mileageMatch[1]);

    memories.push({
      category: MEMORY_CATEGORIES.TRAINING,
      content: `Weekly mileage: approximately ${miles} miles`,
      importance: 7,
      extracted_from: message.slice(0, 200),
    });
  }

  // Extract race goals
  const goalPatterns = [
    /(?:training for|preparing for|goal is|targeting|aiming for)\s+(?:a\s+)?(.+?(?:marathon|half|10k|5k|race|ultra))/i,
    /(?:boston|nyc|chicago|berlin|london|tokyo)\s*(?:marathon)?/i,
    /(?:bq|boston qualify)/i,
    /(?:sub[- ]?\d)/i,
  ];

  for (const pattern of goalPatterns) {
    const match = message.match(pattern);
    if (match) {
      const goalText = match[1] || match[0];
      memories.push({
        category: MEMORY_CATEGORIES.GOAL,
        content: `Goal: ${goalText.trim()}`,
        importance: 8,
        extracted_from: message.slice(0, 200),
      });
      break;
    }
  }

  // Extract experience level
  const experienceMatch = message.match(
    /(?:been running|running for|started running)\s*(?:about|around|for)?\s*(\d+)\s*(?:years?|yrs?|months?)/i
  ) || message.match(
    /(\d+)\s*(?:years?|yrs?)\s*(?:of running|running experience)/i
  );

  if (experienceMatch) {
    const amount = experienceMatch[1];
    const unit = /month/i.test(experienceMatch[0]) ? "months" : "years";
    memories.push({
      category: MEMORY_CATEGORIES.TRAINING,
      content: `Running experience: ${amount} ${unit}`,
      importance: 6,
      extracted_from: message.slice(0, 200),
    });
  }

  // Extract pace information
  const paceMatch = message.match(
    /(?:easy|recovery)\s*(?:pace|run).*?(\d{1,2}):(\d{2})/i
  ) || message.match(
    /(\d{1,2}):(\d{2})\s*(?:per mile|\/ ?mi)?\s*(?:for easy|easy pace)/i
  );

  if (paceMatch) {
    memories.push({
      category: MEMORY_CATEGORIES.TRAINING,
      content: `Easy pace: ${paceMatch[1]}:${paceMatch[2]} per mile`,
      importance: 7,
      extracted_from: message.slice(0, 200),
    });
  }

  // Extract preferred run days
  const daysMatch = message.match(
    /(?:run|train)\s*(?:on)?\s*((?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s*,?\s*(?:and)?\s*(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))*)/i
  );

  if (daysMatch) {
    memories.push({
      category: MEMORY_CATEGORIES.PREFERENCE,
      content: `Preferred run days: ${daysMatch[1]}`,
      importance: 5,
      extracted_from: message.slice(0, 200),
    });
  }

  // Extract long run day
  const longRunMatch = message.match(
    /(?:long run|long runs?)\s*(?:on|every)?\s*(monday|tuesday|wednesday|thursday|friday|saturday|sunday)/i
  );

  if (longRunMatch) {
    memories.push({
      category: MEMORY_CATEGORIES.PREFERENCE,
      content: `Long run day: ${longRunMatch[1]}`,
      importance: 6,
      extracted_from: message.slice(0, 200),
    });
  }

  // Extract cross-training activities
  const crossTrainMatch = message.match(
    /(?:also|cross[- ]?train|do)\s*(cycling|swimming|yoga|strength|weights|pilates|elliptical|rowing)/i
  );

  if (crossTrainMatch) {
    memories.push({
      category: MEMORY_CATEGORIES.PREFERENCE,
      content: `Cross-training: ${crossTrainMatch[1]}`,
      importance: 5,
      extracted_from: message.slice(0, 200),
    });
  }

  // Extract coaching agreements (from both user and assistant messages)
  const agreementPatterns = [
    /(?:let'?s|we should|i want to|i'?d like to)\s+(focus on|work on|build|prioritize|target|stick with|commit to)\s+(.{5,80})/i,
    /(?:we agreed|let'?s agree|the plan is|going forward)\s+(?:to\s+)?(.{5,80})/i,
    /(?:can we|could you|please)\s+(?:keep|make sure|remind me to)\s+(.{5,80})/i,
  ];

  for (const pattern of agreementPatterns) {
    const match = message.match(pattern);
    if (match) {
      const agreement = match[2] ? `${match[1]} ${match[2]}` : match[1];
      memories.push({
        category: MEMORY_CATEGORIES.AGREEMENT,
        content: `Coaching agreement: ${agreement.trim()}`,
        importance: 8,
        extracted_from: message.slice(0, 200),
      });
      break;
    }
  }

  // Extract life context that affects training
  const contextPatterns = [
    { regex: /(?:really|super|very|so)\s+(stressed|exhausted|tired|busy|overwhelmed)/i, template: (m: RegExpMatchArray) => `Currently ${m[1]}` },
    { regex: /(?:not|haven'?t been|barely)\s+sleep(?:ing|t)\s*(?:well|enough|much)?/i, template: () => "Poor sleep quality" },
    { regex: /(?:traveling|on the road|on vacation|on a trip)\s*(?:for\s+.{3,30})?/i, template: (m: RegExpMatchArray) => `Traveling: ${m[0].trim()}` },
    { regex: /(?:new job|started a new|work has been|work is)\s+(.{3,40})/i, template: (m: RegExpMatchArray) => `Work: ${m[0].trim()}` },
    { regex: /(?:pregnant|expecting|having a baby|new baby|newborn)/i, template: (m: RegExpMatchArray) => `Life event: ${m[0].trim()}` },
    { regex: /(?:coming back from|returning from|just had)\s+(?:surgery|illness|covid|flu|cold)/i, template: (m: RegExpMatchArray) => `Recovery: ${m[0].trim()}` },
    { regex: /(?:heat|humidity|altitude|cold weather|winter|summer)\s+(?:is|has been|making)/i, template: (m: RegExpMatchArray) => `Environment: ${m[0].trim().slice(0, 50)}` },
  ];

  for (const { regex, template } of contextPatterns) {
    const match = message.match(regex);
    if (match) {
      memories.push({
        category: MEMORY_CATEGORIES.CONTEXT,
        content: template(match),
        importance: 7,
        expires_at: new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString(), // 14 days
        extracted_from: message.slice(0, 200),
      });
      break;
    }
  }

  return memories;
}

/**
 * Store memories in the database
 * Avoids duplicates by checking for similar existing memories
 */
export async function storeMemories(
  supabase: SupabaseClient,
  userId: string,
  memories: Partial<UserMemory>[],
  conversationId?: string
): Promise<void> {
  if (memories.length === 0) return;

  for (const memory of memories) {
    // Check for existing similar memory
    const { data: existing } = await supabase
      .from("user_memories")
      .select("id, content")
      .eq("user_id", userId)
      .eq("category", memory.category)
      .limit(10);

    // Simple duplicate check - if content is very similar, skip
    const isDuplicate = existing?.some((e) => {
      const similarity = calculateSimilarity(e.content, memory.content || "");
      return similarity > 0.8;
    });

    if (!isDuplicate) {
      await supabase.from("user_memories").insert({
        user_id: userId,
        category: memory.category,
        content: memory.content,
        source_conversation_id: conversationId,
        extracted_from: memory.extracted_from,
        importance: memory.importance || 5,
        expires_at: memory.expires_at,
      });
      console.log(`Stored memory: ${memory.category} - ${memory.content}`);

      // Also create/update injury record in the injuries table
      if (memory.category === MEMORY_CATEGORIES.INJURY && memory.extracted_from) {
        try {
          const detected = detectInjury(memory.extracted_from);
          if (detected) {
            await upsertInjury(supabase, userId, {
              ...detected,
              source: "coaching_chat",
              sourceReferenceId: conversationId,
              description: memory.content,
            });
          }
        } catch (injuryError) {
          console.error("Error creating injury record from memory:", injuryError);
        }
      }
    }
  }
}

/**
 * Retrieve relevant memories for a user
 * Returns memories sorted by importance
 */
export async function getMemories(
  supabase: SupabaseClient,
  userId: string,
  categories?: string[],
  limit: number = 15
): Promise<UserMemory[]> {
  let query = supabase
    .from("user_memories")
    .select("*")
    .eq("user_id", userId)
    .or("expires_at.is.null,expires_at.gt.now()")
    .order("importance", { ascending: false })
    .limit(limit);

  if (categories && categories.length > 0) {
    query = query.in("category", categories);
  }

  const { data, error } = await query;

  if (error) {
    console.error("Error fetching memories:", error);
    return [];
  }

  return data || [];
}

/**
 * Build memory context for the AI prompt
 * Formats memories into a concise string
 */
export function buildMemoryContext(memories: UserMemory[]): string {
  if (!memories || memories.length === 0) {
    return "";
  }

  // Group by category
  const grouped: Record<string, string[]> = {};
  for (const memory of memories) {
    if (!grouped[memory.category]) {
      grouped[memory.category] = [];
    }
    grouped[memory.category].push(memory.content);
  }

  const sections: string[] = [];

  // Format each category
  if (grouped[MEMORY_CATEGORIES.PR]) {
    sections.push(`PRs: ${grouped[MEMORY_CATEGORIES.PR].join(", ")}`);
  }
  if (grouped[MEMORY_CATEGORIES.INJURY]) {
    sections.push(`Health notes: ${grouped[MEMORY_CATEGORIES.INJURY].join(", ")}`);
  }
  if (grouped[MEMORY_CATEGORIES.GOAL]) {
    sections.push(`Goals: ${grouped[MEMORY_CATEGORIES.GOAL].join(", ")}`);
  }
  if (grouped[MEMORY_CATEGORIES.TRAINING]) {
    sections.push(`Training: ${grouped[MEMORY_CATEGORIES.TRAINING].join(", ")}`);
  }
  if (grouped[MEMORY_CATEGORIES.PREFERENCE]) {
    sections.push(`Preferences: ${grouped[MEMORY_CATEGORIES.PREFERENCE].join(", ")}`);
  }
  if (grouped[MEMORY_CATEGORIES.AGREEMENT]) {
    sections.push(`Coaching agreements: ${grouped[MEMORY_CATEGORIES.AGREEMENT].join("; ")}`);
  }
  if (grouped[MEMORY_CATEGORIES.CONTEXT]) {
    sections.push(`Current life context: ${grouped[MEMORY_CATEGORIES.CONTEXT].join("; ")}`);
  }

  if (sections.length === 0) return "";

  return `\nWhat I remember about this runner:\n- ${sections.join("\n- ")}`;
}

/**
 * Simple string similarity calculation
 * Returns a value between 0 and 1
 */
function calculateSimilarity(str1: string, str2: string): number {
  const s1 = str1.toLowerCase().trim();
  const s2 = str2.toLowerCase().trim();

  if (s1 === s2) return 1;

  const words1 = new Set(s1.split(/\s+/));
  const words2 = new Set(s2.split(/\s+/));

  const intersection = [...words1].filter((w) => words2.has(w)).length;
  const union = new Set([...words1, ...words2]).size;

  return intersection / union;
}

/**
 * Update an existing memory (e.g., when a PR improves)
 */
export async function updateMemory(
  supabase: SupabaseClient,
  memoryId: string,
  updates: Partial<UserMemory>
): Promise<void> {
  await supabase
    .from("user_memories")
    .update({
      ...updates,
      updated_at: new Date().toISOString(),
    })
    .eq("id", memoryId);
}

/**
 * Mark an injury as resolved
 */
export async function resolveInjury(
  supabase: SupabaseClient,
  userId: string,
  injuryKeyword: string
): Promise<void> {
  // Resolve in user_memories
  const { data: injuries } = await supabase
    .from("user_memories")
    .select("id, content")
    .eq("user_id", userId)
    .eq("category", MEMORY_CATEGORIES.INJURY)
    .ilike("content", `%${injuryKeyword}%`);

  if (injuries && injuries.length > 0) {
    for (const injury of injuries) {
      await supabase
        .from("user_memories")
        .update({
          content: injury.content.replace("Current issue:", "Resolved:"),
          expires_at: new Date().toISOString(), // Expire immediately
        })
        .eq("id", injury.id);
    }
  }

  // Also resolve in injuries table
  try {
    await supabase
      .from("injuries")
      .update({
        status: "resolved",
        resolved_at: new Date().toISOString(),
      })
      .eq("user_id", userId)
      .ilike("body_area", `%${injuryKeyword}%`)
      .in("status", ["active", "monitoring"]);
  } catch (error) {
    console.error("Error resolving injury in injuries table:", error);
  }
}

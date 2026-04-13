import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

export type InsightType =
  | "post_run_analysis"
  | "injury_warning"
  | "adaptive_workout"
  | "race_readiness"
  | "block_review"
  | "voice_debrief";

export type InsightPriority = "high" | "normal" | "low";
export type InsightStatus = "unread" | "read" | "dismissed" | "acted_on";

export interface CreateInsightParams {
  userId: string;
  insightType: InsightType;
  triggerSource: string;
  title: string;
  summary: string;
  fullAnalysis: Record<string, unknown>;
  referenceId?: string;
  priority?: InsightPriority;
  expiresAt?: string; // ISO date
}

/**
 * Create a new AI insight.
 */
export async function createInsight(params: CreateInsightParams): Promise<string | null> {
  const { data, error } = await supabase
    .from("ai_insights")
    .insert({
      user_id: params.userId,
      insight_type: params.insightType,
      trigger_source: params.triggerSource,
      title: params.title,
      summary: params.summary,
      full_analysis: params.fullAnalysis,
      reference_id: params.referenceId || null,
      priority: params.priority || "normal",
      expires_at: params.expiresAt || null,
    })
    .select("id")
    .single();

  if (error) {
    console.error(`Failed to create insight: ${error.message}`);
    return null;
  }
  return data.id;
}

/**
 * Mark an insight as read.
 */
export async function markInsightRead(insightId: string): Promise<void> {
  await supabase
    .from("ai_insights")
    .update({ status: "read" })
    .eq("id", insightId);
}

/**
 * Fetch recent insights for a user, optionally filtered by type.
 */
export async function getRecentInsights(
  userId: string,
  options?: { type?: InsightType; limit?: number; unreadOnly?: boolean }
): Promise<Record<string, unknown>[]> {
  let query = supabase
    .from("ai_insights")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(options?.limit || 20);

  if (options?.type) {
    query = query.eq("insight_type", options.type);
  }
  if (options?.unreadOnly) {
    query = query.eq("status", "unread");
  }

  const { data, error } = await query;
  if (error) {
    console.error(`Failed to fetch insights: ${error.message}`);
    return [];
  }
  return data || [];
}

/**
 * Clean up expired insights.
 */
export async function cleanupExpiredInsights(): Promise<number> {
  const { data, error } = await supabase
    .from("ai_insights")
    .delete()
    .lt("expires_at", new Date().toISOString())
    .select("id");

  if (error) {
    console.error(`Failed to cleanup insights: ${error.message}`);
    return 0;
  }
  return data?.length || 0;
}

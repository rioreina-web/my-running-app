/**
 * Shared Injury Detection & Management
 *
 * Centralizes injury logic for voice memos, coaching chat, and manual entry.
 * Used by process-training-memo, coaching-agent (via memory.ts), and injury-analysis.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface InjuryRecord {
  id?: string;
  user_id: string;
  body_area: string;
  side: string;
  description?: string;
  severity: number;
  status: string;
  first_reported_at?: string;
  resolved_at?: string;
  source: string;
  source_reference_id?: string;
  ai_analysis?: Record<string, unknown>;
  ai_analysis_at?: string;
}

// Same keywords used in memory.ts and profile.ts
export const INJURY_KEYWORDS = [
  "calf", "hamstring", "quad", "knee", "ankle", "achilles",
  "shin", "hip", "it band", "plantar", "foot", "back", "glute",
];

export const INJURY_INDICATORS = [
  /hurt/i, /pain/i, /injured/i, /sore/i, /tight/i, /stiff/i, /strain/i,
  /pulled/i, /torn/i, /inflammation/i, /tendinitis/i, /aching/i, /tweaked/i,
  /flared/i, /swollen/i, /cramping/i, /throbbing/i, /pinching/i, /stabbing/i,
];

const HEALED_INDICATORS = /healed|recovered|better|gone|resolved|cleared up|no more/i;

/**
 * Detect injury mentions in text.
 * Returns parsed injury data or null if no injury found.
 */
export function detectInjury(text: string): {
  bodyArea: string;
  side: string;
  isResolved: boolean;
  severity: number;
} | null {
  const lower = text.toLowerCase();

  for (const keyword of INJURY_KEYWORDS) {
    if (lower.includes(keyword) && INJURY_INDICATORS.some((p) => p.test(lower))) {
      const side = lower.includes("left")
        ? "left"
        : lower.includes("right")
          ? "right"
          : "unknown";
      const isResolved = HEALED_INDICATORS.test(lower);
      const severity = estimateSeverity(lower);

      return { bodyArea: keyword, side, isResolved, severity };
    }
  }
  return null;
}

/**
 * Estimate severity from text cues. Returns 1-10.
 */
function estimateSeverity(text: string): number {
  if (/torn|severe|can't walk|can't run|excruciating|fracture/i.test(text)) return 9;
  if (/sharp|bad|really hurt|significant|swollen/i.test(text)) return 7;
  if (/strain|pulled|inflammation|tendinitis/i.test(text)) return 6;
  if (/pain|hurt|injured/i.test(text)) return 5;
  if (/sore|tight|stiff|ache|niggle|minor|tender/i.test(text)) return 3;
  return 5;
}

/**
 * Create or update an injury record.
 * - If an active injury exists for the same body_area+side, update it.
 * - If the injury is being reported as resolved, mark it resolved.
 * - Otherwise create a new record.
 */
export async function upsertInjury(
  supabase: SupabaseClient,
  userId: string,
  injury: {
    bodyArea: string;
    side: string;
    isResolved: boolean;
    severity: number;
    source: string;
    sourceReferenceId?: string;
    description?: string;
  }
): Promise<void> {
  try {
    // Check for existing active injury of same type
    const { data: existing } = await supabase
      .from("injuries")
      .select("id, severity, status")
      .eq("user_id", userId)
      .eq("body_area", injury.bodyArea)
      .eq("side", injury.side)
      .in("status", ["active", "monitoring"])
      .order("created_at", { ascending: false })
      .limit(1);

    if (injury.isResolved && existing && existing.length > 0) {
      // Mark as resolved
      await supabase
        .from("injuries")
        .update({
          status: "resolved",
          resolved_at: new Date().toISOString(),
        })
        .eq("id", existing[0].id);
      console.log(`Injury resolved: ${injury.side} ${injury.bodyArea}`);
      return;
    }

    if (existing && existing.length > 0) {
      // Update severity if new mention is more severe
      const updates: Record<string, unknown> = {};
      if (injury.severity > existing[0].severity) {
        updates.severity = injury.severity;
      }
      if (injury.description) {
        updates.description = injury.description;
      }
      if (Object.keys(updates).length > 0) {
        await supabase
          .from("injuries")
          .update(updates)
          .eq("id", existing[0].id);
        console.log(`Injury updated: ${injury.side} ${injury.bodyArea}`);
      }
      return;
    }

    if (!injury.isResolved) {
      // Create new injury record
      await supabase.from("injuries").insert({
        user_id: userId,
        body_area: injury.bodyArea,
        side: injury.side,
        severity: injury.severity,
        status: "active",
        source: injury.source,
        source_reference_id: injury.sourceReferenceId,
        description: injury.description,
      });
      console.log(`Injury created: ${injury.side} ${injury.bodyArea}`);
    }
  } catch (error) {
    console.error("Error upserting injury:", error);
  }
}

/**
 * Fetch active injuries for a user (for AI context).
 */
export async function getActiveInjuries(
  supabase: SupabaseClient,
  userId: string
): Promise<InjuryRecord[]> {
  const { data, error } = await supabase
    .from("injuries")
    .select("*")
    .eq("user_id", userId)
    .in("status", ["active", "monitoring"])
    .order("severity", { ascending: false });

  if (error) {
    console.error("Error fetching injuries:", error);
    return [];
  }
  return data || [];
}

/**
 * Build injury context string for AI prompts.
 */
export function buildInjuryContext(injuries: InjuryRecord[]): string {
  if (!injuries || injuries.length === 0) return "";

  const lines = injuries.map((i) => {
    const daysSince = Math.floor(
      (Date.now() - new Date(i.first_reported_at!).getTime()) / (1000 * 60 * 60 * 24)
    );
    const sideLabel = i.side !== "unknown" ? `${i.side} ` : "";
    return `${sideLabel}${i.body_area} (severity: ${i.severity}/10, ${i.status}, ${daysSince} days)${i.description ? ` - ${i.description}` : ""}`;
  });

  return `\nActive injuries/issues:\n- ${lines.join("\n- ")}`;
}

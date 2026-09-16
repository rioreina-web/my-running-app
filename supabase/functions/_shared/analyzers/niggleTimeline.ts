/**
 * `niggle_timeline` — "Where has this shown up, and when?"
 *
 * Principle X (The body). Reads `body_mentions` (what was said, verbatim) and
 * `niggle_resolutions` (the athlete's own all-clear watermarks).
 *
 * HARD RULE #2 GOVERNS EVERY LINE OF THIS FILE. Detection, not diagnosis:
 *
 *  • **Quote verbatim.** `verbatim_quote` is reproduced exactly. "Could barely
 *    walk" is never coerced into a severity number, and never paraphrased.
 *  • **Closed vocabulary.** `body_area` comes from `bodyVocabulary.ts`. If the
 *    athlete said "subtalar joint" the classifier already mapped it to ankle or
 *    dropped it — this analyzer never invents a body part or a condition.
 *  • **Report, never interpret.** It says what was said and where. It never
 *    says what that means, never names a condition, never assesses severity
 *    itself, and never recommends rest, ice, or a doctor.
 *
 * The fact lines here are mostly counts and dates. The quotes travel in
 * `coverage.missing`-adjacent prose instead of as numeric facts, so Layer 2
 * can see them without them licensing stray numbers.
 *
 * ON RESTRAINT. This analyzer is deliberately only reachable when asked. It is
 * NOT part of any standing bundle, because a signal that fires roughly once
 * every seventy runs should not lead the conversation. See the surfaced
 * watermark in ASK-V2-CONVERSATION.md §3 — that governs what Ask *volunteers*;
 * this analyzer governs what it will *answer*.
 */

import { daysAgoISO } from "./data.ts";
import {
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type FactLine,
} from "./types.ts";
import { fetchAthleteState } from "./athleteState.ts";

const DEFAULT_WINDOW_DAYS = 180;
/** Below this a "timeline" says nothing a single entry doesn't already say. */
const MIN_MENTIONS_FOR_TIMELINE = 3;

interface MentionRow {
  body_area: string | null;
  side: string | null;
  verbatim_quote: string | null;
  severity_hint: string | null;
  mentioned_at: string | null;
  volume_context: string | null;
}

interface ResolutionRow {
  body_area: string | null;
  side: string | null;
  resolved_at: string | null;
}

function areaLabel(area: string | null, side: string | null): string {
  const a = (area ?? "area").replace(/_/g, " ");
  return side ? `${side} ${a}` : a;
}

export const niggleTimeline: Analyzer = {
  id: "niggle_timeline",
  label: "Where has this niggle shown up?",
  group: "body",
  params: {
    body_area: {
      type: "string",
      optional: true,
      describe:
        "Which body area to trace. Omit to use the one mentioned most. Must be a known area or it is dropped.",
    },
    window_days: {
      type: "number",
      min: 30,
      max: 730,
      optional: true,
      describe: "How far back to look. Defaults to 180 days.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const windowDays = Number(params.window_days ?? DEFAULT_WINDOW_DAYS);
    const since = daysAgoISO(ctx.now, windowDays).slice(0, 10);

    const [{ data: mentionData }, { data: resolutionData }, state] = await Promise.all([
      ctx.supabase
        .from("body_mentions")
        .select("body_area, side, verbatim_quote, severity_hint, mentioned_at, volume_context")
        .eq("user_id", ctx.userId)
        .gte("mentioned_at", since)
        .order("mentioned_at", { ascending: true }),
      ctx.supabase
        .from("niggle_resolutions")
        .select("body_area, side, resolved_at")
        .eq("user_id", ctx.userId)
        .order("resolved_at", { ascending: false }),
      fetchAthleteState(ctx.supabase, ctx.userId),
    ]);

    const mentions = (mentionData ?? []) as MentionRow[];
    const resolutions = (resolutionData ?? []) as ResolutionRow[];

    if (mentions.length === 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays, missing: [], confidence: "low" },
        related: ["mood_trend", "load_balance"],
        empty: {
          eyebrow: "Nothing on file",
          nudge:
            "No body-part mentions in this window. These come from what you say in your voice logs, in your own words.",
          cta: null,
        },
      };
    }

    // Which area — the requested one, else the most-mentioned.
    const requested = typeof params.body_area === "string"
      ? params.body_area.toLowerCase().replace(/\s+/g, "_")
      : null;
    const counts = new Map<string, number>();
    for (const m of mentions) {
      const k = (m.body_area ?? "").toLowerCase();
      if (k) counts.set(k, (counts.get(k) ?? 0) + 1);
    }
    const area = requested && counts.has(requested)
      ? requested
      : [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

    if (!area) {
      return {
        facts: [],
        coverage: { sessionsUsed: mentions.length, windowDays, missing: [], confidence: "low" },
        related: ["mood_trend"],
        empty: {
          eyebrow: requested ? "Nothing logged for that area" : "Nothing on file",
          nudge:
            "There are mentions in this window, but none for that body area. Body areas come from a fixed list — anything outside it isn't recorded as one.",
          cta: null,
        },
      };
    }

    const forArea = mentions.filter((m) => (m.body_area ?? "").toLowerCase() === area);
    const side = forArea.find((m) => m.side)?.side ?? null;
    const label = areaLabel(area, side);

    const first = forArea[0];
    const last = forArea[forArea.length - 1];

    // Has the athlete since said it's fine? That watermark is theirs, not ours.
    const resolvedAfter = resolutions.find(
      (r) =>
        (r.body_area ?? "").toLowerCase() === area &&
        r.resolved_at != null &&
        last?.mentioned_at != null &&
        r.resolved_at >= last.mentioned_at,
    );

    const daysSince = last?.mentioned_at
      ? Math.max(
        0,
        Math.round(
          (ctx.now.getTime() - new Date(last.mentioned_at + "T00:00:00Z").getTime()) / 86400000,
        ),
      )
      : null;

    const facts: FactLine[] = [
      {
        key: "mentions",
        label: `Times mentioned · ${label}`,
        value: String(forArea.length),
        tone: "neutral",
      },
    ];

    if (daysSince != null) {
      facts.push({
        key: "days_since",
        label: "Days since last mentioned",
        value: String(daysSince),
        // Silence is not "good" — it is only silence. Neutral, always.
        tone: "neutral",
      });
    }

    if (first?.mentioned_at && last?.mentioned_at && first !== last) {
      const span = Math.round(
        (new Date(last.mentioned_at + "T00:00:00Z").getTime() -
          new Date(first.mentioned_at + "T00:00:00Z").getTime()) / 86400000,
      );
      facts.push({
        key: "span_days",
        label: "Spanning",
        value: String(span),
        unit: " days",
        tone: "neutral",
      });
    }

    // Under the floor, a "timeline" is a single entry wearing a hat. Say so.
    if (forArea.length < MIN_MENTIONS_FOR_TIMELINE) {
      return {
        title: `What have I said about my ${label}?`,
        facts,
        series: null,
        coverage: {
          sessionsUsed: forArea.length,
          windowDays,
          missing: [
            `a timeline gets honest at ${MIN_MENTIONS_FOR_TIMELINE} mentions`,
            ...forArea
              .filter((m) => m.verbatim_quote)
              .map((m) => `${m.mentioned_at}: "${m.verbatim_quote}"`),
          ],
          confidence: "low",
        },
        related: ["mood_trend", "load_balance"],
        empty: {
          eyebrow: `${forArea.length} ${forArea.length === 1 ? "mention" : "mentions"} on file`,
          nudge: forArea[0]?.verbatim_quote
            ? `You said: "${forArea[0].verbatim_quote}". One or two mentions don't make a pattern — this fills in if it keeps coming up.`
            : "One or two mentions don't make a pattern. This fills in if it keeps coming up.",
          cta: null,
        },
      };
    }

    // Verbatim quotes ride in coverage so Layer 2 can read them without them
    // licensing numbers. Newest first, capped — the point is the athlete's own
    // words, not an exhaustive log.
    const quotes = forArea
      .filter((m) => m.verbatim_quote)
      .slice(-4)
      .reverse()
      .map((m) => `${m.mentioned_at}: "${m.verbatim_quote}"`);

    const missing = [...quotes];
    if (resolvedAfter?.resolved_at) {
      missing.push(`you marked this resolved on ${resolvedAfter.resolved_at}`);
    }
    const recurrence = (state?.niggle_recurrence ?? []).find(
      (n) => (n?.body_area ?? "").toLowerCase() === area,
    );
    if (recurrence?.worst_severity) {
      missing.push(`strongest wording used: "${recurrence.worst_severity}"`);
    }

    return {
      title: `Where has my ${label} shown up?`,
      facts,
      series: null,
      coverage: {
        sessionsUsed: forArea.length,
        windowDays,
        missing,
        confidence: forArea.length >= 5 ? "moderate" : "low",
      },
      related: ["load_balance", "mood_trend", "zone_trend"],
    };
  },
};

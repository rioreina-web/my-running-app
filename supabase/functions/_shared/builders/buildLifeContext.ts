/**
 * buildLifeContext — pure qualitative-life slice.
 *
 * Rolls up the structured life fields the voice-memo pipeline extracts into
 * `training_logs.extracted_data` (see _shared/prompts/process-training-memo.v1.ts
 * §extracted_data) into a small, recency-first block the Read can reference.
 *
 * Design rules (audit fix #1, outputs/life-context-implementation-plan-2026-07-02.md):
 *   - Verbatim-adjacent: store the athlete's own labels; never reinterpret.
 *   - Null-heavy tolerance: most memos populate 2-3 fields; many historical
 *     rows carry only the old extraction schema (workout_type / rpe /
 *     sleep_quality / weather) — the builder must degrade gracefully.
 *   - No medical language: illness/soreness details are the athlete's own
 *     phrase; surface, never diagnose (hard rule #2).
 *
 * Input is the 28-day recent-logs window (already fetched by
 * rebuildAthleteState) with `extracted_data` included in the select.
 */

export interface LifeContextLogRow {
  workout_date?: unknown;
  source?: unknown;
  extracted_data?: unknown;
}

export interface LifeContext {
  sleep: {
    poor_mentions_7d: number;
    mentions_28d: number;
    last: { date: string; quality: string; hours: number | null } | null;
  };
  /** Most recent first, up to 5. Labels: fresh | normal | tired | wiped (athlete's framing). */
  fatigue: Array<{ date: string; label: string }>;
  /**
   * Effort trail from `extracted_data.effort_level` — the DENSEST real signal
   * (present on nearly every memo). Labels: easy | moderate | hard | max | tired
   * (athlete's own framing). Most recent first, up to 5. `hard_7d` counts
   * hard/max efforts in the last 7 days (a grind proxy the Read can reference).
   */
  effort: Array<{ date: string; label: string }>;
  hard_7d: number;
  stress: {
    work_high_7d: number;
    life_high_7d: number;
    any_high_28d: number;
    last_mention: string | null; // YYYY-MM-DD of most recent high work/life stress
  };
  /** Mention within 10 days counts as active. Detail is the athlete's own phrase. */
  illness: { active: boolean; detail: string | null; date: string | null };
  /** Mention within 7 days counts as recent. */
  travel: { recent: boolean; detail: string | null; date: string | null };
  motivation: { low_7d: number; last: string | null };
  /** Most recent first, up to 4. Values per the memo prompt's closed set. */
  felt_vs_looked: Array<{ date: string; value: string }>;
  avg_rpe_7d: number | null;
  /** One compressed line for summaries; null when the slice is empty. */
  summary: string | null;
}

const DAY_MS = 86400000;

function str(v: unknown): string | null {
  return typeof v === "string" && v.trim().length > 0 ? v.trim() : null;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return v != null && typeof v === "object" && !Array.isArray(v);
}

/**
 * Returns the life-context slice, or null when NO log in the window carries
 * any life field at all (so the state stores null, not an all-empty object —
 * consumers and data_gaps key off that).
 */
export function buildLifeContext(
  logs: LifeContextLogRow[],
  now: Date,
): LifeContext | null {
  const sevenDaysAgoMs = now.getTime() - 7 * DAY_MS;
  const tenDaysAgoMs = now.getTime() - 10 * DAY_MS;
  const twentyEightDaysAgoMs = now.getTime() - 28 * DAY_MS;

  // Normalize: rows with a parseable date and an extracted_data object,
  // most recent first. Dedup by date is NOT applied — two memos on one day
  // are two real mentions.
  const rows = logs
    .map((l) => {
      const dateRaw = str(l.workout_date);
      const ed = isRecord(l.extracted_data) ? l.extracted_data : null;
      if (!dateRaw || !ed) return null;
      const ms = new Date(dateRaw).getTime();
      if (!isFinite(ms) || ms < twentyEightDaysAgoMs) return null;
      return { date: dateRaw.slice(0, 10), ms, ed };
    })
    .filter((r): r is { date: string; ms: number; ed: Record<string, unknown> } => r != null)
    .sort((a, b) => b.ms - a.ms);

  let sawAnyLifeField = false;

  // ── Sleep ──
  let poorMentions7d = 0;
  let sleepMentions28d = 0;
  let lastSleep: LifeContext["sleep"]["last"] = null;
  for (const r of rows) {
    const q = str(r.ed["sleep_quality"]);
    if (!q) continue;
    sawAnyLifeField = true;
    sleepMentions28d++;
    if (q === "poor" && r.ms >= sevenDaysAgoMs) poorMentions7d++;
    if (!lastSleep) {
      const hours = typeof r.ed["sleep_hours"] === "number" ? (r.ed["sleep_hours"] as number) : null;
      lastSleep = { date: r.date, quality: q, hours };
    }
  }

  // ── Fatigue trail (last 5) ──
  const fatigue: LifeContext["fatigue"] = [];
  for (const r of rows) {
    const f = str(r.ed["fatigue"]);
    if (!f) continue;
    sawAnyLifeField = true;
    if (fatigue.length < 5) fatigue.push({ date: r.date, label: f });
  }

  // ── Effort trail (last 5) + hard-effort count (7d) ──
  // effort_level is the densest field in real memos; treat it as the athlete's
  // own read of how hard the session was. "tired" here is a feeling signal.
  const effort: LifeContext["effort"] = [];
  let hard7d = 0;
  for (const r of rows) {
    const e = str(r.ed["effort_level"]);
    if (!e) continue;
    sawAnyLifeField = true;
    if (effort.length < 5) effort.push({ date: r.date, label: e });
    if ((e === "hard" || e === "max") && r.ms >= sevenDaysAgoMs) hard7d++;
  }

  // ── Stress ──
  // Read both vocabularies: the memo prompt emits work_stress/life_stress; the
  // check-in prompt (and legacy rows) emit a single stress_level. An
  // unattributed stress_level is counted as general life load.
  let workHigh7d = 0, lifeHigh7d = 0, anyHigh28d = 0;
  let lastStressMention: string | null = null;
  for (const r of rows) {
    const w = str(r.ed["work_stress"]);
    const l = str(r.ed["life_stress"]);
    const g = str(r.ed["stress_level"]); // check-in / legacy, unattributed
    if (!w && !l && !g) continue;
    sawAnyLifeField = true;
    const wHigh = w === "high";
    const lHigh = l === "high" || g === "high"; // fold general stress into life
    if (wHigh || lHigh) {
      anyHigh28d++;
      if (!lastStressMention) lastStressMention = r.date; // rows are date-desc
      if (r.ms >= sevenDaysAgoMs) {
        if (wHigh) workHigh7d++;
        if (lHigh) lifeHigh7d++;
      }
    }
  }

  // ── Illness (active = mentioned within 10d) ──
  let illness: LifeContext["illness"] = { active: false, detail: null, date: null };
  for (const r of rows) {
    const i = str(r.ed["illness"]);
    if (!i) continue;
    sawAnyLifeField = true;
    illness = { active: r.ms >= tenDaysAgoMs, detail: i.slice(0, 120), date: r.date };
    break; // most recent mention only
  }

  // ── Travel (recent = mentioned within 7d) ──
  let travel: LifeContext["travel"] = { recent: false, detail: null, date: null };
  for (const r of rows) {
    const t = str(r.ed["travel"]);
    if (!t) continue;
    sawAnyLifeField = true;
    travel = { recent: r.ms >= sevenDaysAgoMs, detail: t.slice(0, 120), date: r.date };
    break;
  }

  // ── Motivation ──
  let motivationLow7d = 0;
  let lastMotivation: string | null = null;
  for (const r of rows) {
    const m = str(r.ed["motivation"]);
    if (!m) continue;
    sawAnyLifeField = true;
    if (!lastMotivation) lastMotivation = m;
    if (m === "low" && r.ms >= sevenDaysAgoMs) motivationLow7d++;
  }

  // ── felt_vs_looked (last 4) ──
  const feltVsLooked: LifeContext["felt_vs_looked"] = [];
  for (const r of rows) {
    const f = str(r.ed["felt_vs_looked"]);
    if (!f) continue;
    sawAnyLifeField = true;
    if (feltVsLooked.length < 4) feltVsLooked.push({ date: r.date, value: f });
  }

  // ── RPE (7d average) ──
  const rpes7d = rows
    .filter((r) => r.ms >= sevenDaysAgoMs)
    .map((r) => r.ed["rpe"])
    .filter((v): v is number => typeof v === "number" && isFinite(v) && v >= 1 && v <= 10);
  if (rpes7d.length > 0) sawAnyLifeField = true;
  const avgRpe7d = rpes7d.length > 0
    ? Math.round((rpes7d.reduce((s, v) => s + v, 0) / rpes7d.length) * 10) / 10
    : null;

  if (!sawAnyLifeField) return null;

  // ── Summary line ──
  const parts: string[] = [];
  if (poorMentions7d > 0) parts.push(`sleep poor ×${poorMentions7d} this week`);
  if (workHigh7d > 0) parts.push(`work stress high ×${workHigh7d}`);
  if (lifeHigh7d > 0) parts.push(`life stress high ×${lifeHigh7d}`);
  const tiredCount = fatigue.filter(
    (f) => (f.label === "tired" || f.label === "wiped") &&
      new Date(f.date).getTime() >= sevenDaysAgoMs,
  ).length;
  if (tiredCount > 0) parts.push(`body ${tiredCount > 1 ? "repeatedly " : ""}tired going in`);
  if (illness.active) parts.push(`illness: "${illness.detail}"`);
  if (travel.recent) parts.push(`travel: "${travel.detail}"`);
  if (motivationLow7d > 0) parts.push(`motivation low ×${motivationLow7d}`);
  const harder7 = feltVsLooked.filter((f) => f.value === "harder than it looks").length;
  if (harder7 >= 2) parts.push(`felt harder than it looked ×${harder7} recently`);
  if (hard7d >= 3) parts.push(`hard efforts ×${hard7d} this week`);

  return {
    sleep: { poor_mentions_7d: poorMentions7d, mentions_28d: sleepMentions28d, last: lastSleep },
    fatigue,
    effort,
    hard_7d: hard7d,
    stress: {
      work_high_7d: workHigh7d,
      life_high_7d: lifeHigh7d,
      any_high_28d: anyHigh28d,
      last_mention: lastStressMention,
    },
    illness,
    travel,
    motivation: { low_7d: motivationLow7d, last: lastMotivation },
    felt_vs_looked: feltVsLooked,
    avg_rpe_7d: avgRpe7d,
    summary: parts.length > 0 ? parts.join(" · ") : null,
  };
}

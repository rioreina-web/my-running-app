/**
 * buildReadiness — the first "reasoning layer" builder.
 *
 * Everything else in athlete_state DESCRIBES the athlete (here's your load,
 * here's your sleep trail). This builder DRAWS A CONCLUSION from that data the
 * way a coach would: it fuses the recovery signal (the qualitative life_context
 * we now capture) with acute training load into a single push / hold / pull
 * read — "is the body absorbing the training right now?"
 *
 * WHY THIS SHAPE (see outputs/readiness-assessment-design-2026-07-03.md):
 *   - Reasoning lives in CODE, not the LLM. This is a pure, deterministic,
 *     unit-tested function. The Coach Read narrates its verdict; it does not
 *     re-derive training science in the prompt (where it would hallucinate).
 *   - SAFETY (CLAUDE.md hard rule #2): the verdict is an OBSERVATION for the
 *     Read / coach to reference. It NEVER prescribes rest, and "pull" is the
 *     internal label — the narration turns it into a soft question, not a
 *     directive. Injuries/medical are out of scope here (handled by niggles).
 *   - Returns null when there isn't enough signal to have an opinion, so the
 *     state stores null (honest) rather than a fabricated "hold".
 *
 * The model is intentionally simple and legible: a signed score built from
 * named drivers, each grounded in a real field and a coaching principle, then
 * mapped to a verdict. Every threshold is commented with its rationale so a
 * coach can pressure-test it against docs/coaching/principles.md.
 */

import type { LifeContext } from "./buildLifeContext.ts";

export interface ReadinessInput {
  /** The qualitative recovery signal (sleep, effort, felt-vs-looked, mood-in-memos). */
  lifeContext: LifeContext | null;
  /** Acute:chronic workload ratio. Null when there isn't enough history. */
  acwr: number | null;
  /** Foster training monotony (7d). High monotony (same load every day) raises
   *  injury/illness risk independent of volume. Null when unavailable. */
  monotony7d: number | null;
  /** "improving" | "declining" | "stable" | null (from buildMoodTrend). */
  moodTrend: string | null;
  /** Most recent mood label: energized|positive|neutral|tired|struggling|injured. */
  lastMood: string | null;
}

export type ReadinessVerdict = "push" | "hold" | "pull";

export interface Readiness {
  /** push = body looks ready to absorb more; hold = neutral/mixed; pull = the
   *  body is asking for less. Internal label — narrate as observation, never a
   *  rest prescription. */
  verdict: ReadinessVerdict;
  /** Signed score behind the verdict (positive = ready, negative = drained).
   *  Exposed for transparency / debugging, not for display. */
  score: number;
  confidence: "high" | "medium" | "low";
  /** Human-readable evidence in the athlete's own framing, most important
   *  first. What the Read cites. */
  drivers: string[];
  /** One compressed, feeling-first observation line the Read can lean on. */
  read: string;
}

/**
 * Returns a readiness read, or null when there isn't enough signal to justify
 * one (no recovery signal AND no load signal).
 */
export function buildReadiness(input: ReadinessInput): Readiness | null {
  const lc = input.lifeContext;
  const drivers: string[] = [];
  const positives: string[] = [];
  let score = 0;
  let signals = 0; // independent signals present → confidence

  // ── Recovery drags (the qualitative side — the point of life_context) ──
  if (lc) {
    // Rough sleep repeatedly is the strongest self-reported recovery drag.
    if (lc.sleep.poor_mentions_7d >= 2) {
      score -= 2; signals++;
      drivers.push(`rough sleep ×${lc.sleep.poor_mentions_7d} this week`);
    } else if (lc.sleep.poor_mentions_7d === 1) {
      score -= 1; signals++;
      drivers.push("a rough night's sleep this week");
    }

    // "Harder than it looks" ≥2 = the classic early-overreach tell a coach
    // prizes: same paces costing more than they show.
    const harder = lc.felt_vs_looked.filter((f) => f.value === "harder than it looks").length;
    if (harder >= 2) {
      score -= 2; signals++;
      drivers.push(`runs felt harder than they looked ×${harder}`);
    } else if (harder === 1) {
      score -= 1; signals++;
      drivers.push("a run felt harder than it looked");
    }
    // The inverse is a genuine green light.
    const easier = lc.felt_vs_looked.filter((f) => f.value === "easier than it looks").length;
    if (easier >= 1) { score += 1; signals++; positives.push("paces feeling easier than they look"); }

    // Body "tired"/"wiped" going into recent runs.
    const tired = lc.fatigue.filter((f) => f.label === "tired" || f.label === "wiped").length;
    if (tired >= 2) { score -= 2; signals++; drivers.push(`body tired going in ×${tired}`); }
    else if (tired === 1) { score -= 1; signals++; drivers.push("body tired going in recently"); }

    // Life load off the run (work/life stress high).
    const stressHigh = lc.stress.work_high_7d + lc.stress.life_high_7d;
    if (stressHigh >= 2) { score -= 1; signals++; drivers.push(`stress high ×${stressHigh} this week`); }

    // A pile of hard efforts with no let-up is a load-from-the-athlete signal.
    if (lc.hard_7d >= 3) { score -= 1; signals++; drivers.push(`hard efforts ×${lc.hard_7d} this week`); }

    // Low motivation is a soft but real recovery/psychological drag.
    if (lc.motivation.low_7d >= 1) { score -= 1; signals++; drivers.push("motivation low this week"); }
  }

  // ── Mood (separate signal, union of memos + check-ins) ──
  if (input.lastMood === "tired" || input.lastMood === "struggling") {
    score -= 1; signals++; drivers.push(`feeling ${input.lastMood}`);
  } else if (input.lastMood === "energized" || input.lastMood === "positive") {
    score += 1; signals++; positives.push(`feeling ${input.lastMood}`);
  }
  if (input.moodTrend === "declining") { score -= 1; signals++; drivers.push("mood trending down"); }
  else if (input.moodTrend === "improving") { score += 1; signals++; positives.push("mood trending up"); }

  // ── Load drags (the quantitative side) ──
  // ACWR danger zone (>1.5) is the classic acute-spike injury-risk band;
  // 1.3–1.5 is elevated; 0.8–1.3 is the "sweet spot".
  if (input.acwr != null) {
    if (input.acwr > 1.5) { score -= 2; signals++; drivers.push(`load spiking (ACWR ${input.acwr.toFixed(2)})`); }
    else if (input.acwr >= 1.3) { score -= 1; signals++; drivers.push(`load climbing (ACWR ${input.acwr.toFixed(2)})`); }
    else if (input.acwr >= 0.8) { score += 1; signals++; positives.push("load in a healthy range"); }
  }
  // High Foster monotony (>2.0) = same stress every day, a distinct
  // injury/illness risk even when volume looks fine.
  if (input.monotony7d != null && input.monotony7d > 2.0) {
    score -= 1; signals++; drivers.push(`training monotony high (${input.monotony7d.toFixed(1)})`);
  }

  // No signal at all → no opinion.
  if (signals === 0) return null;

  // ── Map score → verdict ──
  // Asymmetric on purpose: it takes real evidence to say "push", and we lean
  // conservative toward "pull" because the cost of missing accumulated fatigue
  // (injury) is higher than the cost of an easy day.
  let verdict: ReadinessVerdict;
  if (score <= -3) verdict = "pull";
  else if (score >= 2) verdict = "push";
  else verdict = "hold";

  const confidence: Readiness["confidence"] = signals >= 3 ? "high" : signals === 2 ? "medium" : "low";

  const read = buildReadLine(verdict, drivers, positives);

  return { verdict, score, confidence, drivers: verdict === "push" ? positives : drivers, read };
}

/** One feeling-first observation line. Never a directive. */
function buildReadLine(verdict: ReadinessVerdict, drivers: string[], positives: string[]): string {
  const list = (xs: string[]) => xs.slice(0, 2).join(" and ");
  switch (verdict) {
    case "pull":
      return drivers.length > 0
        ? `The body's been asking for more than it's giving back — ${list(drivers)}.`
        : "The body's showing signs it's carrying some fatigue right now.";
    case "push":
      return positives.length > 0
        ? `Everything's pointing the right way — ${list(positives)}.`
        : "The signals look good — the body seems to be absorbing the work.";
    case "hold":
      return "A mixed picture right now — some good signs, some that say don't force it.";
  }
}

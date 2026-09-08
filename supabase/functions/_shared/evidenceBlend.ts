// ============================================================================
// evidenceBlend.ts — fitness as a recency-weighted blend of races and training.
//
// Everything the athlete has done is evidence about their fitness. A race is
// evidence. A hard session is evidence. Each has a date. Recent evidence
// counts more than old evidence. That is the whole model.
//
//     fitness = Σ(estimate · weight) / Σ(weight)
//     weight  = kindWeight · 0.5 ^ (ageDays / halfLife)
//
// A race gets more weight than a session because it is a measurement — the
// athlete emptied it at a known distance — where a session is an inference
// from work that was prescribed rather than exhausted. That is the only
// distinction the model makes between them. There is no anchor, no decay
// curve applied to one privileged race, no displacement cap, no validation
// band. Just evidence, aged.
//
// THE CASE THIS IS BUILT AGAINST.
//
//     Jan   races 5K in 16:00
//     8 weeks of training, consistently at a 15:35 level
//     Mar   races 5K in 15:35
//
// By March the model should read 15:35 before that race is run — sixteen
// sessions, all newer than January and all saying the same thing, outweigh
// one two-month-old result. The previous rule read 15:55: it moved five
// seconds across eight weeks, because the race was an anchor rather than
// evidence and training was capped at a fixed share of it.
//
// It works with no races at all (training is all the evidence there is), and
// with no training at all (a race is all the evidence there is). Neither is a
// special case in the code.
//
// Pure functions, no I/O. Tests: evidenceBlend.test.ts.
// ============================================================================

/**
 * How fast evidence loses influence. Three weeks: a session from last week
 * counts roughly twice one from a month ago. Matches the fitness curve's own
 * time constant, so the two are not arguing about how fast fitness moves.
 */
export const DEFAULT_HALF_LIFE_DAYS = 21;

/**
 * A race is worth this many sessions of the same age. A race is a maximal
 * effort at a known distance; a session is prescribed work that the model has
 * to interpret. Three keeps a fresh race dominant over the handful of
 * sessions around it, without letting it outvote a whole block.
 */
export const RACE_WEIGHT = 3;
export const SESSION_WEIGHT = 1;

export interface Evidence {
  /** What this performance says the athlete's 10K pace is (sec/mile). */
  tenKPace: number;
  /** "yyyy-MM-dd". */
  date: string;
  kind: "race" | "session";
  /**
   * Optional scale on this item's weight, 0..1 — for a session with thin work
   * behind it, or a race run in doubtful conditions. Defaults to 1.
   */
  quality?: number;
}

export interface BlendResult {
  /** The blended 10K pace (sec/mile), or null when there is no evidence. */
  tenKPace: number | null;
  /** Share of the total weight that came from races, 0..1. */
  raceShare: number;
  raceCount: number;
  sessionCount: number;
  why: string;
}

const dayOf = (iso: string): number | null => {
  const t = Date.parse(`${iso.slice(0, 10)}T00:00:00Z`);
  return Number.isFinite(t) ? t / 86_400_000 : null;
};

/** Blend every piece of evidence by recency. */
export function blendEvidence(
  evidence: readonly Evidence[],
  now: Date,
  halfLifeDays: number = DEFAULT_HALF_LIFE_DAYS,
): BlendResult {
  const nowDay = now.getTime() / 86_400_000;
  let sum = 0, wsum = 0, raceW = 0, races = 0, sessions = 0;

  for (const e of evidence) {
    const day = dayOf(e.date);
    if (day === null || !(e.tenKPace > 0)) continue;
    const ageDays = Math.max(0, nowDay - day);
    const kindW = e.kind === "race" ? RACE_WEIGHT : SESSION_WEIGHT;
    const w = kindW * Math.pow(0.5, ageDays / Math.max(halfLifeDays, 1)) *
      Math.min(Math.max(e.quality ?? 1, 0), 1);
    if (!(w > 0)) continue;
    sum += e.tenKPace * w;
    wsum += w;
    if (e.kind === "race") { raceW += w; races++; } else sessions++;
  }

  if (wsum <= 0) {
    return { tenKPace: null, raceShare: 0, raceCount: 0, sessionCount: 0, why: "no evidence" };
  }
  const raceShare = raceW / wsum;
  return {
    tenKPace: sum / wsum,
    raceShare,
    raceCount: races,
    sessionCount: sessions,
    why: `${races} race${races === 1 ? "" : "s"} + ${sessions} session${
      sessions === 1 ? "" : "s"
    }, ${Math.round(raceShare * 100)}% of the weight from racing`,
  };
}

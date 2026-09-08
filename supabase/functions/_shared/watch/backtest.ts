/**
 * Backtesting a watch against the athlete's own history.
 *
 * "Would have spoken up 3 times, out of 19 easy runs."
 *
 * This is the screen the feature lives or dies on. A threshold picked in the
 * abstract is a guess; a threshold picked after seeing what it would have
 * caught over eight weeks is a decision. It also removes the need for anyone
 * to hand over "correct" default numbers up front — the defaults only have to
 * be close enough to argue with.
 *
 * Method: walk the window a day at a time, rebuild the context as it stood on
 * that day, and evaluate. No look-ahead — a day's evaluation sees only what
 * had happened by then.
 *
 * Honesty about fidelity: some of `athlete_state` is precomputed aggregate
 * (`zone_pct_7d`, `load_distribution`) and cannot be recomputed for a past
 * date from the state object alone. Row-level history — mood labels, easy-run
 * paces — replays exactly. A backtest that leans on an aggregate reports
 * `fidelity: "partial"` and names what it couldn't reconstruct, rather than
 * quietly presenting a today-shaped number as history.
 */

import { buildWatchContext, type WatchStateInput } from "./context.ts";
import type { Watch, WatchFinding, WatchSeverity } from "./types.ts";

const DAY_MS = 86_400_000;

export interface BacktestFire {
  /** ISO date the watch would have spoken. */
  date: string;
  severity: WatchSeverity;
  headline: string;
  evidence: string[];
}

export type BacktestFidelity = "full" | "partial";

export interface BacktestResult {
  watch_id: string;
  /** Days evaluated. */
  window_days: number;
  from: string;
  to: string;
  fires: BacktestFire[];
  /** Fires after the cooldown was applied — the number a person should see. */
  fired_count: number;
  /** Fires before cooldown. The gap between the two is what cooldown bought. */
  raw_fired_count: number;
  /** Days the watch could not run at all (a gap, not an all-clear). */
  blind_days: number;
  fidelity: BacktestFidelity;
  /** Named reasons the replay is imperfect. Empty when fidelity is "full". */
  caveats: string[];
  /** Plain-English summary, ready to render. */
  summary: string;
}

export interface BacktestOptions {
  /** How far back to replay. */
  windowDays?: number;
  /** Minimum days between fires. This is the noise control — without it a
   *  standing condition fires every single day it stays true. */
  cooldownDays?: number;
  /** End of the replay window. Defaults to `now`. */
  to?: Date;
}

const DEFAULT_WINDOW = 56; // eight weeks, the prototype's frame
const DEFAULT_COOLDOWN = 7;

function iso(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * The state as it stood on `asOf` — nothing dated after it survives.
 *
 * Aggregates are dropped rather than carried forward. Carrying today's
 * `zone_pct_7d` into a replay of six weeks ago would make the backtest agree
 * with itself for the wrong reason.
 */
export function stateAsOf(
  state: WatchStateInput,
  asOf: Date,
): { state: WatchStateInput; caveats: string[] } {
  const cutoff = asOf.getTime();
  const caveats: string[] = [];

  const onOrBefore = (d: string | null | undefined): boolean => {
    if (!d) return false;
    const t = Date.parse(d.length === 10 ? `${d}T00:00:00Z` : d);
    return !Number.isNaN(t) && t <= cutoff;
  };

  if (state.load_distribution?.zone_pct_7d || state.load_distribution?.zone_pct_28d) {
    caveats.push(
      "Time-in-zone shares are stored as a current snapshot, so the aggregate read is skipped for past days — only per-run checks replay.",
    );
  }

  // Niggle rows are pre-aggregated: `occurrences` counts mentions up to today,
  // not up to `asOf`. Rows that hadn't been seen yet are dropped, and the
  // count is left alone with the inaccuracy declared.
  const niggles = state.niggle_recurrence?.filter((n) => onOrBefore(n.first_seen)) ?? null;
  if (niggles && niggles.length > 0) {
    caveats.push(
      "Niggle mention counts are aggregated to today, so recurrence may read higher on past days than it did at the time.",
    );
  }

  return {
    state: {
      ...state,
      recent_workouts: state.recent_workouts?.filter((w) => onOrBefore(w.date)) ?? null,
      // Aggregates deliberately dropped — see above.
      load_distribution: null,
      niggle_recurrence: niggles,
      // Nothing scheduled ahead of a past date is knowable from state alone.
      upcoming_workouts: null,
    },
    caveats,
  };
}

/**
 * Replay one watch across the window.
 *
 * Cooldown is applied here rather than inside the watch: a watch answers
 * "is this true today," and how often that's worth saying out loud is a
 * separate, tunable decision.
 */
export function backtestWatch(
  watch: Watch,
  state: WatchStateInput,
  opts: BacktestOptions = {},
): BacktestResult {
  const windowDays = opts.windowDays ?? DEFAULT_WINDOW;
  const cooldownDays = opts.cooldownDays ?? DEFAULT_COOLDOWN;
  const to = opts.to ?? new Date();
  const from = new Date(to.getTime() - windowDays * DAY_MS);

  const fires: BacktestFire[] = [];
  const caveats = new Set<string>();
  let rawFires = 0;
  let blindDays = 0;
  let lastFireMs: number | null = null;

  for (let i = 0; i <= windowDays; i++) {
    const day = new Date(from.getTime() + i * DAY_MS);
    const sliced = stateAsOf(state, day);
    sliced.caveats.forEach((c) => caveats.add(c));

    let result;
    try {
      result = watch.evaluate(buildWatchContext(sliced.state, day));
    } catch (_e) {
      blindDays++;
      continue;
    }

    if (result.kind === "gap") {
      blindDays++;
      continue;
    }
    if (result.kind !== "finding") continue;

    rawFires++;

    // Cooldown: a condition that stays true shouldn't keep talking.
    if (lastFireMs !== null && day.getTime() - lastFireMs < cooldownDays * DAY_MS) {
      continue;
    }
    lastFireMs = day.getTime();

    const f: WatchFinding = result.finding;
    fires.push({
      date: iso(day),
      severity: f.severity,
      headline: f.headline,
      evidence: f.evidence,
    });
  }

  const fidelity: BacktestFidelity = caveats.size === 0 ? "full" : "partial";

  return {
    watch_id: watch.id,
    window_days: windowDays,
    from: iso(from),
    to: iso(to),
    fires,
    fired_count: fires.length,
    raw_fired_count: rawFires,
    blind_days: blindDays,
    fidelity,
    caveats: [...caveats],
    summary: summarize(fires.length, rawFires, blindDays, windowDays, cooldownDays),
  };
}

/**
 * The sentence a person reads before saving.
 *
 * Deliberately blunt about the two failure modes: a watch that never fires is
 * decoration, and a watch that fires constantly gets muted in week two. Both
 * are more useful to say than a bare count.
 */
export function summarize(
  fired: number,
  raw: number,
  blindDays: number,
  windowDays: number,
  cooldownDays: number,
): string {
  const weeks = Math.round(windowDays / 7);
  if (blindDays >= windowDays) {
    return `Couldn't run this against the last ${weeks} weeks — there isn't enough history behind it yet.`;
  }

  const base = fired === 0
    ? `Wouldn't have said anything in the last ${weeks} weeks.`
    : `Would have spoken up ${fired} time${fired === 1 ? "" : "s"} in the last ${weeks} weeks.`;

  const parts = [base];

  if (fired === 0) {
    parts.push("Either nothing's been wrong, or the threshold is set too far out to catch it.");
  } else if (fired >= weeks) {
    // Roughly weekly or more often.
    parts.push(
      "That's often enough that it'll start reading as background noise — worth loosening the threshold before saving.",
    );
  }

  if (raw > fired) {
    const held = raw - fired;
    parts.push(
      `The ${cooldownDays}-day cooldown held back ${held} repeat${held === 1 ? "" : "s"} of the same thing.`,
    );
  }

  if (blindDays > windowDays / 2) {
    parts.push(
      `It couldn't see anything on ${blindDays} of those days, so treat the count as a floor.`,
    );
  }

  return parts.join(" ");
}

/** Backtest several watches at once — the coach's roster view, per athlete. */
export function backtestAll(
  watches: readonly Watch[],
  state: WatchStateInput,
  opts: BacktestOptions = {},
): BacktestResult[] {
  return watches.map((w) => backtestWatch(w, state, opts));
}

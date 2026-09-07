/**
 * Watch — "Is that niggle still talking?"
 *
 * Rio: "if there's a flare up, let's take a day off."
 *
 * The cheapest insurance in the sport, and the one a coach will always take
 * given the information. The hard part is never the decision — it's noticing
 * the third mention of the same calf in a month when each one individually
 * sounded like nothing.
 *
 * Scope discipline (hard rule #2): this reports mentions and recurrence. It
 * never names a condition, never routes to medical care, never says stop
 * training. A day off is a training adjustment; anything past that is a
 * person's call, which is what `defer_to_human` carries.
 */

import {
  clear,
  daysBetween,
  finding,
  gap,
  type Watch,
  type WatchContext,
  type WatchResult,
} from "./types.ts";

const WATCH_ID = "niggle_flare";

/** A mention this recent is live, not history. */
const FLARE_WINDOW_DAYS = 5;

/** Repeat mentions of one area inside this window is a pattern, not bad luck. */
const RECURRENCE_WINDOW_DAYS = 42;
const RECURRENCE_COUNT = 3;

/** Quality inside this many days is close enough that a flare should hold it. */
const QUALITY_PROXIMITY_DAYS = 3;

function label(n: { body_area: string; side: "left" | "right" | null }): string {
  return n.side ? `${n.side} ${n.body_area}` : n.body_area;
}

export const niggleFlare: Watch = {
  id: WATCH_ID,
  domain: "niggles",
  question: "Is anything still talking, and is it getting louder?",
  reads: ["niggles (athlete_state.niggle_recurrence)", "upcomingQualityWithinDays"],

  evaluate(ctx: WatchContext): WatchResult {
    if (ctx.niggles === undefined || ctx.niggles === null) {
      return gap(
        WATCH_ID,
        "niggles",
        "No body-mention history available — nothing to watch against.",
      );
    }

    const active = ctx.niggles.filter((n) => n.status === "active");
    if (active.length === 0) return clear();

    // Live now, versus merely unresolved.
    const flaring = active
      .filter((n) => daysBetween(n.last_seen, ctx.now) <= FLARE_WINDOW_DAYS)
      .sort((a, b) => daysBetween(b.last_seen, ctx.now) - daysBetween(a.last_seen, ctx.now));

    // Recurring, whether or not it's live this week.
    const recurring = active.filter(
      (n) =>
        n.occurrences >= RECURRENCE_COUNT &&
        daysBetween(n.first_seen, ctx.now) <= RECURRENCE_WINDOW_DAYS,
    );

    if (flaring.length === 0 && recurring.length === 0) return clear();

    const qualitySoon = typeof ctx.upcomingQualityWithinDays === "number" &&
      ctx.upcomingQualityWithinDays <= QUALITY_PROXIMITY_DAYS;

    const primary = flaring[0] ?? recurring[0];
    const daysAgo = daysBetween(primary.last_seen, ctx.now);

    const evidence: string[] = [
      `${label(primary)} — ${primary.occurrences} mention${primary.occurrences === 1 ? "" : "s"}, last ${daysAgo === 0 ? "today" : `${daysAgo}d ago`}`,
      `worst reported: ${primary.worst_severity}`,
    ];
    if (recurring.length > 0) {
      evidence.push(
        `${recurring.length} area${recurring.length === 1 ? "" : "s"} recurring inside ${RECURRENCE_WINDOW_DAYS} days`,
      );
    }
    if (qualitySoon) {
      evidence.push(`quality session in ${ctx.upcomingQualityWithinDays}d`);
    }

    // Recurrence is the louder signal. One live mention is a day off; the
    // same area three times in six weeks is a conversation.
    const isRecurring = recurring.some((n) => n.body_area === primary.body_area);
    const severity = isRecurring ? "high" : flaring.length > 0 ? "med" : "low";

    const detail = isRecurring
      ? `${label(primary)} has come up ${primary.occurrences} times since ` +
        `${primary.first_seen}, most recently ${daysAgo === 0 ? "today" : `${daysAgo} days ago`}. ` +
        `Individually each mention read as minor — together they're a pattern, and the ` +
        `pattern is the part worth your attention.` +
        (qualitySoon
          ? ` There's quality on the calendar in ${ctx.upcomingQualityWithinDays} days.`
          : "")
      : `${label(primary)} came up ${daysAgo === 0 ? "today" : `${daysAgo} days ago`} ` +
        `and hasn't been cleared since.` +
        (qualitySoon
          ? ` With quality ${ctx.upcomingQualityWithinDays} days out, a day off now is the cheap version of this.`
          : ` A day off now is the cheap version of this.`);

    return finding({
      watch_id: WATCH_ID,
      domain: "niggles",
      severity,
      headline: isRecurring
        ? `${label(primary)} keeps coming back.`
        : `${label(primary)} is still talking.`,
      detail,
      evidence,
      // Take the day. Hold quality when it's close enough to matter.
      suggested: qualitySoon ? "pause_quality" : "insert_rest",
      confidence: primary.occurrences >= 2 ? "high" : "medium",
      // Recurrence is where a person needs to look; a single mention is a
      // training adjustment the coach can wave through.
      defer_to_human: isRecurring,
    });
  },
};

/**
 * Watch — "Is she running her easy days easy?"
 *
 * The most common way a training block quietly rots. Easy days creep toward
 * moderate, the athlete feels fine for three weeks, and then the quality
 * sessions stop improving because there's no recovery underneath them. It is
 * invisible in weekly mileage and obvious in time-in-zone.
 *
 * Nothing watched this before. `zone_pct_7d` has been computed in
 * `athlete-state.ts` and read by no one.
 *
 * Two reads, because they fail differently:
 *   • Per-run — individual easy days run faster than the athlete's own easy
 *     band. Catches the habitual 30-seconds-too-quick shuffle.
 *   • Aggregate — the share of weekly time actually spent easy. Catches a
 *     week that's nominally easy but has no genuinely easy minutes in it.
 *
 * Paces come from PaceEngine (the athlete's own data) or this watch declares
 * a gap. It never falls back to a default easy pace.
 */

import {
  clear,
  daysBetween,
  finding,
  fmtPace,
  gap,
  type Watch,
  type WatchContext,
  type WatchResult,
} from "./types.ts";

const WATCH_ID = "easy_day_discipline";

/**
 * How much of the week's time should sit in the easy zone.
 *
 * PLACEHOLDER, not doctrine. This is a starting number pending Rio's own —
 * intensity distribution is exactly the kind of thing that belongs in a
 * coach's authored principles, not baked into an evaluator. Deliberately not
 * sourced from any published methodology.
 */
const EASY_SHARE_FLOOR = 0.70;

/** Enough easy runs in the window for the per-run read to mean anything. */
const MIN_EASY_RUNS = 3;

/** How far back the per-run read looks. */
const WINDOW_DAYS = 14;

/** Faster than the easy band by more than this is drift, not noise. */
const DRIFT_TOLERANCE_SEC = 10;

/**
 * Below this, an "easy" row isn't an easy day.
 *
 * Real data, one athlete's 75 days: 25 of 87 easy/recovery rows were under
 * three miles, and they are warmup, cooldown and strides logged as separate
 * workouts around interval sessions — 19:24/mi walking recoveries at one end,
 * a 1-mile rep at 5:19/mi at the other. Counting them as easy days makes the
 * watch report on the athlete's warmup routine.
 */
const MIN_EASY_DISTANCE_MI = 3;

/**
 * Fallback mislabel margin, used only when the athlete has no moderate band.
 *
 * The preferred boundary is structural: a run typed easy that comes in at
 * steady pace or quicker is a different session wearing an easy label. That
 * line is drawn from the athlete's own zones (see `moderateBand`), because a
 * fixed seconds-per-mile margin is wrong for somebody eventually. The real
 * case that proved it: a 7-mile run typed `easy` at 5:42/mi against a 7:03
 * band — 81s/mi fast, which a 90s margin would have waved through, but which
 * sits well inside this athlete's steady zone.
 */
const MISLABEL_FALLBACK_MARGIN_SEC = 60;

export const easyDayDiscipline: Watch = {
  id: WATCH_ID,
  domain: "pace",
  question: "Is she running her easy days easy?",
  reads: ["easyBand (PaceEngine)", "easyRuns", "zonePct7d"],

  evaluate(ctx: WatchContext): WatchResult {
    const band = ctx.easyBand;
    const inWindow = (ctx.easyRuns ?? []).filter(
      (r) => r.paceSecPerMile !== null && daysBetween(r.date, ctx.now) <= WINDOW_DAYS,
    );
    // Fragments are not easy days. A row with no distance is kept — absence of
    // the field shouldn't silently drop a real run.
    const runs = inWindow.filter(
      (r) => r.distanceMiles == null || r.distanceMiles >= MIN_EASY_DISTANCE_MI,
    );

    // ── Aggregate read: does the week contain any genuinely easy time? ──
    const share = ctx.zonePct7d?.easy;
    const aggregateOff = typeof share === "number" && share < EASY_SHARE_FLOOR * 100;

    // ── Per-run read: needs the athlete's own band. ──
    if (!band) {
      // Without a band the per-run read is impossible. If the aggregate still
      // says something, say it; otherwise be explicit that we're blind.
      if (aggregateOff) {
        return finding({
          watch_id: WATCH_ID,
          domain: "pace",
          severity: "low",
          headline: "Not much of this week was actually easy.",
          detail:
            `Only ${Math.round(share!)}% of the last 7 days' training time sat in the easy zone. ` +
            `Without an established easy band for this athlete I can't say which runs drifted — ` +
            `but the week as a whole is short on genuinely easy time.`,
          evidence: [`easy share 7d: ${Math.round(share!)}%`],
          suggested: null,
          confidence: "low",
          defer_to_human: false,
        });
      }
      return gap(
        WATCH_ID,
        "pace",
        "No easy-pace band established yet — needs more logged runs before easy-day discipline can be read.",
      );
    }

    if (runs.length < MIN_EASY_RUNS) {
      return gap(
        WATCH_ID,
        "pace",
        `Only ${runs.length} easy run${runs.length === 1 ? "" : "s"} of ${MIN_EASY_DISTANCE_MI}+ miles in the last ${WINDOW_DAYS} days — not enough to read a pattern.`,
      );
    }

    // Faster than the band's fast end = fewer seconds per mile. Anything
    // beyond the mislabel margin is excluded from the drift read entirely —
    // it distorts the average and it isn't the thing being watched.
    // Steady pace or quicker = not an easy day, whatever the label says.
    const mislabelCutoff = ctx.moderateBand?.paceFast ??
      band.paceFast - MISLABEL_FALLBACK_MARGIN_SEC;
    const mislabelled = runs.filter(
      (r) => (r.paceSecPerMile as number) < mislabelCutoff,
    );
    const genuine = runs.filter((r) => !mislabelled.includes(r));
    const tooHard = genuine.filter(
      (r) => (r.paceSecPerMile as number) < band.paceFast - DRIFT_TOLERANCE_SEC,
    );
    const ratio = genuine.length > 0 ? tooHard.length / genuine.length : 0;

    if (tooHard.length === 0 && !aggregateOff) {
      // Nothing wrong with the running — but if rows are typed easy that
      // plainly aren't, say so. It's a labelling problem rather than a
      // coaching one, and it quietly corrupts every pace read downstream, so
      // swallowing it would be the worse silence.
      if (mislabelled.length > 0) {
        return finding({
          watch_id: WATCH_ID,
          domain: "pace",
          severity: "info",
          headline: "Some runs are filed as easy that aren't.",
          detail:
            `${mislabelled.length} run${mislabelled.length === 1 ? "" : "s"} in the last ${WINDOW_DAYS} days ` +
            `${mislabelled.length === 1 ? "is" : "are"} typed easy but came in at ` +
            `${fmtPace(mislabelCutoff)}/mi or quicker — steady pace or faster for this athlete. ` +
            `The easy running itself looks ` +
            `fine — this is a labelling problem, and it skews every pace read that trusts the type.`,
          evidence: [
            `easy band: ${fmtPace(band.paceFast)}–${fmtPace(band.paceSlow)}/mi`,
            ...mislabelled.slice(0, 3).map((r) =>
              `${r.date}: ${fmtPace(r.paceSecPerMile as number)}/mi typed ${r.workoutType}`
            ),
          ],
          suggested: null,
          confidence: "high",
          defer_to_human: false,
        });
      }
      return clear();
    }

    // How far over, on the runs that drifted — the number a coach wants.
    const avgOver = tooHard.length > 0
      ? tooHard.reduce((s, r) => s + (band.paceFast - (r.paceSecPerMile as number)), 0) /
        tooHard.length
      : 0;

    const severity = ratio >= 0.5 || (aggregateOff && ratio >= 0.34) ? "med" : "low";

    const evidence: string[] = [
      `easy band: ${fmtPace(band.paceFast)}–${fmtPace(band.paceSlow)}/mi`,
      `${tooHard.length} of ${genuine.length} easy runs faster than the band (last ${WINDOW_DAYS}d)`,
    ];
    if (avgOver > 0) {
      evidence.push(`average of ${Math.round(avgOver)}s/mi too quick on those runs`);
    }
    if (typeof share === "number") {
      evidence.push(`easy share 7d: ${Math.round(share)}%`);
    }
    if (mislabelled.length > 0) {
      // Not folded into the finding — reported so the mislabel is visible
      // rather than quietly distorting the average.
      evidence.push(
        `${mislabelled.length} run${mislabelled.length === 1 ? "" : "s"} typed easy but run far too fast to be one — likely mislabelled`,
      );
    }

    const detail = tooHard.length > 0
      ? `${tooHard.length} of the last ${genuine.length} easy runs came in faster than ${fmtPace(band.paceFast)}/mi` +
        (avgOver > 0 ? `, by an average of ${Math.round(avgOver)}s/mi` : "") +
        `. That's the drift that costs quality sessions later, not now — the easy days stop ` +
        `being recovery and the hard days lose their edge.` +
        (aggregateOff
          ? ` Only ${Math.round(share!)}% of this week's time was genuinely easy.`
          : "")
      : `Only ${Math.round(share!)}% of the last 7 days' training time sat in the easy zone, ` +
        `even though the individual runs held their band.`;

    return finding({
      watch_id: WATCH_ID,
      domain: "pace",
      severity,
      headline: "Easy days are drifting quick.",
      detail,
      evidence,
      // Not a plan edit. The paces aren't wrong — the running is. This one is
      // a conversation, and the five-move vocabulary has no verb for it.
      suggested: null,
      confidence: runs.length >= 5 ? "high" : "medium",
      defer_to_human: false,
    });
  },
};

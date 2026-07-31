/**
 * Group A detectors — qual × quant fusions that ship today.
 *
 * All three run on the SAME `TrendsWeekOut[]` the chart renders (plus the
 * raw body-mention rows for A1's grouping). No streams, no biometrics, no
 * new capture. Each returns exactly one `TrendCard` — `active` (pattern
 * fired), `quiet` (gate met, no pattern — the honest sentence), or
 * `hidden` (below the data gate; dropped before responding).
 *
 * Copy variants: each detector carries at least the positive, the
 * watchful, and the no-pattern sentence, written up front (plan §7).
 *
 * Detection, not diagnosis: these observe and stop — no "rest", no cause
 * claims. The BANNED_TERMS lint in detectorsA.test.ts holds the line.
 */

import {
  type DetectCtx,
  type TrendCard,
  type Evidence,
  dayMs,
  fmtPace,
  hiddenCard,
  median,
  slope,
} from "./contract.ts";
import type { TrendsWeekOut } from "../trends-timeline/timeline.ts";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const WEEKDAY = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
];

/** Weeks that actually carried training (miles > 0). */
function loggedWeeks(weeks: TrendsWeekOut[]): TrendsWeekOut[] {
  return weeks.filter((w) => w.miles > 0);
}

/** Index of the week whose Mon–Sun window contains `dateStr`, or -1. */
function weekIndexOf(weeks: TrendsWeekOut[], dateStr: string): number {
  const t = dayMs(dateStr);
  for (let i = 0; i < weeks.length; i++) {
    const s = dayMs(weeks[i].week_start);
    if (t >= s && t < s + WEEK_MS) return i;
  }
  return -1;
}

// ─── A1 · The body talks back to the load ──────────────────────────────
// Injury mentions × volume. Fires when 2+ mentions of the SAME body_area
// land in high-load weeks (top third of the window by miles).

export function detectA1(ctx: DetectCtx): TrendCard {
  const { weeks, mentions } = ctx;
  const logged = loggedWeeks(weeks);

  // Gate: ≥6 logged weeks AND ≥2 body mentions.
  if (logged.length < 6 || mentions.length < 2) return hiddenCard("A1", "A");

  // High-load week = miles in the top third of the window, OR ≥15% above the
  // trailing 4-week average (per the A1 spec). The trailing arm matters:
  // a 57-mile week may sit below the strict tercile cut yet still be a clear
  // spike over the weeks around it — and that's where a niggle "landing in a
  // big week" really lives. Precomputed once, indexed by week position.
  const milesDesc = logged.map((w) => w.miles).sort((a, b) => b - a);
  const tercileIdx = Math.max(0, Math.ceil(milesDesc.length / 3) - 1);
  const tercileThreshold = milesDesc[tercileIdx];

  const highLoad: boolean[] = weeks.map((w, i) => {
    if (w.miles <= 0) return false;
    if (w.miles >= tercileThreshold) return true;
    const prior = weeks
      .slice(Math.max(0, i - 4), i)
      .filter((x) => x.miles > 0)
      .map((x) => x.miles);
    if (prior.length === 0) return false;
    const avg = prior.reduce((a, b) => a + b, 0) / prior.length;
    return avg > 0 && w.miles >= 1.15 * avg;
  });

  // Assign each mention to its week; group by body_area.
  interface AreaHit {
    area: string;
    weekIdxs: Set<number>;
    highLoadWeekIdxs: Set<number>;
    count: number;
  }
  const byArea = new Map<string, AreaHit>();
  for (const m of mentions) {
    const wi = weekIndexOf(weeks, m.mentioned_at);
    if (wi < 0) continue;
    const area = m.body_area.toLowerCase();
    const hit = byArea.get(area) ??
      { area, weekIdxs: new Set<number>(), highLoadWeekIdxs: new Set<number>(), count: 0 };
    hit.weekIdxs.add(wi);
    hit.count += 1;
    if (highLoad[wi]) hit.highLoadWeekIdxs.add(wi);
    byArea.set(area, hit);
  }

  // A body_area is "load-shaped" when it has ≥2 mentions AND every week it
  // appears in is a high-load week (nothing in the down weeks).
  let fired: AreaHit | null = null;
  for (const hit of byArea.values()) {
    if (hit.count >= 2 && hit.highLoadWeekIdxs.size === hit.weekIdxs.size && hit.weekIdxs.size >= 2) {
      if (!fired || hit.count > fired.count) fired = hit;
    }
  }

  if (fired) {
    const evWeeks = [...fired.highLoadWeekIdxs].sort((a, b) => a - b).map((i) => weeks[i]);
    const milesList = evWeeks.map((w) => Math.round(w.miles));
    const evidence: Evidence[] = evWeeks.map((w) => ({
      week: w.date_label,
      value: Math.round(w.miles),
      label: fired!.area,
    }));
    // Full series: weekly miles across the window, with the niggle weeks
    // ringed — the chart tells the A1 story (mentions clustering in the
    // biggest weeks) at a glance.
    const series = {
      points: weeks.map((w) => Math.round(w.miles)),
      labels: weeks.map((w) => w.date_label),
      unit: "mi",
      polarity: "neutral" as const,
      markerIdx: [...fired.weekIdxs].sort((a, b) => a - b),
    };
    return {
      id: "A1",
      group: "A",
      status: "active",
      headline: "The body talks back to the load",
      body:
        `Your ${fired.area} mentions all land in your biggest weeks — ` +
        `${milesList.join(", ")} ${milesList.length === 1 ? "mile" : "miles"}. ` +
        `Nothing in the down weeks. The pattern is load-shaped, in your own words.`,
      evidence,
      series,
      confidence: fired.count >= 3 ? "high" : "medium",
    };
  }

  // Honest no-pattern state: mentions exist but scatter across low and high
  // weeks. That's reassuring, and it's true.
  return {
    id: "A1",
    group: "A",
    status: "quiet",
    headline: "Your niggles don't track your mileage",
    body:
      "Body mentions land in your easy weeks about as often as your hard ones — " +
      "no load-shaped pattern here. Surfaced from your own words, never diagnosed.",
    evidence: [],
    confidence: "medium",
  };
}

// ─── A4 · Which day the body speaks up ─────────────────────────────────
// Niggles × weekday. The one pattern ONLY the calendar earns: a weekly
// series structurally can't see day-of-week (see trends-tab §4). Reads the
// daily substrate to answer where the mentions fell — same weekday, or on/
// after a hard session — and stops there. Co-occurrence, never mechanism.

export function detectA4(ctx: DetectCtx): TrendCard {
  const days = ctx.days ?? [];
  const { mentions } = ctx;
  if (days.length === 0) return hiddenCard("A4", "A"); // no daily substrate

  // Mentions inside the daily window.
  const firstMs = dayMs(days[0].date);
  const lastMs = dayMs(days[days.length - 1].date);
  const inWin = mentions.filter((m) => {
    const t = dayMs(m.mentioned_at);
    return t >= firstMs && t <= lastMs;
  });
  // One mention isn't a rhythm — the gate is the same ≥2 A1 uses.
  if (inWin.length < 2) return hiddenCard("A4", "A");

  // Days that were a hard session (key or long) — the anchor a niggle might
  // trail. Long counts: the long run is a load day a niggle can follow.
  const hardDays = new Set<number>();
  for (const d of days) {
    if (d.type === "key" || d.type === "long") hardDays.add(dayMs(d.date));
  }

  const dows = inWin.map((m) => new Date(dayMs(m.mentioned_at)).getUTCDay());
  const sameWeekday = dows.every((d) => d === dows[0]);
  const onOrAfterHard = inWin.filter((m) => {
    const t = dayMs(m.mentioned_at);
    return hardDays.has(t) || hardDays.has(t - DAY_MS);
  }).length;

  const n = inWin.length;
  const evidence: Evidence[] = inWin.map((m) => ({
    week: `${m.body_area}${m.side ? ` (${m.side})` : ""}`,
    value: new Date(dayMs(m.mentioned_at)).getUTCDay(),
    label: WEEKDAY[new Date(dayMs(m.mentioned_at)).getUTCDay()],
  }));

  // Strongest first: all on one weekday.
  if (sameWeekday) {
    return {
      id: "A4",
      group: "A",
      status: "active",
      headline: "The body speaks up on the same day",
      body:
        `All ${n} mentions land on a ${WEEKDAY[dows[0]]}. ` +
        `That's where they fell, not what they mean.`,
      evidence,
      confidence: n >= 3 ? "high" : "medium",
    };
  }

  // Every mention on or the morning after a hard session.
  if (onOrAfterHard === n) {
    return {
      id: "A4",
      group: "A",
      status: "active",
      headline: "The niggles follow your hard days",
      body:
        `All ${n} land on a key session or the morning after one. ` +
        `Where they fell, never what they mean.`,
      evidence,
      confidence: n >= 3 ? "high" : "medium",
    };
  }

  // Partial link — honest and mixed.
  if (onOrAfterHard >= 2) {
    return {
      id: "A4",
      group: "A",
      status: "quiet",
      headline: "Some land on your hard days",
      body:
        `${onOrAfterHard} of ${n} land on a key session or the morning after; ` +
        `the others don't. Too mixed to call a rhythm either way.`,
      evidence,
      confidence: "medium",
    };
  }

  // No shape — they scatter.
  return {
    id: "A4",
    group: "A",
    status: "quiet",
    headline: "No weekday rhythm to them",
    body:
      "The mentions scatter across the week — no day-of-week or key-session " +
      "pattern to them. Surfaced from your own words, never diagnosed.",
    evidence: [],
    confidence: "low",
  };
}

// ─── A2 · Felt harder than it measured ─────────────────────────────────
// Mood × load. Fires when 2+ consecutive weeks pair a not-elevated load
// with tired/struggling mood — the feeling and the number disagreeing in
// the fatigue direction.

const HEAVY_MOODS = new Set(["tired", "struggling"]);
const LIGHT_MOODS = new Set(["energized", "positive"]);

export function detectA2(ctx: DetectCtx): TrendCard {
  const weeks: TrendsWeekOut[] = ctx.weeks;
  const withMood = weeks.filter((w) => w.miles > 0 && w.mood);

  // Gate: ≥3 weeks carrying both load and a logged mood.
  if (withMood.length < 3) return hiddenCard("A2", "A");

  const med = median(loggedWeeks(weeks).map((w) => w.miles));

  // Walk the timeline; find the longest run of consecutive logged weeks
  // where load is at-or-below median AND mood reads heavy.
  let bestRun: TrendsWeekOut[] = [];
  let run: TrendsWeekOut[] = [];
  for (const w of weeks) {
    if (w.miles <= 0) continue; // skip empty weeks without breaking the run's meaning
    const heavyFeel = w.mood != null && HEAVY_MOODS.has(w.mood.toLowerCase());
    const modestLoad = w.miles <= med;
    if (heavyFeel && modestLoad) {
      run.push(w);
      if (run.length > bestRun.length) bestRun = [...run];
    } else {
      run = [];
    }
  }

  if (bestRun.length >= 2) {
    const evidence: Evidence[] = bestRun.map((w) => ({
      week: w.date_label,
      value: Math.round(w.miles),
      label: w.mood ?? "",
    }));
    // Full series: weekly miles across the window, with the tired-but-modest
    // weeks ringed — the run of markers on an unremarkable line is the point.
    const series = {
      points: weeks.map((w) => Math.round(w.miles)),
      labels: weeks.map((w) => w.date_label),
      unit: "mi",
      polarity: "neutral" as const,
      markerIdx: bestRun.map((w) => weeks.indexOf(w)).filter((i) => i >= 0),
    };
    return {
      id: "A2",
      group: "A",
      status: "active",
      headline: "Felt harder than it measured",
      body:
        `${bestRun.length} weeks running, the mileage was ordinary but the words read tired. ` +
        `The load isn't unusual — the recovery under it might be. Worth watching, not worth panicking.`,
      evidence,
      series,
      confidence: bestRun.length >= 3 ? "high" : "medium",
    };
  }

  // Quiet positive: the reverse — light words on the biggest weeks.
  const bigWeeks = loggedWeeks(weeks).filter((w) => w.miles > med);
  const bigLight = bigWeeks.filter((w) => w.mood && LIGHT_MOODS.has(w.mood.toLowerCase()));
  if (bigWeeks.length >= 2 && bigLight.length >= Math.ceil(bigWeeks.length / 2)) {
    return {
      id: "A2",
      group: "A",
      status: "quiet",
      headline: "The feeling and the number agree",
      body:
        "Your biggest weeks are also your warmest ones — the mood is keeping pace with the load. " +
        "Nothing pulling apart here.",
      evidence: [],
      confidence: "medium",
    };
  }

  return {
    id: "A2",
    group: "A",
    status: "quiet",
    headline: "The feeling and the number agree",
    body: "How the weeks felt and what they measured are moving together — no gap opening up.",
    evidence: [],
    confidence: "low",
  };
}

// ─── A3 · The engine is growing under the fatigue ──────────────────────
// Key-session pace × volume × mood. Pace falling (faster) + volume
// flat-or-up = fitness; then the mood splits the sentence.

export function detectA3(ctx: DetectCtx): TrendCard {
  const weeks = ctx.weeks;
  const paceWeeks = weeks.filter((w) => w.key_pace_sec != null);

  // Gate: ≥4 weeks with a key-session pace.
  if (paceWeeks.length < 4) return hiddenCard("A3", "A");

  const paces = paceWeeks.map((w) => w.key_pace_sec as number);
  const paceSlope = slope(paces); // sec/mi per step; negative = getting faster
  const milesSlope = slope(loggedWeeks(weeks).map((w) => w.miles));

  const firstPace = paces[0];
  const lastPace = paces[paces.length - 1];

  // Fitness = quality pace trending faster while volume holds or climbs.
  const gettingFaster = paceSlope != null && paceSlope < 0 && lastPace < firstPace;
  const volumeHolding = milesSlope != null && milesSlope >= -0.25;

  if (gettingFaster && volumeHolding) {
    const logged = loggedWeeks(weeks);
    const firstMiles = Math.round(logged[0]?.miles ?? 0);
    const lastMiles = Math.round(logged[logged.length - 1]?.miles ?? 0);

    // Split by modal mood across the window.
    const moods = weeks.filter((w) => w.mood).map((w) => (w.mood as string).toLowerCase());
    const tiredShare = moods.filter((m) => HEAVY_MOODS.has(m)).length / Math.max(1, moods.length);
    const paying = tiredShare >= 0.5;

    const evidence: Evidence[] = [
      { week: paceWeeks[0].date_label, value: firstPace, label: "key pace" },
      { week: paceWeeks[paceWeeks.length - 1].date_label, value: lastPace, label: "key pace" },
    ];
    // Full series: every key-session pace in the window. `down_good` so the
    // client can orient it (faster = lower = the win reads upward).
    const series = {
      points: paces,
      labels: paceWeeks.map((w) => w.date_label),
      unit: "sec",
      polarity: "down_good" as const,
    };

    const body = paying
      ? `Quality pace is coming down — ${fmtPace(firstPace)} to ${fmtPace(lastPace)} /mi — ` +
        `but so is the mood; the block reads tired. Fitness is being built, and it's being paid for too.`
      : `Quality pace dropped ${fmtPace(firstPace)} to ${fmtPace(lastPace)} /mi while weekly miles ` +
        `held around ${firstMiles}–${lastMiles}, and the mood stayed warm. You're not just surviving ` +
        `this block, you're absorbing it.`;

    return {
      id: "A3",
      group: "A",
      status: "active",
      headline: paying ? "The engine is growing — and it's costing you" : "The engine is growing under the load",
      body,
      evidence,
      series,
      confidence: paceWeeks.length >= 6 ? "high" : "medium",
    };
  }

  return {
    id: "A3",
    group: "A",
    status: "quiet",
    headline: "Quality pace is holding steady",
    body:
      "Your key-session pace isn't trending faster or slower across this window — the engine is " +
      "level, not climbing. That's a fine place to be mid-block.",
    evidence: [],
    confidence: "low",
  };
}

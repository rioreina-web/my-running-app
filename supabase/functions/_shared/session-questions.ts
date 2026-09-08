/**
 * The preloaded questions for the session ask box.
 *
 * Fifteen questions an athlete would actually ask about one run, gated by
 * what that run can support. The sheet shows five; the rest sit behind
 * "More questions".
 *
 * ── Why this lives on the server ──
 *
 * The list ships in the `ask` response, not in the app binary. Changing what
 * a long run asks versus a rep session is then a config edit and a deploy,
 * not an App Store release and a week of review. This file is the whole
 * reason `suggested` is a response field instead of a Swift array — protect
 * that, because the instinct to "just hardcode the five" removes the only
 * cheap lever this surface has.
 *
 * ── The rule every question here obeys ──
 *
 * A question is only offered when the session can answer it. Offering "did I
 * hold the pace across the reps?" on a steady 6-miler produces a paragraph
 * explaining there were no reps — which reads as the app not knowing what it
 * is looking at. `applies()` is that gate, and it is deliberately strict:
 * a shorter honest rail beats a longer one with two dead entries.
 *
 * ── What is NOT here ──
 *
 * Nothing that needs a chart to answer, and nothing whose honest answer is a
 * number the athlete just scrolled past. The box answers in prose. A question
 * that only works as a chart belongs on Trends, not here.
 */

// ── The shape of a session, as far as question selection cares ──────

export interface SessionShape {
  /** Normalized `training_logs.workout_type`. See `WorkoutLabel.normalize`. */
  workoutType: string | null;
  distanceMiles: number | null;
  /** Reps/intervals parsed out of the session, if any. */
  repCount: number;
  /** Laps or a stream exist — splits can be spoken about at all. */
  hasSplits: boolean;
  hasHeartRate: boolean;
  hasElevation: boolean;
  /** Weather was captured for this run. */
  hasConditions: boolean;
  /** A memo or cleaned note exists — she said something about it. */
  hasNotes: boolean;
  /** A prescribed workout is linked to this log. */
  hasPrescription: boolean;
  /** A comparable prior session exists in the window. */
  hasComparable: boolean;
  /** A body area was mentioned in this session's note or is active. */
  hasBodyMention: boolean;
  /** An active goal race with a target pace exists. */
  hasGoal: boolean;
}

export interface SessionQuestion {
  id: string;
  /** What the athlete taps. First person, plain, no jargon she didn't use. */
  text: string;
  /**
   * Rank within its tier. Lower sorts first. Not a global rank — the picker
   * balances across intents so the rail never shows five variations of
   * "was it fast".
   */
  rank: number;
  /** Used by the picker to avoid stacking the rail with one kind of question. */
  intent:
    | "read"
    | "execution"
    | "effort"
    | "conditions"
    | "comparison"
    | "fit"
    | "body"
    | "next";
  applies: (s: SessionShape) => boolean;
}

// ── Type buckets ────────────────────────────────────────────────────

const REP_TYPES = new Set(["lt", "10k", "5k", "3k", "mile", "hmp", "mp", "long_wo"]);
const LONG_TYPES = new Set(["long_run", "long_wo"]);
const EASY_TYPES = new Set(["easy", "recovery"]);
const STEADY_TYPES = new Set(["steady", "moderate", "mp", "hmp"]);

const isRep = (s: SessionShape) =>
  s.repCount >= 2 || (s.workoutType != null && REP_TYPES.has(s.workoutType));
const isLong = (s: SessionShape) =>
  (s.workoutType != null && LONG_TYPES.has(s.workoutType)) ||
  (s.distanceMiles ?? 0) >= 12;
const isEasy = (s: SessionShape) =>
  s.workoutType != null && EASY_TYPES.has(s.workoutType);
const isSteady = (s: SessionShape) =>
  s.workoutType != null && STEADY_TYPES.has(s.workoutType);
const isQuality = (s: SessionShape) => isRep(s) || isSteady(s);

// ── The fifteen ─────────────────────────────────────────────────────

export const SESSION_QUESTIONS: SessionQuestion[] = [
  // ── The read. Always first, always offered. This is the old
  //    "READ THE INSIGHT" row, now one question among several.
  {
    id: "read",
    text: "What's the read on this session?",
    rank: 0,
    intent: "read",
    applies: () => true,
  },

  // ── Execution: did I do what I set out to do? ─────────────────────
  {
    id: "as_written",
    text: "Did I run this the way it was written?",
    rank: 1,
    intent: "execution",
    // Needs something to have been written. Without a prescription this
    // becomes "did I run the way I ran", which answers nothing.
    applies: (s) => s.hasPrescription,
  },
  {
    id: "held_the_pace",
    text: "Did I hold the pace across the reps?",
    rank: 1,
    intent: "execution",
    applies: (s) => isRep(s) && s.repCount >= 2 && s.hasSplits,
  },
  {
    id: "back_half",
    text: "Did I fade in the back half?",
    rank: 1,
    intent: "execution",
    // Deliberately NOT offered on easy runs: pace drifting slower late is
    // normal there, and the prompt is explicitly told not to read it as a
    // fade. Offering the question invites the answer we don't want.
    applies: (s) => s.hasSplits && (isLong(s) || isSteady(s)),
  },
  {
    id: "first_mile",
    text: "Did I start too fast?",
    rank: 2,
    intent: "execution",
    applies: (s) => s.hasSplits && (s.distanceMiles ?? 0) >= 3,
  },

  // ── Effort: what did it actually cost me? ─────────────────────────
  {
    id: "actually_easy",
    text: "Was this actually easy?",
    rank: 1,
    intent: "effort",
    // The most useful question in the set for most athletes, and only
    // honestly answerable with HR or zones to check the pace against.
    applies: (s) => isEasy(s) && (s.hasHeartRate || s.hasSplits),
  },
  {
    id: "how_hard",
    text: "How hard was this, really?",
    rank: 2,
    intent: "effort",
    applies: (s) => !isEasy(s) && (s.hasHeartRate || s.hasSplits),
  },
  {
    id: "hr_fit",
    text: "Was my heart rate where it should have been?",
    rank: 3,
    intent: "effort",
    applies: (s) => s.hasHeartRate,
  },

  // ── Conditions: was it me, or was it the day? ─────────────────────
  {
    id: "pace_or_conditions",
    text: "Was that pace real, or was it the conditions?",
    rank: 1,
    intent: "conditions",
    applies: (s) => s.hasConditions,
  },
  {
    id: "hills_cost",
    text: "How much did the hills cost me?",
    rank: 2,
    intent: "conditions",
    applies: (s) => s.hasElevation,
  },

  // ── Comparison: where does this sit? ──────────────────────────────
  {
    id: "vs_last_similar",
    text: "How does this compare to the last one like it?",
    rank: 1,
    intent: "comparison",
    applies: (s) => s.hasComparable,
  },
  {
    id: "vs_month_ago",
    text: "Could I have run this a month ago?",
    rank: 2,
    intent: "comparison",
    // Reads fitness_trend + the zone history in athlete state. Needs a
    // quality session to mean anything — "could I have run 4 easy miles a
    // month ago" is not a question.
    applies: (s) => isQuality(s),
  },

  // ── Fit: was this the right session? ──────────────────────────────
  {
    id: "right_session",
    text: "Was this the right session for where I am right now?",
    rank: 1,
    intent: "fit",
    // Leans entirely on athlete state — phase, load vs chronic, days between
    // hard. The question that most rewards §5.4 being done properly.
    applies: () => true,
  },
  {
    id: "toward_goal",
    text: "Does this get me closer to my goal pace?",
    rank: 2,
    intent: "fit",
    applies: (s) => s.hasGoal && isQuality(s),
  },

  // ── Body ──────────────────────────────────────────────────────────
  {
    id: "worth_watching",
    text: "Is there anything here worth paying attention to?",
    rank: 1,
    intent: "body",
    // Offered when she mentioned something, or when the log has an open
    // body mention. NOT offered unprompted on a clean session — inviting a
    // worry question on a good run is its own kind of harm.
    applies: (s) => s.hasBodyMention || s.hasNotes,
  },

  // ── Next ──────────────────────────────────────────────────────────
  {
    id: "next_one",
    text: "What should the next one look like?",
    rank: 1,
    intent: "next",
    applies: (s) => isQuality(s) || isLong(s),
  },
];

// ── The picker ──────────────────────────────────────────────────────

/** How many questions the session sheet shows before "More questions". */
export const RAIL_SIZE = 5;

/**
 * Pick the rail for one session.
 *
 * `read` is pinned first — it's the affordance the old row occupied and the
 * safest default when she doesn't know what to ask. The remaining four are
 * filled **one intent at a time**, best-ranked first, before any intent is
 * allowed a second slot. Without that pass the rail fills with four execution
 * questions on any session with splits, which is a worse rail than a mixed
 * one even though every entry is individually relevant.
 *
 * Returns the full ordered list; the client shows `RAIL_SIZE` and puts the
 * rest behind the disclosure. Nothing is discarded — a question that didn't
 * make the rail is still one tap away, which is the point of having fifteen.
 */
export function pickQuestions(shape: SessionShape): SessionQuestion[] {
  const eligible = SESSION_QUESTIONS.filter((q) => q.applies(shape));

  const read = eligible.filter((q) => q.intent === "read");
  const rest = eligible.filter((q) => q.intent !== "read");

  // Group by intent, each group internally sorted by rank.
  const byIntent = new Map<string, SessionQuestion[]>();
  for (const q of rest) {
    const list = byIntent.get(q.intent) ?? [];
    list.push(q);
    byIntent.set(q.intent, list);
  }
  for (const list of byIntent.values()) list.sort((a, b) => a.rank - b.rank);

  // Intent order. Execution and effort are what athletes ask about a session
  // they just finished; `next` is a good question but rarely the first one.
  const ORDER = ["execution", "effort", "comparison", "conditions", "fit", "body", "next"];

  const out: SessionQuestion[] = [...read];
  let round = 0;
  let added = true;
  while (added) {
    added = false;
    for (const intent of ORDER) {
      const q = byIntent.get(intent)?.[round];
      if (q) {
        out.push(q);
        added = true;
      }
    }
    round++;
  }
  return out;
}

/**
 * The rail before the server has answered once — the app's cold start.
 *
 * Three questions that apply to literally any run, so the box is never empty
 * on a slow connection. An empty rail reads as broken; a generic one reads as
 * a product that hasn't loaded yet, which is what it is.
 *
 * Mirror this list in `SessionAskBlock.swift`. It is the one duplication in
 * the design and it is deliberate: the alternative is a blank rail, and three
 * strings drifting is a smaller problem than that.
 */
export const COLD_START_QUESTIONS: string[] = [
  "What's the read on this session?",
  "Was this the right session for where I am right now?",
  "How does this compare to the last one like it?",
];

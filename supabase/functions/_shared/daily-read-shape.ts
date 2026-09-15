/**
 * daily-read-shape — the pure half of `coaching-daily-read`.
 *
 * Everything in here is a plain function with no I/O and no remote
 * imports, so it can be unit-tested with `deno test` offline
 * (`daily-read-shape.test.ts`) and reused by the eval harness.
 *
 * Responsibilities:
 *   - Types for the Read payload (mirrors `daily_coaching_reads` JSON
 *     columns and the iOS `CoachRead` model).
 *   - `parseModelResponse` — tolerant JSON parse of the model output.
 *   - `validateRead` — strip citations that don't point at ids in the
 *     context, normalize the headline and questions, dedupe sources.
 *   - `weeklyRunningVolume` — the pre-computed volume facts the v3
 *     prompt needs so the model can say "third week above 40" without
 *     doing the arithmetic itself (and getting it wrong).
 */

// ── Types matching the daily_coaching_reads JSON columns ─────────────

export type ParagraphSegment =
  | string
  | { workout_id: string }
  | { doc_id: string };

export interface CantSee {
  eyebrow: string;
  body: string;
}

export interface MemoSource {
  label: string;
  excerpt: string;
  log_id: string;
}

export interface Sources {
  workouts: string[];
  docs: string[];
  memos: MemoSource[];
}

export interface Confidence {
  level: "HIGH" | "MEDIUM" | "LOW";
  sub: string;
}

export interface DailyReadPayload {
  headline: string;
  paragraph: ParagraphSegment[];
  /** v3: 0-2 soft questions. Always present after validation. */
  questions: string[];
  cant_see: CantSee | null;
  sources: Sources;
  confidence: Confidence;
}

/** The id sets the model is allowed to cite. */
export interface CitationContext {
  validWorkoutIds: Set<string>;
  validDocIds: Set<string>;
  validMemoLogIds: Set<string>;
}

export const MAX_QUESTIONS = 2;

// ── Parsing ──────────────────────────────────────────────────────────

/**
 * Parse the raw model text into a payload. Tolerates ```json fences.
 * Throws on a missing headline / paragraph / sources / confidence —
 * those are the fields the row can't be completed without.
 * `questions` is optional at parse time (a v2-shaped response still
 * parses) and defaults to an empty array.
 */
export function parseModelResponse(raw: string): DailyReadPayload {
  const cleaned = raw
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  const obj = JSON.parse(cleaned) as Partial<DailyReadPayload>;

  if (typeof obj.headline !== "string") {
    throw new Error("Missing or invalid headline");
  }
  if (!Array.isArray(obj.paragraph)) {
    throw new Error("Missing or invalid paragraph array");
  }
  if (!obj.sources || typeof obj.sources !== "object") {
    throw new Error("Missing sources object");
  }
  if (!obj.confidence || typeof obj.confidence !== "object") {
    throw new Error("Missing confidence object");
  }

  const level = obj.confidence.level;
  return {
    headline: obj.headline,
    paragraph: obj.paragraph as ParagraphSegment[],
    questions: Array.isArray(obj.questions) ? (obj.questions as unknown[]).map(String) : [],
    cant_see: (obj.cant_see ?? null) as CantSee | null,
    sources: {
      workouts: Array.isArray(obj.sources.workouts) ? obj.sources.workouts : [],
      docs: Array.isArray(obj.sources.docs) ? obj.sources.docs : [],
      memos: Array.isArray(obj.sources.memos) ? obj.sources.memos : [],
    },
    confidence: {
      level: level === "HIGH" || level === "MEDIUM" || level === "LOW" ? level : "LOW",
      sub: typeof obj.confidence.sub === "string" ? obj.confidence.sub : "",
    },
  };
}

// ── Validation / normalization ───────────────────────────────────────

export interface ValidationReport {
  droppedWorkoutCitations: number;
  droppedDocCitations: number;
  droppedQuestions: number;
}

/**
 * Strip any citation that doesn't point at a known id (paragraph AND
 * sources), normalize the headline and questions, and auto-populate
 * `sources.workouts/docs` from the paragraph when the model didn't
 * echo them back. Returns the cleaned payload plus a report the caller
 * can log.
 */
export function validateRead(
  payload: DailyReadPayload,
  ctx: CitationContext,
): { payload: DailyReadPayload; report: ValidationReport } {
  const cleanedParagraph: ParagraphSegment[] = [];
  let droppedWorkouts = 0;
  let droppedDocs = 0;

  for (const seg of payload.paragraph) {
    if (typeof seg === "string") {
      cleanedParagraph.push(seg);
      continue;
    }
    if (seg && typeof seg === "object" && "workout_id" in seg) {
      if (ctx.validWorkoutIds.has(seg.workout_id)) {
        cleanedParagraph.push(seg);
      } else {
        droppedWorkouts++;
      }
      continue;
    }
    if (seg && typeof seg === "object" && "doc_id" in seg) {
      if (ctx.validDocIds.has(seg.doc_id)) {
        cleanedParagraph.push(seg);
      } else {
        droppedDocs++;
      }
      continue;
    }
    // Unknown segment shape — drop quietly. The prompt forbids anything
    // other than the three documented variants.
  }

  const sources: Sources = {
    workouts: dedupe(payload.sources.workouts.filter((id) => ctx.validWorkoutIds.has(id))),
    docs: dedupe(payload.sources.docs.filter((id) => ctx.validDocIds.has(id))),
    memos: payload.sources.memos
      .filter((m) => m && typeof m === "object" && ctx.validMemoLogIds.has(m.log_id))
      .map((m) => ({
        label: String(m.label ?? "").slice(0, 80),
        excerpt: String(m.excerpt ?? "").slice(0, 400),
        log_id: m.log_id,
      })),
  };

  for (const seg of cleanedParagraph) {
    if (typeof seg === "object" && "workout_id" in seg && !sources.workouts.includes(seg.workout_id)) {
      sources.workouts.push(seg.workout_id);
    }
    if (typeof seg === "object" && "doc_id" in seg && !sources.docs.includes(seg.doc_id)) {
      sources.docs.push(seg.doc_id);
    }
  }

  const { questions, dropped: droppedQuestions } = normalizeQuestions(payload.questions);

  return {
    payload: {
      headline: normalizeHeadline(payload.headline),
      paragraph: cleanedParagraph,
      questions,
      cant_see: normalizeCantSee(payload.cant_see),
      sources,
      confidence: payload.confidence,
    },
    report: {
      droppedWorkoutCitations: droppedWorkouts,
      droppedDocCitations: droppedDocs,
      droppedQuestions,
    },
  };
}

/**
 * Design rule (design-system/ui_kits/ios_app/README.md): every
 * standalone headline ends in a period. Make it mechanical — trim,
 * collapse whitespace, strip surrounding quotes, and add the period
 * if the model forgot. Leaves `?` / `!` / `…` alone (the prompt bans
 * them, but rewriting punctuation the model chose is worse than
 * letting the eval harness catch it).
 */
export function normalizeHeadline(raw: string): string {
  let h = raw.replace(/\s+/g, " ").trim();
  h = h.replace(/^["“”']+|["“”']+$/g, "").trim();
  if (h.length === 0) return h;
  if (!/[.!?…]$/.test(h)) h += ".";
  return h;
}

/**
 * Questions: plain strings only, trimmed, non-empty, deduplicated,
 * capped at MAX_QUESTIONS. Anything that isn't a string (a citation
 * object, a number) is dropped and counted.
 */
export function normalizeQuestions(raw: unknown): { questions: string[]; dropped: number } {
  if (!Array.isArray(raw)) return { questions: [], dropped: 0 };
  const out: string[] = [];
  let dropped = 0;
  for (const q of raw) {
    if (typeof q !== "string") {
      dropped++;
      continue;
    }
    const t = q.replace(/\s+/g, " ").trim();
    if (t.length === 0 || out.includes(t)) {
      dropped++;
      continue;
    }
    if (out.length >= MAX_QUESTIONS) {
      dropped++;
      continue;
    }
    out.push(t);
  }
  return { questions: out, dropped };
}

function normalizeCantSee(block: CantSee | null): CantSee | null {
  if (!block || typeof block !== "object") return null;
  const eyebrow = String(block.eyebrow ?? "").trim();
  const body = String(block.body ?? "").trim();
  if (!eyebrow || !body) return null;
  return { eyebrow: eyebrow.toUpperCase().slice(0, 40), body: body.slice(0, 400) };
}

function dedupe<T>(arr: T[]): T[] {
  return Array.from(new Set(arr));
}

// ── Weekly running volume ────────────────────────────────────────────

/**
 * Workout types that are not running. Per the 2026-05-28 decision
 * (Q23), cross-training is a different *kind* of stress and stays out
 * of running-volume math. Anything not listed here is treated as a run
 * — the training_logs vocabulary is open-ended and defaulting the
 * unknown to "run" is the safer failure for a running log.
 */
export const NON_RUNNING_TYPES = new Set([
  "cross_training",
  "cross-training",
  "crosstraining",
  "cross",
  "strength",
  "lift",
  "lifting",
  "weights",
  "gym",
  "cycling",
  "bike",
  "biking",
  "ride",
  "swim",
  "swimming",
  "row",
  "rowing",
  "elliptical",
  "yoga",
  "pilates",
  "mobility",
  "walk",
  "walking",
  "hike",
  "hiking",
  "rest",
]);

export function isRunningType(workoutType: string | null | undefined): boolean {
  if (!workoutType) return true;
  return !NON_RUNNING_TYPES.has(workoutType.toLowerCase().trim());
}

export interface VolumeLogRow {
  workout_date: string | null;
  workout_type: string | null;
  workout_distance_miles: number | string | null;
}

export interface WeekVolume {
  /** ISO date (yyyy-mm-dd) of the Monday that starts this week. */
  weekStart: string;
  miles: number;
  runs: number;
  /** True when `today` falls inside this week — it's still being written. */
  partial: boolean;
}

/**
 * Sum running miles per Monday-start week for the `weeks` most recent
 * weeks ending with the week containing `today` (yyyy-mm-dd). Weeks
 * with no runs are included with 0 so the model sees gaps as gaps.
 * Most recent week first.
 */
export function weeklyRunningVolume(
  logs: VolumeLogRow[],
  today: string,
  weeks = 6,
): WeekVolume[] {
  const thisMonday = mondayOf(today);
  const buckets = new Map<string, { miles: number; runs: number }>();
  for (let i = 0; i < weeks; i++) {
    buckets.set(addDays(thisMonday, -7 * i), { miles: 0, runs: 0 });
  }

  for (const l of logs) {
    if (!l.workout_date || !isRunningType(l.workout_type)) continue;
    const miles = Number(l.workout_distance_miles ?? 0);
    if (!Number.isFinite(miles) || miles <= 0) continue;
    const key = mondayOf(l.workout_date.slice(0, 10));
    const b = buckets.get(key);
    if (!b) continue; // outside the window
    b.miles += miles;
    b.runs += 1;
  }

  return Array.from(buckets.entries()).map(([weekStart, b]) => ({
    weekStart,
    miles: Math.round(b.miles * 10) / 10,
    runs: b.runs,
    partial: weekStart === thisMonday,
  }));
}

/** Render the volume table as the markdown block the prompt reads. */
export function formatWeeklyVolume(rows: WeekVolume[]): string {
  if (rows.length === 0) return "No running volume in the window.";
  return rows
    .map((r) => {
      const label = r.partial ? " (this week so far)" : "";
      const runs = r.runs === 1 ? "1 run" : `${r.runs} runs`;
      return `- Week of ${r.weekStart}: ${r.miles.toFixed(1)} mi · ${runs}${label}`;
    })
    .join("\n");
}

// ── Date helpers (UTC-safe on yyyy-mm-dd strings) ────────────────────

function parseYmd(ymd: string): Date {
  const [y, m, d] = ymd.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function toYmd(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(ymd: string, days: number): string {
  const d = parseYmd(ymd);
  d.setUTCDate(d.getUTCDate() + days);
  return toYmd(d);
}

/** Monday-start week, as yyyy-mm-dd. */
export function mondayOf(ymd: string): string {
  const d = parseYmd(ymd);
  const dow = d.getUTCDay(); // 0 = Sunday
  const back = dow === 0 ? 6 : dow - 1;
  d.setUTCDate(d.getUTCDate() - back);
  return toYmd(d);
}

/** "Tuesday" for a yyyy-mm-dd string. */
export function weekdayName(ymd: string): string {
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][
    parseYmd(ymd).getUTCDay()
  ];
}

/* ════════════════════════════════════════════════════════════════════
   NIGGLES · v2 PROTOTYPE — mock data + derivation
   ────────────────────────────────────────────────────────────────────
   Every row here is shaped like the proposed `body_mentions` table so
   that wiring the real surface is a fetch swap, not a rewrite. See
   `outputs/niggles-v2-dashboard-2026-08-23.md` for the schema and the
   auto-population contract.

   Nothing in this file interprets. Statuses and co-occurrence counts
   are MECHANICAL derivations from dates and session labels — per the
   Niggles rules in CLAUDE.md, the system reports what was said and
   where, never what it means.

   Mock athlete: Maya. 16-week marathon block, May 4 – Aug 23 2026.
   ════════════════════════════════════════════════════════════════════ */

export const DAY_MS = 86_400_000;

/** UTC-stable parse so server and client agree on positions. */
export function day(iso: string): number {
  return Date.parse(`${iso}T00:00:00Z`);
}

export function daysBetween(aIso: string, bIso: string): number {
  return Math.round((day(bIso) - day(aIso)) / DAY_MS);
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "2026-08-17" → "Aug 17". No locale calls — deterministic across environments. */
export function shortDate(iso: string): string {
  const [, m, d] = iso.split("-");
  return `${MONTHS[Number(m) - 1]} ${Number(d)}`;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function weekday(iso: string): string {
  return WEEKDAYS[new Date(day(iso)).getUTCDay()];
}

/* ── The block ────────────────────────────────────────────────────── */

/** "Today" for this prototype. Frozen so the mock never drifts. */
export const TODAY = "2026-08-23";

export const SPAN_START = "2026-05-04";
export const SPAN_END = "2026-08-23";

export type SessionLabel = "Long" | "Easy" | "MP" | "HMP" | "LT" | "10K" | "Rest";

/** Pace-zone labels are the workout labels (CLAUDE.md). Quality = race-pace zone. */
export const QUALITY_LABELS: SessionLabel[] = ["MP", "HMP", "LT", "10K"];

export type Session = {
  label: SessionLabel;
  miles: number;
  pace: string | null;
  detail?: string;
};

export type TrainingWeek = {
  /** Monday, ISO. */
  start: string;
  miles: number;
  longMiles: number;
  longDate: string;
  quality: number;
  partial?: boolean;
};

export const WEEKS: TrainingWeek[] = [
  { start: "2026-05-04", miles: 41, longMiles: 14, longDate: "2026-05-10", quality: 2 },
  { start: "2026-05-11", miles: 44, longMiles: 15, longDate: "2026-05-17", quality: 2 },
  { start: "2026-05-18", miles: 48, longMiles: 16, longDate: "2026-05-24", quality: 2 },
  { start: "2026-05-25", miles: 36, longMiles: 12, longDate: "2026-05-31", quality: 1 },
  { start: "2026-06-01", miles: 47, longMiles: 16, longDate: "2026-06-07", quality: 2 },
  { start: "2026-06-08", miles: 51, longMiles: 18, longDate: "2026-06-14", quality: 2 },
  { start: "2026-06-15", miles: 54, longMiles: 18, longDate: "2026-06-21", quality: 2 },
  { start: "2026-06-22", miles: 39, longMiles: 13, longDate: "2026-06-28", quality: 1 },
  { start: "2026-06-29", miles: 52, longMiles: 17, longDate: "2026-07-05", quality: 2 },
  { start: "2026-07-06", miles: 56, longMiles: 20, longDate: "2026-07-12", quality: 2 },
  { start: "2026-07-13", miles: 58, longMiles: 18, longDate: "2026-07-19", quality: 2 },
  { start: "2026-07-20", miles: 43, longMiles: 14, longDate: "2026-07-26", quality: 1 },
  { start: "2026-07-27", miles: 57, longMiles: 18, longDate: "2026-08-02", quality: 2 },
  { start: "2026-08-03", miles: 61, longMiles: 20, longDate: "2026-08-09", quality: 3 },
  { start: "2026-08-10", miles: 63, longMiles: 21, longDate: "2026-08-16", quality: 2 },
  { start: "2026-08-17", miles: 48, longMiles: 16, longDate: "2026-08-23", quality: 2, partial: true },
];

export function weekOf(iso: string): TrainingWeek | undefined {
  const t = day(iso);
  return WEEKS.find((w) => t >= day(w.start) && t < day(w.start) + 7 * DAY_MS);
}

/* ── body_mentions rows ───────────────────────────────────────────── */

export type MentionKind = "mention" | "resolution";
export type Side = "left" | "right" | "both" | "unspecified";

export type BodyMention = {
  id: string;
  /** Closed vocabulary. The classifier never invents entries. */
  bodyPart: string;
  side: Side;
  kind: MentionKind;
  /** VERBATIM. The athlete's own words, never paraphrased or scored. */
  quote: string;
  mentionedAt: string;
  /** The session the memo was logged against, when there was one. */
  sameDay: Session | null;
  /** The session in the 24 h before the memo. This is the overlay hook. */
  prevDay: Session | null;
};

export const MENTIONS: BodyMention[] = [
  /* ── L. Achilles — the recurring thread ── */
  {
    id: "bm_01", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "left achilles was tight walking down the stairs this morning, day after the long one",
    mentionedAt: "2026-05-18",
    sameDay: null,
    prevDay: { label: "Long", miles: 15.0, pace: "8:31" },
  },
  {
    id: "bm_02", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "achilles is grumbling again, same left one, first mile of the shakeout",
    mentionedAt: "2026-06-15",
    sameDay: { label: "Easy", miles: 5.0, pace: "8:48" },
    prevDay: { label: "Long", miles: 18.0, pace: "8:24" },
  },
  {
    id: "bm_03", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "felt the achilles in the last two MP miles, not sharp, just there",
    mentionedAt: "2026-06-25",
    sameDay: { label: "MP", miles: 8.0, pace: "7:38", detail: "2 × 3 mi @ MP" },
    prevDay: { label: "Easy", miles: 6.0, pace: "8:52" },
  },
  {
    id: "bm_04", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "achilles stiff first thing, took about a mile of walking to loosen up",
    mentionedAt: "2026-07-13",
    sameDay: null,
    prevDay: { label: "Long", miles: 20.0, pace: "8:19" },
  },
  {
    id: "bm_05", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "achilles talking to me again after yesterday, eased off after the first mile",
    mentionedAt: "2026-08-03",
    sameDay: { label: "Easy", miles: 6.0, pace: "8:45" },
    prevDay: { label: "Long", miles: 18.0, pace: "8:16" },
  },
  {
    id: "bm_06", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "same spot on the left achilles, stiff getting out of bed",
    mentionedAt: "2026-08-10",
    sameDay: null,
    prevDay: { label: "Long", miles: 20.0, pace: "8:11" },
  },
  {
    id: "bm_07", bodyPart: "achilles", side: "left", kind: "mention",
    quote: "achilles again, same spot, same story, gone by the end of the run",
    mentionedAt: "2026-08-17",
    sameDay: { label: "Easy", miles: 5.0, pace: "8:50" },
    prevDay: { label: "Long", miles: 21.0, pace: "8:08" },
  },

  /* ── R. Knee — opened and closed ── */
  {
    id: "bm_08", bodyPart: "knee", side: "right", kind: "mention",
    quote: "right knee felt a pinch on the last rep",
    mentionedAt: "2026-06-03",
    sameDay: { label: "10K", miles: 7.5, pace: "7:12", detail: "5 × 1 km @ 10K" },
    prevDay: { label: "Easy", miles: 6.0, pace: "8:50" },
  },
  {
    id: "bm_09", bodyPart: "knee", side: "right", kind: "mention",
    quote: "knee's still there going down hills, fine on the flat",
    mentionedAt: "2026-06-10",
    sameDay: { label: "Easy", miles: 7.0, pace: "8:40" },
    prevDay: { label: "HMP", miles: 8.0, pace: "7:26" },
  },
  {
    id: "bm_10", bodyPart: "knee", side: "right", kind: "resolution",
    quote: "knee's completely gone, haven't thought about it in a couple of weeks",
    mentionedAt: "2026-06-24",
    sameDay: { label: "Easy", miles: 6.0, pace: "8:52" },
    prevDay: null,
  },

  /* ── L. Calf — quiet all summer, then back ── */
  {
    id: "bm_11", bodyPart: "calf", side: "left", kind: "mention",
    quote: "left calf went knotty right after the tempo",
    mentionedAt: "2026-05-12",
    sameDay: { label: "HMP", miles: 7.0, pace: "7:24", detail: "4 mi @ HMP" },
    prevDay: { label: "Easy", miles: 5.0, pace: "8:55" },
  },
  {
    id: "bm_12", bodyPart: "calf", side: "left", kind: "mention",
    quote: "calf tightened up in the last two reps again",
    mentionedAt: "2026-05-26",
    sameDay: { label: "MP", miles: 8.0, pace: "7:41", detail: "3 × 2 mi @ MP" },
    prevDay: null,
  },
  {
    id: "bm_13", bodyPart: "calf", side: "left", kind: "mention",
    quote: "calf is knotty again, same left one, been quiet all summer",
    mentionedAt: "2026-08-05",
    sameDay: { label: "LT", miles: 6.0, pace: "7:16", detail: "4 mi @ LT" },
    prevDay: { label: "Easy", miles: 6.0, pace: "8:47" },
  },

  /* ── R. Hip — one mention, no pattern ── */
  {
    id: "bm_14", bodyPart: "hip", side: "right", kind: "mention",
    quote: "right hip felt locked up on the first mile, probably from sitting all day",
    mentionedAt: "2026-07-22",
    sameDay: { label: "Easy", miles: 8.0, pace: "8:44" },
    prevDay: null,
  },

  /* ── L. Foot — newest thread ── */
  {
    id: "bm_15", bodyPart: "foot", side: "left", kind: "mention",
    quote: "bottom of my left foot is sore, worst on the first steps in the morning",
    mentionedAt: "2026-08-12",
    sameDay: { label: "Easy", miles: 6.0, pace: "8:47" },
    prevDay: { label: "LT", miles: 6.0, pace: "7:14" },
  },
  {
    id: "bm_16", bodyPart: "foot", side: "left", kind: "mention",
    quote: "foot again, that same spot under the arch",
    mentionedAt: "2026-08-20",
    sameDay: { label: "MP", miles: 8.0, pace: "7:33", detail: "2 × 3 mi @ MP" },
    prevDay: { label: "Easy", miles: 5.0, pace: "8:51" },
  },
];

/* ── Threads — grouping, not judgement ──────────────────────────────
   A thread is every mention of one body part + side, in date order.
   Status is derived by a fixed rule, never by the model:

     resolved  the most recent row is a resolution
     active    a mention inside the last 14 days
     quiet     no mention in 14+ days, no resolution on file

   "Quiet" is deliberately not "healed". The system does not know that.
   ────────────────────────────────────────────────────────────────── */

export const ACTIVE_WINDOW_DAYS = 14;
/** A gap this long before a mention reads as a return, not a continuation. */
export const RECURRENCE_GAP_DAYS = 21;

export type ThreadStatus = "active" | "quiet" | "resolved";

export type NiggleThread = {
  key: string;
  bodyPart: string;
  side: Side;
  label: string;
  status: ThreadStatus;
  mentions: BodyMention[];
  resolution: BodyMention | null;
  firstSeen: string;
  lastSeen: string;
  mentionCount: number;
  spanDays: number;
  daysSinceLast: number;
  /** Gaps of RECURRENCE_GAP_DAYS+ between consecutive mentions. */
  returns: { after: number; on: string }[];
};

const SIDE_PREFIX: Record<Side, string> = {
  left: "L.",
  right: "R.",
  both: "Both",
  unspecified: "",
};

function titleCase(part: string): string {
  if (part === "it band") return "IT band";
  return part.charAt(0).toUpperCase() + part.slice(1);
}

function buildThreads(rows: BodyMention[], today: string): NiggleThread[] {
  const groups = new Map<string, BodyMention[]>();
  for (const row of rows) {
    const key = `${row.bodyPart}:${row.side}`;
    const bucket = groups.get(key);
    if (bucket) bucket.push(row);
    else groups.set(key, [row]);
  }

  const threads: NiggleThread[] = [];

  for (const [key, all] of groups) {
    const ordered = [...all].sort((a, b) => day(a.mentionedAt) - day(b.mentionedAt));
    const mentions = ordered.filter((m) => m.kind === "mention");
    const last = ordered[ordered.length - 1];
    const resolution = last.kind === "resolution" ? last : null;

    const lastMention = mentions[mentions.length - 1];
    const daysSinceLast = daysBetween(lastMention.mentionedAt, today);

    const status: ThreadStatus = resolution
      ? "resolved"
      : daysSinceLast <= ACTIVE_WINDOW_DAYS
        ? "active"
        : "quiet";

    const returns: { after: number; on: string }[] = [];
    for (let i = 1; i < mentions.length; i++) {
      const gap = daysBetween(mentions[i - 1].mentionedAt, mentions[i].mentionedAt);
      if (gap >= RECURRENCE_GAP_DAYS) {
        returns.push({ after: gap, on: mentions[i].mentionedAt });
      }
    }

    const first = ordered[0];
    const prefix = SIDE_PREFIX[first.side];

    threads.push({
      key,
      bodyPart: first.bodyPart,
      side: first.side,
      label: prefix ? `${prefix} ${titleCase(first.bodyPart)}` : titleCase(first.bodyPart),
      status,
      mentions,
      resolution,
      firstSeen: mentions[0].mentionedAt,
      lastSeen: lastMention.mentionedAt,
      mentionCount: mentions.length,
      spanDays: daysBetween(mentions[0].mentionedAt, lastMention.mentionedAt),
      daysSinceLast,
      returns,
    });
  }

  const rank: Record<ThreadStatus, number> = { active: 0, quiet: 1, resolved: 2 };
  return threads.sort(
    (a, b) => rank[a.status] - rank[b.status] || day(b.lastSeen) - day(a.lastSeen)
  );
}

export const THREADS = buildThreads(MENTIONS, TODAY);

/* ── Co-occurrence — counting, not causation ────────────────────────
   These are tallies of what the training log already says. They are
   phrased as counts everywhere they surface. The dashboard never
   completes the sentence for the athlete.
   ────────────────────────────────────────────────────────────────── */

/** The session in the mention's own day, or the 24 h before it. */
export function window24h(m: BodyMention): Session[] {
  return [m.sameDay, m.prevDay].filter((s): s is Session => s !== null);
}

export function followsLong(m: BodyMention): boolean {
  return window24h(m).some((s) => s.label === "Long");
}

export function followsQuality(m: BodyMention): boolean {
  return window24h(m).some((s) => QUALITY_LABELS.includes(s.label));
}

export type Tally = { label: string; count: number };

export function tallyBySession(mentions: BodyMention[]): Tally[] {
  const counts = new Map<string, number>();
  for (const m of mentions) {
    const label = m.sameDay ? m.sameDay.label : "Rest";
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}

export const VOLUME_BANDS = [
  { label: "Under 45 mi", test: (mi: number) => mi < 45 },
  { label: "45 – 55 mi", test: (mi: number) => mi >= 45 && mi < 55 },
  { label: "55 mi and up", test: (mi: number) => mi >= 55 },
];

export function tallyByVolumeBand(mentions: BodyMention[]): Tally[] {
  return VOLUME_BANDS.map((band) => ({
    label: band.label,
    count: mentions.filter((m) => {
      const w = weekOf(m.mentionedAt);
      return w ? band.test(w.miles) : false;
    }).length,
  }));
}

export const ALL_MENTIONS = MENTIONS.filter((m) => m.kind === "mention");

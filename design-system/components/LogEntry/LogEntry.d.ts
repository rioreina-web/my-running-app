import * as React from "react";

export interface LogEntryStat {
  label?: React.ReactNode;
  value?: React.ReactNode;
  unit?: React.ReactNode;
}

export interface LogEntryProps {
  /** Tracked date line, e.g. "Friday 21 Aug". */
  date?: React.ReactNode;
  /** Mood ramp: green good, grey nothing, orange tired, reds trouble. */
  mood?: "energized" | "positive" | "neutral" | "tired" | "struggling" | "injured";
  /** Session type shown as a chip, e.g. "Intervals". */
  type?: React.ReactNode;
  /** Solid blue chip: this was the keyed session. */
  keyed?: boolean;
  /** States the session — "6 × 800m." Never a literary title. */
  title?: React.ReactNode;
  /** What the athlete wrote, set in the reading serif. */
  prose?: React.ReactNode;
  /** Raw transcript, set in italic mono. Use instead of prose, not with it. */
  voice?: React.ReactNode;
  /** Up to three stats; the last one right-aligns. */
  stats?: LogEntryStat[];
  /** Provenance line, e.g. "Voice 0:42 · transcribed 8:40". */
  byline?: React.ReactNode;
  style?: React.CSSProperties;
}

/** One run in the feed: mood dot, date, type chip, headline, words, stats. */
export declare function LogEntry(props: LogEntryProps): React.ReactElement;

import Link from "next/link";

// The coach roster as an editorial ledger — Direction I.
//
// This replaces the 3-up AthleteRosterCard grid. The grid made a coach read
// eight boxes to find the one that needs them; a ruled ledger sorts
// attention-first and scans down a single column.
//
// Palette discipline, per design-system/colors_and_type.css:
//   • ink        — volume. Volume is not pace and it is not a feeling.
//   • mood ramp  — the 2px rule under a name, and nothing else.
//   • one red    — only on a row that needs a decision, once per cluster.
// Cards are rules, not boxes: no radius, no shadow, no tint.

export type RosterAdherence = "on_track" | "slipping" | "way_off" | "unknown";

export type RosterRow = {
  subscriptionId: string;
  athleteId: string;
  displayName: string;
  planName: string;
  weeksIn: number;
  totalWeeks: number;
  /** Six weekly mile buckets, oldest → newest. Last entry is this week. */
  mileageTrend: number[];
  thisWeekMiles: number;
  paceAdherence: RosterAdherence;
  /** Whole days since the most recent logged run. null = never logged. */
  daysSinceLastRun: number | null;
  /** athlete_state.last_mood, verbatim and lowercased. */
  mood: string | null;
  /** Short, factual reasons this athlete needs the coach. Never diagnoses. */
  attention: string[];
  /** The athlete's own words from their most recent log, if any. */
  lastVoice: string | null;
};

const MOOD_VAR: Record<string, string> = {
  energized: "var(--color-mood-energized)",
  positive: "var(--color-mood-positive)",
  neutral: "var(--color-mood-neutral)",
  tired: "var(--color-mood-tired)",
  struggling: "var(--color-mood-struggling)",
  injured: "var(--color-mood-injured)",
};

const ADHERENCE_LABEL: Record<RosterAdherence, string> = {
  on_track: "On target",
  slipping: "Slipping",
  way_off: "Off target",
  unknown: "No data",
};

// Off-target is the only adherence state that earns the red. "Slipping" takes
// the tired orange off the mood ramp; on-target and unknown stay ink.
const ADHERENCE_COLOR: Record<RosterAdherence, string> = {
  on_track: "var(--color-text-secondary)",
  slipping: "var(--color-mood-tired)",
  way_off: "var(--red-text)",
  unknown: "var(--color-text-tertiary)",
};

function lastRunLabel(days: number | null): string {
  if (days === null) return "—";
  if (days <= 0) return "Today";
  if (days === 1) return "Yest.";
  return `${days} d`;
}

/** Six ink bars. The current week is solid; the five behind it sit back. */
function VolumeBars({ trend }: { trend: number[] }) {
  const peak = Math.max(...trend, 1);
  return (
    <span className="flex h-[30px] items-end gap-[3px]" aria-hidden="true">
      {trend.map((mi, i) => (
        <i
          key={i}
          className="block flex-1"
          style={{
            height: `${Math.max(6, (mi / peak) * 100)}%`,
            background:
              i === trend.length - 1
                ? "var(--color-text-primary)"
                : "var(--color-text-tertiary)",
          }}
        />
      ))}
    </span>
  );
}

const ROW_GRID =
  "grid items-center gap-4 " +
  "grid-cols-[18px_1fr_88px] " +
  "md:grid-cols-[18px_minmax(180px,1.4fr)_118px_96px_112px_minmax(140px,1.5fr)_70px]";

function LedgerHead() {
  return (
    <div
      className={`${ROW_GRID} hidden md:grid pb-2 pt-[9px]`}
      style={{ borderBottom: "1px solid var(--color-divider)" }}
    >
      <span />
      <span className="drip-eyebrow">Athlete</span>
      <span className="drip-eyebrow">6 wk</span>
      <span className="drip-eyebrow">This week</span>
      <span className="drip-eyebrow">Pace vs plan</span>
      <span className="drip-eyebrow">Signals</span>
      <span className="drip-eyebrow text-right">Last run</span>
    </div>
  );
}

function LedgerRow({ row }: { row: RosterRow }) {
  const flagged = row.attention.length > 0;
  const moodColor = row.mood
    ? MOOD_VAR[row.mood] ?? "var(--color-text-tertiary)"
    : "var(--color-text-tertiary)";

  return (
    <Link
      href={`/coach-portal/athletes/${row.athleteId}`}
      className={`${ROW_GRID} py-[15px] pr-2 transition-colors hover:bg-[var(--color-bg-elevated)]`}
      style={{
        borderBottom: "1px solid var(--color-divider)",
        borderLeft: flagged ? "2px solid var(--red)" : "2px solid transparent",
        paddingLeft: 12,
        marginLeft: -14,
      }}
    >
      <span className="justify-self-center">
        {flagged && (
          <span
            className="block h-[7px] w-[7px] rounded-full"
            style={{ background: "var(--red)" }}
          />
        )}
      </span>

      <span>
        <span className="drip-title block text-[20px]">{row.displayName}</span>
        <span className="drip-eyebrow mt-[5px] block text-[9.5px]" style={{ color: "var(--color-text-tertiary)" }}>
          {row.planName} · wk {row.weeksIn} / {row.totalWeeks}
        </span>
        {/* Mood is a rule, never a fill and never a bare swatch. */}
        <span className="mt-[7px] block h-[2px] w-[26px]" style={{ background: moodColor }} />
      </span>

      <span className="hidden md:block">
        <VolumeBars trend={row.mileageTrend} />
      </span>

      <span>
        <span className="drip-stat text-[16px]">
          {row.thisWeekMiles.toFixed(row.thisWeekMiles >= 100 ? 0 : 1)}
          <span
            className="ml-[2px] text-[10px] font-medium"
            style={{ color: "var(--color-text-tertiary)" }}
          >
            mi
          </span>
        </span>
      </span>

      <span
        className="drip-eyebrow hidden text-[10.5px] font-bold md:block"
        style={{ color: ADHERENCE_COLOR[row.paceAdherence] }}
      >
        {ADHERENCE_LABEL[row.paceAdherence]}
      </span>

      <span className="hidden flex-col gap-[5px] md:flex">
        {row.attention.map((reason) => (
          <span
            key={reason}
            className="drip-eyebrow text-[10px]"
            style={{ color: "var(--red-text)" }}
          >
            {reason}
          </span>
        ))}
        {row.lastVoice && (
          <span
            className="drip-voice text-[12.5px]"
            style={{ color: "var(--color-text-secondary)" }}
          >
            &ldquo;{row.lastVoice}&rdquo;
          </span>
        )}
      </span>

      <span
        className="drip-stat text-right text-[11px] font-normal"
        style={{ color: "var(--color-text-tertiary)" }}
      >
        {lastRunLabel(row.daysSinceLastRun)}
      </span>
    </Link>
  );
}

export function RosterLedger({ rows }: { rows: RosterRow[] }) {
  return (
    <div>
      <LedgerHead />
      {rows.map((row) => (
        <LedgerRow key={row.subscriptionId} row={row} />
      ))}
    </div>
  );
}

/** The quiet tail: on plan, logging, no signals. One line each. */
export function RosterAllClear({ rows }: { rows: RosterRow[] }) {
  if (rows.length === 0) return null;
  return (
    <div className="grid grid-cols-[repeat(auto-fit,minmax(280px,1fr))] gap-x-[34px] pt-[14px]">
      {rows.map((row) => (
        <Link
          key={row.subscriptionId}
          href={`/coach-portal/athletes/${row.athleteId}`}
          className="grid grid-cols-[1fr_auto] items-baseline gap-x-3 py-[10px]"
          style={{ borderBottom: "1px solid var(--color-divider)" }}
        >
          <span className="drip-title col-start-1 row-start-1 whitespace-nowrap text-[15px]">
            {row.displayName}
          </span>
          <span
            className="drip-eyebrow col-start-1 row-start-2 mt-1 overflow-hidden text-ellipsis"
            style={{ color: "var(--color-text-tertiary)" }}
          >
            {row.planName} · wk {row.weeksIn} / {row.totalWeeks}
          </span>
          <span
            className="drip-stat col-start-2 row-span-2 row-start-1 self-center whitespace-nowrap text-[11px] font-normal"
            style={{ color: "var(--color-text-tertiary)" }}
          >
            {row.thisWeekMiles.toFixed(0)} mi · {lastRunLabel(row.daysSinceLastRun).toLowerCase()}
          </span>
        </Link>
      ))}
    </div>
  );
}

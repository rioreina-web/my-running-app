"use client";

import { useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";

// Pace-chart anchor modes. Each mode resolves to a single (distance, time)
// anchor; the full ladder is derived from that anchor via the ratio table.
type Mode = "current" | "projected" | "goal" | "custom";

type AnchorKey = "mile" | "fiveK" | "tenK" | "half" | "marathon";

interface PaceProfile {
  goal_race_distance: string | null;
  goal_time_seconds: number | null;
  easy_pace_seconds: number | null;
  marathon_pace_seconds: number | null;
  marathon_pace_confidence: string | null;
  half_pace_seconds: number | null;
  half_pace_confidence: string | null;
  ten_k_pace_seconds: number | null;
  ten_k_pace_confidence: string | null;
  five_k_pace_seconds: number | null;
  five_k_pace_confidence: string | null;
  mile_pace_seconds: number | null;
  mile_pace_confidence: string | null;
  generated_at: string | null;
}

interface FitnessSnapshot {
  predicted_mile_seconds: number;
  predicted_5k_seconds: number;
  predicted_10k_seconds: number;
  predicted_half_seconds: number;
  predicted_marathon_seconds: number;
  confidence: string;
  created_at: string;
}

// Race-equivalent ratios anchored at 10K = 1.00. Same table as
// supabase/functions/_shared/paces.ts and web/src/components/coach/workout-helpers.ts.
const RACE_RATIOS_TO_10K: Record<AnchorKey, number> = {
  mile:     0.139583,
  fiveK:    0.481250,
  tenK:     1.000000,
  half:     2.204167,
  marathon: 4.615625,
};

const RACE_DISTANCE_MI: Record<AnchorKey, number> = {
  mile:     1.0000,
  fiveK:    3.1069,
  tenK:     6.2137,
  half:     13.1094,
  marathon: 26.2188,
};

// Training-zone bands and the canonical %-MP labels live in workout-helpers.ts
// so the pace-chart page and the coach editor's PaceReferenceEditor stay in
// lockstep. Importing the shared source-of-truth replaces this file's old
// local TRAINING_MP_SPEED_RATIO + inline description strings.
import { TRAINING_MP_SPEED_RANGE, oneHourPaceSecPerMile } from "@/components/coach/workout-helpers";

const RACE_LABEL: Record<AnchorKey, string> = {
  mile: "Mile",
  fiveK: "5K",
  tenK: "10K",
  half: "Half",
  marathon: "Marathon",
};

// Order paces appear in the Race Paces table.
const RACE_ROW_ORDER: AnchorKey[] = ["mile", "fiveK", "tenK", "half", "marathon"];

interface Anchor {
  distance: AnchorKey;
  totalTimeSeconds: number;
}

// Resolve an anchor for the given mode. Returns null if the mode has no data
// (e.g. Projected without a snapshot, Goal without a goal set).
function resolveAnchor(
  mode: Mode,
  profile: PaceProfile | null,
  snapshot: FitnessSnapshot | null,
  custom: { distance: AnchorKey; timeString: string },
): Anchor | null {
  if (mode === "current") {
    if (!profile) return null;
    // Prefer marathon → half → 10K → 5K → mile.
    const candidates: Array<[AnchorKey, number | null]> = [
      ["marathon", profile.marathon_pace_seconds],
      ["half",     profile.half_pace_seconds],
      ["tenK",     profile.ten_k_pace_seconds],
      ["fiveK",    profile.five_k_pace_seconds],
      ["mile",     profile.mile_pace_seconds],
    ];
    for (const [dist, pace] of candidates) {
      if (pace == null) continue;
      return { distance: dist, totalTimeSeconds: pace * RACE_DISTANCE_MI[dist] };
    }
    return null;
  }

  if (mode === "projected") {
    if (!snapshot) return null;
    // Anchor on the marathon prediction; the ratio table derives everything else.
    return { distance: "marathon", totalTimeSeconds: snapshot.predicted_marathon_seconds };
  }

  if (mode === "goal") {
    if (!profile?.goal_race_distance || !profile.goal_time_seconds) return null;
    const dist = goalDistanceToAnchorKey(profile.goal_race_distance);
    if (!dist) return null;
    return { distance: dist, totalTimeSeconds: profile.goal_time_seconds };
  }

  // custom
  const seconds = parseTimeString(custom.timeString);
  if (seconds == null || seconds <= 0) return null;
  return { distance: custom.distance, totalTimeSeconds: seconds };
}

function goalDistanceToAnchorKey(raw: string): AnchorKey | null {
  const k = raw.toLowerCase();
  if (k === "marathon") return "marathon";
  if (k === "half" || k === "half_marathon") return "half";
  if (k === "10k") return "tenK";
  if (k === "5k") return "fiveK";
  if (k === "mile") return "mile";
  return null;
}

// Accept "H:MM:SS", "MM:SS", or "M:SS". For long distances (half/marathon),
// 2-part input is treated as H:MM, matching iOS PaceCalculator.parseTime.
function parseTimeString(raw: string): number | null {
  const parts = raw.trim().split(":").map((s) => parseInt(s, 10));
  if (parts.some((n) => Number.isNaN(n))) return null;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return null;
}

// Pace strings are always M:SS (sec/mile). 3-digit total seconds also accepted
// (e.g. "320" → 5:20).
function parsePaceString(raw: string): number | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  if (trimmed.includes(":")) {
    const parts = trimmed.split(":").map((s) => parseInt(s, 10));
    if (parts.some((n) => Number.isNaN(n))) return null;
    if (parts.length !== 2) return null;
    const total = parts[0] * 60 + parts[1];
    return total > 0 ? total : null;
  }
  const total = parseInt(trimmed, 10);
  if (Number.isNaN(total) || total <= 0) return null;
  return total;
}

// Training zone rows fall into two shapes:
//   - aerobic: a true range of effort (e.g., Steady is 100–90% MP speed).
//     Renders as "fast–slow/mi" with a band label like "100–90% MP".
//   - racePace: a single physiological target (MP, HM, LT, 10K, 5K, Mile).
//     Renders as a single pace; no range because race-pace work is meant
//     to hit a number, not negotiate a band.
type AerobicRow = {
  kind: "aerobic";
  label: string;
  description: string;
  fastSec: number;
  slowSec: number;
  bandLabel: string;
};
type RacePaceRow = {
  kind: "racePace";
  label: string;
  description: string;
  paceSec: number;
};
type TrainingZoneRow = AerobicRow | RacePaceRow;

interface DerivedTable {
  anchor: Anchor;
  racePaceSecPerMile: Record<AnchorKey, number>;
  raceTotalSeconds: Record<AnchorKey, number>;
  mpSecPerMile: number;
  trainingZones: TrainingZoneRow[];
}

function deriveTable(anchor: Anchor): DerivedTable {
  // base 10K time = anchor time / anchor ratio
  const base10K = anchor.totalTimeSeconds / RACE_RATIOS_TO_10K[anchor.distance];

  const raceTotalSeconds = {} as Record<AnchorKey, number>;
  const racePaceSecPerMile = {} as Record<AnchorKey, number>;
  for (const key of RACE_ROW_ORDER) {
    const t = base10K * RACE_RATIOS_TO_10K[key];
    raceTotalSeconds[key] = t;
    racePaceSecPerMile[key] = t / RACE_DISTANCE_MI[key];
  }

  const mp = racePaceSecPerMile.marathon;
  const hm = racePaceSecPerMile.half;

  // Aerobic zones built from the shared TRAINING_MP_SPEED_RANGE table.
  // Long Run is omitted from the display because its 85–75% band overlaps
  // both Moderate and Easy — the workout step editor lets coaches pick it
  // explicitly when they need it; the chart shows the four non-overlapping
  // core zones to avoid mixed signals.
  const aerobic = (key: "steady" | "moderate" | "easy" | "recovery", label: string, description: string): AerobicRow => {
    const band = TRAINING_MP_SPEED_RANGE[key];
    return {
      kind: "aerobic",
      label,
      description,
      fastSec: mp / band.fastRatio,
      slowSec: mp / band.slowRatio,
      bandLabel: band.bandLabel,
    };
  };

  const trainingZones: TrainingZoneRow[] = [
    aerobic("steady",   "Steady",   "marathon-minus, comfortably hard"),
    aerobic("moderate", "Moderate", "steady but working"),
    aerobic("easy",     "Easy",     "aerobic, conversational"),
    aerobic("recovery", "Recovery", "very easy, fully conversational"),
    { kind: "racePace", label: "MP",   description: "goal marathon pace",             paceSec: mp },
    { kind: "racePace", label: "HM",   description: "half marathon race effort",      paceSec: hm },
    { kind: "racePace", label: "LT",   description: "1-hour race pace / threshold",   paceSec: oneHourPaceSecPerMile(racePaceSecPerMile.tenK, hm) },
    { kind: "racePace", label: "10K",  description: "VO₂-adjacent",                   paceSec: racePaceSecPerMile.tenK },
    { kind: "racePace", label: "5K",   description: "VO₂ max",                        paceSec: racePaceSecPerMile.fiveK },
    { kind: "racePace", label: "Mile", description: "neuromuscular",                  paceSec: racePaceSecPerMile.mile },
  ];

  return { anchor, racePaceSecPerMile, raceTotalSeconds, mpSecPerMile: mp, trainingZones };
}

function formatPaceSec(totalSeconds: number): string {
  const t = Math.max(0, Math.round(totalSeconds));
  const m = Math.floor(t / 60);
  const s = t % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function formatFinishTime(totalSeconds: number): string {
  const t = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = t % 60;
  if (h > 0) {
    return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  }
  return `${m}:${s.toString().padStart(2, "0")}`;
}

interface ClientProps {
  profile: PaceProfile | null;
  snapshot: FitnessSnapshot | null;
}

export function PaceChartClient({ profile, snapshot }: ClientProps) {
  const projectedAvailable = !!snapshot;
  const goalAvailable = !!(profile?.goal_race_distance && profile.goal_time_seconds);

  // Default to Goal if available, else Current.
  const [mode, setModeRaw] = useState<Mode>(goalAvailable ? "goal" : "current");
  const [customDist, setCustomDist] = useState<AnchorKey>("marathon");
  const [customTime, setCustomTime] = useState<string>("");

  // Inline-edit override. When set, it takes precedence over the mode's
  // resolved anchor — the user typed a pace directly into one of the race
  // rows and the rest of the ladder is rederived from it. Switching modes
  // clears the override.
  const [override, setOverride] = useState<{ distance: AnchorKey; paceSecPerMile: number } | null>(null);

  const setMode = (m: Mode) => {
    setOverride(null);
    setModeRaw(m);
  };

  const baseAnchor = useMemo(
    () => resolveAnchor(mode, profile, snapshot, { distance: customDist, timeString: customTime }),
    [mode, profile, snapshot, customDist, customTime],
  );

  const anchor: Anchor | null = override
    ? {
        distance: override.distance,
        totalTimeSeconds: override.paceSecPerMile * RACE_DISTANCE_MI[override.distance],
      }
    : baseAnchor;

  const table = useMemo(() => (anchor ? deriveTable(anchor) : null), [anchor]);

  const commitPaceEdit = (key: AnchorKey, raw: string) => {
    const parsed = parsePaceString(raw);
    if (parsed == null) return; // invalid; caller reverts
    setOverride({ distance: key, paceSecPerMile: parsed });
  };

  // Change the anchor distance directly (Marathon → Half, etc.). The time
  // re-equivalents through the ratio table so total fitness stays the same;
  // the user can then tweak the time on the new distance if they want.
  const changeAnchorDistance = (nextDist: AnchorKey) => {
    if (!anchor) return;
    if (nextDist === anchor.distance) return;
    const base10K = anchor.totalTimeSeconds / RACE_RATIOS_TO_10K[anchor.distance];
    const nextTotalTime = base10K * RACE_RATIOS_TO_10K[nextDist];
    const nextPaceSec = nextTotalTime / RACE_DISTANCE_MI[nextDist];
    setOverride({ distance: nextDist, paceSecPerMile: nextPaceSec });
  };

  // Commit a new goal/anchor finish time. Distance stays put; the rest of
  // the ladder rederives.
  const commitAnchorTime = (raw: string) => {
    if (!anchor) return;
    const parsed = parseTimeString(raw);
    if (parsed == null || parsed <= 0) return;
    const paceSec = parsed / RACE_DISTANCE_MI[anchor.distance];
    setOverride({ distance: anchor.distance, paceSecPerMile: paceSec });
  };

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <div>
        <h1 className="font-display text-3xl text-text-primary">Pace Chart</h1>
        <p className="mt-1 font-body text-sm text-text-secondary">
          Pick an anchor — the rest of the chart is derived from it.
        </p>
      </div>

      <ModeToggle
        mode={mode}
        onChange={setMode}
        projectedAvailable={projectedAvailable}
        goalAvailable={goalAvailable}
      />

      {mode === "custom" && (
        <Card>
          <div className="flex flex-wrap items-end gap-3">
            <label className="flex flex-col gap-1">
              <span className="font-mono text-[11px] tracking-wider uppercase text-text-tertiary">
                Distance
              </span>
              <select
                value={customDist}
                onChange={(e) => setCustomDist(e.target.value as AnchorKey)}
                className="rounded border border-divider bg-transparent px-3 py-2 font-body text-sm text-text-primary focus:border-coral focus:outline-none"
              >
                {RACE_ROW_ORDER.map((k) => (
                  <option key={k} value={k}>{RACE_LABEL[k]}</option>
                ))}
              </select>
            </label>

            <label className="flex flex-col gap-1">
              <span className="font-mono text-[11px] tracking-wider uppercase text-text-tertiary">
                Time
              </span>
              <input
                type="text"
                value={customTime}
                onChange={(e) => setCustomTime(e.target.value)}
                placeholder={customDist === "marathon" || customDist === "half" ? "H:MM:SS" : "MM:SS"}
                className="rounded border border-divider bg-transparent px-3 py-2 font-mono text-sm text-text-primary placeholder:text-text-tertiary focus:border-coral focus:outline-none"
              />
            </label>

            <p className="ml-auto max-w-xs text-[11px] italic text-text-tertiary">
              Type a goal time at any distance and the full ladder rebuilds from it.
            </p>
          </div>
        </Card>
      )}

      {!table && (
        <Card>
          <p className="text-center text-sm italic text-text-tertiary">
            {mode === "projected"
              ? "No fitness snapshot yet. Generate a prediction on the Predictor page first."
              : mode === "goal"
              ? "No goal race set. Add one in your profile to see goal-based paces."
              : mode === "custom"
              ? "Pick a distance and enter a target time."
              : "No pace data yet. Pace profile is built from your fitness snapshots — complete a few runs and the chart will populate."}
          </p>
        </Card>
      )}

      {table && (
        <>
          <AnchorBanner
            mode={mode}
            anchor={table.anchor}
            profile={profile}
            snapshot={snapshot}
            modified={!!override}
            onReset={() => setOverride(null)}
            onChangeDistance={changeAnchorDistance}
            onCommitTime={commitAnchorTime}
          />

          <EditorialDivider />

          <RacePacesTable
            mode={mode}
            table={table}
            profile={profile}
            modified={!!override}
            onEditPace={commitPaceEdit}
          />

          <EditorialDivider />

          <TrainingZonesTable zones={table.trainingZones} />

          <Card>
            <p className="text-center text-[11px] italic text-text-tertiary">
              {override
                ? "Source: edited pace (this view only). Hit reset on the anchor to return to the source."
                : mode === "current"
                ? "Source: athlete_pace_profiles · regenerated whenever your fitness snapshot updates."
                : mode === "projected"
                ? `Source: latest fitness snapshot · ${snapshot ? formatDate(snapshot.created_at) : ""}`
                : mode === "goal"
                ? "Source: declared goal race + time."
                : "Source: custom anchor (this view only)."}
            </p>
          </Card>
        </>
      )}
    </div>
  );
}

function ModeToggle({
  mode,
  onChange,
  projectedAvailable,
  goalAvailable,
}: {
  mode: Mode;
  onChange: (m: Mode) => void;
  projectedAvailable: boolean;
  goalAvailable: boolean;
}) {
  const buttons: { key: Mode; label: string; disabled: boolean; hint?: string }[] = [
    { key: "goal",      label: "Goal",      disabled: !goalAvailable, hint: "from your declared goal race" },
    { key: "current",   label: "Current",   disabled: false, hint: "from your latest pace profile" },
    { key: "projected", label: "Projected", disabled: !projectedAvailable, hint: "from your latest fitness prediction" },
    { key: "custom",    label: "Custom",    disabled: false, hint: "pick any distance + time" },
  ];

  return (
    <div className="flex flex-wrap gap-2">
      {buttons.map((b) => {
        const active = mode === b.key;
        return (
          <button
            key={b.key}
            type="button"
            disabled={b.disabled}
            onClick={() => onChange(b.key)}
            title={b.hint}
            className={[
              "rounded-full border px-4 py-2 font-body text-xs tracking-wider uppercase transition-colors",
              active
                ? "border-coral bg-coral/10 text-coral"
                : b.disabled
                ? "cursor-not-allowed border-divider text-text-tertiary opacity-50"
                : "border-divider text-text-secondary hover:border-coral hover:text-coral",
            ].join(" ")}
          >
            {b.label}
          </button>
        );
      })}
    </div>
  );
}

function AnchorBanner({
  mode,
  anchor,
  profile,
  snapshot,
  modified,
  onReset,
  onChangeDistance,
  onCommitTime,
}: {
  mode: Mode;
  anchor: Anchor;
  profile: PaceProfile | null;
  snapshot: FitnessSnapshot | null;
  modified: boolean;
  onReset: () => void;
  onChangeDistance: (next: AnchorKey) => void;
  onCommitTime: (raw: string) => void;
}) {
  const labelByMode: Record<Mode, string> = {
    current:   "Anchor (current)",
    projected: "Anchor (projected fitness)",
    goal:      "Anchor (goal race)",
    custom:    "Anchor (custom)",
  };

  const sourceNote =
    mode === "current"
      ? profile?.generated_at
        ? `updated ${formatDate(profile.generated_at)}`
        : ""
      : mode === "projected"
      ? snapshot
        ? `predicted ${formatDate(snapshot.created_at)} · ${snapshot.confidence.toLowerCase()} confidence`
        : ""
      : "";

  return (
    <Card accent>
      <div className="flex items-baseline justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="font-mono text-[11px] tracking-wider uppercase text-text-tertiary">
              {labelByMode[mode]}
            </span>
            {modified && (
              <button
                type="button"
                onClick={onReset}
                className="rounded-full border border-coral/40 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-coral hover:bg-coral/10"
                title="Reset to source value"
              >
                edited · reset
              </button>
            )}
          </div>
          <div className="mt-1">
            <select
              value={anchor.distance}
              onChange={(e) => onChangeDistance(e.target.value as AnchorKey)}
              className="rounded border border-divider bg-transparent px-2 py-1 font-display text-lg text-text-primary hover:border-coral focus:border-coral focus:outline-none"
              title="Change anchor distance — time will rederive from the ratio table"
            >
              {RACE_ROW_ORDER.map((k) => (
                <option key={k} value={k}>{RACE_LABEL[k]}</option>
              ))}
            </select>
          </div>
          {sourceNote && !modified && (
            <div className="mt-1 font-mono text-[11px] text-text-tertiary">
              {sourceNote}
            </div>
          )}
        </div>
        <div className="text-right">
          <div className="font-mono text-[11px] tracking-wider uppercase text-text-tertiary">
            Time
          </div>
          <div className="mt-1">
            <EditableFinishTime
              totalSeconds={anchor.totalTimeSeconds}
              onCommit={onCommitTime}
            />
          </div>
        </div>
      </div>
    </Card>
  );
}

function EditableFinishTime({
  totalSeconds,
  onCommit,
}: {
  totalSeconds: number;
  onCommit: (raw: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");

  const display = formatFinishTime(totalSeconds);

  if (!editing) {
    return (
      <button
        type="button"
        onClick={() => {
          setDraft(display);
          setEditing(true);
        }}
        className="font-mono text-lg text-coral underline decoration-dotted underline-offset-4 hover:text-coral/80"
        title="Click to edit goal time"
      >
        {display}
      </button>
    );
  }

  const commit = () => {
    if (draft.trim() && draft !== display) onCommit(draft);
    setEditing(false);
  };

  return (
    <input
      autoFocus
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === "Enter") (e.target as HTMLInputElement).blur();
        else if (e.key === "Escape") setEditing(false);
      }}
      placeholder="H:MM:SS"
      className="w-32 rounded border border-coral bg-transparent px-2 py-1 text-right font-mono text-lg text-coral focus:outline-none"
    />
  );
}

function RacePacesTable({
  mode,
  table,
  profile,
  modified,
  onEditPace,
}: {
  mode: Mode;
  table: DerivedTable;
  profile: PaceProfile | null;
  modified: boolean;
  onEditPace: (key: AnchorKey, raw: string) => void;
}) {
  // Show stored DB pace + confidence per row only in Current mode without an
  // active edit override. Once the user has typed a new pace, the table is
  // fully derived from that override and showing per-row stored values would
  // contradict the displayed time column.
  const useStored = mode === "current" && profile && !modified;

  return (
    <div>
      <SectionHeader title="Race Paces" />
      <p className="mt-1 px-4 text-[11px] italic text-text-tertiary">
        Click any pace to edit. The rest of the ladder rebuilds from it.
      </p>
      <Card className="mt-4" padding="sm">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-divider">
              <Th align="left">Distance</Th>
              <Th align="right">Pace /mi</Th>
              <Th align="right">Est. time</Th>
              {useStored && <Th align="right">Conf.</Th>}
            </tr>
          </thead>
          <tbody className="divide-y divide-divider">
            {RACE_ROW_ORDER.map((k) => {
              const derivedPace = table.racePaceSecPerMile[k];
              const derivedTime = table.raceTotalSeconds[k];

              const storedPace = useStored ? storedPaceFor(profile, k) : null;
              const conf = useStored ? storedConfFor(profile, k) : null;

              const pace = storedPace ?? derivedPace;
              const time = storedPace ? storedPace * RACE_DISTANCE_MI[k] : derivedTime;

              return (
                <tr key={k}>
                  <td className="px-4 py-3 font-medium text-text-primary">
                    {RACE_LABEL[k]}
                  </td>
                  <td className="px-4 py-1 text-right">
                    <EditablePaceCell
                      paceSec={pace}
                      onCommit={(raw) => onEditPace(k, raw)}
                    />
                  </td>
                  <td className="px-4 py-3 text-right font-mono text-text-secondary">
                    {formatFinishTime(time)}
                  </td>
                  {useStored && (
                    <td className="px-4 py-3 text-right font-mono text-[11px] text-text-tertiary uppercase tracking-wider">
                      {conf ?? "—"}
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </Card>
    </div>
  );
}

function EditablePaceCell({
  paceSec,
  onCommit,
}: {
  paceSec: number;
  onCommit: (raw: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");

  const display = formatPaceSec(paceSec);

  if (!editing) {
    return (
      <button
        type="button"
        onClick={() => {
          setDraft(display);
          setEditing(true);
        }}
        className="font-mono text-coral underline decoration-dotted underline-offset-4 hover:text-coral/80"
        title="Click to edit"
      >
        {display}
      </button>
    );
  }

  const commit = () => {
    if (draft.trim() && draft !== display) {
      onCommit(draft);
    }
    setEditing(false);
  };

  return (
    <input
      autoFocus
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          (e.target as HTMLInputElement).blur();
        } else if (e.key === "Escape") {
          setEditing(false);
        }
      }}
      placeholder="M:SS"
      className="w-20 rounded border border-coral bg-transparent px-2 py-1 text-right font-mono text-coral focus:outline-none"
    />
  );
}

function TrainingZonesTable({
  zones,
}: {
  zones: TrainingZoneRow[];
}) {
  return (
    <div>
      <SectionHeader title="Training Zones" />
      <Card className="mt-4" padding="sm">
        <p className="px-4 pt-3 text-[11px] text-text-tertiary italic">
          Aerobic zones (Steady → Recovery) are bands of marathon-pace
          speed — coaches reason about them as ranges of effort, not exact
          paces. Race-pace zones (MP, HM, LT, 10K, 5K, Mile) are single
          targets you&apos;re meant to hit, not negotiate.
        </p>
        <table className="w-full text-sm mt-2">
          <tbody className="divide-y divide-divider">
            {zones.map((row) =>
              row.kind === "aerobic" ? (
                <tr key={row.label}>
                  <td className="px-4 py-3 align-top">
                    <div className="font-medium text-text-primary">{row.label}</div>
                    <div className="text-[11px] text-text-tertiary">{row.description}</div>
                  </td>
                  <td className="px-4 py-3 text-right align-top">
                    <div className="font-mono text-coral">
                      {formatPaceSec(row.fastSec)}–{formatPaceSec(row.slowSec)}
                      <span className="text-text-tertiary">/mi</span>
                    </div>
                    <div className="text-[11px] text-text-tertiary font-mono tabular-nums">
                      {row.bandLabel}
                    </div>
                  </td>
                </tr>
              ) : (
                <tr key={row.label}>
                  <td className="px-4 py-3 align-top">
                    <div className="font-medium text-text-primary">{row.label}</div>
                    <div className="text-[11px] text-text-tertiary">{row.description}</div>
                  </td>
                  <td className="px-4 py-3 text-right align-top">
                    <div className="font-mono text-coral">
                      {formatPaceSec(row.paceSec)}
                      <span className="text-text-tertiary">/mi</span>
                    </div>
                  </td>
                </tr>
              ),
            )}
          </tbody>
        </table>
      </Card>
    </div>
  );
}

function Th({ children, align }: { children: React.ReactNode; align: "left" | "right" }) {
  return (
    <th
      className={`px-4 py-3 font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary ${
        align === "left" ? "text-left" : "text-right"
      }`}
    >
      {children}
    </th>
  );
}

function storedPaceFor(p: PaceProfile, k: AnchorKey): number | null {
  switch (k) {
    case "mile":     return p.mile_pace_seconds;
    case "fiveK":    return p.five_k_pace_seconds;
    case "tenK":     return p.ten_k_pace_seconds;
    case "half":     return p.half_pace_seconds;
    case "marathon": return p.marathon_pace_seconds;
  }
}

function storedConfFor(p: PaceProfile, k: AnchorKey): string | null {
  switch (k) {
    case "mile":     return p.mile_pace_confidence;
    case "fiveK":    return p.five_k_pace_confidence;
    case "tenK":     return p.ten_k_pace_confidence;
    case "half":     return p.half_pace_confidence;
    case "marathon": return p.marathon_pace_confidence;
  }
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";
import {
  formatDuration,
  formatDate,
  MOOD_CONFIG,
  WORKOUT_TYPE_CONFIG,
} from "@/lib/utils";
import type { TrainingLog } from "@/lib/types";

const WORKOUT_TYPES = [
  "easy",
  "tempo",
  "interval",
  "long_run",
  "recovery",
  "race",
  "other",
];

const MOODS = [
  "energized",
  "positive",
  "neutral",
  "tired",
  "struggling",
  "injured",
];

export function TrainingLogList({
  initialLogs,
}: {
  initialLogs: TrainingLog[];
}) {
  const [logs, setLogs] = useState(initialLogs);

  function handleUpdate(updated: TrainingLog) {
    setLogs((prev) => prev.map((l) => (l.id === updated.id ? updated : l)));
  }

  return (
    <div className="space-y-4">
      {logs.map((log) => (
        <LogCard key={log.id} log={log} onUpdate={handleUpdate} />
      ))}
    </div>
  );
}

function LogCard({
  log,
  onUpdate,
}: {
  log: TrainingLog;
  onUpdate: (log: TrainingLog) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [draft, setDraft] = useState(log);

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  function startEdit() {
    setDraft(log);
    setEditing(true);
  }

  function cancel() {
    setEditing(false);
    setDraft(log);
  }

  async function save() {
    setSaving(true);
    const { error } = await supabase
      .from("training_logs")
      .update({
        workout_type: draft.workout_type,
        workout_distance_miles: draft.workout_distance_miles,
        workout_duration_minutes: draft.workout_duration_minutes,
        workout_pace_per_mile: draft.workout_pace_per_mile,
        mood: draft.mood,
        cleaned_notes: draft.cleaned_notes,
        workout_notes: draft.workout_notes,
      })
      .eq("id", log.id);

    setSaving(false);
    if (!error) {
      onUpdate(draft);
      setEditing(false);
    }
  }

  const dateStr = formatDate(log.workout_date || log.created_at);
  const type = (editing ? draft.workout_type : log.workout_type) || "other";
  const typeConfig = WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
  const moodKey = editing ? draft.mood : log.mood;
  const mood = moodKey ? MOOD_CONFIG[moodKey] : null;
  const display = editing ? draft : log;
  const isRace = type === "race";
  const isInjured = moodKey === "injured";

  return (
    <div
      className={`rounded-xl border bg-bg-card p-5 space-y-4 ${
        editing
          ? "border-coral/60 ring-1 ring-coral/20"
          : isRace
          ? "border-coral/40"
          : isInjured
          ? "border-mood-injured/40"
          : "border-bg-elevated"
      }`}
    >
      {/* Header row */}
      <div className="flex items-center gap-3">
        <span className="font-mono text-sm text-text-tertiary">{dateStr}</span>
        {isRace && <span className="text-sm">🏁</span>}

        {editing ? (
          <select
            value={draft.workout_type || "other"}
            onChange={(e) =>
              setDraft({ ...draft, workout_type: e.target.value })
            }
            className="rounded-md border border-bg-elevated bg-bg-elevated px-2 py-0.5 text-xs font-medium text-text-primary outline-none focus:border-coral/50"
          >
            {WORKOUT_TYPES.map((t) => (
              <option key={t} value={t}>
                {(WORKOUT_TYPE_CONFIG[t] || WORKOUT_TYPE_CONFIG.other).label}
              </option>
            ))}
          </select>
        ) : (
          <span
            className={`rounded-md px-2 py-0.5 text-xs font-medium ${typeConfig.colorClass}`}
          >
            {typeConfig.label}
          </span>
        )}

        {/* Stats or edit fields */}
        <div className="ml-auto flex items-center gap-3 font-mono text-sm">
          {editing ? (
            <>
              <input
                type="number"
                step="0.1"
                value={draft.workout_distance_miles ?? ""}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    workout_distance_miles: e.target.value
                      ? parseFloat(e.target.value)
                      : null,
                  })
                }
                placeholder="mi"
                className="w-16 rounded border border-bg-elevated bg-bg-elevated px-2 py-0.5 text-right text-xs text-text-primary outline-none focus:border-coral/50"
              />
              <input
                type="text"
                value={draft.workout_pace_per_mile ?? ""}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    workout_pace_per_mile: e.target.value || null,
                  })
                }
                placeholder="/mi"
                className="w-20 rounded border border-bg-elevated bg-bg-elevated px-2 py-0.5 text-right text-xs text-text-primary outline-none focus:border-coral/50"
              />
              <input
                type="number"
                step="0.1"
                value={draft.workout_duration_minutes ?? ""}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    workout_duration_minutes: e.target.value
                      ? parseFloat(e.target.value)
                      : null,
                  })
                }
                placeholder="min"
                className="w-16 rounded border border-bg-elevated bg-bg-elevated px-2 py-0.5 text-right text-xs text-text-primary outline-none focus:border-coral/50"
              />
              <select
                value={draft.mood || ""}
                onChange={(e) =>
                  setDraft({ ...draft, mood: e.target.value || null })
                }
                className="rounded border border-bg-elevated bg-bg-elevated px-2 py-0.5 text-xs text-text-primary outline-none focus:border-coral/50"
              >
                <option value="">Mood</option>
                {MOODS.map((m) => (
                  <option key={m} value={m}>
                    {MOOD_CONFIG[m]?.emoji} {MOOD_CONFIG[m]?.label}
                  </option>
                ))}
              </select>
            </>
          ) : (
            <>
              {display.workout_distance_miles ? (
                <span className="font-medium text-text-primary">
                  {display.workout_distance_miles.toFixed(1)} mi
                </span>
              ) : null}
              {display.workout_pace_per_mile ? (
                <span className="text-text-secondary">
                  {display.workout_pace_per_mile}
                </span>
              ) : null}
              {display.workout_duration_minutes ? (
                <span className="text-text-tertiary">
                  {formatDuration(display.workout_duration_minutes)}
                </span>
              ) : null}
              {mood && (
                <span className={mood.colorClass} title={mood.label}>
                  {mood.emoji}
                </span>
              )}
            </>
          )}
        </div>
      </div>

      {/* Notes */}
      {editing ? (
        <div>
          <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
            NOTES
          </h3>
          <textarea
            value={draft.cleaned_notes ?? ""}
            onChange={(e) =>
              setDraft({ ...draft, cleaned_notes: e.target.value || null })
            }
            rows={3}
            className="w-full rounded-lg border border-bg-elevated bg-bg-elevated px-3 py-2 text-sm leading-relaxed text-text-primary outline-none placeholder-text-tertiary focus:border-coral/50"
            placeholder="Add notes..."
          />
        </div>
      ) : (
        display.cleaned_notes && (
          <div>
            <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
              NOTES
            </h3>
            <p className="text-sm leading-relaxed text-text-secondary">
              {display.cleaned_notes}
            </p>
          </div>
        )
      )}

      {/* Coach Insight (read-only — AI generated) */}
      {display.coach_insight && (
        <div>
          <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
            🧠 COACH INSIGHT
          </h3>
          <div className="rounded-lg bg-bg-elevated px-4 py-3">
            <p className="text-sm leading-relaxed text-text-secondary">
              {display.coach_insight}
            </p>
          </div>
        </div>
      )}

      {/* Workout Details */}
      {editing ? (
        <div>
          <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
            🏃 WORKOUT DETAILS
          </h3>
          <textarea
            value={draft.workout_notes ?? ""}
            onChange={(e) =>
              setDraft({ ...draft, workout_notes: e.target.value || null })
            }
            rows={2}
            className="w-full rounded-lg border border-bg-elevated bg-bg-elevated px-3 py-2 font-mono text-xs leading-relaxed text-text-primary outline-none placeholder-text-tertiary focus:border-coral/50"
            placeholder="Splits, intervals, structure..."
          />
        </div>
      ) : (
        display.workout_notes && (
          <div>
            <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
              🏃 WORKOUT DETAILS
            </h3>
            <div className="rounded-lg bg-bg-elevated px-4 py-3">
              <p className="whitespace-pre-wrap font-mono text-xs leading-relaxed text-text-secondary">
                {display.workout_notes}
              </p>
            </div>
          </div>
        )
      )}

      {/* Extracted Data (read-only) */}
      {!editing &&
        display.extracted_data &&
        Object.keys(display.extracted_data).length > 0 && (
          <ExtractedDataSection data={display.extracted_data} />
        )}

      {/* Raw transcript (read-only) */}
      {!editing && display.notes && display.notes !== display.cleaned_notes && (
        <div>
          <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
            📄 FULL TRANSCRIPT
          </h3>
          <div className="rounded-lg bg-bg-elevated px-4 py-3">
            <p className="whitespace-pre-wrap text-xs italic leading-relaxed text-text-tertiary">
              &ldquo;{display.notes}&rdquo;
            </p>
          </div>
        </div>
      )}

      {/* Action buttons */}
      <div className="flex items-center gap-2 border-t border-bg-elevated pt-3">
        {editing ? (
          <>
            <button
              onClick={save}
              disabled={saving}
              className="rounded-lg bg-coral px-4 py-1.5 font-mono text-xs font-medium text-white transition-colors hover:bg-coral-light disabled:opacity-50"
            >
              {saving ? "Saving..." : "Save"}
            </button>
            <button
              onClick={cancel}
              disabled={saving}
              className="rounded-lg bg-bg-elevated px-4 py-1.5 font-mono text-xs text-text-secondary transition-colors hover:text-text-primary"
            >
              Cancel
            </button>
          </>
        ) : (
          <button
            onClick={startEdit}
            className="font-mono text-xs text-text-tertiary transition-colors hover:text-coral"
          >
            Edit
          </button>
        )}
      </div>
    </div>
  );
}

// --- Extracted data section (read-only) ---

interface IntervalData {
  rest?: string;
  time?: string;
  count?: number;
  distance?: string;
  pace?: string;
}

interface SplitData {
  mile?: number;
  pace?: string;
  time?: string;
}

function ExtractedDataSection({ data }: { data: Record<string, unknown> }) {
  const splits = data.splits as (string | SplitData)[] | undefined;
  const intervals = data.intervals as (string | IntervalData)[] | undefined;
  const warmup = data.warmup as string | undefined;
  const cooldown = data.cooldown as string | undefined;
  const effortLevel = data.effort_level as string | undefined;
  const injuredArea = data.injured_area as string | undefined;

  const hasContent =
    splits?.length ||
    intervals?.length ||
    warmup ||
    cooldown ||
    effortLevel ||
    injuredArea;
  if (!hasContent) return null;

  return (
    <div>
      <h3 className="mb-1.5 font-mono text-[10px] tracking-widest text-text-tertiary">
        📊 STRUCTURED DATA
      </h3>
      <div className="rounded-lg bg-bg-elevated px-4 py-3 space-y-2">
        {effortLevel && (
          <div className="flex gap-2 text-xs">
            <span className="text-text-tertiary">Effort:</span>
            <span className="text-text-secondary">{effortLevel}</span>
          </div>
        )}
        {injuredArea && (
          <div className="flex gap-2 text-xs">
            <span className="text-text-tertiary">Injury noted:</span>
            <span className="text-mood-injured">{injuredArea}</span>
          </div>
        )}
        {warmup && (
          <div className="flex gap-2 text-xs">
            <span className="text-text-tertiary">Warmup:</span>
            <span className="text-text-secondary">{warmup}</span>
          </div>
        )}
        {cooldown && (
          <div className="flex gap-2 text-xs">
            <span className="text-text-tertiary">Cooldown:</span>
            <span className="text-text-secondary">{cooldown}</span>
          </div>
        )}
        {splits && splits.length > 0 && (
          <div className="text-xs">
            <span className="text-text-tertiary">Splits:</span>
            <div className="mt-1 flex flex-wrap gap-2">
              {splits.map((split, i) => (
                <span
                  key={i}
                  className="rounded bg-bg-card px-2 py-0.5 font-mono text-text-secondary"
                >
                  {formatItem(split)}
                </span>
              ))}
            </div>
          </div>
        )}
        {intervals && intervals.length > 0 && (
          <div className="text-xs">
            <span className="text-text-tertiary">Intervals:</span>
            <div className="mt-1 flex flex-wrap gap-2">
              {intervals.map((interval, i) => (
                <span
                  key={i}
                  className="rounded bg-bg-card px-2 py-0.5 font-mono text-text-secondary"
                >
                  {formatItem(interval)}
                </span>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function formatItem(item: string | SplitData | IntervalData): string {
  if (typeof item === "string") return item;
  const obj = item as Record<string, unknown>;
  const parts: string[] = [];
  if (obj.count) parts.push(`${obj.count}x`);
  if (obj.distance) parts.push(String(obj.distance));
  if (obj.time) parts.push(`@ ${obj.time}`);
  if (obj.pace) parts.push(`@ ${obj.pace}`);
  if (obj.rest) parts.push(`(${obj.rest} rest)`);
  if (obj.mile) parts.push(`Mi ${obj.mile}`);
  return parts.length > 0 ? parts.join(" ") : JSON.stringify(item);
}

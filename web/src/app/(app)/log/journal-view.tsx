"use client";

import { useState, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";
import type { TrainingLog } from "@/lib/types";
import { formatDuration, MOOD_CONFIG, WORKOUT_TYPE_CONFIG } from "@/lib/utils";
import { WorkoutDetail } from "./workout-detail";

// ─── Group logs by month ─────────────────────────────────────

function groupByMonth(logs: TrainingLog[]) {
  const map = new Map<string, TrainingLog[]>();

  for (const log of logs) {
    const d = new Date(log.workout_date || log.created_at);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(log);
  }

  return Array.from(map.entries())
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([key, entries]) => {
      const d = new Date(entries[0].workout_date || entries[0].created_at);
      return {
        key,
        month: d.toLocaleDateString("en-US", { month: "long" }),
        year: d.getFullYear().toString(),
        entries,
      };
    });
}

// ─── Main Journal View ───────────────────────────────────────

export function JournalView({ logs: initialLogs }: { logs: TrainingLog[] }) {
  const [logs, setLogs] = useState(initialLogs);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [liveIndicator, setLiveIndicator] = useState<string | null>(null);

  const months = groupByMonth(logs);

  // Realtime subscription — new inserts, updates (processing complete), deletes
  useEffect(() => {
    const supabase = createClient();
    let channel: ReturnType<typeof supabase.channel> | null = null;

    supabase.auth.getUser().then(({ data: { user } }) => {
      if (!user) return;
      const userId = user.id;

      channel = supabase
        .channel("training-logs-realtime")
        .on(
          "postgres_changes",
          { event: "INSERT", schema: "public", table: "training_logs", filter: `user_id=eq.${userId}` },
          (payload) => {
            const newLog = payload.new as TrainingLog;
            if (newLog.source === "auto_sync") return;
            setLogs((prev) => {
              if (prev.some((l) => l.id === newLog.id)) return prev;
              const updated = [newLog, ...prev];
              updated.sort((a, b) => new Date(b.workout_date || b.created_at).getTime() - new Date(a.workout_date || a.created_at).getTime());
              return updated;
            });
            setLiveIndicator("New entry added");
            setTimeout(() => setLiveIndicator(null), 3000);
          }
        )
        .on(
          "postgres_changes",
          { event: "UPDATE", schema: "public", table: "training_logs", filter: `user_id=eq.${userId}` },
          (payload) => {
            const updated = payload.new as TrainingLog;
            setLogs((prev) => prev.map((l) => (l.id === updated.id ? { ...l, ...updated } : l)));
            if (updated.processing_status === "completed" && updated.cleaned_notes) {
              setLiveIndicator("Voice memo processed");
              setTimeout(() => setLiveIndicator(null), 3000);
            }
          }
        )
        .on(
          "postgres_changes",
          { event: "DELETE", schema: "public", table: "training_logs" },
          (payload) => {
            const deletedId = (payload.old as { id: string }).id;
            setLogs((prev) => prev.filter((l) => l.id !== deletedId));
          }
        )
        .subscribe();
    });

    return () => {
      if (channel) supabase.removeChannel(channel);
    };
  }, []);

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <header className="mb-12 text-center">
        <h1 className="font-display text-5xl tracking-tight text-text-primary">
          Training Journal
        </h1>
        <div className="mt-3 flex items-center justify-center gap-3">
          <span className="h-px w-12 bg-coral" />
          <span className="font-mono text-[10px] tracking-[0.3em] text-text-tertiary uppercase">
            {logs.length} entries
          </span>
          <span className="h-px w-12 bg-coral" />
        </div>

        {/* Live sync indicator */}
        {liveIndicator && (
          <div className="mt-4 inline-flex items-center gap-2 rounded-full bg-mood-energized/10 px-3 py-1">
            <span className="h-1.5 w-1.5 rounded-full bg-mood-energized animate-pulse" />
            <span className="font-mono text-[10px] text-mood-energized">
              {liveIndicator}
            </span>
          </div>
        )}
      </header>

      {logs.length === 0 ? (
        <div className="py-20 text-center">
          <p className="font-display text-xl text-text-tertiary">No entries yet</p>
          <p className="mt-2 text-sm text-text-tertiary">
            Record a voice memo or log a run from the app.
          </p>
        </div>
      ) : (
        <div className="space-y-16">
          {months.map((group) => (
            <section key={group.key}>
              <div className="mb-8 flex items-center gap-4">
                <span className="h-px flex-1 bg-divider" />
                <h2 className="font-display text-lg tracking-wide text-text-tertiary">
                  {group.month} {group.year}
                </h2>
                <span className="h-px flex-1 bg-divider" />
              </div>

              <div className="space-y-0">
                {group.entries.map((log, i) => (
                  <JournalEntry
                    key={log.id}
                    log={log}
                    isExpanded={expandedId === log.id}
                    onToggle={() =>
                      setExpandedId(expandedId === log.id ? null : log.id)
                    }
                    onUpdate={(updated) =>
                      setLogs((prev) => prev.map((l) => (l.id === updated.id ? updated : l)))
                    }
                    onDelete={(id) =>
                      setLogs((prev) => prev.filter((l) => l.id !== id))
                    }
                    isLast={i === group.entries.length - 1}
                  />
                ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Journal Entry ───────────────────────────────────────────

function JournalEntry({
  log,
  isExpanded,
  onToggle,
  onUpdate,
  onDelete,
  isLast,
}: {
  log: TrainingLog;
  isExpanded: boolean;
  onToggle: () => void;
  onUpdate: (updated: TrainingLog) => void;
  onDelete: (id: string) => void;
  isLast: boolean;
}) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [draft, setDraft] = useState(log);

  // Sync draft when log updates via realtime
  useEffect(() => { if (!editing) setDraft(log); }, [log, editing]);

  const d = new Date(log.workout_date || log.created_at);
  const dayName = d.toLocaleDateString("en-US", { weekday: "long" });
  const dayNum = d.getDate();
  const monthShort = d.toLocaleDateString("en-US", { month: "short" });
  const display = editing ? draft : log;
  const type = display.workout_type || "easy";
  const typeConfig = WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
  const moodKey = display.mood;
  const mood = moodKey ? MOOD_CONFIG[moodKey] : null;
  const notes = display.cleaned_notes || display.notes;
  const isProcessing = log.processing_status === "pending" || log.processing_status === "processing";
  const isCheckIn = log.source === "check_in";
  const ext = log.extracted_data as Record<string, unknown> | null;
  const readinessScore = ext?.readiness_score as number | null;
  const recommendationType = ext?.recommendation_type as string | null;
  const sorenessAreas = ext?.soreness_areas as string[] | null;
  const energyLevel = ext?.energy_level as string | null;
  const sleepQuality = ext?.sleep_quality as string | null;

  async function save() {
    setSaving(true);
    const supabase = createClient();
    const { error } = await supabase
      .from("training_logs")
      .update({
        cleaned_notes: draft.cleaned_notes,
        workout_notes: draft.workout_notes,
        workout_type: draft.workout_type,
        mood: draft.mood,
        workout_distance_miles: draft.workout_distance_miles,
        workout_duration_minutes: draft.workout_duration_minutes,
      })
      .eq("id", log.id);

    setSaving(false);
    if (!error) {
      onUpdate(draft);
      setEditing(false);
    }
  }

  async function handleDelete() {
    const supabase = createClient();
    const { error } = await supabase
      .from("training_logs")
      .delete()
      .eq("id", log.id);

    if (!error) {
      onDelete(log.id);
    }
    setShowDeleteConfirm(false);
  }

  async function retryProcessing() {
    setRetrying(true);
    try {
      const res = await fetch("/api/retry-processing", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ logId: log.id }),
      });
      const data = await res.json();
      if (data.success) {
        onUpdate({ ...log, processing_status: "processing" });
      }
    } catch {}
    setRetrying(false);
  }

  return (
    <article
      className={`group cursor-pointer ${!isLast ? "border-b border-divider" : ""}`}
      onClick={onToggle}
    >
      <div className="py-6">
        {/* Date + type header */}
        <div className="flex items-baseline gap-3">
          <div className="flex items-baseline gap-2">
            <span className="font-display text-3xl leading-none text-text-primary">
              {dayName}
            </span>
            <span className="font-mono text-xs text-text-tertiary">
              {monthShort} {dayNum}
            </span>
          </div>

          <div className="ml-auto flex items-center gap-3">
            {isCheckIn ? (
              <span className="rounded-md px-2.5 py-1 text-[10px] font-medium tracking-wide uppercase bg-mood-positive/10 text-mood-positive">
                Check-In
              </span>
            ) : editing ? (
              <select
                value={draft.workout_type || "easy"}
                onChange={(e) => setDraft({ ...draft, workout_type: e.target.value })}
                onClick={(e) => e.stopPropagation()}
                className="rounded-md border border-divider bg-bg-elevated px-2 py-1 text-[10px] font-medium text-text-primary outline-none"
              >
                {["easy", "tempo", "interval", "long_run", "recovery", "race", "progression", "strides"].map((t) => (
                  <option key={t} value={t}>{(WORKOUT_TYPE_CONFIG[t] || WORKOUT_TYPE_CONFIG.other).label}</option>
                ))}
              </select>
            ) : (
              <span className={`rounded-md px-2.5 py-1 text-[10px] font-medium tracking-wide uppercase ${typeConfig.colorClass}`}>
                {typeConfig.label}
              </span>
            )}

            {readinessScore != null && (
              <span className={`rounded-md px-2 py-1 text-[10px] font-medium ${
                readinessScore >= 7 ? "bg-mood-positive/10 text-mood-positive" :
                readinessScore >= 4 ? "bg-mood-tired/10 text-mood-tired" :
                "bg-mood-struggling/10 text-mood-struggling"
              }`}>
                {readinessScore}/10
              </span>
            )}

            {editing ? (
              <select
                value={draft.mood || ""}
                onChange={(e) => setDraft({ ...draft, mood: e.target.value || null })}
                onClick={(e) => e.stopPropagation()}
                className="rounded-md border border-divider bg-bg-elevated px-2 py-1 text-[10px] text-text-primary outline-none"
              >
                <option value="">No mood</option>
                {["energized", "positive", "neutral", "tired", "struggling", "injured"].map((m) => (
                  <option key={m} value={m}>{MOOD_CONFIG[m]?.label}</option>
                ))}
              </select>
            ) : mood ? (
              <span className={`rounded-md px-2 py-0.5 text-[10px] font-medium tracking-wide uppercase ${mood.colorClass}`} style={{ backgroundColor: `color-mix(in srgb, currentColor 10%, transparent)` }}>
                {mood.label}
              </span>
            ) : null}
          </div>
        </div>

        {/* Check-in context badges */}
        {isCheckIn && !editing && (sorenessAreas?.length || energyLevel || sleepQuality) && (
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {energyLevel && (
              <span className="rounded-full bg-bg-elevated px-2.5 py-1 font-mono text-[10px] text-text-secondary">
                Energy: {energyLevel}
              </span>
            )}
            {sleepQuality && (
              <span className="rounded-full bg-bg-elevated px-2.5 py-1 font-mono text-[10px] text-text-secondary">
                Sleep: {sleepQuality}
              </span>
            )}
            {sorenessAreas?.map((area) => (
              <span key={area} className="rounded-full bg-mood-struggling/10 px-2.5 py-1 font-mono text-[10px] text-mood-struggling">
                {area}
              </span>
            ))}
            {recommendationType && recommendationType !== "proceed" && (
              <span className={`rounded-full px-2.5 py-1 font-mono text-[10px] font-medium ${
                recommendationType === "rest" ? "bg-mood-struggling/10 text-mood-struggling" :
                recommendationType === "modify" ? "bg-mood-tired/10 text-mood-tired" :
                recommendationType === "medical" ? "bg-mood-injured/10 text-mood-injured" :
                "bg-bg-elevated text-text-secondary"
              }`}>
                {recommendationType}
              </span>
            )}
          </div>
        )}

        {/* Stats line */}
        <div className="mt-3 flex items-center gap-4 font-mono text-sm">
          {editing ? (
            <>
              <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                <input
                  type="number"
                  step="0.1"
                  value={draft.workout_distance_miles ?? ""}
                  onChange={(e) => setDraft({ ...draft, workout_distance_miles: e.target.value ? parseFloat(e.target.value) : null })}
                  placeholder="mi"
                  className="w-14 rounded border border-divider bg-bg-elevated px-2 py-0.5 text-right text-xs text-text-primary outline-none"
                />
                <span className="text-xs text-text-tertiary">mi</span>
              </div>
              <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                <input
                  type="number"
                  step="0.1"
                  value={draft.workout_duration_minutes ?? ""}
                  onChange={(e) => setDraft({ ...draft, workout_duration_minutes: e.target.value ? parseFloat(e.target.value) : null })}
                  placeholder="min"
                  className="w-14 rounded border border-divider bg-bg-elevated px-2 py-0.5 text-right text-xs text-text-primary outline-none"
                />
                <span className="text-xs text-text-tertiary">min</span>
              </div>
            </>
          ) : (
            <>
              {display.workout_distance_miles && (
                <span className="font-medium text-text-primary">
                  {display.workout_distance_miles.toFixed(1)} mi
                </span>
              )}
              {display.workout_duration_minutes && (
                <span className="text-text-secondary">
                  {formatDuration(display.workout_duration_minutes)}
                </span>
              )}
              {display.workout_distance_miles && display.workout_duration_minutes && (
                <span className="text-text-tertiary">
                  {computePace(display.workout_distance_miles, display.workout_duration_minutes)}/mi avg
                </span>
              )}
              {display.workout_pace_per_mile && display.workout_distance_miles && display.workout_duration_minutes &&
                display.workout_pace_per_mile !== computePace(display.workout_distance_miles, display.workout_duration_minutes) && (
                <span className="text-coral text-xs">
                  {display.workout_pace_per_mile}/mi effort
                </span>
              )}
            </>
          )}
        </div>

        {/* Processing / failed indicator with retry */}
        {isProcessing && (
          <div className="mt-3 flex items-center gap-2">
            <div className="h-2.5 w-2.5 rounded-full border-2 border-coral border-t-transparent animate-spin" />
            <span className="font-mono text-[10px] text-text-tertiary">
              Processing voice memo...
            </span>
          </div>
        )}
        {log.processing_status === "failed" && (
          <div className="mt-3 flex items-center gap-3" onClick={(e) => e.stopPropagation()}>
            <span className="font-mono text-[10px] text-mood-injured">
              Processing failed
            </span>
            <button
              onClick={retryProcessing}
              disabled={retrying}
              className="rounded-md bg-coral/10 px-2.5 py-1 font-mono text-[10px] text-coral hover:bg-coral/20 disabled:opacity-50"
            >
              {retrying ? "Retrying..." : "Retry"}
            </button>
          </div>
        )}

        {/* Notes — the journal body */}
        {editing ? (
          <div className="mt-4" onClick={(e) => e.stopPropagation()}>
            <textarea
              value={draft.cleaned_notes ?? ""}
              onChange={(e) => setDraft({ ...draft, cleaned_notes: e.target.value || null })}
              rows={4}
              placeholder="Add notes..."
              className="w-full rounded-lg border border-divider bg-bg-elevated px-3 py-2 text-sm leading-relaxed text-text-primary outline-none placeholder-text-tertiary focus:border-coral/50"
            />
          </div>
        ) : notes ? (
          <p className="mt-4 text-[15px] leading-relaxed text-text-secondary">
            {isExpanded ? notes : truncate(notes, 180)}
          </p>
        ) : null}

        {/* Coach insight (always visible if present) */}
        {!isExpanded && log.coach_insight && (
          <div className="mt-3 rounded-lg border-l-2 border-coral bg-bg-elevated px-3 py-2">
            <p className="text-xs leading-relaxed text-text-secondary line-clamp-2">
              {log.coach_insight}
            </p>
          </div>
        )}

        {/* Expanded: full workout detail with charts, zones, insights */}
        {isExpanded && (
          <div className="mt-5">
            {/* Coach insight full */}
            {log.coach_insight && (
              <div className="mb-5 rounded-lg border-l-2 border-coral bg-bg-elevated px-4 py-3">
                <h4 className="mb-1 font-mono text-[10px] tracking-[0.2em] text-text-tertiary uppercase">Coach Insight</h4>
                <p className="text-sm leading-relaxed text-text-secondary">{log.coach_insight}</p>
              </div>
            )}

            {/* Workout notes */}
            {log.workout_notes && (
              <div className="mb-5">
                <h4 className="mb-2 font-mono text-[10px] tracking-[0.2em] text-text-tertiary uppercase">Workout Details</h4>
                <div className="rounded-lg bg-bg-elevated px-4 py-3">
                  <p className="whitespace-pre-wrap font-mono text-xs leading-relaxed text-text-secondary">{log.workout_notes}</p>
                </div>
              </div>
            )}

            {/* Interactive Vital data */}
            {log.vital_workout_id && (
              <WorkoutDetail log={log} onClose={onToggle} />
            )}

            {/* Pace segments from DB (fallback if no Vital link) */}
            {!log.vital_workout_id && log.pace_segments && log.pace_segments.length > 1 && (
              <div>
                <h4 className="mb-2 font-mono text-[10px] tracking-[0.2em] text-text-tertiary uppercase">Pace Segments</h4>
                <div className="grid grid-cols-1 gap-1">
                  {log.pace_segments.map((seg, i) => (
                    <div key={i} className="flex items-center gap-3 rounded-lg bg-bg-elevated px-3 py-2">
                      <span className={`w-2 h-2 rounded-full ${effortDot(seg.effort)}`} />
                      <span className="font-mono text-xs text-text-secondary capitalize w-20">{seg.effort}</span>
                      <span className="font-mono text-xs font-medium text-text-primary">{seg.distance_miles.toFixed(2)} mi</span>
                      <span className="font-mono text-xs text-text-secondary">{seg.pace_per_mile}/mi</span>
                      {seg.avg_heart_rate && <span className="font-mono text-xs text-mood-struggling">{seg.avg_heart_rate} bpm</span>}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Action bar */}
        <div className="mt-3 flex items-center gap-3">
          {editing ? (
            <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
              <button
                onClick={save}
                disabled={saving}
                className="rounded-lg bg-coral px-3 py-1 font-mono text-[10px] font-medium text-white hover:bg-coral-light disabled:opacity-50"
              >
                {saving ? "Saving..." : "Save"}
              </button>
              <button
                onClick={() => { setEditing(false); setDraft(log); }}
                className="rounded-lg bg-bg-elevated px-3 py-1 font-mono text-[10px] text-text-secondary hover:text-text-primary"
              >
                Cancel
              </button>
              <button
                onClick={() => setShowDeleteConfirm(true)}
                className="rounded-lg px-3 py-1 font-mono text-[10px] text-mood-injured/60 hover:text-mood-injured"
              >
                Delete
              </button>
            </div>
          ) : isExpanded ? (
            <button
              onClick={(e) => { e.stopPropagation(); setEditing(true); }}
              className="font-mono text-[10px] text-text-tertiary hover:text-coral transition-colors"
            >
              edit
            </button>
          ) : (notes || log.pace_segments?.length || log.vital_workout_id) ? (
            <span className="font-mono text-[10px] text-text-tertiary group-hover:text-coral transition-colors">
              tap to expand
            </span>
          ) : null}
        </div>

        {/* Delete confirmation */}
        {showDeleteConfirm && (
          <div className="mt-3 rounded-lg border border-mood-injured/30 bg-mood-injured/5 px-4 py-3" onClick={(e) => e.stopPropagation()}>
            <p className="text-xs text-text-secondary">Delete this training log entry? This cannot be undone.</p>
            <div className="mt-2 flex gap-2">
              <button
                onClick={handleDelete}
                className="rounded-lg bg-mood-injured px-3 py-1 font-mono text-[10px] font-medium text-white"
              >
                Delete
              </button>
              <button
                onClick={() => setShowDeleteConfirm(false)}
                className="rounded-lg bg-bg-elevated px-3 py-1 font-mono text-[10px] text-text-secondary"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </div>
    </article>
  );
}

// ─── Helpers ─────────────────────────────────────────────────

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max).trimEnd() + "...";
}

function computePace(miles: number, minutes: number): string {
  if (miles <= 0) return "";
  const totalSec = Math.round((minutes / miles) * 60);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function effortDot(effort: string): string {
  switch (effort) {
    case "easy":
    case "recovery":
      return "bg-mood-positive";
    case "moderate":
    case "tempo":
    case "threshold":
      return "bg-mood-tired";
    case "interval":
    case "race_pace":
      return "bg-coral";
    default:
      return "bg-text-tertiary";
  }
}

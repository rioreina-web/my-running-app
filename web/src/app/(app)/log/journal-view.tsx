"use client";

import { useState, useEffect, useMemo } from "react";
import { createClient } from "@/lib/supabase/client";
import type { TrainingLog } from "@/lib/types";
import { formatDuration, MOOD_CONFIG, WORKOUT_TYPE_CONFIG } from "@/lib/utils";
import { WorkoutDetail } from "./workout-detail";

// Rail data shapes, sourced server-side in page.tsx.
export interface NextUp {
  planName: string | null;
  date: string;
  workoutType: string | null;
  description: string | null;
  distanceMiles: number | null;
}

export interface Niggle {
  body_area: string;
  side: string | null;
  verbatim_quote: string;
  severity_hint: string | null;
  mentioned_at: string;
}

// Mood → hue. Warm = mood, per the three-palette rule. The journal row's left
// rail and the mood word both carry the mood hue; unset falls back to quiet ink.
const MOOD_HUE: Record<string, string> = {
  energized: "var(--color-mood-energized)",
  positive: "var(--color-mood-positive)",
  neutral: "var(--color-mood-neutral)",
  tired: "var(--color-mood-tired)",
  struggling: "var(--color-mood-struggling)",
  injured: "var(--color-mood-injured)",
};

// ─── Grouping + math ─────────────────────────────────────────

function logDate(l: TrainingLog): Date {
  return new Date(l.workout_date || l.created_at);
}

// Monday 00:00 of the week containing `d` (weeks are Monday-start, matching the
// dashboard/Trends convention).
function weekStartMonday(d: Date): Date {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
  return x;
}

function weekKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

// Group entries into Monday-start calendar weeks, newest first, each with a
// sticky-header label (This week / Last week / Week of Jun 30) + entry count and
// mileage subtotal. A check-in carries no distance, so it counts as an entry but
// not a run and adds no miles.
function groupByWeek(logs: TrainingLog[]) {
  const map = new Map<string, TrainingLog[]>();
  for (const log of logs) {
    const key = weekKey(weekStartMonday(logDate(log)));
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(log);
  }
  const thisWeek = weekStartMonday(new Date());
  return Array.from(map.entries())
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([key, entries]) => {
      const ws = weekStartMonday(logDate(entries[0]));
      const weeksAgo = Math.round((thisWeek.getTime() - ws.getTime()) / (7 * 86400000));
      const label =
        weeksAgo === 0
          ? "This week"
          : weeksAgo === 1
            ? "Last week"
            : `Week of ${ws.toLocaleDateString("en-US", { month: "short", day: "numeric" })}`;
      const miles = entries.reduce((s, e) => s + (e.workout_distance_miles || 0), 0);
      const runs = entries.filter((e) => e.source !== "check_in").length;
      return { key, label, miles, runs, entries };
    });
}

function computePaceStr(miles: number, minutes: number): string {
  if (miles <= 0) return "";
  const totalSec = Math.round((minutes / miles) * 60);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

// Weekly totals for the last `weeks` calendar weeks (most recent last).
function weeklyMileage(logs: TrainingLog[], weeks: number): number[] {
  const now = new Date();
  const buckets = new Array(weeks).fill(0);
  for (const l of logs) {
    const days = Math.floor((now.getTime() - logDate(l).getTime()) / 86400000);
    const w = Math.floor(days / 7);
    if (w >= 0 && w < weeks) buckets[weeks - 1 - w] += l.workout_distance_miles || 0;
  }
  return buckets;
}

// ─── Main Journal View ───────────────────────────────────────

export function JournalView({
  logs: initialLogs,
  nextUp = null,
  niggles = [],
}: {
  logs: TrainingLog[];
  nextUp?: NextUp | null;
  niggles?: Niggle[];
}) {
  const [logs, setLogs] = useState(initialLogs);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [liveIndicator, setLiveIndicator] = useState<string | null>(null);

  const weeks = useMemo(() => groupByWeek(logs), [logs]);

  // Realtime — inserts, updates (processing complete), deletes.
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
              updated.sort((a, b) => logDate(b).getTime() - logDate(a).getTime());
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

  const todayLabel = new Date()
    .toLocaleDateString("en-US", { month: "2-digit", year: "numeric" })
    .replace("/", ".");

  return (
    <div className="-m-4 md:-m-6 min-h-[calc(100vh-56px)] bg-bg-base">
      {/* Plate strip */}
      <div className="sticky top-0 z-[5] flex items-center justify-between border-b border-divider bg-bg-base px-6 py-3.5 md:px-10">
        <span className="font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-text-secondary">
          Running log &nbsp;—&nbsp; Log · v1 journal
        </span>
        <span className="font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-text-tertiary">
          {logs.length} entries · {todayLabel}
        </span>
      </div>

      {/* Feed + rail */}
      <div className="mx-auto flex max-w-[1060px] items-start gap-8 px-6 pb-20 pt-8 md:gap-[52px] md:px-14 md:pt-10">
        {/* ── FEED ── */}
        <div className="min-w-0 flex-1 md:max-w-[640px]">
          <p className="font-mono text-[11px] uppercase tracking-[0.14em] text-text-secondary">
            Your training
          </p>
          <div className="flex items-baseline justify-between gap-4">
            <h1 className="mt-1.5 font-display text-4xl font-bold leading-none tracking-tight text-text-primary md:text-[44px]">
              The log.
            </h1>
            {liveIndicator && (
              <span className="inline-flex flex-shrink-0 items-center gap-2">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-mood-energized" />
                <span className="font-mono text-[10px] uppercase tracking-[0.12em] text-mood-energized">
                  {liveIndicator}
                </span>
              </span>
            )}
          </div>

          {logs.length === 0 ? (
            <div className="mt-10 border-t border-divider pt-10">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                Nothing logged yet
              </p>
              <p className="mt-2 max-w-sm font-body text-[15px] italic leading-relaxed text-text-secondary">
                Record a voice memo or log a run from the app. When you do, your
                latest entry lands here.
              </p>
            </div>
          ) : (
            weeks.map((group) => (
              <section key={group.key}>
                {/* Sticky week header with mileage subtotal (THIS WEEK · 32 mi). */}
                <div className="sticky top-[49px] z-[4] -mx-2 mb-2 mt-8 flex items-center gap-3.5 bg-bg-base/95 px-2 py-2 backdrop-blur-sm">
                  <span className="h-px w-4 flex-none bg-divider" />
                  <span className="whitespace-nowrap font-mono text-[10.5px] uppercase tracking-[0.14em] text-text-secondary">
                    {group.label} · {Math.round(group.miles)} mi
                    {group.runs > 0 && ` · ${group.runs} ${group.runs === 1 ? "run" : "runs"}`}
                  </span>
                  <span className="h-px flex-1 bg-divider" />
                </div>

                {group.entries.map((log) => (
                  <JournalEntry
                    key={log.id}
                    log={log}
                    isExpanded={expandedId === log.id}
                    onToggle={() =>
                      setExpandedId(expandedId === log.id ? null : log.id)
                    }
                    onUpdate={(u) =>
                      setLogs((prev) => prev.map((l) => (l.id === u.id ? u : l)))
                    }
                    onDelete={(id) =>
                      setLogs((prev) => prev.filter((l) => l.id !== id))
                    }
                  />
                ))}
              </section>
            ))
          )}
        </div>

        {/* ── RAIL ── */}
        <Rail logs={logs} nextUp={nextUp} niggles={niggles} />
      </div>
    </div>
  );
}

// ─── Rail ────────────────────────────────────────────────────

function Rail({
  logs,
  nextUp,
  niggles,
}: {
  logs: TrainingLog[];
  nextUp: NextUp | null;
  niggles: Niggle[];
}) {
  const [range, setRange] = useState<"week" | "month">("week");

  const stats = useMemo(() => {
    const now = new Date();
    const days = range === "week" ? 7 : 30;
    const cutoff = now.getTime() - days * 86400000;
    const inRange = logs.filter(
      (l) => logDate(l).getTime() >= cutoff && l.source !== "check_in"
    );
    const miles = inRange.reduce((s, l) => s + (l.workout_distance_miles || 0), 0);
    const minutes = inRange.reduce(
      (s, l) => s + (l.workout_duration_minutes || 0),
      0
    );
    const avgPace = computePaceStr(miles, minutes);
    return { miles: Math.round(miles), runs: inRange.length, avgPace };
  }, [logs, range]);

  const spark = useMemo(() => weeklyMileage(logs, 6), [logs]);

  // Last 7 days of mood, oldest → newest, for the dot grid.
  const moodDots = useMemo(() => {
    const now = new Date();
    const byDay = new Map<number, string>();
    for (const l of logs) {
      const day = Math.floor((now.getTime() - logDate(l).getTime()) / 86400000);
      if (day >= 0 && day < 7 && l.mood && !byDay.has(day)) byDay.set(day, l.mood);
    }
    return Array.from({ length: 7 }, (_, i) => byDay.get(6 - i) || null);
  }, [logs]);

  const railLabel = range === "week" ? "This week" : "This month";
  const target = range === "week" ? 40 : 160;

  // Next up — weekday · type · distance, e.g. "TUE · MP · 7 MI".
  const nextMeta = useMemo(() => {
    if (!nextUp) return null;
    const parts: string[] = [];
    const d = new Date(nextUp.date + "T00:00:00");
    parts.push(d.toLocaleDateString("en-US", { weekday: "short" }).toUpperCase());
    const t = nextUp.workoutType;
    if (t) parts.push((WORKOUT_TYPE_CONFIG[t]?.label || t).toUpperCase());
    if (nextUp.distanceMiles) parts.push(`${nextUp.distanceMiles} MI`);
    return parts.join(" · ");
  }, [nextUp]);

  // Niggles — distinct recent body areas (last 21 days) + latest as caption.
  const niggleSummary = useMemo(() => {
    const now = new Date().getTime();
    const recent = niggles.filter(
      (n) => now - new Date(n.mentioned_at + "T00:00:00").getTime() <= 21 * 86400000
    );
    const areas = new Set(recent.map((n) => n.body_area.toLowerCase()));
    const latest = niggles[0] || null;
    return { count: areas.size, latest };
  }, [niggles]);

  return (
    <aside className="sticky top-20 hidden w-[300px] flex-none lg:block">
      {/* Volume tile */}
      <div className="flex items-center justify-between gap-2.5">
        <span className="font-mono text-[11px] uppercase tracking-[0.12em] text-text-secondary">
          {railLabel}
        </span>
        <div className="flex gap-0.5 rounded-lg bg-bg-calendar p-0.5">
          {(["week", "month"] as const).map((r) => (
            <button
              key={r}
              onClick={() => setRange(r)}
              className={`rounded-md px-2.5 py-1 font-mono text-[10px] uppercase tracking-[0.1em] transition-colors ${
                range === r
                  ? "bg-bg-card text-text-primary shadow-sm"
                  : "text-text-tertiary hover:text-text-secondary"
              }`}
            >
              {r}
            </button>
          ))}
        </div>
      </div>
      <div className="mt-3.5 flex items-baseline gap-1.5">
        <span className="font-mono text-[34px] font-semibold leading-none tabular-nums text-text-primary">
          {stats.miles}
        </span>
        <span className="font-mono text-lg font-medium tabular-nums text-text-tertiary">
          / {target} mi
        </span>
      </div>
      <div className="mt-2.5 font-mono text-[10px] uppercase tracking-[0.1em] text-text-secondary">
        {stats.runs} runs{stats.avgPace ? ` · ${stats.avgPace} / mi avg` : ""}
      </div>
      <Sparkline values={spark} />

      <RailDivider />

      {/* Next up */}
      <p className="font-mono text-[11px] uppercase tracking-[0.12em] text-text-secondary">
        Next up
      </p>
      {nextUp ? (
        <>
          <p className="mt-3 font-display text-xl font-bold text-text-primary">
            {nextUp.planName || nextUp.description || "Next session"}
          </p>
          {nextMeta && (
            <p className="mt-2 font-mono text-[10.5px] uppercase tracking-[0.1em] text-text-secondary">
              {nextMeta}
            </p>
          )}
        </>
      ) : (
        <p className="mt-3 font-body text-[13px] italic leading-relaxed text-text-tertiary">
          Nothing scheduled. Link a plan to see your next session here.
        </p>
      )}

      <RailDivider />

      {/* Mood, 7 days */}
      <p className="font-mono text-[11px] uppercase tracking-[0.12em] text-text-secondary">
        Mood · 7 days
      </p>
      <div className="mt-4 grid max-w-[250px] grid-cols-7 gap-2.5">
        {moodDots.map((m, i) => (
          <span
            key={i}
            className="aspect-square rounded-full"
            style={{
              backgroundColor: m ? MOOD_HUE[m] : "var(--color-divider)",
            }}
            title={m ? MOOD_CONFIG[m]?.label : "No entry"}
          />
        ))}
      </div>
      <p className="mt-4 font-body text-[13px] leading-relaxed text-text-secondary">
        {moodDots.some((m) => m)
          ? "Your last seven days at a glance — warmer means better."
          : "Mood shows up here once you log how runs felt."}
      </p>

      <RailDivider />

      {/* Niggles */}
      <div className="flex items-baseline justify-between gap-3">
        <span className="font-mono text-[11px] uppercase tracking-[0.12em] text-text-secondary">
          Niggles
        </span>
        {niggleSummary.count > 0 && (
          <a
            href="/injuries"
            className="font-mono text-[11px] uppercase tracking-[0.1em] text-coral hover:text-coral-dark"
          >
            {niggleSummary.count} active →
          </a>
        )}
      </div>
      {niggleSummary.latest ? (
        <p className="mt-3 font-body text-[14px] italic leading-relaxed text-text-secondary">
          {capitalize(niggleSummary.latest.body_area)} — “{niggleSummary.latest.verbatim_quote}”
        </p>
      ) : (
        <p className="mt-3 font-body text-[14px] italic leading-relaxed text-text-tertiary">
          Nothing flagged. Body-part mentions from your voice logs surface here.
        </p>
      )}
    </aside>
  );
}

function RailDivider() {
  return (
    <div className="my-6 flex items-center gap-2">
      <span className="h-px flex-1 bg-divider" />
      <span className="h-[3px] w-[3px] rounded-full bg-divider" />
      <span className="h-px flex-1 bg-divider" />
    </div>
  );
}

function Sparkline({ values }: { values: number[] }) {
  const max = Math.max(...values, 1);
  const w = 264;
  const h = 40;
  const step = values.length > 1 ? w / (values.length - 1) : w;
  const pts = values.map((v, i) => {
    const x = i * step;
    const y = h - (v / max) * (h - 6) - 3;
    return [x, y] as const;
  });
  const line = pts.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");
  const area = `${line} L${w} ${h} L0 ${h} Z`;
  const last = pts[pts.length - 1];
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" height="44" className="mt-4 block overflow-visible">
      <path d={area} fill="rgba(26,24,21,0.05)" />
      <path d={line} fill="none" stroke="var(--color-text-secondary)" strokeWidth={1.6} strokeLinejoin="round" />
      {last && <circle cx={last[0]} cy={last[1]} r={3} fill="var(--color-coral)" />}
    </svg>
  );
}

// ─── Journal Entry ───────────────────────────────────────────

function JournalEntry({
  log,
  isExpanded,
  onToggle,
  onUpdate,
  onDelete,
}: {
  log: TrainingLog;
  isExpanded: boolean;
  onToggle: () => void;
  onUpdate: (updated: TrainingLog) => void;
  onDelete: (id: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [draft, setDraft] = useState(log);

  const [syncedLog, setSyncedLog] = useState(log);
  if (!editing && syncedLog !== log) {
    setSyncedLog(log);
    setDraft(log);
  }

  const d = logDate(log);
  const dayName = d.toLocaleDateString("en-US", { weekday: "long" });
  const dayNum = d.getDate();
  const monthShort = d.toLocaleDateString("en-US", { month: "short" }).toUpperCase();
  const display = editing ? draft : log;
  const type = display.workout_type || "easy";
  const typeConfig = WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
  const moodKey = display.mood;
  const mood = moodKey ? MOOD_CONFIG[moodKey] : null;
  const hue = moodKey && MOOD_HUE[moodKey] ? MOOD_HUE[moodKey] : "var(--color-text-tertiary)";
  const notes = display.cleaned_notes || display.notes;
  const isProcessing = log.processing_status === "pending" || log.processing_status === "processing";
  const isCheckIn = log.source === "check_in";
  const isVoice = log.source === "voice_log";

  const pace =
    display.workout_distance_miles && display.workout_duration_minutes
      ? computePaceStr(display.workout_distance_miles, display.workout_duration_minutes)
      : null;

  // Meta line: "JUL 6 · TEMPO · 8.1 MI · 58:13 · 7:11/MI" (mood word appended, colored).
  const metaParts: string[] = [`${monthShort} ${dayNum}`];
  if (isCheckIn) metaParts.push("CHECK-IN");
  else if (display.workout_type) metaParts.push(typeConfig.label.toUpperCase());
  if (display.workout_distance_miles) metaParts.push(`${display.workout_distance_miles.toFixed(1)} MI`);
  if (display.workout_duration_minutes) metaParts.push(formatDuration(display.workout_duration_minutes));
  if (pace) metaParts.push(`${pace}/MI`);

  async function save() {
    setSaving(true);
    const supabase = createClient();
    const { error } = await supabase
      .from("training_logs")
      .update({
        cleaned_notes: draft.cleaned_notes,
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
    const { error } = await supabase.from("training_logs").delete().eq("id", log.id);
    if (!error) onDelete(log.id);
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
      if (data.success) onUpdate({ ...log, processing_status: "processing" });
    } catch {}
    setRetrying(false);
  }

  const badge = isVoice ? "VOICE" : isCheckIn ? "CHECK-IN" : "LOGGED";

  return (
    <article className="grid grid-cols-[3px_1fr] gap-[18px] border-b border-divider py-6">
      {/* Mood rail */}
      <div className="rounded-full" style={{ backgroundColor: hue }} />

      <div className="min-w-0">
        {/* Header: day + badge */}
        <div className="flex items-baseline justify-between gap-4">
          {editing ? (
            <input
              className="min-w-0 flex-1 font-display text-2xl text-text-primary outline-none md:text-[27px]"
              value={dayName}
              readOnly
            />
          ) : (
            <h3 className="font-display text-2xl font-bold leading-none text-text-primary md:text-[27px]">
              {dayName}
            </h3>
          )}
          {!editing && (
            <span
              className={`inline-flex flex-shrink-0 items-center gap-1.5 font-mono text-[11px] uppercase tracking-[0.1em] ${
                isVoice ? "text-coral" : "text-text-tertiary"
              }`}
            >
              {isVoice && (
                <svg width="8" height="8" viewBox="0 0 9 9" aria-hidden="true">
                  <polygon points="1.5,0.8 8,4.5 1.5,8.2" fill="currentColor" />
                </svg>
              )}
              {badge}
            </span>
          )}
        </div>

        {/* Meta line */}
        {editing ? (
          <div className="mt-3 flex flex-wrap items-center gap-2" onClick={(e) => e.stopPropagation()}>
            <select
              value={draft.workout_type || "easy"}
              onChange={(e) => setDraft({ ...draft, workout_type: e.target.value })}
              className="rounded-md border border-divider bg-bg-elevated px-2 py-1 text-[11px] text-text-primary outline-none"
            >
              {["easy", "tempo", "interval", "long_run", "recovery", "race", "progression", "strides"].map((t) => (
                <option key={t} value={t}>{(WORKOUT_TYPE_CONFIG[t] || WORKOUT_TYPE_CONFIG.other).label}</option>
              ))}
            </select>
            <input
              type="number" step="0.1" placeholder="mi"
              value={draft.workout_distance_miles ?? ""}
              onChange={(e) => setDraft({ ...draft, workout_distance_miles: e.target.value ? parseFloat(e.target.value) : null })}
              className="w-16 rounded-md border border-divider bg-bg-elevated px-2 py-1 text-right text-[11px] text-text-primary outline-none"
            />
            <input
              type="number" step="0.1" placeholder="min"
              value={draft.workout_duration_minutes ?? ""}
              onChange={(e) => setDraft({ ...draft, workout_duration_minutes: e.target.value ? parseFloat(e.target.value) : null })}
              className="w-16 rounded-md border border-divider bg-bg-elevated px-2 py-1 text-right text-[11px] text-text-primary outline-none"
            />
            <select
              value={draft.mood || ""}
              onChange={(e) => setDraft({ ...draft, mood: e.target.value || null })}
              className="rounded-md border border-divider bg-bg-elevated px-2 py-1 text-[11px] text-text-primary outline-none"
            >
              <option value="">No mood</option>
              {["energized", "positive", "neutral", "tired", "struggling", "injured"].map((m) => (
                <option key={m} value={m}>{MOOD_CONFIG[m]?.label}</option>
              ))}
            </select>
          </div>
        ) : (
          <p className="mt-2.5 font-mono text-[11px] uppercase tracking-[0.1em] text-text-secondary tabular-nums">
            {metaParts.join("  ·  ")}
            {mood && (
              <span style={{ color: hue }}>{"  ·  "}{mood.label.toUpperCase()}</span>
            )}
          </p>
        )}

        {/* Processing / failed */}
        {isProcessing && (
          <div className="mt-3 flex items-center gap-2">
            <span className="h-2.5 w-2.5 animate-spin rounded-full border-2 border-coral border-t-transparent" />
            <span className="font-mono text-[10px] uppercase tracking-[0.1em] text-text-tertiary">
              Processing voice memo…
            </span>
          </div>
        )}
        {log.processing_status === "failed" && (
          <div className="mt-3 flex items-center gap-3">
            <span className="font-mono text-[10px] uppercase tracking-[0.1em] text-mood-injured">
              Processing failed
            </span>
            <button
              onClick={retryProcessing}
              disabled={retrying}
              className="rounded-md bg-coral/10 px-2.5 py-1 font-mono text-[10px] text-coral hover:bg-coral/20 disabled:opacity-50"
            >
              {retrying ? "Retrying…" : "Retry"}
            </button>
          </div>
        )}

        {/* Quote */}
        {editing ? (
          <textarea
            value={draft.cleaned_notes ?? ""}
            onChange={(e) => setDraft({ ...draft, cleaned_notes: e.target.value || null })}
            rows={4}
            placeholder="Add notes…"
            className="mt-4 w-full rounded-lg border border-divider bg-bg-elevated px-3 py-2 text-sm leading-relaxed text-text-primary outline-none placeholder-text-tertiary focus:border-coral/50"
          />
        ) : notes ? (
          <p
            className={`mt-[13px] font-body text-[15px] italic leading-[1.55] text-text-primary ${
              isExpanded ? "" : "line-clamp-2"
            }`}
          >
            {"“"}{notes}{"”"}
          </p>
        ) : null}

        {/* Coach note */}
        {log.coach_insight && !editing && (
          <div className="mt-[15px] border-l-2 border-coral/50 pl-3.5">
            <p className="font-mono text-[10px] uppercase tracking-[0.12em] text-text-secondary">
              From your coach
            </p>
            <p
              className={`mt-1.5 font-body text-[14px] leading-relaxed text-text-primary ${
                isExpanded ? "" : "line-clamp-2"
              }`}
            >
              {log.coach_insight}
            </p>
          </div>
        )}

        {/* Expanded detail */}
        {isExpanded && !editing && (
          <div className="mt-5">
            {log.workout_notes && (
              <div className="mb-5">
                <p className="mb-2 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
                  Workout details
                </p>
                <div className="rounded-xl bg-bg-elevated px-4 py-3">
                  <p className="whitespace-pre-wrap font-mono text-xs leading-relaxed text-text-secondary">
                    {log.workout_notes}
                  </p>
                </div>
              </div>
            )}
            {log.vital_workout_id && <WorkoutDetail log={log} onClose={onToggle} />}
            {!log.vital_workout_id && log.pace_segments && log.pace_segments.length > 1 && (
              <div>
                <p className="mb-2 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
                  Pace segments
                </p>
                <div className="grid grid-cols-1 gap-1">
                  {log.pace_segments.map((seg, i) => (
                    <div key={i} className="flex items-center gap-3 rounded-lg bg-bg-elevated px-3 py-2">
                      <span className="h-2 w-2 rounded-full" style={{ backgroundColor: effortColor(seg.effort) }} />
                      <span className="w-20 font-mono text-xs capitalize text-text-secondary">{seg.effort}</span>
                      <span className="font-mono text-xs font-medium tabular-nums text-text-primary">{seg.distance_miles.toFixed(2)} mi</span>
                      <span className="font-mono text-xs tabular-nums text-text-secondary">{seg.pace_per_mile}/mi</span>
                      {seg.avg_heart_rate && <span className="font-mono text-xs tabular-nums text-mood-struggling">{seg.avg_heart_rate} bpm</span>}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Action bar */}
        <div className="mt-[11px] flex items-center gap-3">
          {editing ? (
            <div className="flex items-center gap-2">
              <button onClick={save} disabled={saving} className="rounded-lg bg-coral px-3 py-1 font-mono text-[10px] font-medium uppercase tracking-[0.1em] text-white hover:bg-coral-light disabled:opacity-50">
                {saving ? "Saving…" : "Save"}
              </button>
              <button onClick={() => { setEditing(false); setDraft(log); }} className="rounded-lg bg-bg-elevated px-3 py-1 font-mono text-[10px] uppercase tracking-[0.1em] text-text-secondary hover:text-text-primary">
                Cancel
              </button>
              <button onClick={() => setShowDeleteConfirm(true)} className="rounded-lg px-3 py-1 font-mono text-[10px] uppercase tracking-[0.1em] text-mood-injured/60 hover:text-mood-injured">
                Delete
              </button>
            </div>
          ) : (
            <>
              {(notes || log.coach_insight || log.pace_segments?.length || log.vital_workout_id || log.workout_notes) && (
                <button
                  onClick={onToggle}
                  className="font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary transition-colors hover:text-coral"
                >
                  {isExpanded ? "Collapse ↗" : "Tap to expand ↗"}
                </button>
              )}
              <button
                onClick={() => setEditing(true)}
                className="font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary/70 transition-colors hover:text-coral"
              >
                Edit
              </button>
            </>
          )}
        </div>

        {/* Delete confirm */}
        {showDeleteConfirm && (
          <div className="mt-3 rounded-xl border border-mood-injured/30 bg-mood-injured/5 px-4 py-3">
            <p className="text-xs text-text-secondary">Delete this entry? This cannot be undone.</p>
            <div className="mt-2 flex gap-2">
              <button onClick={handleDelete} className="rounded-lg bg-mood-injured px-3 py-1 font-mono text-[10px] font-medium uppercase tracking-[0.1em] text-white">
                Delete
              </button>
              <button onClick={() => setShowDeleteConfirm(false)} className="rounded-lg bg-bg-elevated px-3 py-1 font-mono text-[10px] uppercase tracking-[0.1em] text-text-secondary">
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

function capitalize(s: string): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}

function effortColor(effort: string): string {
  switch (effort) {
    case "easy":
    case "recovery":
      return "#93B9D6";
    case "moderate":
    case "steady":
      return "#578FC0";
    case "tempo":
    case "threshold":
      return "#27549B";
    case "interval":
    case "race_pace":
      return "#1A3679";
    default:
      return "#9B9590";
  }
}

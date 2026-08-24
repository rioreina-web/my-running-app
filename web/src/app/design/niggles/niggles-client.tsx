"use client";

/* ════════════════════════════════════════════════════════════════════
   NIGGLES · v2 PROTOTYPE — the dashboard
   ────────────────────────────────────────────────────────────────────
   Primarily a niggles surface. Training is the OVERLAY, not the
   subject: weekly volume, long-run distance and quality-session count
   sit behind the mention timeline so the athlete can see for herself
   whether the dots land anywhere in particular.

   Three rules from CLAUDE.md govern every string on this page:
     1. Closed body-part vocabulary. No invented medical entities.
     2. Quote verbatim. Never coerced to a number.
     3. Surface, never interpret. Counts are shown; conclusions are not.

   So: no severity scores, no risk gauges, no "your achilles is caused
   by". Co-occurrence is rendered as a tally with the sentence left
   deliberately unfinished.

   Design preview with mock data. No Supabase wiring.
   ════════════════════════════════════════════════════════════════════ */

import Link from "next/link";
import { useMemo, useState } from "react";

import {
  ALL_MENTIONS,
  MENTIONS,
  SPAN_END,
  SPAN_START,
  THREADS,
  TODAY,
  WEEKS,
  day,
  daysBetween,
  followsLong,
  followsQuality,
  shortDate,
  tallyBySession,
  tallyByVolumeBand,
  weekOf,
  weekday,
  type BodyMention,
  type NiggleThread,
  type Session,
  type ThreadStatus,
} from "./niggles-data";

/* ── Tokens ───────────────────────────────────────────────────────── */

/* Every colour resolves through the design tokens in `globals.css`.
   Nothing here is a literal hex, so a rebrand is a token change in one
   file rather than a sweep through this prototype. */
const CORAL = "var(--color-coral)";
const INK_1 = "var(--color-text-primary)";
const INK_2 = "var(--color-text-secondary)";
const INK_3 = "var(--color-text-tertiary)";
const SAGE = "var(--color-success)";
const PAPER = "var(--color-bg-card)";
const WELL = "var(--color-bg-calendar)";
const WELL_SOFT = "var(--color-divider-soft)";

/** Token colour at partial opacity — hex concatenation breaks on var(). */
function wash(color: string, pct: number): string {
  return `color-mix(in srgb, ${color} ${pct}%, transparent)`;
}

const STATUS: Record<ThreadStatus, { label: string; color: string; note: string }> = {
  active: { label: "Active", color: CORAL, note: "mentioned in the last 14 days" },
  quiet: { label: "Quiet", color: INK_3, note: "no mention in 14+ days, not called resolved" },
  resolved: { label: "Resolved", color: SAGE, note: "athlete said it was gone" },
};

/* ── Primitives ───────────────────────────────────────────────────── */

function Mono({
  children,
  color = INK_3,
  className = "",
}: {
  children: React.ReactNode;
  color?: string;
  className?: string;
}) {
  return (
    <span
      className={`font-mono text-[10.5px] tracking-[1.5px] uppercase ${className}`}
      style={{ color }}
    >
      {children}
    </span>
  );
}

function Rule() {
  return <div className="h-px bg-divider" />;
}

function Tile({
  eyebrow,
  value,
  unit,
  secondary,
  accent = false,
}: {
  eyebrow: string;
  value: string;
  unit: string;
  secondary: string;
  accent?: boolean;
}) {
  return (
    <div className="bg-bg-card border border-divider rounded-lg px-5 py-4">
      <Mono>{eyebrow}</Mono>
      <div className="mt-3 flex items-baseline gap-2">
        <span
          className="font-display text-[38px] leading-none tracking-[-0.02em] tabular-nums"
          style={{ color: accent ? CORAL : undefined }}
        >
          {value}
        </span>
        <Mono color={INK_3}>{unit}</Mono>
      </div>
      <p className="mt-2 font-body text-[12.5px] leading-[1.45] text-text-secondary">
        {secondary}
      </p>
    </div>
  );
}

function Section({
  fig,
  title,
  caption,
  children,
}: {
  fig: string;
  title: string;
  caption: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mt-14">
      <Mono color={CORAL}>{fig}</Mono>
      <h2 className="mt-2 font-display text-[24px] sm:text-[30px] leading-[1.1] tracking-[-0.015em]">
        {title}
      </h2>
      <p className="mt-2 max-w-[640px] font-body italic text-[13.5px] leading-[1.5] text-text-secondary">
        {caption}
      </p>
      <div className="mt-6">{children}</div>
    </section>
  );
}

function sessionLine(s: Session | null): string {
  if (!s) return "Rest day";
  if (s.label === "Rest") return "Rest day";
  const parts = [`${s.label} ${s.miles.toFixed(1)} mi`];
  if (s.pace) parts.push(`${s.pace} / mi`);
  if (s.detail) parts.push(s.detail);
  return parts.join(" · ");
}

/* ── Overlay modes — the training layer ───────────────────────────── */

type OverlayMode = "volume" | "long" | "quality" | "off";

const OVERLAYS: {
  id: OverlayMode;
  label: string;
  axis: string;
  value: (w: (typeof WEEKS)[number]) => number;
  format: (n: number) => string;
}[] = [
  {
    id: "volume",
    label: "Weekly mileage",
    axis: "MI / WEEK",
    value: (w) => w.miles,
    format: (n) => `${n} mi`,
  },
  {
    id: "long",
    label: "Long run",
    axis: "LONG RUN MI",
    value: (w) => w.longMiles,
    format: (n) => `${n} mi`,
  },
  {
    id: "quality",
    label: "Quality sessions",
    axis: "SESSIONS / WEEK",
    value: (w) => w.quality,
    format: (n) => `${n}`,
  },
  { id: "off", label: "Off", axis: "", value: () => 0, format: () => "" },
];

/* ── Timeline ─────────────────────────────────────────────────────── */


/* Row geometry differs by breakpoint. On phones the row label sits ABOVE
   its track so the plot gets the full screen width (168px of gutter is
   43% of a 393pt screen); from `sm` up the label returns to a gutter
   beside the track. Heights come from CSS calc over `--rows` / `--i`
   rather than inline px, so one markup tree serves both. */
const ROW_H_CLS = "h-[54px] sm:h-[40px]";
const PLOT_H_CLS = "h-[calc(var(--rows)*54px)] sm:h-[calc(var(--rows)*40px)]";
const ROW_TOP_CLS = "top-[calc(var(--i)*54px)] sm:top-[calc(var(--i)*40px)]";
/** Baseline sits low in the row on phones to clear the label above it. */
const TRACK_Y_CLS = "top-[70%] sm:top-1/2";

function xPct(iso: string): number {
  const span = day(SPAN_END) - day(SPAN_START);
  return ((day(iso) - day(SPAN_START)) / span) * 100;
}

function rowSummary(t: NiggleThread): React.ReactNode {
  return (
    <>
      {t.mentionCount} {t.mentionCount === 1 ? "mention" : "mentions"} ·{" "}
      <span style={{ color: STATUS[t.status].color }}>{STATUS[t.status].label}</span>
    </>
  );
}

function Timeline({
  threads,
  overlay,
  selectedKey,
  onSelectThread,
  selectedMentionId,
  onSelectMention,
}: {
  threads: NiggleThread[];
  overlay: OverlayMode;
  selectedKey: string | null;
  onSelectThread: (key: string | null) => void;
  selectedMentionId: string | null;
  onSelectMention: (id: string | null) => void;
}) {
  const cfg = OVERLAYS.find((o) => o.id === overlay)!;
  const max = overlay === "off" ? 1 : Math.max(...WEEKS.map(cfg.value));
  const axisTicks = WEEKS.filter((_, i) => i % 4 === 0);

  return (
    <div className="bg-bg-card border border-divider rounded-lg overflow-hidden">
      {/* overlay axis readout */}
      {overlay !== "off" && (
        <div className="px-5 pt-4 pb-2 flex flex-col sm:flex-row gap-0.5 sm:gap-4 sm:items-baseline sm:justify-between border-b border-divider-soft">
          <Mono>OVERLAY · {cfg.label}</Mono>
          <Mono color={INK_3}>
            {cfg.axis} · PEAK {cfg.format(max)}
          </Mono>
        </div>
      )}

      <div className="px-5 py-5">
        <div className="flex">
          {/* ── row labels · gutter, from sm up ── */}
          <div className={`hidden sm:block w-[168px] shrink-0 ${PLOT_H_CLS}`}>
            {threads.map((t) => {
              const isSel = selectedKey === t.key;
              return (
                <button
                  key={t.key}
                  type="button"
                  onClick={() => onSelectThread(isSel ? null : t.key)}
                  className={`w-full text-left pr-4 flex flex-col justify-center transition-opacity ${ROW_H_CLS}`}
                  style={{ opacity: selectedKey && !isSel ? 0.35 : 1 }}
                >
                  <span
                    className="font-mono text-[10.5px] tracking-[1.3px] uppercase"
                    style={{ color: isSel ? CORAL : INK_1 }}
                  >
                    {t.label}
                  </span>
                  <span
                    className="font-mono text-[9.5px] tracking-[1.1px] uppercase"
                    style={{ color: INK_3 }}
                  >
                    {rowSummary(t)}
                  </span>
                </button>
              );
            })}
          </div>

          {/* ── plot ── */}
          <div
            className={`relative flex-1 ${PLOT_H_CLS}`}
            style={{ "--rows": threads.length } as React.CSSProperties}
          >
            {/* training overlay bars, behind everything */}
            {overlay !== "off" && (
              <div className="absolute inset-0 flex items-end" aria-hidden>
                {WEEKS.map((w) => (
                  <div key={w.start} className="flex-1 h-full flex items-end px-[1.5px]">
                    <div
                      className="w-full rounded-t-[1px]"
                      style={{
                        height: `${(cfg.value(w) / max) * 100}%`,
                        background: w.partial ? WELL : WELL_SOFT,
                      }}
                      title={`Week of ${shortDate(w.start)} · ${cfg.format(cfg.value(w))}`}
                    />
                  </div>
                ))}
              </div>
            )}

            {/* month gridlines */}
            {["2026-06-01", "2026-07-01", "2026-08-01"].map((m) => (
              <div
                key={m}
                className="absolute top-0 bottom-0 w-px bg-divider-soft"
                style={{ left: `${xPct(m)}%` }}
                aria-hidden
              />
            ))}

            {/* row baselines + dots */}
            {threads.map((t, i) => {
              const isSel = selectedKey === t.key;
              const dim = selectedKey !== null && !isSel;
              return (
                <div
                  key={t.key}
                  className={`absolute left-0 right-0 transition-opacity ${ROW_TOP_CLS} ${ROW_H_CLS}`}
                  style={{ "--i": i, opacity: dim ? 0.22 : 1 } as React.CSSProperties}
                >
                  {/* label above the track — phones only */}
                  <button
                    type="button"
                    onClick={() => onSelectThread(isSel ? null : t.key)}
                    className="sm:hidden absolute top-0 left-0 right-0 text-left font-mono text-[9.5px] tracking-[1.1px] uppercase truncate"
                    style={{ color: isSel ? CORAL : INK_1 }}
                  >
                    {t.label} <span style={{ color: INK_3 }}>· {rowSummary(t)}</span>
                  </button>

                  <div className={`absolute left-0 right-0 h-px bg-divider ${TRACK_Y_CLS}`} />

                  {/* quiet-since tail, drawn from the last mention to today */}
                  {t.status === "quiet" && (
                    <div
                      className={`absolute h-px ${TRACK_Y_CLS}`}
                      style={{
                        left: `${xPct(t.lastSeen)}%`,
                        right: 0,
                        background: `repeating-linear-gradient(90deg,${INK_3} 0 3px,transparent 3px 7px)`,
                      }}
                      aria-hidden
                    />
                  )}

                  {MENTIONS.filter((m) => `${m.bodyPart}:${m.side}` === t.key).map((m) => {
                    const isDotSel = selectedMentionId === m.id;
                    const resolved = m.kind === "resolution";
                    const size = isDotSel ? 13 : 9;
                    return (
                      <button
                        key={m.id}
                        type="button"
                        onClick={() => {
                          onSelectMention(isDotSel ? null : m.id);
                          onSelectThread(t.key);
                        }}
                        title={`${shortDate(m.mentionedAt)} — "${m.quote}"`}
                        /* The visible dot stays 9px; the button around it is
                           30px on touch so a mention is actually tappable. */
                        className={`absolute -translate-y-1/2 -translate-x-1/2 grid place-items-center w-[30px] h-[30px] sm:w-[22px] sm:h-[22px] ${TRACK_Y_CLS}`}
                        style={{ left: `${xPct(m.mentionedAt)}%` }}
                      >
                        <span
                          className="rounded-full transition-transform"
                          style={{
                            width: size,
                            height: size,
                            background: resolved ? "transparent" : STATUS[t.status].color,
                            border: `2px solid ${resolved ? SAGE : PAPER}`,
                            boxShadow: isDotSel ? `0 0 0 3px ${wash(CORAL, 22)}` : "none",
                          }}
                        />
                        <span className="sr-only">
                          {t.label}, {shortDate(m.mentionedAt)}
                        </span>
                      </button>
                    );
                  })}
                </div>
              );
            })}

            {/* today */}
            <div
              className="absolute top-0 bottom-0 w-px"
              style={{ left: `${xPct(TODAY)}%`, background: CORAL, opacity: 0.5 }}
              aria-hidden
            />
          </div>
        </div>

        {/* ── axis ── */}
        <div className="flex mt-2">
          <div className="hidden sm:block w-[168px] shrink-0" />
          <div className="relative flex-1 h-4">
            {axisTicks.map((w, i) => (
              <span
                key={w.start}
                /* Every 4th week is legible on desktop; on a phone that many
                   ticks collide, so only alternates survive. */
                className={`absolute font-mono text-[9.5px] tracking-[1.1px] uppercase ${
                  i % 2 === 1 ? "hidden sm:inline" : ""
                }`}
                style={{ left: `${xPct(w.start)}%`, color: INK_3 }}
              >
                {shortDate(w.start)}
              </span>
            ))}
            <span
              className="absolute right-0 font-mono text-[9.5px] tracking-[1.1px] uppercase"
              style={{ color: CORAL }}
            >
              Today
            </span>
          </div>
        </div>
      </div>

      {/* ── legend ── */}
      <div className="px-5 py-3 border-t border-divider-soft bg-bg-elevated flex flex-wrap items-center gap-x-6 gap-y-2">
        <LegendDot color={CORAL} label="Mention · active thread" />
        <LegendDot color={INK_3} label="Mention · quiet thread" />
        <LegendDot color={SAGE} label="Resolved · athlete's own words" hollow />
        <span className="inline-flex items-center gap-2">
          <span className="w-5 h-2 rounded-[1px]" style={{ background: WELL_SOFT }} />
          <Mono color={INK_2}>Training overlay</Mono>
        </span>
      </div>
    </div>
  );
}


function LegendDot({
  color,
  label,
  hollow = false,
}: {
  color: string;
  label: string;
  hollow?: boolean;
}) {
  return (
    <span className="inline-flex items-center gap-2">
      <span
        className="w-[9px] h-[9px] rounded-full"
        style={{
          background: hollow ? "transparent" : color,
          border: `2px solid ${color}`,
        }}
      />
      <Mono color={INK_2}>{label}</Mono>
    </span>
  );
}

/* ── Mention readout ──────────────────────────────────────────────── */

function MentionReadout({ mention, thread }: { mention: BodyMention; thread: NiggleThread }) {
  const w = weekOf(mention.mentionedAt);
  return (
    <div className="mt-4 bg-bg-card border-l-2 rounded-r-lg px-5 py-4" style={{ borderColor: CORAL }}>
      <div className="flex items-baseline justify-between gap-4">
        <Mono color={CORAL}>
          {thread.label} · {weekday(mention.mentionedAt)} {shortDate(mention.mentionedAt)}
        </Mono>
        <Mono color={INK_3}>
          {mention.kind === "resolution" ? "Resolution" : "Mention"}
        </Mono>
      </div>

      <p className="mt-3 font-body italic text-[17px] leading-[1.45] text-text-primary">
        &ldquo;{mention.quote}&rdquo;
      </p>

      <div className="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4 pt-3 border-t border-divider-soft">
        <ReadoutCell eyebrow="That day" value={sessionLine(mention.sameDay)} />
        <ReadoutCell eyebrow="24 h before" value={sessionLine(mention.prevDay)} />
        <ReadoutCell
          eyebrow="That week"
          value={w ? `${w.miles} mi · long ${w.longMiles} mi · ${w.quality} quality` : "No training logged"}
        />
      </div>
    </div>
  );
}

function ReadoutCell({ eyebrow, value }: { eyebrow: string; value: string }) {
  return (
    <div>
      <Mono>{eyebrow}</Mono>
      <p className="mt-1.5 font-body text-[13.5px] leading-[1.45] text-text-primary">{value}</p>
    </div>
  );
}

/* ── Thread card ──────────────────────────────────────────────────── */

function ThreadCard({ thread }: { thread: NiggleThread }) {
  const st = STATUS[thread.status];
  const rows = [...thread.mentions].reverse().slice(0, 3);

  return (
    <div className="bg-bg-card border border-divider rounded-lg overflow-hidden">
      <div className="px-5 py-4 border-b border-divider-soft flex items-baseline justify-between gap-3">
        <span className="font-display text-[21px] leading-none tracking-[-0.01em]">
          {thread.label}
        </span>
        <span
          className="font-mono text-[9.5px] tracking-[1.3px] uppercase px-2 py-1 rounded-[2px]"
          style={{ color: st.color, background: wash(st.color, 12) }}
        >
          {st.label}
        </span>
      </div>

      {/* the ledger */}
      <div className="px-5 py-4 grid grid-cols-2 gap-y-3 gap-x-4 border-b border-divider-soft">
        <Stat eyebrow="Mentions" value={String(thread.mentionCount)} />
        <Stat
          eyebrow="Last said"
          value={
            thread.daysSinceLast === 0
              ? "Today"
              : `${thread.daysSinceLast} ${thread.daysSinceLast === 1 ? "day" : "days"} ago`
          }
        />
        <Stat eyebrow="First said" value={shortDate(thread.firstSeen)} />
        <Stat
          eyebrow="Carried"
          value={thread.spanDays === 0 ? "Single day" : `${thread.spanDays} days`}
        />
      </div>

      {/* recurrence */}
      <div className="px-5 py-4 border-b border-divider-soft">
        <Mono>Recurrence</Mono>
        {thread.returns.length === 0 ? (
          <p className="mt-2 font-body text-[13.5px] leading-[1.5] text-text-secondary">
            {thread.mentionCount === 1
              ? "Said once. Nothing to compare it to yet."
              : "No gap longer than three weeks between mentions."}
          </p>
        ) : (
          <ul className="mt-2 space-y-1.5">
            {thread.returns.map((r) => (
              <li
                key={r.on}
                className="font-body text-[13.5px] leading-[1.5] text-text-primary"
              >
                Returned {shortDate(r.on)}, after{" "}
                <span className="tabular-nums" style={{ color: CORAL }}>
                  {r.after} days
                </span>{" "}
                quiet.
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* resolution */}
      {thread.resolution && (
        <div className="px-5 py-4 border-b border-divider-soft" style={{ background: wash(SAGE, 5) }}>
          <Mono color={SAGE}>Resolved · {shortDate(thread.resolution.mentionedAt)}</Mono>
          <p className="mt-2 font-body italic text-[14px] leading-[1.45] text-text-primary">
            &ldquo;{thread.resolution.quote}&rdquo;
          </p>
          <p className="mt-2 font-body text-[12.5px] leading-[1.45] text-text-secondary">
            Closed on the athlete&rsquo;s word, {daysBetween(thread.firstSeen, thread.resolution.mentionedAt)} days
            after the first mention.
          </p>
        </div>
      )}

      {/* verbatim log with session context */}
      <div className="px-5 py-4">
        <Mono>What was said · latest first</Mono>
        <ul className="mt-3 space-y-4">
          {rows.map((m) => {
            const w = weekOf(m.mentionedAt);
            return (
              <li key={m.id}>
                <div className="flex items-baseline gap-2">
                  <Mono color={INK_2}>
                    {weekday(m.mentionedAt)} {shortDate(m.mentionedAt)}
                  </Mono>
                  {followsLong(m) && <Mono color={INK_2}>· within 24 h of a long</Mono>}
                </div>
                <p className="mt-1 font-body italic text-[14px] leading-[1.45] text-text-primary">
                  &ldquo;{m.quote}&rdquo;
                </p>
                <p className="mt-1 font-mono text-[9.5px] tracking-[1.1px] uppercase" style={{ color: INK_3 }}>
                  {sessionLine(m.sameDay)}
                  {w ? ` · week ${w.miles} mi` : ""}
                </p>
              </li>
            );
          })}
        </ul>
        {thread.mentionCount > rows.length && (
          <p className="mt-4 font-mono text-[9.5px] tracking-[1.1px] uppercase" style={{ color: INK_3 }}>
            + {thread.mentionCount - rows.length} earlier{" "}
            {thread.mentionCount - rows.length === 1 ? "mention" : "mentions"}
          </p>
        )}
      </div>
    </div>
  );
}

function Stat({ eyebrow, value }: { eyebrow: string; value: string }) {
  return (
    <div>
      <Mono>{eyebrow}</Mono>
      <p className="mt-1 font-body text-[14px] leading-none text-text-primary tabular-nums">
        {value}
      </p>
    </div>
  );
}

/* ── Co-occurrence ────────────────────────────────────────────────── */

function TallyBars({ rows, accent }: { rows: { label: string; count: number }[]; accent: string }) {
  const max = Math.max(1, ...rows.map((r) => r.count));
  return (
    <ul className="space-y-2.5">
      {rows.map((r) => (
        <li key={r.label} className="grid grid-cols-[84px_1fr_24px] sm:grid-cols-[104px_1fr_28px] items-center gap-2 sm:gap-3">
          <Mono color={INK_2}>{r.label}</Mono>
          <span className="h-[7px] bg-divider-soft rounded-[1px] overflow-hidden">
            <span
              className="block h-full rounded-[1px]"
              style={{ width: `${(r.count / max) * 100}%`, background: accent }}
            />
          </span>
          <span
            className="font-mono text-[11px] tabular-nums text-right"
            style={{ color: r.count === 0 ? INK_3 : INK_1 }}
          >
            {r.count}
          </span>
        </li>
      ))}
    </ul>
  );
}

function CoOccurrence({ thread }: { thread: NiggleThread | null }) {
  const mentions = thread ? thread.mentions : ALL_MENTIONS;
  const scope = thread ? thread.label : "All niggles";

  const longCount = mentions.filter(followsLong).length;
  const qualityCount = mentions.filter(followsQuality).length;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
      <div className="bg-bg-card border border-divider rounded-lg px-5 py-5 lg:col-span-1">
        <Mono>{scope} · 24 h window</Mono>
        <p className="mt-4 font-display text-[34px] sm:text-[40px] leading-none tracking-[-0.02em] tabular-nums" style={{ color: CORAL }}>
          {longCount}
          <span className="text-text-tertiary"> / {mentions.length}</span>
        </p>
        <p className="mt-3 font-body text-[14px] leading-[1.5] text-text-primary">
          mentions came within 24 hours of a long run.
        </p>
        <p className="mt-4 pt-3 border-t border-divider-soft font-body text-[13.5px] leading-[1.5] text-text-secondary tabular-nums">
          {qualityCount} of {mentions.length} came within 24 hours of a race-pace session.
        </p>
      </div>

      <div className="bg-bg-card border border-divider rounded-lg px-5 py-5">
        <Mono>Session on the day</Mono>
        <div className="mt-4">
          <TallyBars rows={tallyBySession(mentions)} accent={CORAL} />
        </div>
      </div>

      <div className="bg-bg-card border border-divider rounded-lg px-5 py-5">
        <Mono>Volume that week</Mono>
        <div className="mt-4">
          <TallyBars rows={tallyByVolumeBand(mentions)} accent={INK_2} />
        </div>
      </div>
    </div>
  );
}

/* ── Page ─────────────────────────────────────────────────────────── */

export default function NigglesDashboard() {
  const [overlay, setOverlay] = useState<OverlayMode>("volume");
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [selectedMentionId, setSelectedMentionId] = useState<string | null>(null);

  const selectedThread = useMemo(
    () => THREADS.find((t) => t.key === selectedKey) ?? null,
    [selectedKey]
  );

  const selectedMention = useMemo(
    () => MENTIONS.find((m) => m.id === selectedMentionId) ?? null,
    [selectedMentionId]
  );

  const mentionThread = useMemo(
    () =>
      selectedMention
        ? THREADS.find((t) => t.key === `${selectedMention.bodyPart}:${selectedMention.side}`) ?? null
        : null,
    [selectedMention]
  );

  const activeCount = THREADS.filter((t) => t.status === "active").length;
  const quietCount = THREADS.filter((t) => t.status === "quiet").length;
  const resolvedCount = THREADS.filter((t) => t.status === "resolved").length;
  const returnCount = THREADS.reduce((n, t) => n + t.returns.length, 0);

  const blockWeeks = WEEKS.length;

  function selectThread(key: string | null) {
    setSelectedKey(key);
    if (key === null) setSelectedMentionId(null);
  }

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      {/* plate strip */}
      <header className="border-b border-divider px-5 sm:px-10 py-4">
        <div className="mx-auto max-w-[1080px] flex items-baseline justify-between gap-4">
          <Mono color={INK_2}>Niggles · v2 prototype</Mono>
          <Mono color={INK_3}>Internal · mock data</Mono>
        </div>
      </header>

      <main className="mx-auto max-w-[1080px] px-5 sm:px-10 py-10 sm:py-14">
        {/* ── opening figure ── */}
        <section>
          <Mono color={CORAL}>Fig. 01 · The body, as you described it</Mono>
          <h1 className="mt-3 font-display text-[40px] sm:text-[56px] leading-[1.0] tracking-[-0.02em]">
            Niggles.
          </h1>
          <p className="mt-5 max-w-[660px] font-body text-[16px] leading-[1.6] text-text-secondary">
            Every body-part mention pulled out of your voice logs, in your own
            words, on the day you said it. Training sits behind as an overlay so
            you can see where the mentions land. What that means is your call.
          </p>
          <p className="mt-4 font-mono text-[10px] tracking-[1.3px] uppercase" style={{ color: INK_3 }}>
            {shortDate(SPAN_START)} – {shortDate(SPAN_END)} 2026 · {blockWeeks} weeks ·{" "}
            {ALL_MENTIONS.length} mentions across {THREADS.length} body areas
          </p>
        </section>

        {/* ── tiles ── */}
        <section className="mt-10 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
          <Tile
            eyebrow="Active"
            value={String(activeCount)}
            unit={activeCount === 1 ? "Thread" : "Threads"}
            secondary="Mentioned in the last 14 days."
            accent
          />
          <Tile
            eyebrow="Quiet"
            value={String(quietCount)}
            unit={quietCount === 1 ? "Thread" : "Threads"}
            secondary="Not mentioned in a while. Not called resolved either."
          />
          <Tile
            eyebrow="Resolved"
            value={String(resolvedCount)}
            unit={resolvedCount === 1 ? "Thread" : "Threads"}
            secondary="You said it was gone."
          />
          <Tile
            eyebrow="Returns"
            value={String(returnCount)}
            unit="After 3+ wks"
            secondary="A body area came back after three weeks or more of quiet."
          />
        </section>

        <div className="mt-12">
          <Rule />
        </div>

        {/* ── FIG 02 · timeline ── */}
        <Section
          fig="Fig. 02 · The timeline"
          title="When you said it."
          caption="One row per body area. Each dot is a voice log. Pick an overlay to put your training behind the dots; tap a dot to read what you actually said that day."
        >
          {/* overlay switcher */}
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <Mono className="mr-1">Overlay</Mono>
            {OVERLAYS.map((o) => {
              const on = overlay === o.id;
              return (
                <button
                  key={o.id}
                  type="button"
                  onClick={() => setOverlay(o.id)}
                  className="font-mono text-[10px] tracking-[1.3px] uppercase px-2.5 sm:px-3 py-1.5 rounded-[3px] border transition-colors"
                  style={{
                    color: on ? PAPER : INK_2,
                    background: on ? CORAL : "transparent",
                    borderColor: on ? CORAL : "var(--color-divider)",
                  }}
                >
                  {o.label}
                </button>
              );
            })}
            {selectedKey && (
              <button
                type="button"
                onClick={() => selectThread(null)}
                className="ml-auto font-mono text-[10px] tracking-[1.3px] uppercase underline underline-offset-4"
                style={{ color: CORAL }}
              >
                Clear filter ↩
              </button>
            )}
          </div>

          <Timeline
            threads={THREADS}
            overlay={overlay}
            selectedKey={selectedKey}
            onSelectThread={selectThread}
            selectedMentionId={selectedMentionId}
            onSelectMention={setSelectedMentionId}
          />

          {selectedMention && mentionThread ? (
            <MentionReadout mention={selectedMention} thread={mentionThread} />
          ) : (
            <p className="mt-4 font-body italic text-[13.5px] leading-[1.5] text-text-secondary">
              No dot selected. Tap one and the voice log behind it lands here,
              with the session you ran that day.
            </p>
          )}
        </Section>

        <div className="mt-12">
          <Rule />
        </div>

        {/* ── FIG 03 · co-occurrence ── */}
        <Section
          fig="Fig. 03 · Where the dots fall"
          title="What the mentions sit next to."
          caption="Counts, not conclusions. These tally what your training log already says about the days you spoke up. The system does not finish the sentence."
        >
          <CoOccurrence thread={selectedThread} />
          <p className="mt-5 font-body italic text-[13.5px] leading-[1.5] text-text-secondary">
            {selectedThread
              ? `Scoped to ${selectedThread.label}. Clear the filter above to count every body area together.`
              : "Tap a body area in the timeline above to scope these counts to one thread."}
          </p>
        </Section>

        <div className="mt-12">
          <Rule />
        </div>

        {/* ── FIG 04 · threads ── */}
        <Section
          fig="Fig. 04 · The threads"
          title="Each one, in full."
          caption="Recurrence, resolution, and the verbatim log. Nothing here is rated, ranked by severity, or given a name it did not already have."
        >
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
            {THREADS.map((t) => (
              <ThreadCard key={t.key} thread={t} />
            ))}
          </div>
        </Section>

        {/* ── how status is decided ── */}
        <section className="mt-14 bg-bg-elevated border border-divider rounded-lg px-6 py-5">
          <Mono>How a thread gets its status</Mono>
          <ul className="mt-4 space-y-2.5">
            {(["active", "quiet", "resolved"] as ThreadStatus[]).map((s) => (
              <li key={s} className="flex items-baseline gap-3">
                <span
                  className="font-mono text-[9.5px] tracking-[1.3px] uppercase px-2 py-1 rounded-[2px] shrink-0"
                  style={{ color: STATUS[s].color, background: wash(STATUS[s].color, 12) }}
                >
                  {STATUS[s].label}
                </span>
                <span className="font-body text-[13.5px] leading-[1.5] text-text-secondary">
                  {STATUS[s].note}
                </span>
              </li>
            ))}
          </ul>
          <p className="mt-4 pt-3 border-t border-divider-soft font-body italic text-[13px] leading-[1.5] text-text-secondary">
            A rule, not a judgement. Quiet is not the same as healed, and the
            app will not claim otherwise.
          </p>
        </section>

        {/* ── footer ── */}
        <footer className="mt-12 pt-6 border-t border-divider-soft">
          <p className="font-body italic text-[13px] leading-[1.5] text-text-secondary">
            Not medical advice. If anything gets sharper, see a clinician.
          </p>
          <div className="mt-5 flex items-center justify-between gap-4">
            <Mono color={INK_3}>
              Prototype · outputs/niggles-v2-dashboard-2026-08-23.md
            </Mono>
            <Link
              href="/design"
              className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-primary hover:text-coral transition-colors"
            >
              Back to previews ↗
            </Link>
          </div>
        </footer>
      </main>
    </div>
  );
}

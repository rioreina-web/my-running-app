"use client";

import { useEffect, useState, type ReactNode } from "react";
import { PACE_ZONE_COLORS, zoneLabelShort } from "@/components/coach/workout-helpers";
import { ZoneDot } from "@/components/ui/zone-dot";
import { createClient } from "@/lib/supabase/client";
import { WorkoutTelemetryChart } from "./workout-telemetry-chart";
import type { DashboardDay, Mood, WorkoutRead } from "@/lib/coach-dashboard/types";

/**
 * WorkoutDrawer — the key-session drill-down (redesign 2026-07-16, FIG 24).
 * Slides in from the right and answers the coach's five questions in reading
 * order across ten sections:
 *   1 verdict header · 2 headline strip · 3 telemetry chart · 4 conditions ·
 *   5 splits · 6 voice + mood · 7 body · 8 week & load · 9 the read · 10 actions
 *
 * Every enrichment block (detail.prescribed / conditions / chart / weekContext
 * / bodyContext / read) is OPTIONAL — the drawer renders what it gets, so a
 * thin live row and a fully-enriched fixture both stay valid. Driven by
 * DrawerProvider; `day` is null when closed.
 */

// Mood → the warm-palette color (mood is warm ONLY; three-palette rule).
const MOOD_COLOR: Record<Mood, string> = {
  energized: "var(--color-mood-energized)",
  positive: "var(--color-mood-positive)",
  neutral: "var(--color-mood-neutral)",
  tired: "var(--color-mood-tired)",
  struggling: "var(--color-mood-struggling)",
  injured: "var(--color-mood-injured)",
};

const ACWR_BAND_LABEL: Record<string, string> = {
  detraining: "detraining",
  low: "building",
  sweet: "sweet band",
  high: "high end of the sweet band",
  spike: "spike",
};

// Render inline **bold** emphasis in captions and the read, keeping the rest as
// plain text (no markdown lib — the payload only ever uses **…**).
function withEmphasis(text: string): ReactNode[] {
  return text.split(/(\*\*[^*]+\*\*)/g).map((part, i) =>
    part.startsWith("**") && part.endsWith("**") ? (
      <b key={i} className="font-semibold text-text-primary">
        {part.slice(2, -2)}
      </b>
    ) : (
      <span key={i}>{part}</span>
    ),
  );
}

function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <span className="font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
      {children}
    </span>
  );
}

function SectionHead({ title, right }: { title: ReactNode; right?: ReactNode }) {
  return (
    <div className="mb-2.5 flex items-baseline justify-between">
      <Eyebrow>{title}</Eyebrow>
      {right ? (
        <span className="font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">
          {right}
        </span>
      ) : null}
    </div>
  );
}

export function WorkoutDrawer({
  day,
  onClose,
  athleteId,
}: {
  day: DashboardDay | null;
  onClose: () => void;
  /** Present on the live dashboard — enables on-demand "generate the read".
   *  Absent in the static design preview (generation is off there). */
  athleteId?: string;
}) {
  const open = day != null;
  // Keep the last opened day mounted through the close animation. React's
  // "adjust state when a prop changes" pattern: retain the last non-null day
  // and only advance it while `day` is set, so content stays put on close.
  const [shown, setShown] = useState<DashboardDay | null>(day);
  const [prevDay, setPrevDay] = useState<DashboardDay | null>(day);
  if (day !== prevDay) {
    setPrevDay(day);
    if (day) setShown(day);
  }

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);

  // On-demand "the read" — generated reads live here, keyed by log id, so a
  // generated read survives close/reopen within the session.
  const [genReads, setGenReads] = useState<Record<string, WorkoutRead>>({});
  const [genBusyId, setGenBusyId] = useState<string | null>(null);
  const [genError, setGenError] = useState<string | null>(null);

  async function generateRead(logId: string) {
    if (!athleteId) return;
    setGenBusyId(logId);
    setGenError(null);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.functions.invoke("coach-workout-read", {
        body: { training_log_id: logId, athlete_user_id: athleteId },
      });
      if (error) throw error;
      const payload = data as { body?: string; question?: string };
      if (!payload?.body || !payload?.question) throw new Error("The read came back empty.");
      setGenReads((prev) => ({ ...prev, [logId]: { body: payload.body!, question: payload.question! } }));
    } catch (e) {
      setGenError(e instanceof Error ? e.message : "Could not generate the read.");
    } finally {
      setGenBusyId(null);
    }
  }

  const d = day ?? shown;
  const detail = d?.detail;
  const presc = detail?.prescribed;
  const cond = detail?.conditions;
  const chart = detail?.chart;
  const wk = detail?.weekContext;
  const body = detail?.bodyContext;
  const read = detail?.read;
  const zoneColor = d?.zone ? PACE_ZONE_COLORS[d.zone] : "var(--color-text-tertiary)";

  return (
    <>
      <div
        onClick={onClose}
        className={`fixed inset-0 z-40 bg-[rgba(26,24,21,0.4)] transition-opacity duration-200 ${
          open ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
      />
      <aside
        role="dialog"
        aria-modal="true"
        aria-hidden={!open}
        className={`fixed right-0 top-0 z-50 h-screen w-[min(452px,94vw)] overflow-y-auto bg-bg-base shadow-[-8px_0_30px_rgba(0,0,0,0.16)] transition-transform duration-300 ease-out ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        {d ? (
          <div className="relative p-7 pb-16">
            <button
              type="button"
              onClick={onClose}
              aria-label="Close"
              className="absolute right-5 top-5 flex h-8 w-8 items-center justify-center rounded-full bg-bg-calendar font-mono text-sm text-text-secondary hover:text-text-primary"
            >
              ✕
            </button>

            {/* ① verdict header */}
            <div className="flex items-center gap-2">
              {d.key ? (
                <span className="rounded-full bg-text-primary px-2 py-[3px] font-mono text-[9px] uppercase tracking-[0.1em] text-white">
                  ★ Key session
                </span>
              ) : null}
              <span className="font-mono text-[10px] uppercase tracking-[0.1em] text-text-tertiary">
                {d.dateLabel} · {d.dow}
              </span>
            </div>

            <h3 className="mt-3 font-display text-[27px] font-bold leading-[1.05] text-text-primary">
              {detail?.verdictTitle ?? d.label}
            </h3>
            <div className="mt-2 flex flex-wrap items-center gap-2 font-mono text-[10.5px] uppercase tracking-[0.06em] text-text-secondary">
              <ZoneDot color={zoneColor} size={9} />
              {presc ? (
                <span>
                  {presc.label} · prescribed {presc.distance} mi · {presc.window}
                </span>
              ) : (
                <span>{d.zone ? zoneLabelShort(d.zone) : "Rest"} · prescribed vs. actual</span>
              )}
              {presc && typeof presc.cutAtMi === "number" ? (
                <span className="rounded-full bg-coral/10 px-2 py-[2px] font-mono text-[9.5px] font-semibold tracking-[0.08em] text-coral-dark">
                  CUT AT {Math.round(presc.distance + presc.cutAtMi)} · {presc.cutAtMi > 0 ? "+" : "−"}
                  {Math.abs(presc.cutAtMi).toFixed(1)} MI
                </span>
              ) : null}
            </div>

            {detail ? (
              <>
                {/* ② headline strip */}
                <div className="mt-[18px] grid grid-cols-4 border-y border-divider py-[13px]">
                  {detail.kpis.map((k, i) => (
                    <div
                      key={k.k}
                      className={`flex flex-col gap-1 px-2.5 ${
                        i < detail.kpis.length - 1 ? "border-r border-divider" : ""
                      } ${i === 0 ? "pl-0" : ""}`}
                    >
                      <span className="font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">
                        {k.k}
                      </span>
                      <span
                        className="font-mono text-[19px] font-semibold leading-none tabular-nums"
                        style={{ color: k.accent ? "var(--color-pace-steady)" : "var(--color-text-primary)" }}
                      >
                        {k.v}
                      </span>
                      {k.sub ? (
                        <span className="font-mono text-[8.5px] uppercase tracking-[0.05em] text-text-tertiary">
                          {withEmphasis(k.sub)}
                        </span>
                      ) : null}
                    </div>
                  ))}
                </div>

                {/* ③ telemetry chart */}
                {chart ? (
                  <section className="mt-[22px]">
                    <SectionHead title="Telemetry · pace × HR × elevation" right="Drag to scrub" />
                    <WorkoutTelemetryChart chart={chart} />
                  </section>
                ) : null}

                {/* ④ conditions */}
                {cond ? (
                  <section className="mt-[22px]">
                    <SectionHead title={`Conditions${cond.startTime ? ` · ${cond.startTime} start` : ""}`} />
                    <div className="grid grid-cols-5 border-y border-divider py-[11px]">
                      <CondCell label="Temp" value={`${cond.tempF}°`} unit="F" />
                      <CondCell
                        label="Dew pt"
                        value={`${cond.dewPointF}°`}
                        unit={cond.dewHot ? "Hot band" : "F"}
                        alert={cond.dewHot}
                      />
                      <CondCell label="Climb" value={cond.climbFt.toLocaleString()} unit="ft" />
                      <CondCell label="HR avg" value={String(cond.hrAvg)} unit={cond.hrZone ?? "bpm"} />
                      {cond.drift ? (
                        <CondCell label="Drift" value={cond.drift} unit="Pa:HR" />
                      ) : (
                        <CondCell label="Drift" value="not derived" unit="" muted />
                      )}
                    </div>
                    {cond.caption ? (
                      <p className="mt-2.5 font-body text-[12.5px] italic leading-[1.5] text-text-secondary">
                        {withEmphasis(cond.caption)}
                      </p>
                    ) : null}
                  </section>
                ) : null}

                {/* ⑤ splits */}
                {detail.splits.length > 0 ? (
                  <section className="mt-[22px]">
                    <SectionHead
                      title={detail.splitLabel}
                      right={detail.splits.some((s) => s.adj) ? "Heat-adj · raw" : undefined}
                    />
                    {detail.splits.map((s, i) => (
                      <div
                        key={i}
                        className="flex items-center gap-2.5 border-t border-divider py-2 first:border-t-0"
                      >
                        <ZoneDot
                          color={
                            s.pace === null || !s.onTarget
                              ? "var(--color-text-tertiary)"
                              : "var(--color-pace-moderate)"
                          }
                          size={8}
                        />
                        <span
                          className="flex-1 font-body text-[13.5px]"
                          style={{
                            color: s.pace === null ? "var(--color-text-tertiary)" : "var(--color-text-primary)",
                          }}
                        >
                          {s.name}
                        </span>
                        {s.adj ? (
                          <span
                            className="font-mono text-[10px] tracking-[0.02em]"
                            style={{ color: "var(--color-pace-easy-text)" }}
                          >
                            {s.adj}
                          </span>
                        ) : null}
                        {s.pace === null ? (
                          <span className="min-w-[44px] text-right font-mono text-[12px] text-text-tertiary">
                            not run
                          </span>
                        ) : (
                          <span className="min-w-[44px] text-right font-mono text-[14px] font-semibold tabular-nums text-text-primary">
                            {s.pace}
                          </span>
                        )}
                      </div>
                    ))}
                    <div className="mt-[7px] font-mono text-[8.5px] uppercase tracking-[0.06em] text-text-tertiary">
                      {detail.splits.some((s) => s.adj)
                        ? "Blue = inside band · gray = over · adj = heat-adjusted"
                        : "Blue = at or under target · gray = over"}
                    </div>
                  </section>
                ) : null}

                <hr className="mt-[22px] border-t border-divider" />

                {/* ⑥ voice + mood */}
                {d.note ? (
                  <section className="mt-[22px]">
                    <div className="mb-2.5 flex items-baseline justify-between">
                      <Eyebrow>Voice note · verbatim</Eyebrow>
                      <MoodPill mood={d.mood} />
                    </div>
                    <blockquote className="rounded-[10px] bg-bg-elevated px-4 py-3.5 font-body text-[14px] italic leading-[1.65] text-text-primary">
                      &ldquo;{d.note}&rdquo;
                    </blockquote>
                  </section>
                ) : (
                  <section className="mt-[22px]">
                    <SectionHead title="Mood that day" />
                    <MoodPill mood={d.mood} />
                  </section>
                )}

                {/* ⑦ body */}
                <section className="mt-[22px]">
                  <SectionHead title="Body · niggles" />
                  {d.niggle ? (
                    <div className="rounded-lg border-l-2 border-coral bg-coral/10 px-3.5 py-3">
                      <div className="font-mono text-[10px] uppercase tracking-[0.08em] text-coral-dark">
                        {d.niggle.area}
                      </div>
                      <div className="mt-1 font-body text-[13.5px] italic leading-snug text-text-primary">
                        &ldquo;{d.niggle.quote}&rdquo;
                      </div>
                    </div>
                  ) : (
                    <>
                      <p className="font-body text-[13.5px] text-text-primary">
                        {body?.line ?? "No niggles mentioned on this run."}
                      </p>
                      {body?.sub ? (
                        <p className="mt-1 font-body text-[12px] italic text-text-tertiary">{body.sub}</p>
                      ) : null}
                    </>
                  )}
                </section>

                {/* ⑧ week & load */}
                {wk ? (
                  <section className="mt-[22px]">
                    <SectionHead title="Where it sits" />
                    <p className="mb-2.5 font-body text-[13.5px] leading-snug text-text-primary">
                      {withEmphasis(wk.loadLine)}
                    </p>
                    <AcwrBar band={wk.acwrBand} value={wk.acwr} />
                    {wk.nextKey ? (
                      <div className="mt-3 flex items-center gap-1.5 font-mono text-[10px] uppercase tracking-[0.06em] text-text-secondary">
                        <ZoneDot color={PACE_ZONE_COLORS[wk.nextKey.zone]} size={7} />
                        Next key session · {wk.nextKey.label}
                      </div>
                    ) : null}
                  </section>
                ) : null}

                {/* ⑨ the read — cached, or generated on demand */}
                {(() => {
                  const effectiveRead = read ?? (d ? genReads[d.id] : undefined);
                  if (effectiveRead) {
                    return (
                      <section className="mt-[22px] border-t-2 border-text-primary pt-3">
                        <Eyebrow>The read · AI observation</Eyebrow>
                        <p className="mt-2 font-body text-[14px] leading-[1.65] text-text-primary">
                          {withEmphasis(effectiveRead.body)}
                        </p>
                        <p className="mt-2 font-body text-[14px] italic leading-[1.65] text-text-secondary">
                          {effectiveRead.question}
                        </p>
                      </section>
                    );
                  }
                  // No cached read: offer on-demand generation on the live
                  // dashboard (athleteId present). Off in the static preview.
                  if (!athleteId || !d) return null;
                  return (
                    <section className="mt-[22px] border-t-2 border-text-primary pt-3">
                      <Eyebrow>The read · AI observation</Eyebrow>
                      <p className="mt-2 font-body text-[13.5px] italic leading-snug text-text-tertiary">
                        A short observation on this session, synthesized on demand.
                      </p>
                      <button
                        type="button"
                        onClick={() => generateRead(d.id)}
                        disabled={genBusyId === d.id}
                        className="mt-2.5 rounded-lg border border-divider px-3.5 py-2 font-display text-[13.5px] font-semibold text-text-primary hover:border-text-primary disabled:opacity-60"
                      >
                        {genBusyId === d.id ? "Reading…" : "Generate the read"}
                      </button>
                      {genError ? (
                        <p className="mt-2 font-body text-[12px] text-coral-dark">{genError}</p>
                      ) : null}
                    </section>
                  );
                })()}

                {/* ⑩ actions */}
                <div className="mt-6 flex items-center justify-between border-t border-divider pt-4">
                  <a
                    href="#"
                    className="border-b border-divider pb-px font-display text-[13.5px] font-semibold text-text-secondary hover:text-text-primary"
                  >
                    Open full log
                  </a>
                  <button
                    type="button"
                    className="rounded-[10px] bg-coral px-[18px] py-2.5 font-display text-[14.5px] font-semibold text-white shadow-[0_4px_12px_rgba(212,89,42,0.3)] hover:bg-coral-light"
                  >
                    Adjust this week
                  </button>
                </div>
              </>
            ) : (
              // No drill-down detail (rest day / thin row): mood + note only.
              <>
                <section className="mt-6">
                  <SectionHead title="Mood that day" />
                  <MoodPill mood={d.mood} />
                </section>
                {d.niggle ? (
                  <section className="mt-6">
                    <SectionHead title="Niggle mentioned" />
                    <div className="rounded-lg border-l-2 border-coral bg-coral/10 px-3.5 py-3">
                      <div className="font-mono text-[10px] uppercase tracking-[0.08em] text-coral-dark">
                        {d.niggle.area}
                      </div>
                      <div className="mt-1 font-body text-[13.5px] italic leading-snug text-text-primary">
                        &ldquo;{d.niggle.quote}&rdquo;
                      </div>
                    </div>
                  </section>
                ) : null}
                {d.note ? (
                  <section className="mt-6">
                    <SectionHead title="Voice note" />
                    <p className="rounded-[10px] bg-bg-elevated px-4 py-3.5 font-body text-[14.5px] italic leading-relaxed text-text-primary">
                      &ldquo;{d.note}&rdquo;
                    </p>
                  </section>
                ) : null}
              </>
            )}
          </div>
        ) : null}
      </aside>
    </>
  );
}

function CondCell({
  label,
  value,
  unit,
  alert,
  muted,
}: {
  label: string;
  value: string;
  unit: string;
  alert?: boolean;
  muted?: boolean;
}) {
  return (
    <div className="flex flex-col items-center gap-[3px] border-r border-divider last:border-r-0">
      <span className="font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">{label}</span>
      <span
        className="font-mono text-[14px] font-semibold leading-none tabular-nums"
        style={{
          color: alert
            ? "var(--color-coral)"
            : muted
              ? "var(--color-text-tertiary)"
              : "var(--color-text-primary)",
        }}
      >
        {value}
      </span>
      {unit ? (
        <span className="font-mono text-[8.5px] uppercase tracking-[0.04em] text-text-tertiary">{unit}</span>
      ) : null}
    </div>
  );
}

function MoodPill({ mood }: { mood: Mood }) {
  const color = MOOD_COLOR[mood];
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 font-mono text-[9.5px] font-semibold uppercase tracking-[0.1em]"
      style={{ color, backgroundColor: `color-mix(in srgb, ${color} 14%, transparent)` }}
    >
      <span className="h-[7px] w-[7px] rounded-full" style={{ backgroundColor: color }} />
      {mood.charAt(0).toUpperCase() + mood.slice(1)}
    </span>
  );
}

// ACWR banded bar — grays only; coral appears solely on the spike band and the
// marker sits at the run's value (three-palette rule).
function AcwrBar({ band, value }: { band: WeekBand; value: number }) {
  // Map ACWR 0.6…1.6 across the bar; clamp the marker inside.
  const pct = Math.max(0, Math.min(1, (value - 0.6) / (1.6 - 0.6))) * 100;
  return (
    <div>
      <div className="relative flex h-2 overflow-hidden rounded">
        <div className="h-full" style={{ flex: 0.6, background: "#DDD8D2" }} />
        <div className="h-full" style={{ flex: 0.2, background: "#CFC9C2" }} />
        <div className="h-full" style={{ flex: 0.5, background: "#BDB6AE" }} />
        <div className="h-full" style={{ flex: 0.2, background: "#CFC9C2" }} />
        <div
          className="h-full"
          style={{ flex: 0.5, background: band === "spike" ? "var(--color-coral)" : "#DDD8D2" }}
        />
        <span
          className="absolute top-[-3px] h-3.5 w-[2px] bg-text-primary"
          style={{ left: `${pct}%` }}
        />
      </div>
      <div className="relative mt-1.5 h-3.5">
        {[
          { l: "0.8", left: "20%", strong: false },
          { l: ACWR_BAND_LABEL[band] ?? band, left: "50%", strong: true },
          { l: "1.3", left: "70%", strong: false },
          { l: "spike", left: "90%", strong: false },
        ].map((t) => (
          <span
            key={t.l}
            className="absolute top-0 -translate-x-1/2 whitespace-nowrap font-mono text-[8px] uppercase tracking-[0.05em]"
            style={{ left: t.left, color: t.strong ? "var(--color-text-secondary)" : "var(--color-text-tertiary)" }}
          >
            {t.l}
          </span>
        ))}
      </div>
    </div>
  );
}

type WeekBand = "detraining" | "low" | "sweet" | "high" | "spike";

"use client";

import Link from "next/link";
import { useState } from "react";
import { EditorialRule, Eyebrow, Section, Spacer } from "@/components/mockup/primitives";
import { CycleOverlay, ShareBar } from "@/components/mockup/charts";
import { CALENDAR, CALENDAR_WEEK_NOTES, DAY_ONE_WEEK, GOAL, RACES, THIS_WEEK, WEEK_TOTALS } from "@/components/mockup/data";
import { EmptyState } from "@/components/mockup/primitives";

/* Train · three modes behind one segmenter (roadmap Phase 3):
     CURRENT  — this week + today
     CALENDAR — month view, past + planned together, plan layered in
     HISTORY  — longer-arc analytics: pace × volume, cycle comparison
   The tab works with or without a plan. `activePlan == nil` is a state,
   not an empty state. */

type View = "current" | "calendar" | "history";

const PACE_VOLUME = [
  { zone: "EASY", miles: 118.4, pct: 62 },
  { zone: "MODERATE", miles: 22.9, pct: 12 },
  { zone: "STEADY", miles: 15.3, pct: 8 },
  { zone: "MP", miles: 17.2, pct: 9, coral: true },
  { zone: "HMP", miles: 3.8, pct: 2 },
  { zone: "LT", miles: 9.5, pct: 5 },
  { zone: "5K · 3K", miles: 3.8, pct: 2 },
];

const THIS_BUILD = [34, 36, 31, 38, 40, 37, 39, 38, 40, 42, 45, 44.6];
const HOUSTON_BUILD = [30, 32, 33, 31, 35, 36, 34, 37, 38, 36, 40, 39];

/** With no plan, the calendar keeps what was run and leaves the rest open. */
const DAY_ONE_CALENDAR = CALENDAR.map((week) =>
  week.map((c) => (c.state === "done" ? c : { ...c, zone: undefined, miles: undefined, state: "future" as const })),
);

export function TrainViews({ dayOne = false }: { dayOne?: boolean }) {
  const [view, setView] = useState<View>("current");
  const [window, setWindow] = useState("12 WK");
  const today = THIS_WEEK.find((d) => d.state === "today")!;
  const week = dayOne ? DAY_ONE_WEEK : THIS_WEEK;

  return (
    <>
      <div className="m-seg m-mt-18" role="tablist">
        {(
          [
            ["current", "CURRENT"],
            ["calendar", "CALENDAR"],
            ["history", "HISTORY"],
          ] as [View, string][]
        ).map(([id, label]) => (
          <button key={id} role="tab" aria-selected={view === id} className={`m-seg__tab${view === id ? " is-active" : ""}`} onClick={() => setView(id)}>
            {label}
          </button>
        ))}
      </div>

      {view === "current" ? (
        <>
          <Spacer h={24} />
          {dayOne ? (
            <>
              <Eyebrow coral>
                TODAY · {today.dow} · {today.dateUpper}
              </Eyebrow>
              <EmptyState
                nudge="Nothing planned for today. Runs you record show up here on their own."
                cta={{ label: "Log a run", href: "/mockup/log?day=1" }}
              />
            </>
          ) : (
            <>
              <div className="m-row">
                <Eyebrow coral>
                  TODAY · {today.dow} · {today.dateUpper}
                </Eyebrow>
                <Eyebrow>
                  {today.plannedMiles} MI · {today.zone.toUpperCase()}
                </Eyebrow>
              </div>
              <h2 className="m-display m-display--m m-mt-6">{today.title}</h2>
              <p className="m-caption m-mt-10">{today.structure}</p>
              <p className="m-quote m-quote--sub m-mt-12">{today.intent}</p>
              <div className="m-flex m-gap-16 m-items-baseline m-mt-18">
                <Link href={`/mockup/train/day/${today.id}`} className="m-link m-link--sm">
                  Open the session ↗
                </Link>
                <Link href="/mockup/log" className="m-link m-link--quiet m-link--sm">
                  Log it ↗
                </Link>
              </div>
            </>
          )}

          <Spacer h={24} />
          <EditorialRule />
          <Spacer h={16} />

          <Section eyebrow="THE WEEK" eyebrowRight={WEEK_TOTALS.range}>
            <div className="m-wkstrip">
              {week.map((d) => {
                // With no plan, a day that has not been run yet is simply open.
                const open = dayOne && !d.actualMiles;
                const inner = (
                  <>
                    <span className="m-wkday__name">{d.dow}</span>
                    <span className="m-wkday__dot" />
                    <span className="m-wkday__miles">{open || d.state === "rest" ? "·" : d.actualMiles ?? d.plannedMiles}</span>
                    <span className="m-wkday__type">{open ? "" : d.zone}</span>
                  </>
                );
                const cls = `m-wkday is-${open ? "rest" : d.state}`;
                if (open || d.state === "rest") return <div key={d.id} className={cls}>{inner}</div>;
                const href = d.workoutId ? `/mockup/workouts/${d.workoutId}` : `/mockup/train/day/${d.id}`;
                return (
                  <Link key={d.id} href={href} className={cls}>
                    {inner}
                  </Link>
                );
              })}
            </div>
          </Section>

          <Spacer h={20} />

          <Section eyebrow="WEEKLY MILEAGE" eyebrowRight={dayOne ? `${WEEK_TOTALS.runsDone} RUNS SO FAR` : `${WEEK_TOTALS.runsDone} OF ${WEEK_TOTALS.runsPlanned} RUNS`}>
            <div className="m-flex m-items-baseline m-gap-8 m-mt-6">
              <span className="m-big-num">{WEEK_TOTALS.done}</span>
              <span className="m-caption">{dayOne ? "MILES THIS WEEK" : `OF ${WEEK_TOTALS.planned} PLANNED`}</span>
            </div>
            {dayOne ? (
              <p className="m-body-sm m-mt-8">Last week 45.0. Four-week average 41.2.</p>
            ) : (
              <p className="m-quote m-quote--faint m-mt-8">Last week 45.0. Three weeks above 40.</p>
            )}
          </Section>

          <Spacer h={24} />
          <EditorialRule />
          <Spacer h={12} />

          {dayOne ? (
            <>
              <Eyebrow>A PLAN, IF YOU WANT ONE</Eyebrow>
              <div className="m-mt-4">
                <div className="m-listrow m-listrow--2 is-link">
                  <div>
                    <span className="m-listrow__label">Start from a template</span>
                    <span className="m-listrow__hint">Marathon, half, 10K. Built around your long-run day.</span>
                  </div>
                  <span className="m-listrow__value is-coral">BROWSE ↗</span>
                </div>
                <div className="m-listrow m-listrow--2 is-link">
                  <div>
                    <span className="m-listrow__label">Join a coach&rsquo;s plan</span>
                    <span className="m-listrow__hint">If someone is writing your weeks, connect here.</span>
                  </div>
                  <span className="m-listrow__value">CONNECT ↗</span>
                </div>
              </div>
              <p className="m-body-sm m-mt-14">Train works either way. Without a plan it shows what you have run.</p>
            </>
          ) : (
            <div className="m-listrow m-listrow--2">
              <div>
                <span className="m-listrow__label">{GOAL.planName}</span>
                <span className="m-listrow__hint">{GOAL.planTemplate}. Change it or drop it; Train keeps working without one.</span>
              </div>
              <span className="m-listrow__value">TEMPLATE ↗</span>
            </div>
          )}
        </>
      ) : null}

      {view === "calendar" ? (
        <>
          <Spacer h={20} />
          <div className="m-row">
            <span className="m-link m-link--mono">← AUG</span>
            <div className="m-center">
              <div className="m-caption m-caption--ink">SEPTEMBER 2026</div>
              <div className="m-caption m-caption--faint m-eyebrow--sm m-mt-4">
                {dayOne ? "WHAT YOU RAN · NOTHING PLANNED" : "PAST + PLANNED · PLAN LAYERED IN"}
              </div>
            </div>
            <span className="m-link m-link--mono">OCT →</span>
          </div>
          <Spacer h={16} />
          <div className="m-cal">
            {["M", "T", "W", "T", "F", "S", "S"].map((d, i) => (
              <div key={i} className="m-cal__dow">
                {d}
              </div>
            ))}
            {(dayOne ? DAY_ONE_CALENDAR : CALENDAR).map((w, wi) => (
              <CalendarWeek key={wi} week={w} note={dayOne ? { ...CALENDAR_WEEK_NOTES[wi], phase: "LOGGED" } : CALENDAR_WEEK_NOTES[wi]} dayOne={dayOne} />
            ))}
          </div>
          <Spacer h={16} />
          <div className="m-legend">
            <span className="m-legend__item">
              <span className="m-wkday__dot m-legend__sw" />
              DONE
            </span>
            <span className="m-legend__item">
              <span className="m-legend__sw is-coral" />
              TODAY
            </span>
            <span className="m-legend__item">
              <span className="m-legend__sw is-dashed" />
              PLANNED
            </span>
          </div>
          <p className={`m-mt-12 ${dayOne ? "m-body-sm" : "m-quote m-quote--faint"}`}>
            {dayOne
              ? "Filled days are runs that synced. The rest are open until you run them or add a plan."
              : "Completed days are what you did. Planned days are the template. Tap any day to open it."}
          </p>
        </>
      ) : null}

      {view === "history" ? (
        <>
          <Spacer h={20} />
          <div className="m-row">
            <Eyebrow coral>TRAINING · LAST {window}</Eyebrow>
            <div className="m-period">
              {["4 WK", "8 WK", "12 WK", "26 WK"].map((w) => (
                <button key={w} className={`m-period__opt${window === w ? " is-active" : ""}`} onClick={() => setWindow(w)}>
                  {w}
                </button>
              ))}
            </div>
          </div>
          <h2 className="m-display m-display--m m-mt-6">Since Houston.</h2>
          {dayOne ? (
            <p className="m-body-sm m-mt-6">Imported from Apple Health. This view never needed a plan.</p>
          ) : (
            <p className="m-quote m-quote--sub m-mt-6">
              Volume climbing 38, 40, 42, 45. Marathon-pace work locking in a few seconds faster each month.
            </p>
          )}

          <Spacer h={20} />
          <div className="m-strip m-strip--3">
            <div className="m-strip__cell"><span className="m-strip__l">TO DATE</span><span className="m-strip__v">464<span>MI</span></span><span className="m-strip__s">{window}</span></div>
            <div className="m-strip__cell"><span className="m-strip__l">AVG WEEK</span><span className="m-strip__v">38.7<span>MI</span></span><span className="m-strip__s">+11% VS HOUSTON</span></div>
            <div className="m-strip__cell"><span className="m-strip__l">LONG TOPS</span><span className="m-strip__v">16<span>MI</span></span><span className="m-strip__s">AUG 16</span></div>
          </div>

          <Section eyebrow={`PACE × VOLUME · ${window}`} eyebrowRight="MILES BY ZONE">
            <div className="m-col m-gap-12 m-mt-8">
              {PACE_VOLUME.map((z) => (
                <div key={z.zone} className="m-pv">
                  <span className="m-pv__lbl">{z.zone}</span>
                  <ShareBar pct={z.pct} coral={z.coral} />
                  <span className="m-pv__val">{z.miles}</span>
                </div>
              ))}
            </div>
            {dayOne ? null : (
              <p className="m-quote m-quote--faint m-mt-10">Easy days stayed easy. That is what let the total climb.</p>
            )}
          </Section>

          <Section eyebrow="CYCLE COMPARISON" eyebrowRight="WEEKS 1–12">
            <div className="m-card m-card--tight m-mt-6">
              <CycleOverlay current={THIS_BUILD} prior={HOUSTON_BUILD} />
              <div className="m-legend">
                <span className="m-legend__item"><span className="m-legend__sw" />THIS BUILD · CIM</span>
                <span className="m-legend__item"><span className="m-legend__sw is-dashed" />HOUSTON BUILD · 2025</span>
              </div>
            </div>
          </Section>

          <Section eyebrow="RACES IN THE WINDOW">
            <div className="m-mt-4">
              {RACES.slice(0, 3).map((r) => (
                <Link key={r.id} href={dayOne ? "/mockup/races?day=1" : "/mockup/races"} className="m-listrow m-listrow--2 is-link">
                  <div>
                    <span className="m-listrow__label">{r.name}</span>
                    <span className="m-listrow__hint">{r.dateUpper} · {r.distance}{r.anchor ? " · ANCHOR" : ""}</span>
                  </div>
                  <span className="m-listrow__value m-listrow__value--lg">{r.time}</span>
                </Link>
              ))}
            </div>
          </Section>
        </>
      ) : null}

      <Spacer h={24} />
    </>
  );
}

function CalendarWeek({
  week,
  note,
  dayOne = false,
}: {
  week: (typeof CALENDAR)[number];
  note: (typeof CALENDAR_WEEK_NOTES)[number];
  dayOne?: boolean;
}) {
  const logged = week.reduce((sum, c) => sum + (parseFloat(c.miles ?? "") || 0), 0);
  return (
    <>
      {week.map((c, i) => {
        const cls = `m-cal__cell is-${c.state}`;
        const inner = (
          <>
            <span className="m-cal__day">
              <span>{c.day}{c.day === 1 ? ` ${c.month}` : ""}</span>
            </span>
            {c.zone ? <span className="m-cal__zone">{c.zone}</span> : null}
            {c.miles ? <span className="m-cal__miles">{c.miles}</span> : null}
          </>
        );
        if (c.state === "rest") return <div key={i} className={cls}>{inner}</div>;
        const href = c.workoutId ? `/mockup/workouts/${c.workoutId}` : c.state === "today" ? "/mockup/train/day/thu" : "/mockup/train/day/sun";
        return (
          <Link key={i} href={href} className={cls}>
            {inner}
          </Link>
        );
      })}
      <div className="m-cal__weeknote">
        <span className="m-caption m-caption--faint m-eyebrow--sm">{note.wk} · {note.phase}</span>
        <span className="m-caption m-caption--faint m-eyebrow--sm">{dayOne ? logged.toFixed(1) : note.miles} MI</span>
      </div>
    </>
  );
}

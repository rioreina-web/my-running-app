"use client";

import { useState } from "react";
import { Eyebrow, MoodPill, StatTile } from "./editorial";

/* ──────────────────────────────────────────────────────────────────────
   APP PREVIEW — the four athlete-facing surfaces, in a device frame.

   Mirrors design-system/ui_kits/ios_app/{Log,Trends,Training,Coach}Screen.jsx
   and the target 4-tab IA (Log · Trends · Train · Coach) from CLAUDE.md.
   Layout only — the numbers are Maya's, held here as sample data.

   The site shows the target IA, not the 5 tabs currently shipping, because
   this is what the product is; Plan is a mode inside Train.
   ────────────────────────────────────────────────────────────────────── */

export type PreviewTab = "log" | "trends" | "train" | "coach";

export const TAB_DEFS: { id: PreviewTab; label: string }[] = [
  { id: "log", label: "Log" },
  { id: "trends", label: "Trends" },
  { id: "train", label: "Train" },
  { id: "coach", label: "Coach" },
];

/** Interactive: tab bar switches the screen. Used on the landing hero. */
export function AppPreview({ initialTab = "log" }: { initialTab?: PreviewTab }) {
  const [tab, setTab] = useState<PreviewTab>(initialTab);
  return (
    <DeviceFrame>
      <Screen tab={tab} />
      <TabBar active={tab} onChange={setTab} />
    </DeviceFrame>
  );
}

/** Static: one fixed surface, no tab interaction. Used on /how-it-works. */
export function AppScreenshot({ tab }: { tab: PreviewTab }) {
  return (
    <DeviceFrame>
      <Screen tab={tab} />
      <TabBar active={tab} />
    </DeviceFrame>
  );
}

function DeviceFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-[340px] rounded-[44px] bg-text-primary p-[10px] shadow-[0_30px_60px_-30px_rgba(26,24,21,0.45)]">
      <div className="relative flex h-[660px] flex-col overflow-hidden rounded-[36px] bg-bg-base">
        <div className="flex items-center justify-between px-6 pt-3 pb-1">
          <Eyebrow>9:41</Eyebrow>
          <div className="h-[18px] w-[70px] rounded-full bg-text-primary" />
          <Eyebrow>Aug 27</Eyebrow>
        </div>
        {children}
      </div>
    </div>
  );
}

function Screen({ tab }: { tab: PreviewTab }) {
  return (
    <div className="flex-1 overflow-hidden">
      {tab === "log" && <LogSurface />}
      {tab === "trends" && <TrendsSurface />}
      {tab === "train" && <TrainSurface />}
      {tab === "coach" && <CoachSurface />}
    </div>
  );
}

/* ── LOG ─────────────────────────────────────────────────────────────── */

const JOURNAL = [
  {
    day: "Tuesday",
    meta: "Aug 26 · 8.2 mi · 8:22 / mi · 1:08:44",
    body:
      "Legs were heavy the first two miles, then it clicked. Held 8:10s coming home without pushing for them.",
    mood: "positive",
    niggle: "L. achilles",
    rail: "var(--color-mood-positive)",
  },
  {
    day: "Monday",
    meta: "Aug 25 · Rest",
    body: "Work ran long. Walked the dog and called it a day.",
    mood: "neutral",
    rail: "var(--color-text-tertiary)",
  },
  {
    day: "Sunday",
    meta: "Aug 24 · 16.0 mi · 8:48 / mi · 2:20:48",
    body:
      "Long one. Fueled at 6 and 12 this time, which helped. Last three miles were a grind.",
    mood: "tired",
    rail: "var(--color-mood-tired)",
  },
];

function LogSurface() {
  return (
    <div className="h-full overflow-y-auto">
      <PlateStripCompact surface="Log · voice + journal" fig="Fig. 01" />

      <div className="flex flex-col items-center px-6 pt-6 pb-5">
        <div className="relative grid h-[104px] w-[104px] place-items-center">
          <div className="prd-record-ring absolute inset-0 rounded-full border-[1.5px] border-coral/20" />
          <div className="grid h-[80px] w-[80px] place-items-center rounded-full bg-coral shadow-[0_4px_12px_rgba(212,89,42,0.30)]">
            <div className="h-7 w-7 rounded-full bg-white" />
          </div>
        </div>
        <p className="mt-3 font-body text-[13px] italic text-text-tertiary">
          Hold to log the run in your own words.
        </p>
      </div>

      <div className="grid grid-cols-2 border-y border-divider">
        <div className="pt-3 text-center">
          <span className="font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-coral">
            Voice
          </span>
          <div className="mt-2.5 h-[2px] bg-coral" />
        </div>
        <div className="pt-3 text-center">
          <span className="font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-text-secondary">
            Manual
          </span>
          <div className="mt-2.5 h-[2px] bg-transparent" />
        </div>
      </div>

      <div className="flex items-baseline justify-between px-6 pt-5 pb-2">
        <Eyebrow coral>Journal · last 6 months</Eyebrow>
        <Eyebrow>128 entries</Eyebrow>
      </div>

      {JOURNAL.map((entry) => (
        <div
          key={entry.day}
          className="grid grid-cols-[2px_1fr] gap-3.5 border-b border-divider px-6 py-5"
        >
          <div
            className="my-1 rounded-[1px]"
            style={{ background: entry.rail }}
          />
          <div>
            <div className="font-display text-[19px] font-bold tracking-[-0.01em] text-text-primary">
              {entry.day}
            </div>
            <div className="mt-1 font-mono text-[9px] font-medium tracking-[0.08em] uppercase text-text-secondary">
              {entry.meta}
            </div>
            <p className="mt-3 font-body text-[13px] italic leading-[1.55] text-text-primary">
              “{entry.body}”
            </p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <MoodPill mood={entry.mood} />
              {entry.niggle && (
                <span className="inline-flex rounded-full border border-divider px-2 py-[3px] font-mono text-[9px] font-medium tracking-[0.10em] uppercase text-text-secondary">
                  {entry.niggle}
                </span>
              )}
            </div>
          </div>
        </div>
      ))}
      <div className="h-6" />
    </div>
  );
}

/* ── TRENDS ──────────────────────────────────────────────────────────── */

function TrendsSurface() {
  return (
    <div className="h-full overflow-y-auto">
      <PlateStripCompact surface="Trends · analytics surface" fig="Fig. 02" />

      <div className="px-6 pt-5">
        <div className="flex items-baseline justify-between">
          <Eyebrow coral>Opening figure</Eyebrow>
          <Eyebrow>26 wk</Eyebrow>
        </div>
        <h2 className="mt-2 font-display text-[28px] font-bold leading-[1.05] tracking-[-0.01em] text-text-primary">
          The 5-second view.
        </h2>
        <p className="mt-1 font-body text-[12px] italic text-text-tertiary">
          — August 2026 · 26 weeks logged. —
        </p>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-2.5 px-6">
        <StatTile
          label="Volume · 7d"
          value="42.4"
          unit="mi"
          caption="+6% vs 4-wk avg"
          captionTone="good"
        />
        <StatTile
          label="Marathon"
          value="3:19–3:25"
          size="sm"
          caption="Mid 3:22 · high"
          captionTone="coral"
        />
        <StatTile
          label="Load · ACWR"
          value="1.12"
          unit="ratio"
          caption="Productive"
          captionTone="good"
        />
        <StatTile
          label="Niggles"
          value="1"
          unit="tracking"
          caption="L. achilles"
          captionTone="watch"
        />
      </div>

      <div className="px-6 pt-6">
        <div className="flex items-baseline justify-between border-b border-divider pb-2">
          <Eyebrow>Fitness · 26 weeks</Eyebrow>
          <Eyebrow>Race-anchored</Eyebrow>
        </div>
        <div className="mt-3 rounded-xl bg-bg-card p-3.5 shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
          <FitnessChart />
          <div className="mt-2 flex items-baseline justify-between">
            <Eyebrow>Mar</Eyebrow>
            <Eyebrow className="!text-coral">Goal 3:16</Eyebrow>
            <Eyebrow>Aug</Eyebrow>
          </div>
        </div>
        <p className="mt-3 font-body text-[12px] italic leading-[1.5] text-text-tertiary">
          — anchored to your 3:28 marathon and two halves since. Range
          widens where the training thins out. —
        </p>
      </div>

      <div className="px-6 pt-6 pb-8">
        <div className="flex items-baseline justify-between border-b border-divider pb-2">
          <Eyebrow>Volume · weekly</Eyebrow>
          <Eyebrow>13 wk · mi</Eyebrow>
        </div>
        <div className="mt-3 flex h-16 items-end gap-[3px]">
          {[31, 34, 30, 36, 38, 34, 40, 43, 38, 44, 46, 40, 42].map((h, i) => (
            <div
              key={i}
              className="flex-1 rounded-t-[1px] bg-text-tertiary"
              style={{
                height: `${h * 1.35}%`,
                opacity: i === 12 ? 1 : 0.55,
                background:
                  i === 12 ? "var(--color-text-primary)" : undefined,
              }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

/** 26-week fitness line with race anchors as vertical markers + goal line. */
function FitnessChart() {
  const pts = [
    218, 216, 217, 214, 212, 213, 210, 208, 209, 206, 204, 205, 203,
    202, 203, 201, 199, 200, 198, 197, 196, 197, 195, 194, 193, 192,
  ];
  const w = 280;
  const h = 84;
  const min = Math.min(...pts) - 3;
  const max = Math.max(...pts) + 3;
  const x = (i: number) => (i / (pts.length - 1)) * w;
  const y = (v: number) => h - ((v - min) / (max - min)) * (h - 10) - 5;
  const path = pts
    .map((v, i) => `${i === 0 ? "M" : "L"} ${x(i).toFixed(1)} ${y(v).toFixed(1)}`)
    .join(" ");
  const band = pts
    .map((v, i) => `${i === 0 ? "M" : "L"} ${x(i).toFixed(1)} ${y(v + 4).toFixed(1)}`)
    .concat(
      [...pts]
        .reverse()
        .map((v, i) => `L ${x(pts.length - 1 - i).toFixed(1)} ${y(v - 4).toFixed(1)}`)
    )
    .join(" ");

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-[84px] w-full" role="img" aria-label="26-week fitness trend with race anchors">
      {/* goal line — direction, not destination */}
      <line
        x1="0"
        x2={w}
        y1={y(191)}
        y2={y(191)}
        stroke="#D4592A"
        strokeWidth="1"
        strokeDasharray="3 4"
        opacity="0.7"
      />
      {/* confidence band — predictions never ship as a single point */}
      <path d={`${band} Z`} fill="#1A1815" opacity="0.06" />
      <path d={path} fill="none" stroke="#1A1815" strokeWidth="1.5" strokeLinejoin="round" />
      {/* race anchors */}
      {[4, 17].map((i) => (
        <g key={i}>
          <line x1={x(i)} x2={x(i)} y1="0" y2={h} stroke="#9B9590" strokeWidth="1" strokeDasharray="2 3" />
          <circle cx={x(i)} cy={y(pts[i])} r="3" fill="#D4592A" />
        </g>
      ))}
      <circle cx={x(pts.length - 1)} cy={y(pts[pts.length - 1])} r="3.5" fill="#1A1815" />
    </svg>
  );
}

/* ── TRAIN ───────────────────────────────────────────────────────────── */

const WEEK = [
  { d: "M", label: "Rest", pace: "", state: "done" },
  { d: "T", label: "MP 7 mi", pace: "7:28 / mi", state: "done" },
  { d: "W", label: "Easy 6 mi", pace: "8:35 / mi", state: "done" },
  { d: "T", label: "LT 6 mi", pace: "7:04 / mi", state: "today" },
  { d: "F", label: "Easy 5 mi", pace: "8:40 / mi", state: "ahead" },
  { d: "S", label: "Easy 6 mi", pace: "8:40 / mi", state: "ahead" },
  { d: "S", label: "Long 17 mi", pace: "8:45 / mi", state: "ahead" },
];

function TrainSurface() {
  return (
    <div className="h-full overflow-y-auto">
      <PlateStripCompact surface="Train · current" fig="Fig. 03" />

      <div className="grid grid-cols-3 border-b border-divider">
        {["Current", "Calendar", "History"].map((m, i) => (
          <div key={m} className="pt-3 text-center">
            <span
              className={`font-mono text-[10px] font-medium tracking-[0.12em] uppercase ${
                i === 0 ? "text-coral" : "text-text-secondary"
              }`}
            >
              {m}
            </span>
            <div className={`mt-2.5 h-[2px] ${i === 0 ? "bg-coral" : "bg-transparent"}`} />
          </div>
        ))}
      </div>

      <div className="px-6 pt-5">
        <Eyebrow coral>Build · week 7 of 16</Eyebrow>
        <h2 className="mt-2 font-display text-[28px] font-bold leading-[1.05] tracking-[-0.01em] text-text-primary">
          Thursday.
        </h2>
        <p className="mt-1 font-body text-[12px] italic text-text-tertiary">
          — 47 mi this week · 21 logged · 91 days to Chicago. —
        </p>
      </div>

      <div className="mt-4 flex gap-1.5 px-6">
        {WEEK.map((day, i) => (
          <div
            key={i}
            className={`flex flex-1 flex-col items-center gap-1.5 rounded-lg py-2 ${
              day.state === "today" ? "bg-bg-card ring-[1.5px] ring-coral" : ""
            }`}
          >
            <span className="font-mono text-[9px] font-medium tracking-[0.08em] uppercase text-text-secondary">
              {day.d}
            </span>
            <span
              className={`h-[6px] w-[6px] rounded-full ${
                day.state === "done"
                  ? "bg-text-primary"
                  : day.state === "today"
                    ? "bg-coral"
                    : "bg-divider"
              }`}
            />
          </div>
        ))}
      </div>

      <div className="px-6 pt-6">
        <div className="flex items-baseline justify-between border-b border-divider pb-2">
          <Eyebrow>This week</Eyebrow>
          <Eyebrow>Zone · target</Eyebrow>
        </div>
        {WEEK.map((day, i) => (
          <div
            key={i}
            className="flex items-baseline justify-between border-b border-divider py-3"
          >
            <div>
              <span
                className={`font-display text-[15px] font-semibold ${
                  day.state === "today" ? "text-coral" : "text-text-primary"
                }`}
              >
                {day.label}
              </span>
              <span className="mt-0.5 block font-mono text-[9px] font-medium tracking-[0.08em] uppercase text-text-tertiary">
                {day.state === "done"
                  ? "Logged"
                  : day.state === "today"
                    ? "Today"
                    : "Planned"}
              </span>
            </div>
            <span className="font-mono text-[13px] font-semibold tabular-nums text-text-secondary">
              {day.pace || "—"}
            </span>
          </div>
        ))}
        <p className="mt-3 pb-8 font-body text-[12px] italic leading-[1.5] text-text-tertiary">
          — paces derived from your 3:28 marathon, not your goal time. —
        </p>
      </div>
    </div>
  );
}

/* ── COACH ───────────────────────────────────────────────────────────── */

const LENSES = [
  "How does this cycle compare to my last?",
  "What's my long run doing?",
  "Read my last three weeks.",
];

function CoachSurface() {
  return (
    <div className="h-full overflow-y-auto">
      <PlateStripCompact surface="Coach · the daily read" fig="Fig. 04" />

      <div className="px-6 pt-6">
        <Eyebrow coral>Wednesday · Aug 27</Eyebrow>
        <h2 className="mt-2 font-display text-[27px] font-bold leading-[1.08] tracking-[-0.01em] text-text-primary">
          Easy is getting easier.
        </h2>

        <div className="mt-4 space-y-3 font-body text-[14px] leading-[1.6] text-text-primary">
          <p>
            You said Tuesday felt heavy for two miles and then clicked. That
            matches what the splits did — 8:35 out, 8:10 home, and you
            didn&rsquo;t push for the second half.
          </p>
          <p>
            Easy pace has come down about 13 seconds a mile over four weeks
            while volume held at 42. Same effort, faster running.
          </p>
          <p>
            The left achilles has shown up in three logs this month, always on
            the morning after a long run.
          </p>
        </div>

        <p className="mt-4 font-body text-[14px] italic leading-[1.6] text-text-secondary">
          Does the achilles ease off once you&rsquo;re warm, or does it stay
          with you? And is 42 a week still feeling like a floor, or is it
          starting to feel like a ceiling?
        </p>

        <div className="mt-6 border-t border-divider pt-4">
          <Eyebrow>Read it another way</Eyebrow>
          <div className="mt-3 flex flex-col gap-2">
            {LENSES.map((lens) => (
              <span
                key={lens}
                className="rounded-full border border-divider bg-bg-card px-3 py-2 font-display text-[13px] font-medium text-text-primary"
              >
                {lens}
              </span>
            ))}
          </div>
        </div>

        <p className="mt-5 pb-8 font-body text-[11px] italic leading-[1.5] text-text-tertiary">
          Not medical advice. If anything gets sharper, see a clinician.
        </p>
      </div>
    </div>
  );
}

/* ── Chrome ──────────────────────────────────────────────────────────── */

function PlateStripCompact({
  surface,
  fig,
}: {
  surface: string;
  fig: string;
}) {
  return (
    <div className="flex items-start justify-between border-b border-divider px-6 py-2.5">
      <div className="flex flex-col gap-0.5">
        <Eyebrow className="!text-text-primary">Running log</Eyebrow>
        <Eyebrow>— {surface}</Eyebrow>
      </div>
      <Eyebrow>{fig}</Eyebrow>
    </div>
  );
}

function TabBar({
  active,
  onChange,
}: {
  active: PreviewTab;
  onChange?: (tab: PreviewTab) => void;
}) {
  return (
    <div className="grid grid-cols-4 border-t border-divider bg-bg-base px-2 pt-2.5 pb-4">
      {TAB_DEFS.map((tab) => {
        const isActive = tab.id === active;
        const content = (
          <>
            <span
              className={`h-[6px] w-[6px] rounded-full ${
                isActive ? "bg-coral" : "bg-transparent"
              }`}
            />
            <span
              className={`font-mono text-[10px] font-medium tracking-[0.12em] uppercase ${
                isActive ? "text-coral" : "text-text-secondary"
              }`}
            >
              {tab.label}
            </span>
          </>
        );
        return onChange ? (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            aria-pressed={isActive}
            className="flex flex-col items-center gap-1.5 py-1"
          >
            {content}
          </button>
        ) : (
          <div key={tab.id} className="flex flex-col items-center gap-1.5 py-1">
            {content}
          </div>
        );
      })}
    </div>
  );
}

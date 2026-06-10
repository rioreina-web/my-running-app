import type { Metadata } from "next";
import Link from "next/link";

/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — TRAINING SUMMARY (preview port)
   Ported from /Post Run Drip Design System/training-summary.jsx (v1).
   "This week" at a glance. The dashboard, in editorial form.

   This is a DESIGN PREVIEW with mock data. No Supabase wiring.
   ════════════════════════════════════════════════════════════════════ */

export const metadata: Metadata = {
  title: "Training summary · Design preview",
  description: "Design preview ported from training-summary.jsx (mock data).",
  robots: { index: false, follow: false },
};

const ACCENT = "#D4592A";
const SAGE = "#6B8068";

type MoodKey =
  | "energized"
  | "positive"
  | "neutral"
  | "tired"
  | "struggling"
  | "injured";

const MOOD: Record<MoodKey, { color: string; label: string }> = {
  energized: { color: "#2D8A4E", label: "Energized" },
  positive: { color: "#4A9E6B", label: "Positive" },
  neutral: { color: "#9B9590", label: "Neutral" },
  tired: { color: "#C4873A", label: "Tired" },
  struggling: { color: "#C45A3A", label: "Struggling" },
  injured: { color: "#B83A4A", label: "Injured" },
};

/* ── Helpers ─────────────────────────────────────────────────────── */
function Mono({
  children,
  color = "#9B9590",
  className = "",
  weight,
}: {
  children: React.ReactNode;
  color?: string;
  className?: string;
  weight?: number;
}) {
  return (
    <span
      className={`font-mono text-[10.5px] tracking-[1.5px] uppercase ${className}`}
      style={{ color, fontWeight: weight }}
    >
      {children}
    </span>
  );
}

function paceToMin(p: string | null): number | null {
  if (!p) return null;
  const [m, s] = p.split(":").map(Number);
  return m + s / 60;
}
function formatPace(min: number): string {
  if (!min) return "—";
  const m = Math.floor(min);
  const s = Math.round((min - m) * 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/* ── DATA ─────────────────────────────────────────────────────────── */

const WEEK_LABEL = { start: "May 11", end: "May 17", year: "2026" };

type WeekDay = {
  day: string;
  date: string;
  miles: number;
  pace: string | null;
  mood: MoodKey | null;
  type: string;
};

const WEEK_DAYS: WeekDay[] = [
  { day: "MON", date: "May 11", miles: 0, pace: null, mood: null, type: "rest" },
  { day: "TUE", date: "May 12", miles: 8.0, pace: "7:14", mood: "positive", type: "tempo" },
  { day: "WED", date: "May 13", miles: 6.0, pace: "8:32", mood: "positive", type: "easy" },
  { day: "THU", date: "May 14", miles: 8.0, pace: "8:08", mood: "neutral", type: "medium" },
  { day: "FRI", date: "May 15", miles: 5.0, pace: "8:36", mood: "energized", type: "easy" },
  { day: "SAT", date: "May 16", miles: 0, pace: null, mood: null, type: "planned" },
  { day: "SUN", date: "May 17", miles: 0, pace: null, mood: null, type: "planned" },
];

const WEEK_TOTALS = (() => {
  const done = WEEK_DAYS.filter((d) => d.miles > 0);
  const miles = done.reduce((s, d) => s + d.miles, 0);
  const planned = 51;
  const totalMin = done.reduce(
    (s, d) => s + (paceToMin(d.pace) || 0) * d.miles,
    0
  );
  const avgPace = miles > 0 ? totalMin / miles : 0;
  const moods = done.map((d) => d.mood).filter(Boolean) as MoodKey[];
  const moodCounts = moods.reduce<Record<string, number>>(
    (acc, m) => ((acc[m] = (acc[m] || 0) + 1), acc),
    {}
  );
  const topMood =
    (Object.entries(moodCounts).sort(
      (a, b) => b[1] - a[1]
    )[0]?.[0] as MoodKey) || "neutral";
  return {
    miles,
    planned,
    runs: done.length,
    avgPace,
    avgPaceLabel: formatPace(avgPace),
    topMood,
  };
})();

type Week = {
  label: string;
  miles: number;
  qualities: number;
  current?: boolean;
  partial?: boolean;
};

const FOUR_WEEKS: Week[] = [
  { label: "Apr 20", miles: 48, qualities: 2 },
  { label: "Apr 27", miles: 42, qualities: 1 },
  { label: "May 4", miles: 50, qualities: 2 },
  { label: "May 11", miles: WEEK_TOTALS.miles, qualities: 1, current: true, partial: true },
];

const MOOD_GRID: (MoodKey | null)[][] = [
  [null, "positive", "neutral", null, "positive", "energized", "tired"],
  ["positive", "positive", "tired", null, "neutral", "positive", "struggling"],
  ["positive", "energized", "positive", null, "positive", "positive", "energized"],
  [null, "positive", "positive", "neutral", "energized", null, null],
];

type Run = {
  date: string;
  weekday: string;
  type: string;
  miles: number;
  duration: string;
  pace: string;
  mood: MoodKey;
  note: string;
};

const RECENT: Run[] = [
  { date: "May 12", weekday: "TUE", type: "tempo", miles: 8.0, duration: "1:00", pace: "7:14", mood: "positive", note: "5 × 1 mi at threshold. Last four inside 7:00." },
  { date: "May 10", weekday: "SUN", type: "long", miles: 16.0, duration: "2:18", pace: "8:38", mood: "tired", note: "Sixteen on a warm day. Hydrated late." },
  { date: "May 8", weekday: "FRI", type: "easy", miles: 5.0, duration: "43:00", pace: "8:36", mood: "energized", note: "Easy + 4 × 100 m strides. Body catching up." },
  { date: "May 6", weekday: "WED", type: "intervals", miles: 6.5, duration: "52:00", pace: "7:12", mood: "positive", note: "6 × 800 m on track. Clean negative split." },
  { date: "May 2", weekday: "SAT", type: "race", miles: 13.1, duration: "1:27:08", pace: "6:38", mood: "energized", note: "Tune-up HM. Goal-race indicator." },
];

const NIGGLES = [
  { part: "L. Achilles", last: "May 10", quote: "tight first mile, eased up", severity: "passing", trend: "down" },
];

const UPCOMING = [
  { kind: "workout", label: "Saturday's long run", in: "3 days", detail: "18 mi · last 4 at MP" },
  { kind: "race", label: "Boston Marathon", in: "8 weeks", detail: "Jul 12 · goal sub-3:15" },
];

/* ════════════════════════════════════════════════════════════════════ */
export default function TrainingSummaryPreview() {
  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <div className="flex flex-1 flex-col overflow-hidden">
          <TopNav />
          <main className="flex-1 overflow-y-auto">
            <SummaryPage />
          </main>
        </div>
      </div>
    </div>
  );
}

/* ── SIDEBAR ─────────────────────────────────────────────────────── */
function Sidebar() {
  const items = [
    { label: "Dashboard", on: true },
    { label: "Training log", on: false },
    { label: "Coach", on: false },
    { label: "Plan", on: false },
  ];
  const more = [
    { label: "Coach portal", href: "#" },
    { label: "Goals", href: "#" },
    { label: "Analysis", href: "/design/training-analysis" },
    { label: "Injuries", href: "#" },
    { label: "Fitness predictor", href: "/design/fitness-predictor" },
    { label: "Pace chart", href: "#" },
    { label: "Content library", href: "#" },
  ];
  return (
    <aside className="hidden sm:flex flex-col w-[224px] shrink-0 bg-bg-base border-r border-divider">
      <div className="px-5 py-5 border-b border-divider">
        <span className="font-display text-[18px] tracking-[-0.01em]">
          Post Run Drip
        </span>
      </div>
      <nav className="flex-1 overflow-y-auto px-3 py-4">
        <Mono className="px-2">PRIMARY</Mono>
        <ul className="mt-2 space-y-0.5">
          {items.map((it) => (
            <li key={it.label}>
              <a
                href="#"
                className={`block px-3 py-1.5 rounded-md text-[13px] ${
                  it.on
                    ? "bg-coral/10 text-coral font-semibold"
                    : "text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                }`}
              >
                {it.label}
              </a>
            </li>
          ))}
        </ul>
        <div className="mt-6">
          <Mono className="px-2">MORE</Mono>
          <ul className="mt-2 space-y-0.5">
            {more.map((it) => (
              <li key={it.label}>
                <a
                  href={it.href}
                  className="block px-3 py-1.5 rounded-md text-[13px] text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                >
                  {it.label}
                </a>
              </li>
            ))}
          </ul>
        </div>
      </nav>
      <div className="border-t border-divider px-4 py-3 flex items-center gap-2.5">
        <span className="h-8 w-8 rounded-full bg-coral/15 flex items-center justify-center font-display text-[15px] text-coral">
          M
        </span>
        <div className="leading-tight">
          <p className="text-[12.5px] text-text-primary">M. Kerr</p>
          <p className="font-mono text-[9.5px] tracking-[1.2px] text-text-tertiary uppercase">
            Athlete
          </p>
        </div>
      </div>
    </aside>
  );
}

function TopNav() {
  return (
    <header className="bg-bg-base border-b border-divider px-8 py-3 flex items-center justify-between">
      <Mono>RUNNING LOG · DASHBOARD · PREVIEW</Mono>
      <div className="flex items-center gap-5">
        <a href="#" className="text-[13px] text-text-secondary hover:text-text-primary">
          Voice log
        </a>
        <a href="#" className="text-[13px] text-text-secondary hover:text-text-primary">
          Ask coach
        </a>
        <Link
          href="/design"
          className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary hover:text-coral transition-colors"
        >
          ← Design index
        </Link>
        <span className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
          Thu · May 14
        </span>
      </div>
    </header>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PAGE
   ════════════════════════════════════════════════════════════════════ */
function SummaryPage() {
  return (
    <div className="mx-auto max-w-[1080px] px-10 py-10 space-y-12">
      <PlateHeader />
      <Lede />
      <StatsGrid />
      <WeekStrip />
      <TwoUp />
      <RecentRuns />
      <SignaturesAndUpcoming />
      <CoachPull />
      <Footer />
    </div>
  );
}

function PlateHeader() {
  return (
    <div className="flex items-baseline justify-between border-b border-divider-soft pb-3">
      <Mono>RUNNING LOG · TRAINING SUMMARY</Mono>
      <Mono>WK 9 OF 16 · SUB-3:15 MARATHON BUILD</Mono>
    </div>
  );
}

function Lede() {
  const t = WEEK_TOTALS;
  return (
    <section>
      <Mono color={ACCENT}>
        THIS WEEK · {WEEK_LABEL.start} – {WEEK_LABEL.end}
      </Mono>
      <h1 className="mt-3 font-display text-[64px] leading-[0.98] tracking-[-0.02em] max-w-[840px]">
        <span className="tabular-nums">{t.miles.toFixed(1)}</span> miles
        <span className="text-text-tertiary"> across </span>
        <span className="tabular-nums">{t.runs}</span> runs
        <br />
        <em className="font-display italic text-text-secondary">
          averaging{" "}
          <span style={{ color: ACCENT }} className="tabular-nums">
            {t.avgPaceLabel}
          </span>{" "}
          a mile.
        </em>
      </h1>
      <p className="mt-5 max-w-[640px] font-body text-[16px] leading-[1.6] text-text-secondary">
        Halfway through the week and the build is holding. Tuesday&rsquo;s
        tempo was the centerpiece; Sunday&rsquo;s 18 is the test that follows.
      </p>
    </section>
  );
}

/* ── stats grid ──────────────────────────────────────────────────── */
function StatsGrid() {
  const t = WEEK_TOTALS;
  const milesPct = Math.round((t.miles / t.planned) * 100);
  return (
    <section className="grid grid-cols-2 md:grid-cols-4 gap-0 border-y border-divider divide-x divide-divider">
      <StatCell
        label="MILES"
        value={t.miles.toFixed(1)}
        unit="mi"
        hint={`${milesPct}% of ${t.planned} planned`}
        accent
      >
        <MileagePctBar pct={milesPct} accent={ACCENT} />
      </StatCell>

      <StatCell label="RUNS" value={String(t.runs)} unit="of 6" hint="1 quality · 1 rest">
        <RunsDots done={t.runs} planned={6} />
      </StatCell>

      <StatCell
        label="AVG PACE"
        value={t.avgPaceLabel}
        unit="/ mi"
        hint="↓ 8 sec vs last week"
        trend="up"
      >
        <DailyPaceLine days={WEEK_DAYS} accent={ACCENT} />
      </StatCell>

      <StatCell label="MOOD" value={MOOD[t.topMood].label} hint="across the run days">
        <MoodPills days={WEEK_DAYS} />
      </StatCell>
    </section>
  );
}

function StatCell({
  label,
  value,
  unit,
  hint,
  accent,
  trend,
  children,
}: {
  label: string;
  value: string;
  unit?: string;
  hint?: string;
  accent?: boolean;
  trend?: "up" | "down";
  children?: React.ReactNode;
}) {
  return (
    <div className="px-6 py-6">
      <Mono color={accent ? ACCENT : "#9B9590"}>{label}</Mono>
      <p className="mt-2 font-display text-[40px] leading-none tabular-nums tracking-[-0.02em]">
        {value}
        {unit ? (
          <span className="ml-1.5 font-mono text-[11px] tracking-[1.4px] uppercase text-text-tertiary">
            {unit}
          </span>
        ) : null}
      </p>
      {hint ? (
        <p className="mt-1.5 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary inline-flex items-center gap-1">
          {trend === "up" ? <span style={{ color: "#2D8A4E" }}>↑</span> : null}
          {trend === "down" ? <span style={{ color: "#C45A3A" }}>↓</span> : null}
          {hint}
        </p>
      ) : null}
      {children ? <div className="mt-4">{children}</div> : null}
    </div>
  );
}

function MileagePctBar({ pct, accent }: { pct: number; accent: string }) {
  return (
    <div className="relative h-1.5 bg-divider/60 rounded-[1px] overflow-hidden">
      <div
        className="absolute inset-y-0 left-0"
        style={{ width: `${Math.min(100, pct)}%`, background: accent }}
      />
    </div>
  );
}

function RunsDots({ done, planned }: { done: number; planned: number }) {
  return (
    <div className="flex items-center gap-1.5">
      {Array.from({ length: planned }).map((_, i) => (
        <span
          key={i}
          className="block h-2 w-2 rounded-full"
          style={{
            background: i < done ? "#1A1815" : "transparent",
            border: i < done ? "none" : "1px solid #C4C0BB",
          }}
        />
      ))}
    </div>
  );
}

function DailyPaceLine({ days, accent }: { days: WeekDay[]; accent: string }) {
  const paces = days.map((d) => paceToMin(d.pace));
  const valid = paces.filter((p): p is number => p !== null);
  if (!valid.length) return null;
  const min = Math.min(...valid);
  const max = Math.max(...valid);
  const range = Math.max(0.6, max - min);
  return (
    <div className="relative h-6">
      <div className="absolute top-1/2 left-0 right-0 h-px bg-divider" />
      <div className="absolute inset-0 flex items-center justify-between">
        {paces.map((p, i) => {
          if (!p) return <span key={i} className="w-2" />;
          const y = ((p - min) / range) * 16;
          return (
            <span
              key={i}
              className="block w-2 h-2 rounded-full"
              style={{
                background: accent,
                transform: `translateY(${-y + 8}px)`,
              }}
            />
          );
        })}
      </div>
    </div>
  );
}

function MoodPills({ days }: { days: WeekDay[] }) {
  return (
    <div className="flex items-center gap-1">
      {days.map((d, i) => (
        <span
          key={i}
          className="flex-1 h-2 rounded-[1px]"
          style={{
            background: d.mood ? MOOD[d.mood].color : "transparent",
            border: d.mood ? "none" : "1px solid #C4C0BB",
            opacity: d.mood ? 0.85 : 1,
          }}
          title={d.mood ? `${d.day} · ${MOOD[d.mood].label}` : `${d.day} · no run`}
        />
      ))}
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   THE WEEK STRIP — Mon–Sun. miles + mood, today highlighted.
   ════════════════════════════════════════════════════════════════════ */
function WeekStrip() {
  const TODAY_IDX = 3; // Thu
  const maxMiles = Math.max(...WEEK_DAYS.map((d) => d.miles), 8);
  return (
    <section>
      <div className="flex items-baseline justify-between border-b border-divider-soft pb-3 mb-5">
        <Mono>FIG. A · DAY BY DAY</Mono>
        <Mono>MON – SUN</Mono>
      </div>
      <div className="grid grid-cols-7 border border-divider rounded-lg overflow-hidden bg-bg-card">
        {WEEK_DAYS.map((d, i) => {
          const isToday = i === TODAY_IDX;
          const isPast = i < TODAY_IDX;
          const isFuture = i > TODAY_IDX;
          const h = (d.miles / maxMiles) * 64;
          return (
            <div
              key={d.day}
              className={`relative px-3 py-4 ${i < 6 ? "border-r border-divider-soft" : ""}`}
              style={{ background: isToday ? "rgba(212,89,42,0.05)" : "transparent" }}
            >
              {isToday ? (
                <span
                  aria-hidden
                  className="absolute left-0 top-0 right-0 h-[2px]"
                  style={{ background: ACCENT }}
                />
              ) : null}
              <Mono color={isToday ? ACCENT : "#9B9590"} weight={isToday ? 700 : 500}>
                {d.day}
              </Mono>
              <p className="mt-0.5 font-mono text-[9.5px] text-text-tertiary tabular-nums">
                {d.date.replace("May ", "")}
              </p>

              <div className="mt-3 h-[64px] flex items-end">
                {d.miles > 0 ? (
                  <div
                    className="w-full rounded-[1px]"
                    style={{
                      height: `${h}px`,
                      background:
                        d.type === "tempo" || d.type === "intervals"
                          ? ACCENT
                          : d.type === "long"
                            ? SAGE
                            : "#1A1815",
                      opacity: 0.85,
                    }}
                  />
                ) : (
                  <div className="w-full h-px bg-divider" />
                )}
              </div>

              <p className="mt-2 font-mono tabular-nums text-[12px] text-text-primary">
                {d.miles > 0 ? d.miles.toFixed(1) : isFuture ? "—" : "rest"}
                {d.miles > 0 ? (
                  <span className="ml-0.5 text-[9px] tracking-[1.3px] uppercase text-text-tertiary">
                    mi
                  </span>
                ) : null}
              </p>

              <div className="mt-1.5 h-2">
                {d.mood ? (
                  <span
                    className="block h-1.5 w-1.5 rounded-full"
                    style={{ background: MOOD[d.mood].color, opacity: 0.85 }}
                  />
                ) : null}
              </div>

              {isPast && d.miles > 0 ? (
                <p className="mt-1 font-mono text-[9px] tracking-[1.2px] uppercase text-mood-positive">
                  ✓ done
                </p>
              ) : isFuture && d.type === "planned" ? (
                <p className="mt-1 font-mono text-[9px] tracking-[1.2px] uppercase text-text-tertiary">
                  planned
                </p>
              ) : isToday ? (
                <p
                  className="mt-1 font-mono text-[9px] tracking-[1.2px] uppercase"
                  style={{ color: ACCENT }}
                >
                  today
                </p>
              ) : (
                <p className="mt-1 font-mono text-[9px] tracking-[1.2px] uppercase text-text-tertiary">
                  &nbsp;
                </p>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   TWO-UP — mileage trajectory + mood heatmap
   ════════════════════════════════════════════════════════════════════ */
function TwoUp() {
  return (
    <section className="grid lg:grid-cols-2 gap-x-8 gap-y-10">
      <TrajectoryTile />
      <MoodTile />
    </section>
  );
}

function TrajectoryTile() {
  const max = Math.max(...FOUR_WEEKS.map((w) => w.miles)) * 1.15;
  return (
    <article className="border border-divider bg-bg-card rounded-lg p-6">
      <div className="flex items-baseline justify-between">
        <Mono>FIG. B · MILEAGE · LAST 4 WEEKS</Mono>
        <Mono>MILES / WK</Mono>
      </div>
      <div className="mt-4">
        <TrajectoryChart weeks={FOUR_WEEKS} max={max} accent={ACCENT} />
      </div>
      <p className="mt-4 font-body italic text-[13px] leading-[1.5] text-text-secondary">
        Build climbing back after last week&rsquo;s deload. Peak weeks 10–13.
      </p>
    </article>
  );
}

function TrajectoryChart({
  weeks,
  max,
  accent,
}: {
  weeks: Week[];
  max: number;
  accent: string;
}) {
  const W = 480;
  const H = 180;
  const padL = 40;
  const padR = 12;
  const padT = 14;
  const padB = 34;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const slot = innerW / weeks.length;
  const barW = slot * 0.5;

  const yTicks = [0, 20, 40, 60];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {yTicks.map((t) => {
        const y = padT + ((max - t) / max) * innerH;
        return (
          <g key={t}>
            <line
              x1={padL}
              x2={W - padR}
              y1={y}
              y2={y}
              stroke="#E8E4E0"
              strokeDasharray={t === 0 ? "0" : "2 3"}
              strokeWidth="1"
            />
            <text
              x={padL - 8}
              y={y + 3}
              textAnchor="end"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9"
              letterSpacing="1.2"
              fill="#9B9590"
            >
              {t}
            </text>
          </g>
        );
      })}
      {weeks.map((w, i) => {
        const x = padL + i * slot + (slot - barW) / 2;
        const h = (w.miles / max) * innerH;
        const y = padT + (innerH - h);
        const planned = w.partial ? (51 / max) * innerH : null;
        return (
          <g key={i}>
            {planned !== null ? (
              <rect
                x={x}
                y={padT + (innerH - planned)}
                width={barW}
                height={planned - h}
                fill="transparent"
                stroke={accent}
                strokeDasharray="3 3"
                strokeWidth="1"
                opacity="0.7"
              />
            ) : null}
            <rect
              x={x}
              y={y}
              width={barW}
              height={h}
              fill={w.current ? accent : "#1A1815"}
              opacity={w.current ? 1 : 0.78}
              rx="1"
            />
            <text
              x={x + barW / 2}
              y={H - 18}
              textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9.5"
              letterSpacing="1.2"
              fill={w.current ? accent : "#1A1815"}
              fontWeight={w.current ? 700 : 500}
            >
              {w.miles.toFixed(0)}
            </text>
            <text
              x={x + barW / 2}
              y={H - 6}
              textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="8.5"
              letterSpacing="1.2"
              fill="#9B9590"
            >
              {w.label}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

function MoodTile() {
  const days = ["M", "T", "W", "T", "F", "S", "S"];
  return (
    <article className="border border-divider bg-bg-card rounded-lg p-6">
      <div className="flex items-baseline justify-between">
        <Mono>FIG. C · MOOD · LAST 4 WEEKS</Mono>
        <Mono>{Object.keys(MOOD).length} STATES</Mono>
      </div>

      <div className="mt-4 grid grid-cols-[20px_1fr] gap-x-3">
        <div className="flex flex-col justify-between py-1">
          {["Apr 20", "Apr 27", "May 4", "This wk"].map((wk, i) => (
            <span
              key={i}
              className="font-mono text-[8.5px] tracking-[1.2px] uppercase text-text-tertiary leading-none whitespace-nowrap"
            >
              {wk}
            </span>
          ))}
        </div>

        <div>
          <div className="grid grid-cols-7 gap-[4px]">
            {MOOD_GRID.map((row, w) =>
              row.map((m, d) => (
                <div
                  key={`${w}-${d}`}
                  className="aspect-square rounded-[2px]"
                  style={{
                    background: m ? MOOD[m].color : "#EFECE8",
                    opacity: m ? 0.85 : 1,
                  }}
                  title={m ? MOOD[m].label : "no run"}
                />
              ))
            )}
          </div>
          <div className="mt-2 grid grid-cols-7 gap-[4px]">
            {days.map((d, i) => (
              <span
                key={i}
                className="text-center font-mono text-[8.5px] tracking-[1px] uppercase text-text-tertiary"
              >
                {d}
              </span>
            ))}
          </div>
        </div>
      </div>

      <div className="mt-4 pt-4 border-t border-divider-soft flex flex-wrap gap-3">
        {Object.entries(MOOD).map(([k, v]) => (
          <span key={k} className="inline-flex items-center gap-1.5">
            <span className="block h-2 w-2 rounded-[1px]" style={{ background: v.color }} />
            <span className="font-mono text-[9px] tracking-[1.2px] uppercase text-text-secondary">
              {v.label}
            </span>
          </span>
        ))}
      </div>
    </article>
  );
}

/* ════════════════════════════════════════════════════════════════════
   RECENT RUNS — five latest
   ════════════════════════════════════════════════════════════════════ */
function RecentRuns() {
  return (
    <section>
      <div className="flex items-baseline justify-between border-b border-divider-soft pb-3 mb-5">
        <Mono>FIG. D · RECENT RUNS</Mono>
        <Link
          href="/design/training-log"
          className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-primary hover:text-coral"
        >
          Open the journal ↗
        </Link>
      </div>

      <div className="border border-divider rounded-lg bg-bg-card overflow-hidden">
        {RECENT.map((r, i) => (
          <RunRow key={r.date} run={r} isLast={i === RECENT.length - 1} />
        ))}
      </div>
    </section>
  );
}

function RunRow({ run, isLast }: { run: Run; isLast: boolean }) {
  const typeColor =
    run.type === "tempo" || run.type === "intervals"
      ? ACCENT
      : run.type === "long"
        ? SAGE
        : run.type === "race"
          ? "#B83A4A"
          : "#9B9590";

  return (
    <Link
      href="/design/training-log"
      className={`relative grid grid-cols-[80px_84px_1fr_72px_72px_60px_18px] items-baseline gap-3 px-5 py-3.5 hover:bg-bg-elevated transition-colors ${
        !isLast ? "border-b border-divider-soft" : ""
      }`}
    >
      <span
        aria-hidden
        className="absolute left-0 top-1 bottom-1 w-[2px] rounded"
        style={{ background: typeColor, opacity: 0.7 }}
      />
      <span className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary">
        {run.weekday} · {run.date.replace("May ", "")}
      </span>
      <span
        className="font-mono text-[10.5px] tracking-[1.4px] uppercase"
        style={{ color: typeColor, fontWeight: 600 }}
      >
        {run.type}
      </span>
      <span className="font-body italic text-[13.5px] leading-[1.45] text-text-secondary truncate">
        {run.note}
      </span>
      <span className="font-mono tabular-nums text-[13px] text-text-primary text-right">
        {run.miles.toFixed(1)}
        <span className="ml-0.5 text-[9px] tracking-[1.2px] uppercase text-text-tertiary">mi</span>
      </span>
      <span className="font-mono tabular-nums text-[13px] text-text-secondary text-right">
        {run.pace}
        <span className="ml-0.5 text-[9px] tracking-[1.2px] uppercase text-text-tertiary">/mi</span>
      </span>
      <span className="font-mono tabular-nums text-[11px] text-text-tertiary text-right">
        {run.duration}
      </span>
      <span
        className="block h-2.5 w-2.5 rounded-full place-self-end"
        style={{ background: MOOD[run.mood].color, opacity: 0.85 }}
        title={MOOD[run.mood].label}
      />
    </Link>
  );
}

/* ════════════════════════════════════════════════════════════════════
   SIGNATURES & UPCOMING — niggles + what's next, two columns
   ════════════════════════════════════════════════════════════════════ */
function SignaturesAndUpcoming() {
  return (
    <section className="grid lg:grid-cols-2 gap-x-8 gap-y-8">
      <NigglesTile />
      <UpcomingTile />
    </section>
  );
}

function NigglesTile() {
  return (
    <article className="border border-divider bg-bg-card rounded-lg p-6">
      <div className="flex items-baseline justify-between">
        <Mono>FIG. E · NIGGLES</Mono>
        <Mono>VERBATIM · NOT DIAGNOSIS</Mono>
      </div>
      {NIGGLES.length === 0 ? (
        <p className="mt-4 font-body italic text-[14px] text-text-tertiary">
          Nothing flagged this week.
        </p>
      ) : (
        <div className="mt-4 space-y-4">
          {NIGGLES.map((n) => (
            <div key={n.part} className="grid grid-cols-[1fr_auto] gap-x-3">
              <div>
                <span className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-primary">
                  {n.part}
                </span>
                <span className="ml-2 font-mono text-[9.5px] tracking-[1.2px] uppercase text-text-tertiary">
                  last {n.last}
                </span>
                <p className="mt-1 font-body italic text-[14px] leading-[1.4] text-text-secondary">
                  &ldquo;{n.quote}&rdquo;
                </p>
              </div>
              <span
                className="self-start font-mono text-[9.5px] tracking-[1.3px] uppercase px-1.5 py-0.5 rounded-[2px]"
                style={{ color: ACCENT, background: "rgba(212,89,42,0.08)" }}
              >
                {n.severity}
              </span>
            </div>
          ))}
        </div>
      )}
      <p className="mt-5 pt-4 border-t border-divider-soft font-body italic text-[11.5px] leading-[1.45] text-text-tertiary">
        Not medical advice. If anything gets sharper, see a clinician.
      </p>
    </article>
  );
}

function UpcomingTile() {
  return (
    <article className="border border-divider bg-bg-card rounded-lg p-6">
      <div className="flex items-baseline justify-between">
        <Mono>FIG. F · WHAT&rsquo;S NEXT</Mono>
        <Mono>8 WK TO BOSTON</Mono>
      </div>
      <div className="mt-4 space-y-4">
        {UPCOMING.map((u) => (
          <div key={u.label} className="grid grid-cols-[1fr_auto] gap-x-3 items-baseline">
            <div>
              <p className="font-display text-[20px] tracking-[-0.005em]">{u.label}.</p>
              <p className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary mt-0.5">
                {u.detail}
              </p>
            </div>
            <span
              className="font-mono text-[10.5px] tracking-[1.4px] uppercase"
              style={{ color: u.kind === "race" ? ACCENT : "#1A1815" }}
            >
              IN {u.in}
            </span>
          </div>
        ))}
      </div>
      <Link
        href="/design/plan"
        className="mt-5 pt-4 border-t border-divider-soft block font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-primary hover:text-coral"
      >
        Open the plan ↗
      </Link>
    </article>
  );
}

function CoachPull() {
  return (
    <section className="max-w-[720px] mx-auto text-center py-4">
      <Mono color={ACCENT}>FROM YOUR COACH</Mono>
      <p className="mt-4 font-display italic text-[24px] leading-[1.3] tracking-[-0.005em] text-text-primary">
        &ldquo;You&rsquo;re ahead on miles, fine on pace, and the Tuesday tempo
        landed inside the window. Saturday&rsquo;s 18 is the only thing this
        week is really asking — get there fresh.&rdquo;
      </p>
      <p className="mt-3 font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary">
        Week 9 · auto-generated, coach-reviewed
      </p>
      <div className="mt-5 flex items-center justify-center gap-3">
        <span className="block h-px w-12 bg-divider" />
        <span
          className="block h-[5px] w-[5px] rounded-full"
          style={{ background: ACCENT }}
        />
        <span className="block h-px w-12 bg-divider" />
      </div>
    </section>
  );
}

function Footer() {
  return (
    <div className="pt-6 border-t border-divider-soft flex items-center justify-between">
      <Mono>POST RUN DRIP · TRAINING SUMMARY</Mono>
      <Mono>WK 9 · SPRING &rsquo;26</Mono>
    </div>
  );
}

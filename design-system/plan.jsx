/* global React */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — PLAN PAGE (v1)
   Today / This week / The block — one editorial plate.
   ════════════════════════════════════════════════════════════════════ */

const ACCENT = "#D4592A";
const SAGE = "#6B8068";

const Mono = ({ children, color = "#9B9590", className = "", weight }) => (
  <span
    className={`font-mono text-[10.5px] tracking-[1.5px] uppercase ${className}`}
    style={{ color, fontWeight: weight }}
  >
    {children}
  </span>
);

/* ─── PLAN DATA (mocked, believable) ──────────────────────────────── */

// Marathon block — Sub-3:15 build, currently Week 9 of 16
const BLOCK_WEEKS = [
  { idx: 1,  miles: 30, phase: "base",  isDone: true },
  { idx: 2,  miles: 34, phase: "base",  isDone: true },
  { idx: 3,  miles: 38, phase: "base",  isDone: true },
  { idx: 4,  miles: 28, phase: "base",  isDone: true },
  { idx: 5,  miles: 42, phase: "build", isDone: true },
  { idx: 6,  miles: 46, phase: "build", isDone: true },
  { idx: 7,  miles: 50, phase: "build", isDone: true },
  { idx: 8,  miles: 54, phase: "build", isDone: true },
  { idx: 9,  miles: 51, phase: "build", isCurrent: true },
  { idx: 10, miles: 58, phase: "peak" },
  { idx: 11, miles: 62, phase: "peak" },
  { idx: 12, miles: 66, phase: "peak" },
  { idx: 13, miles: 48, phase: "peak" },
  { idx: 14, miles: 42, phase: "taper" },
  { idx: 15, miles: 30, phase: "taper" },
  { idx: 16, miles: 22, phase: "taper" },
];

// This week — Mon-first. Today = Tue (tempo).
const WEEK = [
  {
    day: "MON", date: "MAY 11",
    type: "rest", title: "Rest",
    miles: 0,                load: 0,
    pace: null,
    note: "Let the work consolidate.",
    isDone: true,
  },
  {
    day: "TUE", date: "MAY 12",
    type: "quality", title: "Tempo · 5 × 1 mi",
    miles: 8.0,              load: 78,
    pace: "7:00 / mi",
    note: "Threshold work — reps at HM effort. Don't chase faster.",
    isToday: true,
  },
  {
    day: "WED", date: "MAY 13",
    type: "easy", title: "Easy",
    miles: 6.0,              load: 32,
    pace: "8:30 / mi",
    note: "Conversational. Save the legs for Thursday.",
  },
  {
    day: "THU", date: "MAY 14",
    type: "medium", title: "Medium",
    miles: 8.0,              load: 52,
    pace: "8:00 / mi",
    note: "Steady aerobic — firmer than easy, softer than tempo.",
  },
  {
    day: "FRI", date: "MAY 15",
    type: "easy", title: "Easy + 4 × 100 m strides",
    miles: 5.0,              load: 28,
    pace: "8:30 / mi",
    note: "Strides keep the legs sharp. Don&rsquo;t time them.",
  },
  {
    day: "SAT", date: "MAY 16",
    type: "long", title: "Long run",
    miles: 18.0,             load: 92,
    pace: "8:30 / mi",
    note: "Longest of the block&rsquo;s build. Last 4 mi at MP if it&rsquo;s in there.",
  },
  {
    day: "SUN", date: "MAY 17",
    type: "easy", title: "Recovery",
    miles: 6.0,              load: 26,
    pace: "9:00 / mi",
    note: "Recovery only. Tomorrow needs fresh legs.",
  },
];

const WEEK_TOTAL = WEEK.reduce((s, d) => s + d.miles, 0);

// Pace zones from canonical race-equivalence + percent-of-MP-speed.
// Goal: sub-3:15 → MP 7:25 / mi.
const ZONES = [
  { key: "easy",   label: "Easy",   pace: "9:42", range: "9:25 – 9:55", note: "Aerobic base" },
  { key: "steady", label: "Steady", pace: "8:01", range: "7:55 – 8:25", note: "Firm aerobic" },
  { key: "mp",     label: "MP",     pace: "7:25", range: "7:25",        note: "Marathon pace" },
  { key: "lt",     label: "LT",     pace: "7:00", range: "7:00",        note: "1-hour effort" },
  { key: "tenk",   label: "10K",    pace: "6:45", range: "6:45",        note: "" },
  { key: "fivek",  label: "5K",     pace: "6:25", range: "6:25",        note: "" },
  { key: "mile",   label: "Mile",   pace: "5:55", range: "5:55",        note: "" },
];

/* ════════════════════════════════════════════════════════════════════ */
function App() {
  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <div className="flex flex-1 flex-col overflow-hidden">
          <TopNav />
          <main className="flex-1 overflow-y-auto">
            <PlanPage />
          </main>
        </div>
      </div>
    </div>
  );
}

/* ── SIDEBAR ────────────────────────────────────────────────────────── */
function Sidebar() {
  const items = [
    { label: "Dashboard", on: false },
    { label: "Training log", on: false },
    { label: "Coach", on: false },
    { label: "Plan", on: true },
  ];
  const more = [
    { label: "Coach portal", href: "#" },
    { label: "Goals", href: "#" },
    { label: "Analysis", href: "Training Analysis.html" },
    { label: "Injuries", href: "#" },
    { label: "Fitness predictor", href: "#" },
    { label: "Pace chart", href: "#" },
    { label: "Content library", href: "#" },
  ];
  return (
    <aside className="hidden sm:flex flex-col w-[224px] shrink-0 bg-bg-base border-r border-divider">
      <div className="px-5 py-5 border-b border-divider">
        <span className="font-display text-[18px] tracking-[-0.01em]">Post Run Drip</span>
      </div>
      <nav className="flex-1 overflow-y-auto px-3 py-4">
        <Mono color="#9B9590" className="px-2">PRIMARY</Mono>
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
          <Mono color="#9B9590" className="px-2">MORE</Mono>
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
        <span className="h-8 w-8 rounded-full bg-coral/15 flex items-center justify-center font-display text-[15px] text-coral">M</span>
        <div className="leading-tight">
          <p className="text-[12.5px] text-text-primary">M. Kerr</p>
          <p className="font-mono text-[9.5px] tracking-[1.2px] text-text-tertiary uppercase">Athlete</p>
        </div>
      </div>
    </aside>
  );
}

/* ── TOP NAV ────────────────────────────────────────────────────────── */
function TopNav() {
  return (
    <header className="bg-bg-base border-b border-divider px-8 py-3 flex items-center justify-between">
      <Mono color="#9B9590">RUNNING LOG · PLAN</Mono>
      <div className="flex items-center gap-5">
        <a href="#" className="text-[13px] text-text-secondary hover:text-text-primary">Voice log</a>
        <a href="#" className="text-[13px] text-text-secondary hover:text-text-primary">Ask coach</a>
        <span className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
          Tue · May 12
        </span>
      </div>
    </header>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PLAN PAGE BODY
   ════════════════════════════════════════════════════════════════════ */
function PlanPage() {
  return (
    <div className="mx-auto max-w-[1180px] px-10 py-10 space-y-10">
      <PlateHeader />
      <TitleAndCountdown />
      <TodayPlate />
      <ThisWeek />
      <TheBlock />
      <CoachPull />
    </div>
  );
}

/* ── plate strip ──────────────────────────────────────────────────── */
function PlateHeader() {
  return (
    <div className="flex items-baseline justify-between border-b border-divider-soft pb-3">
      <Mono color="#9B9590">PLAN · SUB-3:15 MARATHON BUILD</Mono>
      <Mono color="#9B9590">WEEK 9 OF 16 · BUILD PHASE</Mono>
    </div>
  );
}

/* ── title + race countdown ───────────────────────────────────────── */
function TitleAndCountdown() {
  return (
    <div className="grid lg:grid-cols-[1fr_auto] gap-x-12 gap-y-6 items-end">
      <div>
        <Mono color={ACCENT}>THIS WEEK · MAY 11 – 17</Mono>
        <h1 className="mt-3 font-display text-[68px] leading-[0.96] tracking-[-0.02em]">
          The build is almost done.
          <br />
          <em className="font-display italic" style={{ color: ACCENT }}>
            Then the peak.
          </em>
        </h1>
      </div>
      <Countdown />
    </div>
  );
}

function Countdown() {
  const weeks = 8;
  const days = 56;
  return (
    <div className="border border-divider rounded-lg bg-bg-card p-5 min-w-[280px] shadow-[0_2px_8px_rgba(26,24,21,0.04)]">
      <Mono color="#9B9590">RACE COUNTDOWN</Mono>
      <p className="mt-2 font-display text-[44px] leading-none tabular-nums tracking-[-0.02em]">
        {weeks}<span className="text-[18px] tracking-[1.5px] uppercase font-mono text-text-tertiary ml-2">weeks</span>
      </p>
      <p className="mt-0.5 font-mono text-[11px] tracking-[1.3px] uppercase text-text-tertiary tabular-nums">
        {days} DAYS · BOSTON MARATHON · JUL 12
      </p>
      <div className="mt-4 pt-4 border-t border-divider-soft">
        <div className="flex items-baseline justify-between">
          <Mono color="#9B9590">TAPER READINESS</Mono>
          <span className="font-mono text-[11px] tabular-nums text-text-secondary">62 / 100</span>
        </div>
        <div className="mt-2">
          <TaperReadiness value={62} accent={ACCENT} />
        </div>
        <p className="mt-2 font-body italic text-[11.5px] leading-[1.45] text-text-tertiary">
          Climbing. Peak weeks 10–13, then the curve bends.
        </p>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   TODAY PLATE — the workout, expanded
   ════════════════════════════════════════════════════════════════════ */
function TodayPlate() {
  const today = WEEK.find((d) => d.isToday);
  return (
    <section className="relative bg-bg-card border border-divider rounded-lg overflow-hidden shadow-[0_4px_20px_-8px_rgba(26,24,21,0.10)]">
      {/* coral edge rule */}
      <span
        aria-hidden
        className="absolute left-0 top-0 bottom-0 w-[3px]"
        style={{ background: ACCENT }}
      />

      <div className="grid lg:grid-cols-[1.05fr_0.95fr] gap-x-12 px-8 py-8">
        {/* LEFT — title + description + coach note + actions */}
        <div>
          <div className="flex items-baseline justify-between">
            <Mono color="#9B9590">
              TODAY · {today.day} · {today.date}
            </Mono>
            <Mono color={ACCENT} weight={700}>QUALITY · LT</Mono>
          </div>

          <h2 className="mt-3 font-display text-[52px] leading-[0.98] tracking-[-0.02em]">
            Tempo,
            <br />
            <em className="font-display italic" style={{ color: ACCENT }}>
              5 × 1 mi at threshold.
            </em>
          </h2>

          <p className="mt-5 font-mono text-[13px] tracking-[0.5px] uppercase text-text-secondary tabular-nums">
            8.0 MI &middot; ~1:00 &middot; 5 × 1 MI @ 7:00 / MI &middot; 90 S JOG REC
          </p>

          <p className="mt-5 font-body text-[16.5px] leading-[1.55] text-text-primary max-w-[480px]">
            One mile warm-up, then five hard miles at threshold with 90 seconds of jog
            recovery between. One mile cool-down. Eight total. Try to hit each rep
            within two seconds of 7:00.
          </p>

          {/* coach note */}
          <div className="mt-6 coach-note text-[16px] leading-[1.55]">
            Reps at half-marathon effort, not faster. The point is to spend forty
            minutes at the line you can&rsquo;t cross — not to win the workout. If
            the last two feel sharper than 7:00, hold them; if they feel ragged,
            pull back to 7:05. Saturday&rsquo;s 18 needs you whole.
            <p className="mt-2 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary not-italic">
              From your coach · Week 9
            </p>
          </div>

          {/* actions */}
          <div className="mt-7 flex flex-wrap items-center gap-3">
            <button
              type="button"
              className="rounded-md px-5 py-2.5 font-body text-[13.5px] font-semibold text-white"
              style={{
                background: ACCENT,
                boxShadow: `0 1px 0 #B84420, 0 6px 16px -6px rgba(212,89,42,0.5)`,
              }}
            >
              Mark complete ↗
            </button>
            <button
              type="button"
              className="rounded-md border border-divider px-4 py-2.5 font-body text-[13.5px] text-text-primary hover:border-text-tertiary"
            >
              Why this, why now?
            </button>
            <button
              type="button"
              className="rounded-md border border-divider px-4 py-2.5 font-body text-[13.5px] text-text-secondary hover:text-text-primary hover:border-text-tertiary"
            >
              Move the day
            </button>
          </div>
        </div>

        {/* RIGHT — pace zones table */}
        <div className="lg:pl-8 lg:border-l lg:border-divider-soft">
          <div className="flex items-baseline justify-between">
            <Mono color="#9B9590">PACE TARGETS · TODAY</Mono>
            <Mono color="#9B9590">GOAL · SUB-3:15</Mono>
          </div>
          <p className="mt-3 font-display italic text-[15px] leading-[1.4] text-text-secondary max-w-[360px]">
            Your zones from this block&rsquo;s goal time. LT is the line today.
          </p>
          <div className="mt-5">
            <PaceZonesTable zones={ZONES} highlight="lt" accent={ACCENT} />
          </div>
          <p className="mt-4 font-body italic text-[12px] leading-[1.45] text-text-tertiary">
            Aerobic zones ship as ranges; race-pace zones as exact targets.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   THIS WEEK — 7-day strip + load preview
   ════════════════════════════════════════════════════════════════════ */
function ThisWeek() {
  return (
    <section>
      <div className="flex items-baseline justify-between border-b border-divider-soft pb-3 mb-6">
        <Mono color="#9B9590">FIG. A · THIS WEEK · 7 DAYS</Mono>
        <span className="font-mono text-[11px] tabular-nums text-text-secondary">
          {WEEK_TOTAL.toFixed(0)} MI &middot; 1 QUALITY &middot; 1 LONG &middot; 1 REST
        </span>
      </div>

      <div className="grid lg:grid-cols-[1fr_320px] gap-x-10 gap-y-8 items-start">
        {/* DAY LIST */}
        <div className="border border-divider rounded-lg bg-bg-card overflow-hidden">
          {WEEK.map((d, i) => (
            <DayRow key={d.day} day={d} isLast={i === WEEK.length - 1} />
          ))}
        </div>

        {/* LOAD PREVIEW */}
        <aside className="bg-bg-card border border-divider rounded-lg p-5">
          <Mono color="#9B9590">LOAD &middot; 7 DAYS</Mono>
          <div className="mt-3">
            <LoadPreview
              days={WEEK.map((d) => ({
                label: d.day.slice(0, 1),
                load: d.load,
                type: d.type,
                isToday: !!d.isToday,
              }))}
              accent={ACCENT}
            />
          </div>
          <div className="mt-4 pt-4 border-t border-divider-soft space-y-2.5">
            <LegendRow color={ACCENT} label="Quality" />
            <LegendRow color={SAGE} label="Long run" />
            <LegendRow color="#6B6560" label="Easy / medium" />
            <LegendRow color="#E8E4E0" label="Rest" hollow />
          </div>
          <p className="mt-4 font-body italic text-[12.5px] leading-[1.5] text-text-secondary border-t border-divider-soft pt-4">
            Saturday is the spike. Friday&rsquo;s easy + strides is the on-ramp;
            Sunday&rsquo;s recovery is the off-ramp.
          </p>
        </aside>
      </div>
    </section>
  );
}

function DayRow({ day, isLast }) {
  const isQuality = day.type === "quality";
  const isLong = day.type === "long";
  const isRest = day.type === "rest";

  const accent =
    isQuality ? ACCENT :
    isLong ? SAGE :
    null;

  return (
    <div
      className={`relative grid grid-cols-[44px_1fr_auto_120px] items-baseline gap-x-4 px-5 py-3.5 ${
        !isLast ? "border-b border-divider-soft" : ""
      } ${day.isToday ? "bg-coral/[0.04]" : ""}`}
    >
      {accent ? (
        <span
          aria-hidden
          className="absolute left-0 top-1 bottom-1 w-[2px] rounded"
          style={{ background: accent, opacity: day.isToday ? 1 : 0.7 }}
        />
      ) : null}

      {/* day */}
      <div>
        <p
          className="font-mono text-[10.5px] tracking-[1.4px]"
          style={{ color: day.isToday ? ACCENT : "#9B9590", fontWeight: day.isToday ? 700 : 500 }}
        >
          {day.day}
        </p>
        <p className="font-mono text-[9.5px] tabular-nums text-text-tertiary mt-0.5">
          {day.date.replace("MAY ", "")}
        </p>
      </div>

      {/* title + note */}
      <div className="min-w-0">
        <p
          className={`font-display tracking-[-0.005em] leading-tight ${
            isQuality || isLong ? "text-[20px]" : "text-[17px]"
          } ${isRest ? "italic text-text-tertiary" : "text-text-primary"}`}
        >
          {day.title}
        </p>
        {!isRest ? (
          <p
            className="mt-1 font-body italic text-[13px] leading-[1.4] text-text-secondary"
            dangerouslySetInnerHTML={{ __html: day.note }}
          />
        ) : (
          <p className="mt-1 font-body italic text-[12.5px] text-text-tertiary">
            {day.note}
          </p>
        )}
      </div>

      {/* miles + pace */}
      <div className="text-right">
        {day.miles ? (
          <>
            <p className="font-mono tabular-nums text-[15px] text-text-primary">
              {day.miles.toFixed(1)}
              <span className="ml-1 text-[10px] tracking-[1.3px] uppercase text-text-tertiary">mi</span>
            </p>
            {day.pace ? (
              <p className="font-mono text-[10.5px] tabular-nums text-text-tertiary mt-0.5">
                {day.pace}
              </p>
            ) : null}
          </>
        ) : (
          <p className="font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-tertiary">
            —
          </p>
        )}
      </div>

      {/* actions */}
      <div className="flex justify-end gap-1.5">
        {day.isDone ? (
          <span className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-mood-positive">
            ✓ done
          </span>
        ) : day.isToday ? (
          <span
            className="font-mono text-[9.5px] tracking-[1.3px] uppercase"
            style={{ color: ACCENT }}
          >
            ↗ today
          </span>
        ) : (
          <>
            <button className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary hover:text-text-primary">
              why
            </button>
            <span className="text-text-tertiary">·</span>
            <button className="font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary hover:text-text-primary">
              move
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function LegendRow({ color, label, hollow }) {
  return (
    <div className="flex items-center gap-2.5">
      <span
        className="block h-[10px] w-[10px] rounded-[1px]"
        style={{
          background: hollow ? "transparent" : color,
          border: hollow ? `1px solid ${color}` : "none",
        }}
      />
      <span className="font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-secondary">
        {label}
      </span>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   THE BLOCK — 16-week mileage bars + plan stats
   ════════════════════════════════════════════════════════════════════ */
function TheBlock() {
  return (
    <section>
      <div className="flex items-baseline justify-between border-b border-divider-soft pb-3 mb-6">
        <Mono color="#9B9590">FIG. B · THE BLOCK · 16 WEEKS</Mono>
        <Mono color="#9B9590">MILES / WEEK</Mono>
      </div>

      <div className="grid lg:grid-cols-[1fr_280px] gap-x-10 items-start">
        <div className="bg-bg-card border border-divider rounded-lg p-5">
          <BlockMileageBars weeks={BLOCK_WEEKS} accent={ACCENT} />
        </div>

        <aside className="space-y-5">
          <BlockStat
            label="DONE"
            value={`${BLOCK_WEEKS.filter((w) => w.isDone).reduce((s, w) => s + w.miles, 0)}`}
            unit="mi"
            hint="across 8 weeks"
          />
          <BlockStat
            label="REMAINING"
            value={`${BLOCK_WEEKS.filter((w) => !w.isDone && !w.isCurrent).reduce((s, w) => s + w.miles, 0)}`}
            unit="mi"
            hint="7 weeks to peak + taper"
          />
          <BlockStat
            label="PEAK WEEK"
            value="66"
            unit="mi"
            hint="Week 12 · 4 weeks out"
            highlight
          />
          <p className="font-body italic text-[13px] leading-[1.5] text-text-secondary border-t border-divider-soft pt-4">
            The peak isn&rsquo;t the race. The peak is what the race is built on.
            The taper takes it from there.
          </p>
        </aside>
      </div>
    </section>
  );
}

function BlockStat({ label, value, unit, hint, highlight }) {
  return (
    <div>
      <Mono color={highlight ? ACCENT : "#9B9590"}>{label}</Mono>
      <p className="mt-1 font-display text-[36px] tabular-nums leading-none tracking-[-0.01em]">
        {value}
        <span className="ml-1.5 font-mono text-[12px] tracking-[1.3px] uppercase text-text-tertiary">
          {unit}
        </span>
      </p>
      <p className="mt-1 font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-tertiary">
        {hint}
      </p>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   COACH PULL-QUOTE — closing editorial signature
   ════════════════════════════════════════════════════════════════════ */
function CoachPull() {
  return (
    <section className="max-w-[720px] mx-auto text-center py-6">
      <Mono color={ACCENT}>FROM YOUR COACH</Mono>
      <p className="mt-4 font-display italic text-[26px] leading-[1.25] tracking-[-0.005em] text-text-primary">
        &ldquo;Two more build weeks, then we peak. Hold the easy days easy and
        don&rsquo;t race the tempos. The block is doing its work.&rdquo;
      </p>
      <p className="mt-4 font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary">
        Week 9 &middot; auto-generated, coach-reviewed
      </p>
      <div className="mt-6 flex items-center justify-center gap-3">
        <span className="block h-px w-12 bg-divider" />
        <span className="block h-[5px] w-[5px] rounded-full" style={{ background: ACCENT }} />
        <span className="block h-px w-12 bg-divider" />
      </div>
    </section>
  );
}

/* ── mount ──────────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

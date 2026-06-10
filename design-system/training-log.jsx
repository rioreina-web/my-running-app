/* global React */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — TRAINING LOG (v1 · journal)
   Editorial journal of voice logs + workout notes + AI feedback.
   Each entry clickable to a workout-detail panel. Exportable.
   ════════════════════════════════════════════════════════════════════ */

const { useState, useMemo } = React;
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

/* ════════════════════════════════════════════════════════════════════
   ENTRIES — mocked but believable. Three months of an athlete's log.
   Voice log quote is verbatim ("I/my"); coach note is second-person.
   Mood vocab from CLAUDE.md.
   ════════════════════════════════════════════════════════════════════ */

const MOOD_COLORS = {
  energized: "#2D8A4E",
  positive: "#4A9E6B",
  neutral: "#9B9590",
  tired: "#C4873A",
  struggling: "#C45A3A",
  injured: "#B83A4A",
};

const ENTRIES = [
  {
    id: "may-12",
    date: "2026-05-12",
    weekday: "TUE",
    monthDay: "May 12",
    type: "tempo",
    typeLabel: "Tempo",
    mood: "positive",
    miles: 8.0,
    durationMin: 60,
    pace: "7:14",
    splits: [7.5, 7.45, 7.42, 7.0, 7.02, 7.0, 7.05, 8.2],
    quote:
      "Felt rough in the warm-up — legs were heavy for the first two miles — but by the second rep the rhythm came in. Held 7:00 for four of five. Last one a little ragged, settled to 7:05 on the cool down. River trail still flooded near the second bridge so I cut up onto the road.",
    coachNote:
      "Locked in. Four reps inside the 7:00 window is exactly what week 9 is supposed to feel like — last one giving back five seconds isn&rsquo;t fade, it&rsquo;s discipline. Tomorrow easy, save the legs for Saturday.",
    tags: ["LT", "5 × 1 mi", "MP-derived target"],
    raceLink: null,
    niggles: [],
    weekNo: 9,
  },
  {
    id: "may-10",
    date: "2026-05-10",
    weekday: "SUN",
    monthDay: "May 10",
    type: "long",
    typeLabel: "Long run",
    mood: "tired",
    miles: 16.0,
    durationMin: 138,
    pace: "8:38",
    splits: [8.6, 8.5, 8.5, 8.45, 8.4, 8.4, 8.35, 8.3, 8.3, 8.5, 8.6, 8.7, 8.8, 9.0, 9.2, 9.5],
    quote:
      "First 12 felt fine — pretty conversational, splits were creeping down without trying. Then the last 4 the wheels came off a bit, especially the last two. Hot. Drained the bottle by mile 10 which was dumb. Left achilles a little tight first mile but eased up after.",
    coachNote:
      "Sixteen on a warm day with a bonk in the last two is data, not failure. The first twelve were honest. Hydrate earlier next long — start drinking before you feel like you need to.",
    tags: ["Aerobic", "Boston block · LR 4 of 8"],
    raceLink: null,
    niggles: [{ part: "L. Achilles", quote: "a little tight first mile", severity: "passing" }],
    weekNo: 8,
  },
  {
    id: "may-08",
    date: "2026-05-08",
    weekday: "FRI",
    monthDay: "May 8",
    type: "easy",
    typeLabel: "Easy + strides",
    mood: "energized",
    miles: 5.0,
    durationMin: 43,
    pace: "8:36",
    splits: [8.7, 8.6, 8.5, 8.55, 8.5],
    quote:
      "Short and easy on Town Lake. Four strides at the end, didn&rsquo;t time them but they felt snappy. Body finally feels like it&rsquo;s catching up to the volume.",
    coachNote:
      "Good. The point of these is to stay easy enough that the strides cost nothing.",
    tags: ["Easy", "4 × 100 m strides"],
    raceLink: null,
    niggles: [],
    weekNo: 8,
  },
  {
    id: "may-06",
    date: "2026-05-06",
    weekday: "WED",
    monthDay: "May 6",
    type: "intervals",
    typeLabel: "Intervals · 6 × 800 m",
    mood: "positive",
    miles: 6.5,
    durationMin: 52,
    pace: "7:12 avg",
    splits: [],
    intervals: [
      { label: "REP 1", time: "2:52", pace: "5:44 / mi" },
      { label: "REP 2", time: "2:51", pace: "5:42 / mi" },
      { label: "REP 3", time: "2:50", pace: "5:40 / mi" },
      { label: "REP 4", time: "2:50", pace: "5:40 / mi" },
      { label: "REP 5", time: "2:49", pace: "5:38 / mi" },
      { label: "REP 6", time: "2:48", pace: "5:36 / mi" },
    ],
    quote:
      "Six by 800 at 5K effort, 400 jog between. Negative split all the way through. Last one was the fastest and didn&rsquo;t feel desperate. Track was empty, sunset.",
    coachNote:
      "Negative splits on track reps is the textbook execution. The last one being the cleanest tells me there&rsquo;s a 10K in your legs we haven&rsquo;t seen yet.",
    tags: ["5K pace", "Track", "Quality"],
    raceLink: null,
    niggles: [],
    weekNo: 8,
  },
  {
    id: "may-04",
    date: "2026-05-04",
    weekday: "MON",
    monthDay: "May 4",
    type: "rest",
    typeLabel: "Check-in · rest day",
    mood: "neutral",
    miles: 0,
    durationMin: 0,
    pace: null,
    quote:
      "Took the rest day. Walked the dog twice, did the foam-roll routine before bed. Right knee felt a pinch on the stairs but it was fine after a few minutes.",
    coachNote:
      "Rest day check-ins are gold. Knee pinch on stairs is mechanical — if it shows up on the warm-up Wednesday, back off the reps.",
    tags: ["Check-in", "Recovery"],
    raceLink: null,
    niggles: [{ part: "R. Knee", quote: "felt a pinch on the stairs", severity: "passing" }],
    weekNo: 8,
  },
  {
    id: "may-02",
    date: "2026-05-02",
    weekday: "SAT",
    monthDay: "May 2",
    type: "race",
    typeLabel: "Tune-up race · HM",
    mood: "energized",
    miles: 13.1,
    durationMin: 87,
    pace: "6:38",
    splits: [],
    intervals: [
      { label: "5K", time: "20:48", pace: "6:42 / mi" },
      { label: "10K", time: "41:32", pace: "6:42 / mi" },
      { label: "15K", time: "1:02:01", pace: "6:39 / mi" },
      { label: "FINISH", time: "1:27:08", pace: "6:38 / mi" },
    ],
    quote:
      "Went out conservative — first three at 6:45, found the rhythm by 5K, started picking people off through the middle 10K. Last 5K hurt a lot but the legs were still there. Felt like a small breakthrough.",
    coachNote:
      "1:27 flat for a tune-up is the indicator I was hoping for. Honest pacing, controlled middle, brave finish — all three. This shifts the goal-race window. Let&rsquo;s talk Tuesday.",
    tags: ["Race", "Half marathon", "Goal-race indicator"],
    raceLink: { dist: "HM", time: "1:27:08", confidence: "HIGH" },
    niggles: [],
    weekNo: 7,
  },
  {
    id: "apr-29",
    date: "2026-04-29",
    weekday: "WED",
    monthDay: "Apr 29",
    type: "medium",
    typeLabel: "Medium",
    mood: "neutral",
    miles: 8.0,
    durationMin: 65,
    pace: "8:08",
    splits: [8.2, 8.15, 8.1, 8.05, 8.0, 8.05, 8.1, 8.15],
    quote:
      "Steady. Wind was up so I ran the loop counterclockwise. Nothing to say about it — got it done.",
    coachNote:
      "Nothing to say about it&rsquo; is a feature. Most days in a marathon block should be uneventful.",
    tags: ["Aerobic"],
    raceLink: null,
    niggles: [],
    weekNo: 7,
  },
  {
    id: "apr-26",
    date: "2026-04-26",
    weekday: "SUN",
    monthDay: "Apr 26",
    type: "long",
    typeLabel: "Long run",
    mood: "struggling",
    miles: 14.0,
    durationMin: 124,
    pace: "8:51",
    splits: [],
    quote:
      "Bad one. Got 10 miles in and felt completely cooked — pulled the plug on a planned 16. Slept like garbage Friday night, probably should&rsquo;ve listened earlier in the run. Calf was knotty post-tempo.",
    coachNote:
      "Calling it at 14 instead of digging a hole at 16 is the right call. The block doesn&rsquo;t care about ego.",
    tags: ["Aerobic", "Cut short"],
    raceLink: null,
    niggles: [{ part: "L. Calf", quote: "knotty post-tempo", severity: "mild" }],
    weekNo: 6,
  },
];

/* ════════════════════════════════════════════════════════════════════
   APP SHELL — sidebar + topnav (matches Plan page)
   ════════════════════════════════════════════════════════════════════ */

function App() {
  const [openId, setOpenId] = useState(null);
  const [exportOpen, setExportOpen] = useState(false);
  const [filter, setFilter] = useState("all");

  const openEntry = ENTRIES.find((e) => e.id === openId);

  // Filter
  const filtered = useMemo(() => {
    if (filter === "all") return ENTRIES;
    if (filter === "quality")
      return ENTRIES.filter((e) =>
        ["tempo", "intervals", "race", "long"].includes(e.type)
      );
    if (filter === "voice") return ENTRIES.filter((e) => e.quote);
    if (filter === "niggles") return ENTRIES.filter((e) => e.niggles.length > 0);
    return ENTRIES;
  }, [filter]);

  // Group by month
  const grouped = useMemo(() => {
    const map = new Map();
    for (const e of filtered) {
      const d = new Date(e.date);
      const key = d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(e);
    }
    return Array.from(map.entries());
  }, [filtered]);

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <div className="flex h-screen overflow-hidden">
        <Sidebar />
        <div className="flex flex-1 flex-col overflow-hidden">
          <TopNav />
          <main className="flex-1 overflow-y-auto">
            <LogPage
              grouped={grouped}
              filter={filter}
              setFilter={setFilter}
              onOpen={setOpenId}
              onExport={() => setExportOpen(true)}
            />
          </main>
        </div>
      </div>

      {openEntry ? (
        <EntryDetailDrawer entry={openEntry} onClose={() => setOpenId(null)} />
      ) : null}

      {exportOpen ? (
        <ExportDialog onClose={() => setExportOpen(false)} count={filtered.length} />
      ) : null}
    </div>
  );
}

/* ── SIDEBAR ────────────────────────────────────────────────────────── */
function Sidebar() {
  const items = [
    { label: "Dashboard", on: false },
    { label: "Training log", on: true },
    { label: "Coach", on: false },
    { label: "Plan", on: false },
  ];
  const more = [
    { label: "Coach portal", href: "#" },
    { label: "Goals", href: "#" },
    { label: "Analysis", href: "Training Analysis.html" },
    { label: "Injuries", href: "#" },
    { label: "Fitness predictor", href: "Fitness Predictor.html" },
    { label: "Pace chart", href: "#" },
    { label: "Content library", href: "#" },
  ];
  return (
    <aside className="hidden sm:flex flex-col w-[224px] shrink-0 bg-bg-base border-r border-divider">
      <div className="px-5 py-5 border-b border-divider">
        <span className="font-display text-[18px] tracking-[-0.01em]">Post Run Drip</span>
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
        <span className="h-8 w-8 rounded-full bg-coral/15 flex items-center justify-center font-display text-[15px] text-coral">M</span>
        <div className="leading-tight">
          <p className="text-[12.5px] text-text-primary">M. Kerr</p>
          <p className="font-mono text-[9.5px] tracking-[1.2px] text-text-tertiary uppercase">Athlete</p>
        </div>
      </div>
    </aside>
  );
}

function TopNav() {
  return (
    <header className="bg-bg-base border-b border-divider px-8 py-3 flex items-center justify-between">
      <Mono>RUNNING LOG · TRAINING LOG</Mono>
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
   PAGE BODY
   ════════════════════════════════════════════════════════════════════ */

function LogPage({ grouped, filter, setFilter, onOpen, onExport }) {
  const totalEntries = grouped.reduce((s, [, list]) => s + list.length, 0);
  return (
    <div className="mx-auto max-w-[1080px] px-10 py-10">
      <PlateHeader onExport={onExport} count={totalEntries} />
      <Title />
      <FilterStrip filter={filter} setFilter={setFilter} count={totalEntries} />

      {/* Month-grouped feed */}
      <div className="mt-10 space-y-16">
        {grouped.map(([monthLabel, entries]) => (
          <MonthSection
            key={monthLabel}
            label={monthLabel}
            entries={entries}
            onOpen={onOpen}
          />
        ))}
      </div>

    </div>
  );
}

function PlateHeader({ onExport, count }) {
  return (
    <div className="flex items-baseline justify-between border-b border-divider-soft pb-3">
      <Mono>RUNNING LOG · TRAINING LOG · v1 JOURNAL</Mono>
      <div className="flex items-center gap-5">
        <Mono>{count} ENTRIES</Mono>
        <button
          type="button"
          onClick={onExport}
          className="font-mono text-[10.5px] tracking-[1.5px] uppercase text-text-primary hover:text-coral inline-flex items-center gap-1.5"
        >
          Export the journal ↗
        </button>
      </div>
    </div>
  );
}

function Title() {
  return (
    <div className="mt-10">
      <Mono color={ACCENT}>VOL. 1 &middot; SPRING ’26</Mono>
      <h1 className="mt-3 font-display text-[68px] leading-[0.96] tracking-[-0.02em]">
        The training journal.
      </h1>
      <p className="mt-4 max-w-[560px] font-body text-[17px] leading-[1.6] text-text-secondary">
        What you said, what the watch saw, what the coach made of it. Every entry
        opens to the workout in full.
      </p>
    </div>
  );
}

function FilterStrip({ filter, setFilter, count }) {
  const opts = [
    { id: "all", label: "All" },
    { id: "quality", label: "Quality" },
    { id: "voice", label: "Voice logs" },
    { id: "niggles", label: "Niggles" },
  ];
  return (
    <div className="mt-10 flex items-center justify-between border-t border-divider-soft pt-5">
      <div className="flex items-center gap-1">
        {opts.map((o) => {
          const on = filter === o.id;
          return (
            <button
              key={o.id}
              onClick={() => setFilter(o.id)}
              className="font-mono text-[10.5px] tracking-[1.5px] uppercase px-3 py-1.5 rounded-md transition-colors"
              style={{
                color: on ? ACCENT : "#6B6560",
                background: on ? "rgba(212,89,42,0.08)" : "transparent",
                fontWeight: on ? 700 : 500,
              }}
            >
              {o.label}
            </button>
          );
        })}
      </div>
      <Mono>SHOWING {count} OF {ENTRIES.length}</Mono>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   MONTH SECTION + ENTRY CARD
   ════════════════════════════════════════════════════════════════════ */
function MonthSection({ label, entries, onOpen }) {
  const totalMi = entries.reduce((s, e) => s + (e.miles || 0), 0);
  const qualityCount = entries.filter((e) =>
    ["tempo", "intervals", "race"].includes(e.type)
  ).length;
  return (
    <section>
      <div className="flex items-baseline justify-between border-b border-divider pb-3 mb-7">
        <h2 className="font-display text-[40px] leading-none tracking-[-0.02em]">
          {label}
        </h2>
        <Mono>
          {entries.length} ENTRIES &middot; {totalMi.toFixed(1)} MI &middot; {qualityCount} QUALITY
        </Mono>
      </div>
      <div className="space-y-8">
        {entries.map((e) => (
          <EntryCard key={e.id} entry={e} onOpen={onOpen} />
        ))}
      </div>
    </section>
  );
}

function EntryCard({ entry, onOpen }) {
  const isRace = entry.type === "race";
  const isQuality = ["tempo", "intervals", "race", "long"].includes(entry.type);

  return (
    <article
      className="entry-card relative bg-bg-card border border-divider rounded-lg overflow-hidden shadow-[0_2px_8px_rgba(26,24,21,0.04)] cursor-pointer"
      onClick={() => onOpen(entry.id)}
    >
      {/* Left rule */}
      <span
        aria-hidden
        className="absolute left-0 top-0 bottom-0 w-[3px]"
        style={{
          background:
            isRace ? ACCENT :
            entry.type === "tempo" || entry.type === "intervals" ? ACCENT :
            entry.type === "long" ? SAGE :
            entry.type === "rest" ? "transparent" :
            "#C4C0BB",
          opacity: isQuality ? 1 : 0.6,
        }}
      />

      <div className="grid lg:grid-cols-[1fr_280px]">
        {/* LEFT — entry body */}
        <div className="px-7 py-7 lg:border-r lg:border-divider-soft">
          <EntryHeader entry={entry} />

          {/* Voice quote */}
          {entry.quote ? (
            <p className="mt-5 drop-cap font-body italic text-[17px] leading-[1.6] text-text-primary">
              &ldquo;{entry.quote}&rdquo;
            </p>
          ) : null}

          {/* Coach feedback */}
          {entry.coachNote ? (
            <div className="mt-6 coach-note text-[15px] leading-[1.55]">
              <span dangerouslySetInnerHTML={{ __html: entry.coachNote }} />
              <p className="mt-2 font-mono text-[9.5px] tracking-[1.3px] uppercase text-text-tertiary not-italic">
                From your coach &middot; Week {entry.weekNo}
              </p>
            </div>
          ) : null}

          {/* Niggles inline (if any) */}
          {entry.niggles && entry.niggles.length > 0 ? (
            <div className="mt-5 pt-4 border-t border-divider-soft">
              <Mono>NIGGLES</Mono>
              <div className="mt-2 space-y-1.5">
                {entry.niggles.map((n) => (
                  <p key={n.part} className="font-body text-[13px] leading-[1.4] text-text-secondary">
                    <span className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-primary mr-2">
                      {n.part}
                    </span>
                    <span className="italic">&ldquo;{n.quote}&rdquo;</span>
                    <span className="ml-2 font-mono text-[9.5px] tracking-[1.3px] uppercase" style={{ color: ACCENT }}>
                      {n.severity}
                    </span>
                  </p>
                ))}
              </div>
            </div>
          ) : null}

          {/* Tags */}
          {entry.tags && entry.tags.length > 0 ? (
            <div className="mt-5 flex flex-wrap items-center gap-x-3 gap-y-1.5">
              {entry.tags.map((t) => (
                <span
                  key={t}
                  className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary border border-divider rounded-[3px] px-1.5 py-0.5"
                >
                  {t}
                </span>
              ))}
            </div>
          ) : null}

          <div className="mt-6 inline-flex items-center gap-2 font-mono text-[10.5px] tracking-[1.5px] uppercase" style={{ color: ACCENT }}>
            Open the workout
            <span className="open-arrow inline-block">↗</span>
          </div>
        </div>

        {/* RIGHT — workout stat rail + mini split chart */}
        <aside className="px-6 py-7 bg-bg-elevated/60 lg:bg-bg-elevated">
          <Mono>WORKOUT DATA</Mono>
          {entry.miles > 0 ? (
            <div className="mt-3">
              <p className="font-display text-[44px] leading-none tabular-nums tracking-[-0.02em]">
                {entry.miles.toFixed(1)}
                <span className="ml-1.5 font-mono text-[11px] tracking-[1.4px] uppercase text-text-tertiary">mi</span>
              </p>
              <p className="mt-2 font-mono text-[12px] tabular-nums text-text-secondary">
                {entry.durationMin ? formatDuration(entry.durationMin) : "—"}
                {entry.pace ? <> &middot; {entry.pace}<span className="ml-0.5 text-[10px] tracking-[1.2px] uppercase text-text-tertiary"> /mi</span></> : null}
              </p>
            </div>
          ) : (
            <p className="mt-3 font-display italic text-[20px] text-text-tertiary">
              No miles &mdash; check-in only.
            </p>
          )}

          {/* mood pill */}
          <div className="mt-5">
            <Mono>MOOD</Mono>
            <div className="mt-2 inline-flex items-center gap-2">
              <span
                className="block h-[10px] w-[10px] rounded-full"
                style={{ background: MOOD_COLORS[entry.mood] }}
              />
              <span className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-primary" style={{ fontWeight: 600 }}>
                {entry.mood}
              </span>
            </div>
          </div>

          {/* mini splits chart or intervals table */}
          {entry.splits && entry.splits.length > 1 ? (
            <div className="mt-5">
              <SplitsBars data={entry.splits} accent={ACCENT} />
            </div>
          ) : entry.intervals && entry.intervals.length > 0 ? (
            <div className="mt-5">
              <Mono>{isRace ? "SPLITS" : "REPS"}</Mono>
              <div className="mt-2 space-y-1">
                {entry.intervals.slice(0, 4).map((it) => (
                  <div key={it.label} className="flex items-baseline justify-between font-mono text-[11px] tabular-nums">
                    <span className="text-text-tertiary tracking-[1.2px]">{it.label}</span>
                    <span className="text-text-primary">{it.time}</span>
                  </div>
                ))}
                {entry.intervals.length > 4 ? (
                  <p className="font-mono text-[9.5px] tracking-[1.2px] uppercase text-text-tertiary pt-1">
                    + {entry.intervals.length - 4} MORE
                  </p>
                ) : null}
              </div>
            </div>
          ) : null}

          {/* race link callout */}
          {entry.raceLink ? (
            <div className="mt-5 pt-5 border-t border-divider-soft">
              <Mono color={ACCENT}>RACE INDICATOR</Mono>
              <p className="mt-2 font-display text-[22px] tabular-nums leading-none">
                {entry.raceLink.time}
              </p>
              <p className="font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary mt-1">
                {entry.raceLink.dist} &middot; {entry.raceLink.confidence} confidence
              </p>
            </div>
          ) : null}
        </aside>
      </div>
    </article>
  );
}

function EntryHeader({ entry }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <div>
        <Mono>
          {entry.weekday} &middot; {entry.monthDay}
        </Mono>
        <h3 className="mt-1 font-display text-[26px] leading-tight tracking-[-0.01em]">
          {entry.typeLabel}.
        </h3>
      </div>
      <div className="text-right">
        <Mono>WK {entry.weekNo}</Mono>
        {entry.quote ? (
          <p className="mt-1 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary inline-flex items-center gap-1.5">
            <span className="block h-1.5 w-1.5 rounded-full bg-coral/70" /> voice
          </p>
        ) : null}
      </div>
    </div>
  );
}

/* ── mini splits bar chart for entry rail ──────────────────────── */
function SplitsBars({ data, accent }) {
  const fmt = (v) => {
    const m = Math.floor(v);
    const s = Math.round((v - m) * 60);
    return `${m}:${String(s).padStart(2, "0")}`;
  };
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = Math.max(0.4, max - min);
  const avg = data.reduce((a, b) => a + b, 0) / data.length;

  const barH = (v) => 18 + ((v - min) / range) * 38;

  const half = Math.floor(data.length / 2);
  const firstAvg = data.slice(0, half).reduce((a, b) => a + b, 0) / Math.max(1, half);
  const lastAvg = data.slice(-half).reduce((a, b) => a + b, 0) / Math.max(1, half);
  const diff = lastAvg - firstAvg;
  const trend =
    diff < -0.05 ? "NEGATIVE SPLIT" :
    diff > 0.05 ? "POSITIVE SPLIT" :
    "EVEN";

  const fastestIdx = data.indexOf(min);
  const slowestIdx = data.indexOf(max);

  return (
    <div>
      <div className="flex items-baseline justify-between">
        <Mono>SPLITS &middot; PER MI</Mono>
        <span
          className="font-mono text-[9.5px] tracking-[1.3px] uppercase"
          style={{
            color: trend === "NEGATIVE SPLIT" ? "#2D8A4E" : trend === "POSITIVE SPLIT" ? "#C45A3A" : "#9B9590",
          }}
        >
          {trend}
        </span>
      </div>

      <div className="mt-3 flex items-end gap-[3px] h-[60px]">
        {data.map((v, i) => {
          const isFast = i === fastestIdx;
          const isSlow = i === slowestIdx;
          return (
            <div
              key={i}
              className="flex-1 flex flex-col items-stretch justify-end"
              title={`Mile ${i + 1} · ${fmt(v)}`}
            >
              <div
                className="rounded-[1px]"
                style={{
                  height: `${barH(v)}px`,
                  background: isFast ? accent : isSlow ? "#C4C0BB" : "#1A1815",
                  opacity: isFast ? 1 : isSlow ? 1 : 0.7,
                }}
              />
            </div>
          );
        })}
      </div>

      <div className="mt-1.5 flex items-center gap-[3px]">
        {data.map((v, i) => (
          <span
            key={i}
            className="flex-1 text-center font-mono text-[8.5px] tracking-[1px] text-text-tertiary tabular-nums"
          >
            {i + 1}
          </span>
        ))}
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2 pt-3 border-t border-divider-soft">
        <div>
          <p className="font-mono text-[9px] tracking-[1.3px] uppercase" style={{ color: accent }}>
            FASTEST &middot; MI {fastestIdx + 1}
          </p>
          <p className="font-mono text-[12px] tabular-nums text-text-primary mt-0.5">{fmt(min)}</p>
        </div>
        <div className="text-right">
          <p className="font-mono text-[9px] tracking-[1.3px] uppercase text-text-tertiary">
            AVG
          </p>
          <p className="font-mono text-[12px] tabular-nums text-text-primary mt-0.5">{fmt(avg)}</p>
        </div>
      </div>
    </div>
  );
}

/* ── inline split sparkline ──────────────────────────────────────── */
function SplitsSparkInline({ data, accent }) {
  const W = 240;
  const H = 50;
  const padL = 4;
  const padR = 4;
  const padT = 6;
  const padB = 6;
  const min = Math.min(...data) - 0.05;
  const max = Math.max(...data) + 0.05;
  const pts = data.map((v, i) => {
    const x = padL + (i * (W - padL - padR)) / Math.max(1, data.length - 1);
    const y = padT + ((v - min) / (max - min)) * (H - padT - padB);
    return [x, y];
  });
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="mt-2 w-full h-auto">
      <polyline
        points={pts.map(([x, y]) => `${x},${y}`).join(" ")}
        fill="none"
        stroke={accent}
        strokeWidth="1.5"
      />
      {pts.map(([x, y], i) => (
        <circle key={i} cx={x} cy={y} r="1.6" fill={accent} />
      ))}
    </svg>
  );
}

function formatDuration(min) {
  const h = Math.floor(min / 60);
  const m = Math.round(min - h * 60);
  if (h === 0) return `${m}:00`;
  return `${h}:${String(m).padStart(2, "0")}`;
}

/* ════════════════════════════════════════════════════════════════════
   ENTRY DETAIL DRAWER — opens when an entry is clicked.
   "Actual workout data" view: full splits, HR if available, map placeholder.
   ════════════════════════════════════════════════════════════════════ */
function EntryDetailDrawer({ entry, onClose }) {
  return (
    <div
      className="fixed inset-0 z-40 bg-black/30 flex justify-end"
      onClick={onClose}
    >
      <div
        className="w-full max-w-[680px] h-full bg-bg-base overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Drawer header */}
        <div className="sticky top-0 z-10 bg-bg-base border-b border-divider px-8 py-4 flex items-center justify-between">
          <div>
            <Mono>{entry.weekday} &middot; {entry.monthDay} &middot; WK {entry.weekNo}</Mono>
            <h2 className="font-display text-[24px] tracking-[-0.01em] mt-0.5">
              {entry.typeLabel}.
            </h2>
          </div>
          <button
            onClick={onClose}
            className="font-mono text-[11px] tracking-[1.5px] uppercase text-text-secondary hover:text-text-primary"
          >
            Close ✕
          </button>
        </div>

        <div className="px-8 py-7 space-y-8">
          {/* Hero stats */}
          <div className="grid grid-cols-3 gap-4 border-b border-divider-soft pb-6">
            <DetailStat label="MILES" value={entry.miles ? entry.miles.toFixed(1) : "—"} />
            <DetailStat label="TIME" value={entry.durationMin ? formatDuration(entry.durationMin) : "—"} />
            <DetailStat label="PACE" value={entry.pace || "—"} unit="/ mi" />
          </div>

          {/* Map placeholder */}
          <div>
            <Mono>ROUTE</Mono>
            <div className="mt-3 rounded-md border border-divider bg-bg-card overflow-hidden">
              <RouteSketch accent={ACCENT} />
            </div>
            <p className="mt-2 font-body italic text-[12.5px] text-text-tertiary">
              Town Lake loop &middot; clockwise &middot; GPS via Apple Health
            </p>
          </div>

          {/* Splits — full */}
          {entry.splits && entry.splits.length > 0 ? (
            <div>
              <Mono>SPLITS &middot; PER MILE</Mono>
              <SplitsTable splits={entry.splits} accent={ACCENT} />
            </div>
          ) : null}

          {entry.intervals && entry.intervals.length > 0 ? (
            <div>
              <Mono>{entry.type === "race" ? "RACE SPLITS" : "INTERVAL REPS"}</Mono>
              <IntervalTable intervals={entry.intervals} accent={ACCENT} />
            </div>
          ) : null}

          {/* HR + load */}
          <div className="grid grid-cols-3 gap-6">
            <DetailStat label="AVG HR" value="156" unit="bpm" muted />
            <DetailStat label="MAX HR" value="178" unit="bpm" muted />
            <DetailStat label="LOAD" value="78" unit="/ 100" muted />
          </div>

          {/* Voice transcript */}
          {entry.quote ? (
            <div>
              <Mono>VOICE LOG &middot; VERBATIM</Mono>
              <p className="mt-3 font-body italic text-[16px] leading-[1.6] text-text-primary">
                &ldquo;{entry.quote}&rdquo;
              </p>
              <p className="mt-2 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
                Transcribed &middot; 42 sec audio
              </p>
            </div>
          ) : null}

          {entry.coachNote ? (
            <div>
              <Mono>COACH FEEDBACK</Mono>
              <div className="mt-3 coach-note text-[16px] leading-[1.6]">
                <span dangerouslySetInnerHTML={{ __html: entry.coachNote }} />
              </div>
            </div>
          ) : null}

          {/* Actions */}
          <div className="border-t border-divider-soft pt-5 flex flex-wrap items-center gap-3">
            <button
              className="rounded-md px-4 py-2 font-body text-[13px] font-semibold text-white"
              style={{
                background: ACCENT,
                boxShadow: `0 1px 0 #B84420, 0 6px 16px -6px rgba(212,89,42,0.45)`,
              }}
            >
              Ask the coach about this
            </button>
            <button className="rounded-md border border-divider px-3.5 py-2 font-body text-[13px] text-text-primary hover:border-text-tertiary">
              Edit notes
            </button>
            <button className="rounded-md border border-divider px-3.5 py-2 font-body text-[13px] text-text-secondary hover:text-text-primary hover:border-text-tertiary">
              Export this entry
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function DetailStat({ label, value, unit, muted }) {
  return (
    <div>
      <Mono>{label}</Mono>
      <p
        className="mt-1 font-display tabular-nums tracking-[-0.01em] leading-none"
        style={{ fontSize: muted ? 26 : 36, color: muted ? "#6B6560" : "#1A1815" }}
      >
        {value}
        {unit ? (
          <span className="ml-1.5 font-mono text-[10px] tracking-[1.3px] uppercase text-text-tertiary">
            {unit}
          </span>
        ) : null}
      </p>
    </div>
  );
}

function SplitsTable({ splits, accent }) {
  const min = Math.min(...splits);
  return (
    <div className="mt-3 border border-divider-soft rounded-md overflow-hidden">
      {splits.map((s, i) => {
        const isFastest = Math.abs(s - min) < 0.001;
        const pct = ((s - (min - 0.4)) / 1.4) * 100;
        return (
          <div
            key={i}
            className={`grid grid-cols-[40px_1fr_60px] items-center gap-3 px-3 py-2 ${
              i < splits.length - 1 ? "border-b border-divider-soft" : ""
            }`}
            style={{ background: i % 2 === 0 ? "#FFFFFF" : "#FAFAF8" }}
          >
            <span className="font-mono text-[10.5px] tracking-[1.3px] uppercase text-text-tertiary">
              MI {i + 1}
            </span>
            <div className="h-2 bg-divider/60 rounded-[1px] relative overflow-hidden">
              <div
                className="absolute inset-y-0 left-0"
                style={{
                  width: `${Math.min(100, pct)}%`,
                  background: isFastest ? accent : "#1A1815",
                  opacity: isFastest ? 1 : 0.7,
                }}
              />
            </div>
            <span
              className="font-mono text-[11.5px] tabular-nums text-right"
              style={{ color: isFastest ? accent : "#1A1815", fontWeight: isFastest ? 700 : 500 }}
            >
              {Math.floor(s)}:{String(Math.round((s - Math.floor(s)) * 60)).padStart(2, "0")}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function IntervalTable({ intervals, accent }) {
  return (
    <div className="mt-3 border border-divider-soft rounded-md overflow-hidden">
      {intervals.map((it, i) => (
        <div
          key={it.label}
          className={`grid grid-cols-[80px_1fr_auto] items-baseline gap-3 px-3.5 py-2.5 ${
            i < intervals.length - 1 ? "border-b border-divider-soft" : ""
          }`}
          style={{ background: i % 2 === 0 ? "#FFFFFF" : "#FAFAF8" }}
        >
          <span className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary">
            {it.label}
          </span>
          <span className="font-mono text-[14px] tabular-nums text-text-primary">
            {it.time}
          </span>
          <span className="font-mono text-[11px] tabular-nums text-text-secondary">
            {it.pace}
          </span>
        </div>
      ))}
    </div>
  );
}

/* Simple route sketch — squiggle on paper */
function RouteSketch({ accent }) {
  return (
    <svg viewBox="0 0 600 200" className="w-full h-auto block bg-bg-elevated">
      <defs>
        <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
          <path d="M 20 0 L 0 0 0 20" fill="none" stroke="#E8E4E0" strokeWidth="0.5" />
        </pattern>
      </defs>
      <rect width="600" height="200" fill="url(#grid)" />
      <path
        d="M40,140 C90,80 150,60 220,90 C290,120 320,170 400,150 C470,135 510,100 560,60"
        fill="none"
        stroke={accent}
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <circle cx="40" cy="140" r="5" fill="#1A1815" />
      <circle cx="560" cy="60" r="5" fill={accent} />
      <text x="50" y="158" fontFamily="ui-monospace, Menlo, monospace" fontSize="10" letterSpacing="1.2" fill="#9B9590">START</text>
      <text x="528" y="48" fontFamily="ui-monospace, Menlo, monospace" fontSize="10" letterSpacing="1.2" fill="#9B9590">FINISH</text>
    </svg>
  );
}

/* ════════════════════════════════════════════════════════════════════
   EXPORT DIALOG
   ════════════════════════════════════════════════════════════════════ */
function ExportDialog({ onClose, count }) {
  const [format, setFormat] = useState("pdf");
  const [range, setRange] = useState("all");
  const [include, setInclude] = useState({ voice: true, coach: true, workouts: true, niggles: true });

  return (
    <div
      className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center px-6"
      onClick={onClose}
    >
      <div
        className="w-full max-w-[520px] bg-bg-card rounded-lg border border-divider shadow-[0_30px_80px_-20px_rgba(26,24,21,0.4)] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-6 py-5 border-b border-divider-soft flex items-baseline justify-between">
          <div>
            <Mono>EXPORT &middot; THE JOURNAL</Mono>
            <h2 className="mt-1 font-display text-[26px] tracking-[-0.01em]">
              Take it with you.
            </h2>
          </div>
          <button onClick={onClose} className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-secondary hover:text-text-primary">
            ✕
          </button>
        </div>

        <div className="px-6 py-5 space-y-5">
          {/* Format */}
          <div>
            <Mono>FORMAT</Mono>
            <div className="mt-2 grid grid-cols-3 gap-2">
              {[
                { id: "pdf", label: "PDF journal", hint: "Typeset, prints clean" },
                { id: "csv", label: "CSV", hint: "Workouts as a table" },
                { id: "md", label: "Markdown", hint: "Plain text · for coaches" },
              ].map((opt) => {
                const on = format === opt.id;
                return (
                  <button
                    key={opt.id}
                    onClick={() => setFormat(opt.id)}
                    className="text-left rounded-md border px-3 py-2.5 transition-colors"
                    style={{
                      borderColor: on ? ACCENT : "#E8E4E0",
                      background: on ? "rgba(212,89,42,0.05)" : "transparent",
                    }}
                  >
                    <p className="font-display text-[15px] tracking-[-0.005em] text-text-primary">
                      {opt.label}
                    </p>
                    <p className="font-mono text-[9.5px] tracking-[1.2px] uppercase text-text-tertiary mt-0.5">
                      {opt.hint}
                    </p>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Range */}
          <div>
            <Mono>RANGE</Mono>
            <div className="mt-2 flex flex-wrap gap-2">
              {[
                { id: "all", label: "All entries" },
                { id: "30d", label: "Last 30 days" },
                { id: "block", label: "This marathon block" },
                { id: "custom", label: "Custom…" },
              ].map((opt) => {
                const on = range === opt.id;
                return (
                  <button
                    key={opt.id}
                    onClick={() => setRange(opt.id)}
                    className="font-mono text-[10.5px] tracking-[1.4px] uppercase px-3 py-1.5 rounded-md border transition-colors"
                    style={{
                      color: on ? ACCENT : "#6B6560",
                      borderColor: on ? ACCENT : "#E8E4E0",
                      background: on ? "rgba(212,89,42,0.05)" : "transparent",
                      fontWeight: on ? 700 : 500,
                    }}
                  >
                    {opt.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Include */}
          <div>
            <Mono>INCLUDE</Mono>
            <div className="mt-2 space-y-2">
              {[
                ["voice", "Voice-log transcripts"],
                ["coach", "Coach feedback"],
                ["workouts", "Workout data (splits, HR, route)"],
                ["niggles", "Niggles &amp; body-part mentions"],
              ].map(([k, lbl]) => (
                <label
                  key={k}
                  className="flex items-center gap-2.5 cursor-pointer text-[13.5px] text-text-primary"
                >
                  <input
                    type="checkbox"
                    checked={include[k]}
                    onChange={(e) => setInclude({ ...include, [k]: e.target.checked })}
                    className="h-4 w-4 accent-coral"
                  />
                  <span dangerouslySetInnerHTML={{ __html: lbl }} />
                </label>
              ))}
            </div>
          </div>

          {/* Summary */}
          <div className="bg-bg-elevated border border-divider-soft rounded-md p-3 flex items-baseline justify-between">
            <div>
              <Mono>EXPORTING</Mono>
              <p className="mt-0.5 font-display text-[18px] tracking-[-0.005em]">
                {range === "all" ? count : range === "30d" ? Math.min(count, 12) : range === "block" ? 6 : count} entries
              </p>
            </div>
            <p className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-tertiary">
              {format.toUpperCase()}
            </p>
          </div>
        </div>

        <div className="px-6 py-4 border-t border-divider-soft flex items-center justify-between bg-bg-elevated">
          <p className="font-body italic text-[12px] text-text-tertiary">
            One file. Yours. No watermark.
          </p>
          <div className="flex items-center gap-2">
            <button onClick={onClose} className="font-mono text-[10.5px] tracking-[1.4px] uppercase text-text-secondary px-3 py-2 hover:text-text-primary">
              Cancel
            </button>
            <button
              className="rounded-md px-4 py-2 font-body text-[13px] font-semibold text-white"
              style={{
                background: ACCENT,
                boxShadow: `0 1px 0 #B84420, 0 6px 16px -6px rgba(212,89,42,0.45)`,
              }}
            >
              Export ↗
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── mount ──────────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

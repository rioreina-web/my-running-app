/* global React */
const { useState, useEffect, useRef } = React;

/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — HOME PAGE
   Editorial redesign honoring brand voice doc:
   - "A coach that actually knows you." in the hook
   - AI never appears in headline / tagline / CTA
   - Every claim grounded in a specific number, workout, or paces
   - Peer energy, restrained typography, citations under every insight
   ════════════════════════════════════════════════════════════════════ */

const HOMEPAGE_TWEAKS = /*EDITMODE-BEGIN*/{
  "headline": "knows-you",
  "heroLayout": "split",
  "accent": "#D4592A",
  "persona": "marathoner",
  "showEvidence": true,
  "showCoachWont": true
}/*EDITMODE-END*/;

const HEADLINES = {
  "knows-you": {
    kicker: "A running coach",
    main: "that actually knows",
    italic: "you.",
  },
  "reads-training": {
    kicker: "Built for serious runners",
    main: "A coach that reads",
    italic: "your training.",
  },
  "run-with-us": {
    kicker: "Coaching, implemented carefully",
    main: "Run with us.",
    italic: "We'll catch up.",
  },
};

const ACCENTS = {
  "#D4592A": { hex: "#D4592A", soft: "rgba(212,89,42,0.10)", deep: "#B84420" },
  "#2D6A4F": { hex: "#2D6A4F", soft: "rgba(45,106,79,0.10)", deep: "#1F4D38" },
  "#1F3A5F": { hex: "#1F3A5F", soft: "rgba(31,58,95,0.10)", deep: "#142943" },
};
const ACCENT_KEYS = Object.keys(ACCENTS);

const PERSONAS = {
  marathoner: {
    label: "Marathoner · Sub-3:00 chase",
    weekTotal: "62.4",
    weekRuns: "6",
    weekAvg: "10.4",
    weekPace: "7:42",
    threshold: "6:18",
    thresholdRef: "5×1mi target",
    weatherPace: "6:12–6:18",
    weatherWhy: "dew point 68° at 6 a.m.",
    raceDist: "Marathon",
    prediction: "2:58:42",
    predictionDelta: "−14s in 4 weeks",
    coachMessage: {
      headline: "Tuesday's threshold is up.",
      body: "Last three came in 4s under target each time. Pace zone shifts down: hit 6:18 today, not 6:22.",
      cites: [
        "Tue · 5/05  tempo, 5×1mi @ 6:18 avg",
        "Tue · 4/28  tempo, 5×1mi @ 6:18 avg",
        "Tue · 4/21  tempo, 4×1mi @ 6:21 avg",
      ],
    },
  },
  fiveK: {
    label: "5K · Sub-17 chase",
    weekTotal: "38.2",
    weekRuns: "5",
    weekAvg: "7.6",
    weekPace: "7:08",
    threshold: "5:24",
    thresholdRef: "8×400m target",
    weatherPace: "5:34–5:38",
    weatherWhy: "headwind 11 mph on the back straight",
    raceDist: "5K",
    prediction: "16:48",
    predictionDelta: "−6s in 3 weeks",
    coachMessage: {
      headline: "Saturday's 8×400 is dialed.",
      body: "You hit 5:24 average last week feeling controlled. Holding target. No reason to push the rep pace until we see a slower week.",
      cites: [
        "Sat · 5/02  8×400 @ 5:24 avg, 90s jog",
        "Sat · 4/25  8×400 @ 5:26 avg, 90s jog",
        "Tue · 4/21  6×800 @ 5:32 avg",
      ],
    },
  },
  coach: {
    label: "Coach view · Roster of 14",
    weekTotal: "—",
    weekRuns: "14",
    weekAvg: "—",
    weekPace: "—",
    threshold: "varies",
    thresholdRef: "by athlete",
    weatherPace: "by athlete",
    weatherWhy: "shared pace logic, per-athlete data",
    raceDist: "Mixed",
    prediction: "14 athletes",
    predictionDelta: "11 on plan this week",
    coachMessage: {
      headline: "Maya missed Tuesday's threshold.",
      body: "Sleep was 5h Mon and Tue. She kept logging easy runs at 8:30/mi instead of 8:45. Recommend pushing Saturday long to Sunday and notes on cumulative load.",
      cites: [
        "Tue · 5/05  skipped, logged sleep 5h",
        "Wed · 5/06  easy 6mi @ 8:30/mi",
        "Athlete state: ACWR 1.41, flagged",
      ],
    },
  },
};

/* ── shared ────────────────────────────────────────────────────────── */
const Kicker = ({ children, accent }) => (
  <span
    className="font-mono text-[11px] font-medium tracking-[2px] uppercase"
    style={{ color: accent }}
  >
    {children}
  </span>
);

const MutedKicker = ({ children }) => (
  <span className="font-mono text-[11px] font-medium tracking-[2px] uppercase text-text-tertiary">
    {children}
  </span>
);

const RuleDot = () => (
  <span className="inline-block h-[3px] w-[3px] rounded-full bg-divider align-middle mx-2" />
);

const EditorialRule = () => (
  <div className="flex items-center gap-2 my-12">
    <div className="flex-1 h-px bg-divider" />
    <div className="w-[3px] h-[3px] rounded-full bg-divider" />
    <div className="flex-1 h-px bg-divider" />
  </div>
);

/* ════════════════════════════════════════════════════════════════════
   APP
   ════════════════════════════════════════════════════════════════════ */
function App() {
  const [t, setTweak] = useTweaks(HOMEPAGE_TWEAKS);
  const accent = ACCENTS[t.accent] || ACCENTS["#D4592A"];
  const headline = HEADLINES[t.headline];
  const persona = PERSONAS[t.persona];

  // expose accent as a CSS var so children can use it without prop drilling
  useEffect(() => {
    document.documentElement.style.setProperty("--accent", accent.hex);
    document.documentElement.style.setProperty("--accent-soft", accent.soft);
    document.documentElement.style.setProperty("--accent-deep", accent.deep);
  }, [accent]);

  return (
    <div className="min-h-screen bg-bg-base text-text-primary font-body">
      <Header accent={accent} />
      <main>
        <Hero
          headline={headline}
          persona={persona}
          accent={accent}
          layout={t.heroLayout}
        />
        <PrinciplesBand accent={accent} />
        <ProblemSection />
        <HowItWorks accent={accent} />
        {t.showEvidence && <EvidenceSection persona={persona} accent={accent} />}
        <WeekInTheLife persona={persona} accent={accent} />
        <ProofSection persona={persona} accent={accent} />
        {t.showCoachWont && <WhatCoachWontDo />}
        <NotForEveryone />
        <FinalCTA accent={accent} />
      </main>
      <Footer />

      <TweaksPanel title="Tweaks">
        <TweakSection label="Hook">
          <TweakSelect
            label="Headline"
            value={t.headline}
            onChange={(v) => setTweak("headline", v)}
            options={[
              { value: "knows-you", label: "A coach that actually knows you." },
              { value: "reads-training", label: "A coach that reads your training." },
              { value: "run-with-us", label: "Run with us." },
            ]}
          />
          <TweakRadio
            label="Hero layout"
            value={t.heroLayout}
            onChange={(v) => setTweak("heroLayout", v)}
            options={[
              { value: "split", label: "Split" },
              { value: "typographic", label: "Type-led" },
            ]}
          />
        </TweakSection>

        <TweakSection label="Voice & data">
          <TweakSelect
            label="Athlete persona in examples"
            value={t.persona}
            onChange={(v) => setTweak("persona", v)}
            options={[
              { value: "marathoner", label: "Marathoner · sub-3:00" },
              { value: "fiveK", label: "5K · sub-17" },
              { value: "coach", label: "Coach view · roster of 14" },
            ]}
          />
        </TweakSection>

        <TweakSection label="Visual">
          <TweakColor
            label="Accent"
            value={t.accent}
            onChange={(v) => setTweak("accent", v)}
            options={ACCENT_KEYS}
          />
        </TweakSection>

        <TweakSection label="Sections">
          <TweakToggle
            label="Show evidence section"
            value={t.showEvidence}
            onChange={(v) => setTweak("showEvidence", v)}
          />
          <TweakToggle
            label="Show 'what the coach won't do'"
            value={t.showCoachWont}
            onChange={(v) => setTweak("showCoachWont", v)}
          />
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   HEADER
   ════════════════════════════════════════════════════════════════════ */
function Header({ accent }) {
  return (
    <header className="border-b border-divider bg-bg-base/80 backdrop-blur sticky top-0 z-30">
      <div className="mx-auto max-w-[1180px] flex items-center justify-between px-8 py-5 whitespace-nowrap gap-6">
        <a href="#" className="font-display text-[22px] tracking-[-0.01em] shrink-0">
          Post Run Drip
        </a>
        <div className="flex items-center gap-6 shrink-0">
          <a
            href="#login"
            className="font-body text-[14px] text-text-secondary hover:text-text-primary"
          >
            Sign in
          </a>
          <a
            href="#start"
            className="rounded-md px-4 py-2 font-body text-[14px] font-semibold text-white transition-colors"
            style={{ backgroundColor: accent.hex }}
          >
            Get the app
          </a>
        </div>
      </div>
    </header>
  );
}

/* ════════════════════════════════════════════════════════════════════
   HERO
   ════════════════════════════════════════════════════════════════════ */
function Hero({ headline, persona, accent, layout }) {
  if (layout === "typographic") return <HeroTypographic headline={headline} accent={accent} />;
  return <HeroSplit headline={headline} persona={persona} accent={accent} />;
}

function HeroSplit({ headline, persona, accent }) {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1180px] grid lg:grid-cols-[1.05fr_0.95fr] gap-16 px-8 pt-20 pb-24">
        {/* LEFT — type */}
        <div className="flex flex-col">
          <Kicker accent={accent.hex}>{headline.kicker}</Kicker>
          <h1 className="mt-7 font-display text-[68px] leading-[0.98] tracking-[-0.015em] text-text-primary">
            {headline.main}
            <br />
            <em className="not-italic font-display" style={{ color: accent.hex, fontStyle: "italic" }}>
              {headline.italic}
            </em>
          </h1>
          <p className="mt-8 max-w-[460px] font-body text-[17px] leading-[1.55] text-text-secondary">
            Reads every workout you log. Tracks how each pace zone is actually
            holding up. Adjusts your week when the weather, the calendar, or
            your sleep tells it to. Says so when it's guessing.
          </p>

          <div className="mt-10 flex items-center gap-3">
            <a
              href="#start"
              className="rounded-md px-6 py-3.5 font-body text-[14px] font-semibold text-white"
              style={{
                backgroundColor: accent.hex,
                boxShadow: `0 1px 0 ${accent.deep}, 0 8px 24px -8px ${accent.soft}`,
              }}
            >
              Run with us
            </a>
            <a
              href="#how"
              className="rounded-md border border-divider px-6 py-3.5 font-body text-[14px] font-medium text-text-secondary hover:border-text-tertiary"
            >
              See how the coach reads a week
            </a>
          </div>

          <p className="mt-6 font-mono text-[11px] text-text-tertiary tracking-[1px]">
            First week is on us — we use it to understand your training.
            <RuleDot />
            iOS, TestFlight invite.
          </p>

          {/* tiny ground-level number row */}
          <dl className="mt-14 grid grid-cols-3 gap-8 border-t border-divider pt-6">
            <Ground k="Workouts read" v="412,000" sub="and counting" />
            <Ground k="Median runner" v="32 mi/wk" sub="not a beginner app" />
            <Ground k="Recommendations" v="100%" sub="cite the source" accent={accent.hex} />
          </dl>
        </div>

        {/* RIGHT — coach moment */}
        <div className="relative">
          <div className="sticky top-28">
            <CoachMomentCard persona={persona} accent={accent} />
            <p className="mt-3 font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary text-right">
              Actual coach message — {persona.label}
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

function HeroTypographic({ headline, accent }) {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1080px] px-8 pt-28 pb-24 text-center">
        <Kicker accent={accent.hex}>{headline.kicker}</Kicker>
        <h1 className="mt-8 font-display text-[112px] leading-[0.95] tracking-[-0.02em]">
          {headline.main}
          <br />
          <em style={{ color: accent.hex, fontStyle: "italic" }}>{headline.italic}</em>
        </h1>
        <p className="mx-auto mt-10 max-w-[560px] font-body text-[18px] leading-[1.6] text-text-secondary">
          The discipline and voice of a great coach, implemented carefully.
          Every recommendation cites the workout it's based on. When there
          isn't enough data, the coach says so.
        </p>
        <div className="mt-10 flex justify-center gap-3">
          <a
            href="#start"
            className="rounded-md px-6 py-3.5 font-body text-[14px] font-semibold text-white"
            style={{ backgroundColor: accent.hex }}
          >
            Run with us
          </a>
          <a
            href="#how"
            className="rounded-md border border-divider px-6 py-3.5 font-body text-[14px] font-medium text-text-secondary"
          >
            See how it works
          </a>
        </div>
      </div>
    </section>
  );
}

function Ground({ k, v, sub, accent }) {
  return (
    <div>
      <dt className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
        {k}
      </dt>
      <dd className="mt-1 font-display text-[26px] tracking-[-0.01em]" style={{ color: accent || undefined }}>
        {v}
      </dd>
      <span className="font-body text-[12px] text-text-tertiary">{sub}</span>
    </div>
  );
}

/* ── the coach moment card — the hero's "screenshot" ─────────────── */
function CoachMomentCard({ persona, accent }) {
  const m = persona.coachMessage;
  return (
    <div className="rounded-2xl bg-bg-card border border-divider shadow-[0_30px_80px_-40px_rgba(26,24,21,0.25)] overflow-hidden">
      {/* header strip */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-divider-soft bg-bg-elevated">
        <div className="flex items-center gap-2.5">
          <span
            className="inline-block h-2 w-2 rounded-full"
            style={{ backgroundColor: accent.hex }}
          />
          <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-secondary">
            Coach · Tuesday 6:42 a.m.
          </span>
        </div>
        <span className="font-mono text-[10px] text-text-tertiary">v.142</span>
      </div>

      {/* body */}
      <div className="px-7 pt-7 pb-6">
        <p className="font-display text-[26px] leading-[1.15] tracking-[-0.01em] text-text-primary">
          {m.headline}
        </p>
        <p className="mt-4 font-body text-[15px] leading-[1.55] text-text-secondary">
          {m.body}
        </p>

        {/* the move */}
        <div className="mt-6 grid grid-cols-3 gap-4 border-t border-divider pt-5">
          <NumberCell k="Today's target" v={persona.threshold} sub={persona.thresholdRef} accent={accent.hex} />
          <NumberCell k="Confidence" v="High" sub="3 of 3 quality runs hit target" />
          <NumberCell k="Last 3 weeks" v="−4s/mi" sub="avg under target" />
        </div>
      </div>

      {/* citations footer */}
      <div className="px-7 pb-6 pt-2">
        <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary mb-3">
          Based on
        </p>
        <ul className="space-y-1.5">
          {m.cites.map((c, i) => (
            <li
              key={i}
              className="flex items-baseline gap-2 font-mono text-[12px] text-text-secondary"
            >
              <span style={{ color: accent.hex }}>·</span>
              <span>{c}</span>
            </li>
          ))}
        </ul>
        <div className="mt-5 flex items-center justify-between border-t border-divider-soft pt-4">
          <button
            className="font-body text-[13px] font-medium"
            style={{ color: accent.hex }}
          >
            See the workouts →
          </button>
          <button className="font-body text-[13px] text-text-tertiary">
            Push back
          </button>
        </div>
      </div>
    </div>
  );
}

function NumberCell({ k, v, sub, accent }) {
  return (
    <div>
      <p className="font-mono text-[9px] tracking-[1.5px] uppercase text-text-tertiary">
        {k}
      </p>
      <p
        className="mt-1 font-mono text-[22px] tabular-nums font-semibold text-text-primary"
        style={{ color: accent || undefined }}
      >
        {v}
      </p>
      <p className="mt-0.5 font-body text-[11px] leading-tight text-text-tertiary">
        {sub}
      </p>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PRINCIPLES BAND
   ════════════════════════════════════════════════════════════════════ */
function PrinciplesBand({ accent }) {
  const items = [
    ["01", "Reads", "every workout you log — including the ones you skipped."],
    ["02", "Cites", "the specific runs each recommendation came from."],
    ["03", "Adjusts", "when the weather, the calendar, or your sleep changes."],
    ["04", "Admits", "when the data isn't there yet. No hallucinating."],
  ];
  return (
    <section className="bg-bg-elevated border-b border-divider">
      <div className="mx-auto max-w-[1180px] grid md:grid-cols-4 divide-x divide-divider">
        {items.map(([n, verb, rest]) => (
          <div key={n} className="px-7 py-9">
            <span className="font-mono text-[10px] tracking-[1.5px] text-text-tertiary">
              {n}
            </span>
            <p className="mt-3 font-display text-[28px] tracking-[-0.01em] text-text-primary">
              <span style={{ color: accent.hex }}>{verb}</span>
            </p>
            <p className="mt-1 font-body text-[13px] leading-[1.5] text-text-secondary">
              {rest}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PROBLEM
   ════════════════════════════════════════════════════════════════════ */
function ProblemSection() {
  return (
    <section className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[860px] px-8 py-28 text-center">
        <MutedKicker>The state of AI running coaches</MutedKicker>
        <p className="mt-8 font-display text-[40px] leading-[1.15] tracking-[-0.01em] text-text-primary">
          Generic AI coaches give generic advice.
          <span className="text-text-tertiary"> You're not a generic runner.</span>
        </p>
        <p className="mx-auto mt-8 max-w-[640px] font-body text-[17px] leading-[1.65] text-text-secondary">
          Most "AI-powered" running apps take your last run and feed it through
          a chatbot. They miss what a good human coach catches in 30 seconds —
          that Tuesday's threshold came in 4 seconds under target three weeks
          running, that your easy days have crept faster, that the long run
          you skipped two Saturdays ago is the reason this Saturday hurts.
        </p>
        <p className="mx-auto mt-6 max-w-[640px] font-body text-[17px] leading-[1.65] text-text-secondary">
          We built the software to do the boring work — reading logs, tracking
          paces, watching weather — so the coaching can focus on the
          decisions. When to push. When to recover. When to move the long run.
        </p>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   HOW IT WORKS
   ════════════════════════════════════════════════════════════════════ */
function HowItWorks({ accent }) {
  return (
    <section id="how" className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-8 py-24">
        <div className="grid md:grid-cols-[0.9fr_2fr] gap-12 border-b border-divider pb-10">
          <div>
            <MutedKicker>How the coach works</MutedKicker>
            <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
              Four things,<br />done <em style={{ color: accent.hex, fontStyle: "italic" }}>well</em>.
            </h2>
          </div>
          <p className="font-body text-[17px] leading-[1.6] text-text-secondary self-end">
            None of these are clever. They're the things a great human coach
            does without thinking. We just made the software actually do them.
          </p>
        </div>

        <div className="mt-2 grid md:grid-cols-2 gap-x-12 gap-y-2">
          <Capability
            n="01"
            verb="Reads"
            title="every workout, voice-logged or imported"
            body="Talk after your run, or sync from your watch. We pull distance, splits, intervals, heart rate, perceived effort, mood. No forms."
            example="“Did five on the river trail. Pickups in the middle, felt strong.”"
            exampleAfter="→ 5.1 mi · 8:15/mi · 4×30s pickups · mood ↑"
            accent={accent}
          />
          <Capability
            n="02"
            verb="Adjusts"
            title="your pace zones when you change"
            body="Pace zones aren't fixed targets from a calculator. They drift as your training holds up — or doesn't. We notice and shift."
            example="Last 3 thresholds: 6:22 → 6:21 → 6:18"
            exampleAfter="→ Threshold zone shifted: 6:25 → 6:18"
            accent={accent}
          />
          <Capability
            n="03"
            verb="Watches"
            title="the weather and the calendar"
            body="Dew point, wind, heat-acclimatization week, the meeting you booked at 6 a.m. — these are inputs. They change the right call."
            example="Sat forecast: dew point 68° at 6 a.m."
            exampleAfter="→ Long run pace shifted +14s/mi for the heat"
            accent={accent}
          />
          <Capability
            n="04"
            verb="Admits"
            title="when it's guessing"
            body="If we don't have enough recent data, we say so — out loud. No hedging into confidence. Honesty is the trust-builder."
            example="“Your pace profile is fresh from last week.”"
            exampleAfter="→ Confidence: low · waiting on 2 more quality sessions"
            accent={accent}
          />
        </div>
      </div>
    </section>
  );
}

function Capability({ n, verb, title, body, example, exampleAfter, accent }) {
  return (
    <div className="grid grid-cols-[auto_1fr] gap-5 border-b border-divider py-9 last:border-b-0 md:[&:nth-last-child(2)]:border-b-0">
      <span className="font-mono text-[11px] tracking-[1.5px] text-text-tertiary mt-2">
        {n}
      </span>
      <div>
        <h3 className="font-display text-[28px] tracking-[-0.01em] leading-[1.1]">
          <span style={{ color: accent.hex }}>{verb}</span>{" "}
          <span className="text-text-primary">{title}.</span>
        </h3>
        <p className="mt-3 font-body text-[15px] leading-[1.55] text-text-secondary max-w-[440px]">
          {body}
        </p>
        <div className="mt-5 border-l-2 pl-4" style={{ borderColor: accent.hex }}>
          <p className="font-display italic text-[14px] leading-[1.5] text-text-secondary">
            {example}
          </p>
          <p className="mt-1.5 font-mono text-[12px] text-text-primary tabular-nums">
            {exampleAfter}
          </p>
        </div>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   EVIDENCE — every recommendation cites the workout
   ════════════════════════════════════════════════════════════════════ */
function EvidenceSection({ persona, accent }) {
  return (
    <section id="evidence" className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-8 py-24 grid lg:grid-cols-[0.8fr_1.2fr] gap-16 items-center">
        <div>
          <MutedKicker>The honesty layer</MutedKicker>
          <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
            Every recommendation
            <br />
            <em style={{ color: accent.hex, fontStyle: "italic" }}>
              cites the workout.
            </em>
          </h2>
          <p className="mt-6 font-body text-[16px] leading-[1.6] text-text-secondary max-w-[420px]">
            Tap any insight to see the runs it came from — paces, dates,
            conditions, and how confident the coach is in the call. If the
            data isn't there, you'll see that too.
          </p>
          <ul className="mt-7 space-y-3 font-body text-[14px] text-text-secondary">
            <Bullet accent={accent.hex}>
              No hidden weighting. Every input the coach used is visible.
            </Bullet>
            <Bullet accent={accent.hex}>
              Confidence levels: <em className="font-mono not-italic">high · medium · low · insufficient data</em>.
            </Bullet>
            <Bullet accent={accent.hex}>
              You can disagree. Push back and the coach revises in front of you.
            </Bullet>
          </ul>
        </div>

        {/* Annotated coach card */}
        <div className="relative">
          <AnnotatedCoachCard persona={persona} accent={accent} />
        </div>
      </div>
    </section>
  );
}

function Bullet({ children, accent }) {
  return (
    <li className="flex items-baseline gap-3">
      <span className="font-mono text-[14px]" style={{ color: accent }}>·</span>
      <span className="leading-[1.55]">{children}</span>
    </li>
  );
}

function AnnotatedCoachCard({ persona, accent }) {
  const m = persona.coachMessage;
  return (
    <div className="relative">
      {/* the card itself */}
      <div className="rounded-2xl bg-bg-card border border-divider shadow-[0_30px_60px_-40px_rgba(26,24,21,0.2)] overflow-hidden">
        <div className="px-7 pt-6 pb-5 border-b border-divider-soft">
          <div className="flex items-center justify-between">
            <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-secondary">
              Coach insight
            </span>
            <span
              className="rounded-full px-2 py-0.5 font-mono text-[9px] tracking-[1.5px] uppercase"
              style={{ backgroundColor: accent.soft, color: accent.hex }}
            >
              Confidence · high
            </span>
          </div>
          <p className="mt-3 font-display text-[22px] leading-[1.2] tracking-[-0.01em]">
            {m.headline}
          </p>
          <p className="mt-2 font-body text-[14px] leading-[1.55] text-text-secondary">
            {m.body}
          </p>
        </div>
        <div className="px-7 py-5">
          <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary mb-3">
            Based on
          </p>
          <ul className="space-y-2.5">
            {m.cites.map((c, i) => (
              <li key={i} className="grid grid-cols-[auto_1fr_auto] gap-3 items-baseline border-b border-divider-soft pb-2.5 last:border-b-0">
                <span className="font-mono text-[9px] tracking-[1.5px] uppercase text-text-tertiary">
                  Cite · {String(i + 1).padStart(2, "0")}
                </span>
                <span className="font-mono text-[12px] text-text-secondary tabular-nums">
                  {c}
                </span>
                <span className="font-body text-[11px]" style={{ color: accent.hex }}>
                  open →
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>

      {/* annotations */}
      <Annotation
        className="hidden lg:block absolute -left-44 top-12 w-40 text-right"
        label="The headline"
        body="Plain language. Says what to do, not what's possible."
        accent={accent.hex}
        arrowSide="right"
      />
      <Annotation
        className="hidden lg:block absolute -right-44 top-32 w-40"
        label="Confidence chip"
        body="High / medium / low / insufficient. Always visible."
        accent={accent.hex}
        arrowSide="left"
      />
      <Annotation
        className="hidden lg:block absolute -right-44 bottom-6 w-40"
        label="Citations"
        body="Every claim links to the specific run it came from."
        accent={accent.hex}
        arrowSide="left"
      />
    </div>
  );
}

function Annotation({ className, label, body, accent, arrowSide }) {
  return (
    <div className={className}>
      <span
        className="font-mono text-[9px] tracking-[1.5px] uppercase"
        style={{ color: accent }}
      >
        {arrowSide === "right" ? `${label} →` : `← ${label}`}
      </span>
      <p className="mt-1 font-display italic text-[13px] leading-[1.4] text-text-secondary">
        {body}
      </p>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   A WEEK IN THE LIFE — editorial spread of one runner's actual week
   ════════════════════════════════════════════════════════════════════ */
function WeekInTheLife({ persona, accent }) {
  const days = [
    { d: "Mon", label: "Easy", dist: "8.2", pace: "7:58", note: "Recovery", done: true, mood: "#4A9E6B" },
    { d: "Tue", label: "Threshold", dist: "10.1", pace: "6:18", note: "5×1mi · target hit", done: true, mood: "#2D8A4E", quality: true },
    { d: "Wed", label: "Easy", dist: "6.5", pace: "8:05", note: "Tired legs — held back", done: true, mood: "#9B9590" },
    { d: "Thu", label: "Easy + strides", dist: "7.2", pace: "7:48", note: "6×20s strides", done: true, mood: "#4A9E6B" },
    { d: "Fri", label: "Rest", dist: "—", pace: "—", note: "Sleep priority", done: true, mood: null },
    { d: "Sat", label: "Long", dist: "18.4", pace: "7:42", note: "Last 5 mi @ MP", done: true, mood: "#2D8A4E", quality: true },
    { d: "Sun", label: "Easy", dist: "12.0", pace: "8:12", note: "Coffee on the porch first", done: true, mood: "#4A9E6B" },
  ];

  return (
    <section className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-8 py-28">
        <div className="grid md:grid-cols-[1.05fr_0.95fr] gap-12 items-end border-b border-divider pb-10">
          <div>
            <MutedKicker>A week, as the coach sees it</MutedKicker>
            <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
              <em style={{ color: accent.hex, fontStyle: "italic" }}>{persona.weekTotal}</em> miles.
              <br />
              <span className="text-text-primary">{persona.weekRuns} runs.</span>{" "}
              <span className="text-text-tertiary">One real picture.</span>
            </h2>
          </div>
          <p className="font-body text-[16px] leading-[1.6] text-text-secondary">
            This is how the coach reads a week. Not seven boxes on a calendar —
            seven separate decisions, each grounded in the run before it,
            the run after, and what the next week is asking for.
          </p>
        </div>

        {/* WEEK GRID */}
        <div className="mt-10 grid grid-cols-1 md:grid-cols-7 gap-3">
          {days.map((day) => (
            <DayCard key={day.d} day={day} accent={accent} />
          ))}
        </div>

        {/* WEEK NARRATIVE */}
        <div className="mt-10 grid md:grid-cols-[1.4fr_1fr] gap-10 border-t border-divider pt-10">
          <div>
            <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
              Coach&rsquo;s read on the week
            </span>
            <div className="mt-4 flex gap-3">
              <span className="font-display text-[64px] leading-[0.85] text-coral pt-1" style={{ color: accent.hex }}>
                A
              </span>
              <p className="font-body text-[16px] leading-[1.65] text-text-secondary">
                solid quality week — threshold and long run both landed where
                we wanted them. Easy days crept a hair quick (7:58 and 7:48,
                target is 8:05+), which is the third week running we&rsquo;ve
                seen that. Not changing anything yet, but if Tuesday&rsquo;s
                next threshold comes in fast we&rsquo;ll talk about pulling
                easy pace back. Sleep on Friday paid off — Saturday&rsquo;s
                last five at marathon pace were the cleanest in this block.
              </p>
            </div>
            <p className="mt-4 font-mono text-[11px] text-text-tertiary tracking-[1px]">
              <span style={{ color: accent.hex }}>Cites:</span> 7 logs ·
              forecast · pace zone history · ACWR
            </p>
          </div>

          <div className="grid grid-cols-2 gap-x-6 gap-y-5 self-center">
            <Stat k="Week mileage" v={persona.weekTotal} unit="mi" trend="+8% vs last 4 wk avg" />
            <Stat k="Avg run length" v={persona.weekAvg} unit="mi" />
            <Stat k="Avg pace" v={persona.weekPace} unit="/mi" trend="held to easy target" />
            <Stat k="ACWR" v="1.18" unit="" trend="optimal range" accent={accent.hex} />
          </div>
        </div>
      </div>
    </section>
  );
}

function DayCard({ day, accent }) {
  const quality = day.quality;
  return (
    <div
      className={`rounded-xl border bg-bg-card p-4 min-h-[150px] flex flex-col ${
        quality ? "" : "border-divider"
      }`}
      style={
        quality
          ? { borderColor: accent.hex, boxShadow: `0 0 0 3px ${accent.soft}` }
          : {}
      }
    >
      <div className="flex items-baseline justify-between">
        <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
          {day.d}
        </span>
        {day.mood && (
          <span
            className="inline-block h-1.5 w-1.5 rounded-full"
            style={{ backgroundColor: day.mood }}
          />
        )}
      </div>
      <p
        className="mt-2 font-display text-[16px] leading-tight"
        style={{ color: quality ? accent.hex : undefined }}
      >
        {day.label}
      </p>
      <div className="mt-auto pt-3">
        <p className="font-mono text-[18px] tabular-nums text-text-primary">
          {day.dist}
          <span className="text-[11px] text-text-tertiary ml-0.5">{day.dist !== "—" ? "mi" : ""}</span>
        </p>
        <p className="font-mono text-[11px] text-text-tertiary tabular-nums">
          {day.pace !== "—" ? `${day.pace}/mi` : "—"}
        </p>
        <p className="mt-2 font-body text-[11px] leading-tight text-text-secondary">
          {day.note}
        </p>
      </div>
    </div>
  );
}

function Stat({ k, v, unit, trend, accent }) {
  return (
    <div>
      <p className="font-mono text-[9px] tracking-[1.5px] uppercase text-text-tertiary">
        {k}
      </p>
      <p className="mt-0.5 font-display text-[32px] tracking-[-0.01em]" style={{ color: accent || undefined }}>
        {v}
        <span className="font-body text-[12px] text-text-tertiary ml-1">{unit}</span>
      </p>
      {trend && (
        <p className="font-mono text-[10px] text-text-tertiary tracking-[1px]">
          {trend}
        </p>
      )}
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   PROOF — concrete examples
   ════════════════════════════════════════════════════════════════════ */
function ProofSection({ persona, accent }) {
  return (
    <section className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-8 py-24">
        <div className="text-center max-w-[700px] mx-auto">
          <MutedKicker>Three things only this coach does</MutedKicker>
          <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
            Specific, because{" "}
            <em style={{ color: accent.hex, fontStyle: "italic" }}>
              you are.
            </em>
          </h2>
        </div>

        <div className="mt-16 grid md:grid-cols-3 gap-px bg-divider border border-divider rounded-2xl overflow-hidden">
          <ProofCard
            kicker="Weather, adjusted"
            title="Saturday's long run, accounting for the dew point."
            body="Most training plans give you one pace target and ignore the morning. We watch the forecast and shift the call."
            example={
              <>
                <ProofRow label="Plan pace" v="7:30/mi" muted />
                <ProofRow label="Dew point at 6 a.m." v="68°" muted />
                <ProofRow
                  label="Adjusted target"
                  v={persona.weatherPace}
                  accent={accent.hex}
                />
              </>
            }
            footnote={`Why: ${persona.weatherWhy}`}
          />
          <ProofCard
            kicker="Pace zones, alive"
            title="Your threshold zone moves when your threshold moves."
            body="No more entering a 5K time once a year and racing a calculator. The zone shifts as the workouts do."
            example={
              <>
                <ProofRow label="6 weeks ago" v="6:25/mi" muted />
                <ProofRow label="3 weeks ago" v="6:21/mi" muted />
                <ProofRow label="This week" v={persona.threshold + "/mi"} accent={accent.hex} />
              </>
            }
            footnote="Adjusts after 3 quality runs in a zone."
          />
          <ProofCard
            kicker="Plans that move"
            title="Miss a Tuesday and the rest of the week recovers."
            body="When life moves the workout, the plan doesn't pretend it didn't. We rebalance load, not just dates."
            example={
              <>
                <ProofRow label="Planned: Tue threshold" v="missed" muted />
                <ProofRow label="Moved to" v="Wed (truncated)" accent={accent.hex} />
                <ProofRow label="Saturday long" v="−2 mi" />
              </>
            }
            footnote="Cumulative load held within ACWR target."
          />
        </div>
      </div>
    </section>
  );
}

function ProofCard({ kicker, title, body, example, footnote }) {
  return (
    <div className="bg-bg-card p-7 flex flex-col">
      <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
        {kicker}
      </span>
      <h3 className="mt-4 font-display text-[22px] leading-[1.15] tracking-[-0.01em] text-text-primary">
        {title}
      </h3>
      <p className="mt-3 font-body text-[14px] leading-[1.55] text-text-secondary">
        {body}
      </p>
      <div className="mt-6 border-t border-divider pt-4 space-y-1.5">
        {example}
      </div>
      <p className="mt-5 font-mono text-[10px] text-text-tertiary tracking-[1px]">
        {footnote}
      </p>
    </div>
  );
}

function ProofRow({ label, v, muted, accent }) {
  return (
    <div className="flex items-baseline justify-between font-mono text-[12px] tabular-nums">
      <span className="text-text-tertiary tracking-[1px] uppercase text-[10px]">
        {label}
      </span>
      <span
        className={`font-semibold ${muted ? "text-text-secondary" : "text-text-primary"}`}
        style={{ color: accent || undefined }}
      >
        {v}
      </span>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   WHAT THE COACH WON'T DO — skeptic-friendly
   ════════════════════════════════════════════════════════════════════ */
function WhatCoachWontDo() {
  const items = [
    [
      "Won't tell you to push through pain.",
      "Hard-coded safety rule. If you log a sharp pain in the same place twice, the coach pulls back regardless of the plan.",
    ],
    [
      "Won't invent data.",
      "If we don't have the workout, the coach can't reference it. No averaging across users to fill in a gap.",
    ],
    [
      "Won't comment on your diet, weight, or stress.",
      "It's a running coach. Sleep and mood are training signals, not things to fix.",
    ],
    [
      "Won't pretend to be certain.",
      "If your last six weeks are light on quality, the coach says \"I'm guessing on fitness\" — and shows you why.",
    ],
    [
      "Won't streak-shame, badge, or gamify.",
      "Numbers matter. Outcomes matter. Vibes don't.",
    ],
    [
      "Won't say it's powered by AI.",
      "We built the software so the coaching can focus on the decisions. AI is the engine, not the face.",
    ],
  ];
  return (
    <section className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-8 py-24">
        <div className="grid md:grid-cols-[0.9fr_2fr] gap-12 border-b border-divider pb-10">
          <div>
            <MutedKicker>The honest list</MutedKicker>
            <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
              What the coach
              <br />
              <em className="italic font-display text-text-tertiary">
                won't do.
              </em>
            </h2>
          </div>
          <p className="font-body text-[17px] leading-[1.6] text-text-secondary self-end">
            Saying what we don't do is the fastest way to show what we do.
            None of this is a roadmap item. It's by design.
          </p>
        </div>

        <ul className="mt-2 divide-y divide-divider">
          {items.map(([title, body], i) => (
            <li key={i} className="grid md:grid-cols-[auto_1.2fr_2fr] gap-6 py-7">
              <span className="font-mono text-[11px] tracking-[1.5px] text-text-tertiary mt-2">
                NO. {String(i + 1).padStart(2, "0")}
              </span>
              <h3 className="font-display text-[24px] leading-[1.15] tracking-[-0.01em] text-text-primary">
                {title}
              </h3>
              <p className="font-body text-[15px] leading-[1.6] text-text-secondary">
                {body}
              </p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   NOT FOR EVERYONE
   ════════════════════════════════════════════════════════════════════ */
function NotForEveryone() {
  return (
    <section className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[860px] px-8 py-24 text-center">
        <MutedKicker>Honest signposting</MutedKicker>
        <p className="mt-6 font-display text-[32px] leading-[1.25] tracking-[-0.01em] text-text-primary">
          If you're brand new to running, this probably isn't the right app
          for you{" "}
          <span className="text-text-tertiary">yet.</span>
        </p>
        <p className="mt-6 font-body text-[16px] leading-[1.65] text-text-secondary mx-auto max-w-[580px]">
          Post Run Drip is built for runners with a goal race, a base of
          consistent miles, and an interest in their own splits. If you're
          chasing a marathon time, training for your second or third half,
          or you're a coach managing a roster — yes. If you're starting from
          zero — we'd rather you build a base first and come back. There are
          better apps for that, and we'll happily name them.
        </p>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FINAL CTA
   ════════════════════════════════════════════════════════════════════ */
function FinalCTA({ accent }) {
  return (
    <section id="start" className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[860px] px-8 py-28 text-center">
        <MutedKicker>Open invite</MutedKicker>
        <h2 className="mt-6 font-display text-[72px] leading-[0.98] tracking-[-0.015em] text-text-primary">
          Run with us.
          <br />
          <em style={{ color: accent.hex, fontStyle: "italic" }}>
            We'll catch up.
          </em>
        </h2>
        <p className="mt-8 font-body text-[17px] leading-[1.6] text-text-secondary max-w-[520px] mx-auto">
          First week is on us — we use it to read your training and tune the
          coach to your paces. No credit card. iOS only for now.
        </p>
        <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
          <a
            href="#"
            className="rounded-md px-7 py-4 font-body text-[15px] font-semibold text-white"
            style={{
              backgroundColor: accent.hex,
              boxShadow: `0 1px 0 ${accent.deep}, 0 12px 32px -12px ${accent.soft}`,
            }}
          >
            Request a TestFlight invite
          </a>
          <a
            href="#"
            className="rounded-md border border-divider px-7 py-4 font-body text-[15px] font-medium text-text-secondary hover:border-text-tertiary"
          >
            Read the field notes
          </a>
        </div>
        <p className="mt-10 font-mono text-[11px] text-text-tertiary tracking-[1.5px] uppercase">
          Available on iOS · TestFlight · v.142
          <RuleDot />
          Built in Austin
          <RuleDot />
          Made by runners
        </p>
      </div>
    </section>
  );
}

/* ════════════════════════════════════════════════════════════════════
   FOOTER
   ════════════════════════════════════════════════════════════════════ */
function Footer() {
  return (
    <footer className="bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-8 py-16 grid md:grid-cols-[2fr_1fr_1fr_1fr] gap-12">
        <div>
          <div className="font-display text-[22px] tracking-[-0.01em]">
            Post Run Drip
          </div>
          <p className="mt-3 font-body text-[13px] leading-[1.6] text-text-secondary max-w-[300px]">
            A coach that actually knows you. Reads your training. Cites every
            recommendation. Says when it's guessing.
          </p>
        </div>
        <FooterCol
          title="Product"
          links={["How it works", "Evidence", "What it won't do", "Field notes"]}
        />
        <FooterCol
          title="Company"
          links={["About", "Why we built this", "Working with coaches", "Press"]}
        />
        <FooterCol
          title="Reach us"
          links={["hi@postrundrip.com", "Strava club", "Instagram", "r/AdvancedRunning"]}
        />
      </div>
      <div className="border-t border-divider">
        <div className="mx-auto max-w-[1180px] flex flex-wrap items-center justify-between px-8 py-6 gap-4">
          <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
            © {new Date().getFullYear()} Post Run Drip
            <RuleDot />
            Built in Austin, TX
          </p>
          <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
            Privacy
            <RuleDot />
            Terms
            <RuleDot />
            Coach charter
          </p>
        </div>
      </div>
    </footer>
  );
}

function FooterCol({ title, links }) {
  return (
    <div>
      <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-secondary">
        {title}
      </p>
      <ul className="mt-3 space-y-2">
        {links.map((l) => (
          <li key={l}>
            <a href="#" className="font-body text-[13px] text-text-tertiary hover:text-text-primary">
              {l}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}

/* ── mount ─────────────────────────────────────────────────────────── */
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);

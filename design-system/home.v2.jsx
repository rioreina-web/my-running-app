/* global React */
const { useState, useEffect, useRef } = React;

/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP — HOME PAGE  (v2: honest)
   Rewrites the page around what the software actually is:
   - a training log (voice or synced)
   - AI feedback after each run
   - an adaptive training plan
   No fabricated stats. No features-as-fact that aren't shipped.
   ════════════════════════════════════════════════════════════════════ */

const HOMEPAGE_TWEAKS = /*EDITMODE-BEGIN*/{
  "headline": "reads-back",
  "heroLayout": "split",
  "accent": "#D4592A",
  "persona": "marathoner"
}/*EDITMODE-END*/;

const HEADLINES = {
  "reads-back": {
    kicker: "For runners with a goal time",
    main: "A running log",
    italic: "that reads back.",
  },
  "log-listen-train": {
    kicker: "A simpler stack for serious running",
    main: "Log. Listen. Train.",
    italic: "Repeat.",
  },
  "talk-back": {
    kicker: "Built for serious runners",
    main: "Your training log,",
    italic: "with a coach reading along.",
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
    label: "Sample athlete · marathon block",
    transcript:
      "Did ten on the river trail. Held 7:42 pace mostly, picked it up the last two miles to 7:15. Legs felt good — better than Tuesday.",
    parsed: ["10.0 mi", "7:42 avg", "last 2 @ 7:15", "mood: positive"],
    feedback:
      "Solid progression run — finishing 27 seconds faster than your average is right in the marathon-pace window we're building toward. Tuesday's threshold and today's long run are the two quality sessions; everything else this week should sit at 8:00+. Sleep was light on Wednesday — if it's light again tonight, take Saturday easier than planned.",
    weekTotal: "48.2",
    weekRuns: "5",
  },
  fiveK: {
    label: "Sample athlete · 5K block",
    transcript:
      "Six by 800 on the track. Hit 2:42, 2:41, 2:43, 2:42, 2:40, 2:41. Felt controlled — could've done one more.",
    parsed: ["6×800m", "2:41 avg", "rec 90s", "track session"],
    feedback:
      "Right on target — that's the second week running you've held 2:41 average for the 800s. You said you could've done one more, but the controlled feeling is what we're after at this stage. Next week we'll keep the volume the same and add one mile of warm-up so total time on feet creeps up without changing the workout itself.",
    weekTotal: "32.6",
    weekRuns: "5",
  },
  comeback: {
    label: "Sample athlete · returning from injury",
    transcript:
      "Three miles easy. Right calf felt okay at first but tightened up around mile two. Walked the last half mile.",
    parsed: ["3.0 mi", "9:48 avg", "calf flag", "walk break"],
    feedback:
      "Calf tightening for the second run in a row is the signal — we're going to pull Saturday's planned 5-miler and replace it with a 30-minute walk/jog. The pattern matters more than today's distance. If it tightens again on Thursday's easy run, we stop running entirely until you've had three pain-free days.",
    weekTotal: "9.2",
    weekRuns: "3",
  },
};

/* ── shared ────────────────────────────────────────────────────────── */
const Kicker = ({ children, color }) => (
  <span
    className="font-mono text-[11px] font-medium tracking-[2px] uppercase"
    style={{ color }}
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

/* ════════════════════════════════════════════════════════════════════
   APP
   ════════════════════════════════════════════════════════════════════ */
function App() {
  const [t, setTweak] = useTweaks(HOMEPAGE_TWEAKS);
  const accent = ACCENTS[t.accent] || ACCENTS["#D4592A"];
  const headline = HEADLINES[t.headline] || HEADLINES["reads-back"];
  const persona = PERSONAS[t.persona] || PERSONAS.marathoner;

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
        <ThreeThings persona={persona} accent={accent} />
        <CloserLook persona={persona} accent={accent} />
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
              { value: "reads-back", label: "A running log that reads back." },
              { value: "log-listen-train", label: "Log. Listen. Train. Repeat." },
              { value: "talk-back", label: "Your training log, with a coach reading along." },
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

        <TweakSection label="Sample athlete in examples">
          <TweakSelect
            label="Persona"
            value={t.persona}
            onChange={(v) => setTweak("persona", v)}
            options={[
              { value: "marathoner", label: "Marathon block" },
              { value: "fiveK", label: "5K block" },
              { value: "comeback", label: "Returning from injury" },
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
  if (layout === "typographic")
    return <HeroTypographic headline={headline} accent={accent} />;
  return <HeroSplit headline={headline} persona={persona} accent={accent} />;
}

function HeroSplit({ headline, persona, accent }) {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto max-w-[1180px] grid lg:grid-cols-[1.05fr_0.95fr] gap-16 px-8 pt-20 pb-24">
        {/* LEFT — type */}
        <div className="flex flex-col">
          <Kicker color={accent.hex}>{headline.kicker}</Kicker>
          <h1 className="mt-7 font-display text-[68px] leading-[0.98] tracking-[-0.015em] text-text-primary">
            {headline.main}
            <br />
            <em
              className="font-display italic"
              style={{ color: accent.hex }}
            >
              {headline.italic}
            </em>
          </h1>
          <p className="mt-8 max-w-[480px] font-body text-[18px] leading-[1.55] text-text-secondary">
            A training log built for people chasing a time. Log a run by
            voice or sync from your watch. After every run, an AI coach
            takes a look and writes back. Your training plan moves as your
            week does.
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
              Try the beta
            </a>
            <a
              href="#what"
              className="rounded-md border border-divider px-6 py-3.5 font-body text-[14px] font-medium text-text-secondary hover:border-text-tertiary"
            >
              What it does
            </a>
          </div>

          <p className="mt-6 font-mono text-[11px] text-text-tertiary tracking-[1px]">
            iOS, in beta · TestFlight invite required
          </p>
        </div>

        {/* RIGHT — single grounded sample */}
        <div className="relative">
          <div className="lg:sticky lg:top-28">
            <SampleFeedbackCard persona={persona} accent={accent} />
            <p className="mt-3 font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary text-right">
              Sample feedback · illustrative
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
        <Kicker color={accent.hex}>{headline.kicker}</Kicker>
        <h1 className="mt-8 font-display text-[112px] leading-[0.95] tracking-[-0.02em]">
          {headline.main}
          <br />
          <em className="font-display italic" style={{ color: accent.hex }}>
            {headline.italic}
          </em>
        </h1>
        <p className="mx-auto mt-10 max-w-[600px] font-body text-[19px] leading-[1.6] text-text-secondary">
          A training log built for people chasing a time. Voice-log or sync
          your runs. Get AI feedback after each one. Run a training plan that
          moves with your week.
        </p>
        <div className="mt-10 flex justify-center gap-3">
          <a
            href="#start"
            className="rounded-md px-6 py-3.5 font-body text-[14px] font-semibold text-white"
            style={{ backgroundColor: accent.hex }}
          >
            Try the beta
          </a>
          <a
            href="#what"
            className="rounded-md border border-divider px-6 py-3.5 font-body text-[14px] font-medium text-text-secondary"
          >
            What it does
          </a>
        </div>
      </div>
    </section>
  );
}

/* ── the sample feedback card (hero's "screenshot") ──────────────── */
function SampleFeedbackCard({ persona, accent }) {
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
            After your run · Tuesday
          </span>
        </div>
        <span className="font-mono text-[10px] text-text-tertiary">10:14 a.m.</span>
      </div>

      {/* what you said */}
      <div className="px-7 pt-6 pb-5 border-b border-divider-soft">
        <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary mb-3">
          You logged
        </p>
        <p className="font-display italic text-[17px] leading-[1.5] text-text-secondary">
          “{persona.transcript}”
        </p>
        <div className="mt-4 flex flex-wrap gap-1.5">
          {persona.parsed.map((p, i) => (
            <span
              key={i}
              className="rounded-full px-2.5 py-1 font-mono text-[11px] tabular-nums"
              style={{
                backgroundColor: accent.soft,
                color: accent.deep,
              }}
            >
              {p}
            </span>
          ))}
        </div>
      </div>

      {/* coach */}
      <div className="px-7 py-6">
        <div className="flex items-center justify-between mb-3">
          <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
            Coach said
          </p>
          <span
            className="font-body text-[11px]"
            style={{ color: accent.hex }}
          >
            Ask a follow-up →
          </span>
        </div>
        <p className="font-body text-[15px] leading-[1.6] text-text-primary">
          {persona.feedback}
        </p>
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   THREE THINGS — what the software actually does
   ════════════════════════════════════════════════════════════════════ */
function ThreeThings({ persona, accent }) {
  return (
    <section id="what" className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-8 py-24">
        <div className="grid md:grid-cols-[0.9fr_2fr] gap-12 border-b border-divider pb-10">
          <div>
            <MutedKicker>What it does</MutedKicker>
            <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
              Three things,
              <br />
              done <em className="font-display italic" style={{ color: accent.hex }}>well</em>.
            </h2>
          </div>
          <p className="font-body text-[17px] leading-[1.6] text-text-secondary self-end">
            Not a feed. Not a wellness product. Not a marketplace for coaches.
            A training log, a coach that reads it, and a plan that adapts.
            That's the whole thing.
          </p>
        </div>

        <div className="mt-12 grid md:grid-cols-3 gap-px bg-divider border border-divider rounded-2xl overflow-hidden">
          <ThingCard
            n="01"
            verb="Log"
            title="every run, by voice or from your watch"
            body="Talk after a run and we extract distance, pace, splits, intervals, mood. Or sync runs from your watch and add a note. No forms."
            example={
              <div>
                <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary mb-2">
                  You said
                </p>
                <p className="font-display italic text-[13px] leading-[1.5] text-text-secondary">
                  “Did five on the river trail. Pickups in the middle, felt strong.”
                </p>
                <p className="mt-3 font-mono text-[11px] tabular-nums text-text-primary leading-relaxed">
                  → 5.0 mi · 8:15/mi · 4×30s pickups · mood ↑
                </p>
              </div>
            }
            accent={accent}
          />
          <ThingCard
            n="02"
            verb="Listen"
            title="to what your last run actually says"
            body="After every run, an AI coach reads what you logged, looks at the recent context, and writes back. Ask a follow-up in plain language."
            example={
              <div>
                <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary mb-2">
                  Coach said
                </p>
                <p className="font-body text-[12.5px] leading-[1.55] text-text-secondary">
                  “Right on target — second week running at 2:41 average for
                  the 800s. Same volume next week, with a longer warm-up.”
                </p>
              </div>
            }
            accent={accent}
          />
          <ThingCard
            n="03"
            verb="Train"
            title="on a plan that moves with your week"
            body="Pick a goal race. Get a plan. It updates as your weeks land — adjusting load when you miss a day, scaling back when something hurts, keying off your actual paces, not a one-time test."
            example={
              <div>
                <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary mb-2">
                  This week
                </p>
                <div className="space-y-1.5 font-mono text-[11px] tabular-nums text-text-secondary">
                  <Row v="Tue · Threshold" right="5×1mi" />
                  <Row v="Thu · Easy" right="6 mi" />
                  <Row v="Sat · Long" right="14 mi" highlight={accent.hex} />
                  <Row v="Sun · Recovery" right="4 mi" />
                </div>
              </div>
            }
            accent={accent}
          />
        </div>

        <p className="mt-10 font-mono text-[11px] text-text-tertiary tracking-[1px] text-center">
          That's it. We're not building a feed. We're not adding badges.
        </p>
      </div>
    </section>
  );
}

function ThingCard({ n, verb, title, body, example, accent }) {
  return (
    <div className="bg-bg-card p-7 flex flex-col">
      <div className="flex items-baseline justify-between mb-4">
        <span className="font-mono text-[10px] tracking-[1.5px] text-text-tertiary">
          {n}
        </span>
        <Kicker color={accent.hex}>·</Kicker>
      </div>
      <h3 className="font-display text-[30px] leading-[1.1] tracking-[-0.01em]">
        <span style={{ color: accent.hex }}>{verb}</span>{" "}
        <span className="text-text-primary">{title}.</span>
      </h3>
      <p className="mt-3 font-body text-[15px] leading-[1.55] text-text-secondary">
        {body}
      </p>
      <div className="mt-6 border-t border-divider pt-5">{example}</div>
    </div>
  );
}

function Row({ v, right, highlight }) {
  return (
    <div className="flex items-baseline justify-between">
      <span style={{ color: highlight || undefined }}>{v}</span>
      <span className="text-text-tertiary">{right}</span>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   A CLOSER LOOK — sample of the coach in context
   ════════════════════════════════════════════════════════════════════ */
function CloserLook({ persona, accent }) {
  return (
    <section className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[1180px] px-8 py-28">
        <div className="grid md:grid-cols-[1fr_1fr] gap-16 items-center">
          <div>
            <MutedKicker>A closer look</MutedKicker>
            <h2 className="mt-5 font-display text-[44px] leading-[1.05] tracking-[-0.015em]">
              The coach isn't a chatbot.
              <br />
              <em className="font-display italic" style={{ color: accent.hex }}>
                It's a reader.
              </em>
            </h2>
            <p className="mt-6 font-body text-[17px] leading-[1.6] text-text-secondary">
              When you log a run, we don't just store it — we hand it to a
              model that's been given your last six weeks of training as
              context. The reply you get back is grounded in what you've
              actually been doing, not in a generic notion of how runners
              train.
            </p>
            <p className="mt-4 font-body text-[17px] leading-[1.6] text-text-secondary">
              You can keep talking. Ask why it said something. Push back on a
              plan change. Ask about Saturday's long run. It will tell you
              when it doesn't have enough data to answer — and what it
              would need to give a better one.
            </p>

            <ul className="mt-8 space-y-3 font-body text-[15px] text-text-secondary">
              <Bullet accent={accent.hex}>
                Grounded in <em className="not-italic" style={{ color: accent.hex }}>your</em> last six weeks of training.
              </Bullet>
              <Bullet accent={accent.hex}>
                Says when it&rsquo;s guessing, instead of bluffing.
              </Bullet>
              <Bullet accent={accent.hex}>
                Conversational — push back, ask follow-ups.
              </Bullet>
            </ul>
          </div>

          <div className="relative">
            <ConversationMock persona={persona} accent={accent} />
            <p className="mt-3 font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary text-right">
              Sample conversation · illustrative
            </p>
          </div>
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

function ConversationMock({ persona, accent }) {
  return (
    <div className="rounded-2xl bg-bg-card border border-divider shadow-[0_30px_60px_-40px_rgba(26,24,21,0.2)] overflow-hidden">
      <div className="px-6 py-4 border-b border-divider-soft bg-bg-elevated flex items-center justify-between">
        <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-secondary">
          Conversation · {persona.label}
        </span>
        <span
          className="inline-block h-2 w-2 rounded-full"
          style={{ backgroundColor: accent.hex }}
        />
      </div>
      <div className="p-6 space-y-4">
        {/* Coach msg */}
        <ChatBubble side="left" accent={accent}>
          {persona.feedback}
        </ChatBubble>

        {/* User reply */}
        <ChatBubble side="right" accent={accent}>
          Should I still do Saturday's long run as planned?
        </ChatBubble>

        {/* Coach answer */}
        <ChatBubble side="left" accent={accent}>
          Yes — keep it on the calendar, but back the pace off ten seconds
          per mile from what we discussed last week. The faster finish
          today already gave you the stimulus we were looking for. If
          Friday's easy run feels heavy, drop the long run to 12 instead
          of 14.
        </ChatBubble>
      </div>
    </div>
  );
}

function ChatBubble({ side, accent, children }) {
  const right = side === "right";
  return (
    <div className={`flex ${right ? "justify-end" : ""}`}>
      <div
        className={`max-w-[85%] rounded-2xl px-4 py-3 font-body text-[14px] leading-[1.55] ${
          right
            ? "text-white"
            : "bg-bg-elevated border border-divider-soft text-text-primary"
        }`}
        style={right ? { backgroundColor: accent.hex } : {}}
      >
        {children}
      </div>
    </div>
  );
}

/* ════════════════════════════════════════════════════════════════════
   NOT FOR EVERYONE
   ════════════════════════════════════════════════════════════════════ */
function NotForEveryone() {
  return (
    <section className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[920px] px-8 py-24 text-center">
        <MutedKicker>Honest signposting</MutedKicker>
        <p className="mt-6 font-display text-[34px] leading-[1.2] tracking-[-0.01em] text-text-primary">
          If you&rsquo;re brand new to running, this probably isn&rsquo;t
          the right app for you{" "}
          <span className="text-text-tertiary">yet.</span>
        </p>
        <p className="mt-6 font-body text-[17px] leading-[1.6] text-text-secondary mx-auto max-w-[620px]">
          Post Run Drip is built for runners with a goal race, a base of
          consistent miles, and an interest in their own splits. If
          you&rsquo;re chasing a marathon time, training for your second or
          third half, or coming back from a layoff carefully — yes. If
          you&rsquo;re starting from zero, there are better apps for that
          and we&rsquo;ll happily name a few.
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
    <section id="start" className="border-b border-divider bg-bg-base">
      <div className="mx-auto max-w-[920px] px-8 py-28 text-center">
        <MutedKicker>The beta</MutedKicker>
        <h2 className="mt-6 font-display text-[64px] leading-[1] tracking-[-0.015em] text-text-primary">
          Try it for a week.
          <br />
          <em className="font-display italic" style={{ color: accent.hex }}>
            Tell us what doesn&rsquo;t work.
          </em>
        </h2>
        <p className="mt-8 font-body text-[17px] leading-[1.6] text-text-secondary max-w-[560px] mx-auto">
          We&rsquo;re sending out TestFlight invites in small batches. Drop
          your email, mention what you&rsquo;re training for, and we&rsquo;ll
          send you a link.
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
            Read the changelog
          </a>
        </div>
        <p className="mt-10 font-mono text-[11px] text-text-tertiary tracking-[1.5px] uppercase">
          iOS only for now
          <RuleDot />
          Built in Austin
          <RuleDot />
          By runners
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
      <div className="mx-auto max-w-[1180px] px-8 py-14 grid md:grid-cols-[2fr_1fr_1fr] gap-12">
        <div>
          <div className="font-display text-[22px] tracking-[-0.01em]">
            Post Run Drip
          </div>
          <p className="mt-3 font-body text-[14px] leading-[1.6] text-text-secondary max-w-[320px]">
            A training log for runners chasing a time. Voice-log a run,
            sync your watch, get AI feedback, follow an adaptive plan.
          </p>
        </div>
        <FooterCol title="Product" links={["What it does", "Changelog", "Sign in"]} />
        <FooterCol title="Reach us" links={["hi@postrundrip.com", "Strava club", "Instagram"]} />
      </div>
      <div className="border-t border-divider">
        <div className="mx-auto max-w-[1180px] flex flex-wrap items-center justify-between px-8 py-6 gap-4">
          <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
            © {new Date().getFullYear()} Post Run Drip
            <RuleDot />
            Austin, TX
          </p>
          <p className="font-mono text-[10px] tracking-[1.5px] uppercase text-text-tertiary">
            Privacy
            <RuleDot />
            Terms
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
            <a href="#" className="font-body text-[14px] text-text-tertiary hover:text-text-primary">
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

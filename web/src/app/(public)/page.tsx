import Link from "next/link";

/* ── tiny helpers ── */
const Dot = ({ color = "bg-coral" }: { color?: string }) => (
  <span className={`inline-block h-1.5 w-1.5 rounded-full ${color}`} />
);

const MiniBar = ({ h, color = "bg-coral" }: { h: string; color?: string }) => (
  <div className={`w-full rounded-sm ${color}`} style={{ height: h }} />
);

/* ══════════════════════════════════════════════════════════════════════ */

export default function LandingPage() {
  return (
    <div className="overflow-hidden">
      {/* ─── HERO ─── */}
      <section className="relative bg-bg-base px-6 pb-8 pt-16 md:pb-16 md:pt-28">
        <div className="mx-auto grid max-w-6xl items-center gap-12 md:grid-cols-2">
          {/* Copy */}
          <div className="max-w-lg">
            <p className="font-body text-[11px] font-medium tracking-[2px] uppercase text-coral">
              Post Run Drip
            </p>
            <h1 className="mt-4 font-display text-5xl leading-[1.1] text-text-primary md:text-6xl">
              The AI-powered
              <br />
              <span className="italic text-coral">training log.</span>
            </h1>
            <p className="mt-6 max-w-md font-body text-base leading-relaxed text-text-secondary">
              Voice-log your runs. Get instant AI coaching. Track mileage, pace,
              injuries, and training load — everything in one place.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-4">
              <Link
                href="/login"
                className="rounded-xl bg-coral px-7 py-3.5 font-body text-sm font-semibold text-white shadow-[0_4px_14px_rgba(212,89,42,0.35)] transition-all hover:shadow-[0_6px_20px_rgba(212,89,42,0.45)] hover:brightness-110"
              >
                Get Started Free
              </Link>
              <Link
                href="#features"
                className="rounded-xl border border-divider px-7 py-3.5 font-body text-sm font-medium text-text-secondary transition-colors hover:border-coral hover:text-coral"
              >
                See how it works
              </Link>
            </div>
          </div>

          {/* Phone mockup ─ dashboard */}
          <div className="flex justify-center md:justify-end">
            <PhoneMockup>
              <DashboardScreen />
            </PhoneMockup>
          </div>
        </div>
      </section>

      {/* ─── SOCIAL PROOF STRIP ─── */}
      <section className="border-y border-divider bg-bg-card">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-center gap-x-12 gap-y-4 px-6 py-6 text-center">
          {[
            ["4.9", "App Store Rating"],
            ["25K+", "Runs Logged"],
            ["1M+", "Miles Tracked"],
          ].map(([stat, label]) => (
            <div key={label} className="flex items-baseline gap-2">
              <span className="font-mono text-xl font-semibold text-text-primary">
                {stat}
              </span>
              <span className="font-body text-xs text-text-tertiary">
                {label}
              </span>
            </div>
          ))}
        </div>
      </section>

      {/* ─── FEATURES ─── */}
      <section id="features" className="bg-bg-base px-6 py-20 md:py-28">
        <div className="mx-auto max-w-6xl">
          <p className="text-center font-body text-[11px] font-medium tracking-[2px] uppercase text-text-tertiary">
            Everything you need
          </p>
          <h2 className="mt-3 text-center font-display text-3xl text-text-primary md:text-4xl">
            Built for runners who care about the details
          </h2>

          {/* Feature grid */}
          <div className="mt-16 space-y-28">
            {/* 1 ─ Voice Logging */}
            <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
              <div>
                <FeatureBadge>Voice First</FeatureBadge>
                <h3 className="mt-4 font-display text-3xl text-text-primary">
                  Talk about your run.
                  <br />
                  <span className="text-coral">We&apos;ll handle the rest.</span>
                </h3>
                <p className="mt-4 max-w-md font-body text-base leading-relaxed text-text-secondary">
                  Just talk naturally after your run. Our AI extracts distance,
                  pace, splits, intervals, mood, and injury notes — no forms, no
                  typing.
                </p>
                <FeatureList
                  items={[
                    "Natural language processing",
                    "Automatic split & interval detection",
                    "Mood & energy tracking",
                  ]}
                />
              </div>
              <div className="flex justify-center">
                <PhoneMockup>
                  <VoiceLoggingScreen />
                </PhoneMockup>
              </div>
            </div>

            {/* 2 ─ AI Coaching */}
            <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
              <div className="order-2 flex justify-center md:order-1">
                <PhoneMockup>
                  <CoachScreen />
                </PhoneMockup>
              </div>
              <div className="order-1 md:order-2">
                <FeatureBadge>AI Coach</FeatureBadge>
                <h3 className="mt-4 font-display text-3xl text-text-primary">
                  A coach that
                  <br />
                  <span className="text-coral">knows your data.</span>
                </h3>
                <p className="mt-4 max-w-md font-body text-base leading-relaxed text-text-secondary">
                  Every log gets a personalized coaching insight. Ask follow-up
                  questions, get race strategy advice, or discuss your training
                  plan.
                </p>
                <FeatureList
                  items={[
                    "Personalized post-run insights",
                    "Conversational follow-ups",
                    "Race strategy & pacing advice",
                  ]}
                />
              </div>
            </div>

            {/* 3 ─ Analysis */}
            <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
              <div>
                <FeatureBadge>Deep Analytics</FeatureBadge>
                <h3 className="mt-4 font-display text-3xl text-text-primary">
                  See the full picture
                  <br />
                  <span className="text-coral">of your fitness.</span>
                </h3>
                <p className="mt-4 max-w-md font-body text-base leading-relaxed text-text-secondary">
                  Mileage trends, pace progression, workout distribution, mood
                  tracking, training load gauge, and race predictions — all in
                  one editorial-style view.
                </p>
                <FeatureList
                  items={[
                    "12-week mileage & pace charts",
                    "ACWR training load gauge",
                    "Mood heatmaps & distributions",
                  ]}
                />
              </div>
              <div className="flex justify-center">
                <PhoneMockup>
                  <AnalysisScreen />
                </PhoneMockup>
              </div>
            </div>

            {/* 4 ─ Training Plans */}
            <div className="grid items-center gap-10 md:grid-cols-2 md:gap-16">
              <div className="order-2 flex justify-center md:order-1">
                <PhoneMockup>
                  <PlanScreen />
                </PhoneMockup>
              </div>
              <div className="order-1 md:order-2">
                <FeatureBadge>Smart Plans</FeatureBadge>
                <h3 className="mt-4 font-display text-3xl text-text-primary">
                  Plans that adapt
                  <br />
                  <span className="text-coral">to your life.</span>
                </h3>
                <p className="mt-4 max-w-md font-body text-base leading-relaxed text-text-secondary">
                  AI-generated training plans that match your fitness level,
                  goals, and schedule. Track compliance and adjust as you go.
                </p>
                <FeatureList
                  items={[
                    "AI-generated periodization",
                    "Compliance tracking",
                    "Auto-adjust for missed days",
                  ]}
                />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ─── CTA ─── */}
      <section className="border-t border-divider bg-bg-card px-6 py-20 md:py-28">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="font-display text-4xl text-text-primary md:text-5xl">
            Ready to run
            <br />
            <span className="italic text-coral">smarter?</span>
          </h2>
          <p className="mt-4 font-body text-lg text-text-secondary">
            Join thousands of runners who train with AI-powered insights.
          </p>
          <div className="mt-8">
            <Link
              href="/login"
              className="inline-block rounded-xl bg-coral px-10 py-4 font-body text-base font-semibold text-white shadow-[0_4px_14px_rgba(212,89,42,0.35)] transition-all hover:shadow-[0_6px_20px_rgba(212,89,42,0.45)] hover:brightness-110"
            >
              Get Started Free
            </Link>
          </div>
          <p className="mt-4 font-body text-xs text-text-tertiary">
            No credit card required. Available on iOS.
          </p>
        </div>
      </section>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════
   COMPONENTS
   ══════════════════════════════════════════════════════════════════════ */

function FeatureBadge({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-block rounded-full bg-coral/10 px-3 py-1 font-mono text-[10px] font-medium tracking-wider uppercase text-coral">
      {children}
    </span>
  );
}

function FeatureList({ items }: { items: string[] }) {
  return (
    <ul className="mt-6 space-y-2">
      {items.map((item) => (
        <li key={item} className="flex items-center gap-2.5 text-sm text-text-secondary">
          <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-coral/10">
            <span className="text-[8px] text-coral">&#10003;</span>
          </span>
          {item}
        </li>
      ))}
    </ul>
  );
}

/* ─── Phone Mockup Shell ─── */
function PhoneMockup({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative mx-auto w-[280px] shrink-0">
      {/* Outer bezel */}
      <div className="rounded-[40px] bg-[#1A1815] p-[10px] shadow-[0_25px_60px_-12px_rgba(0,0,0,0.35)]">
        {/* Dynamic Island */}
        <div className="absolute left-1/2 top-[14px] z-10 h-[28px] w-[100px] -translate-x-1/2 rounded-full bg-[#1A1815]" />
        {/* Screen */}
        <div className="overflow-hidden rounded-[30px] bg-[#F5F3F0]">
          <div className="h-[560px] overflow-hidden">{children}</div>
        </div>
      </div>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════════════════
   APP SCREEN MOCKUPS
   ══════════════════════════════════════════════════════════════════════ */

/* ─── Dashboard ─── */
function DashboardScreen() {
  return (
    <div className="px-5 pt-14 pb-6">
      {/* Status bar spacer */}
      <p className="font-body text-[9px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
        This Week
      </p>
      <p className="mt-0.5 font-display text-[22px] leading-tight text-text-primary">
        Feb 28 &ndash; Mar 7
      </p>

      {/* Narrative stat */}
      <div className="mt-4 border-t border-divider pt-4">
        <p className="font-body text-[11px] leading-relaxed text-text-secondary">
          <span className="font-display text-[28px] font-bold text-text-primary">
            25.8
          </span>{" "}
          miles across{" "}
          <span className="font-mono text-sm font-semibold text-coral">4</span>{" "}
          runs — avg{" "}
          <span className="font-mono text-sm font-semibold text-coral">
            6.4
          </span>{" "}
          mi at{" "}
          <span className="font-mono text-sm font-semibold text-coral">
            9:44
          </span>
          /mi.
        </p>
      </div>

      {/* Stat cards */}
      <div className="mt-4 grid grid-cols-2 gap-2">
        {[
          { value: "25.8", label: "MILES", trend: "up" },
          { value: "4", label: "RUNS", trend: null },
          { value: "9:44", label: "PER MILE", trend: "down" },
          { value: "\u{1F60A}", label: "POSITIVE", trend: null },
        ].map((s) => (
          <div
            key={s.label}
            className="rounded-xl bg-white p-3 shadow-[0_1px_4px_rgba(0,0,0,0.06)]"
          >
            <div className="flex items-start justify-between">
              <span className="font-mono text-lg font-semibold text-text-primary">
                {s.value}
              </span>
              {s.trend && (
                <span
                  className={`text-[9px] ${s.trend === "up" ? "text-[#2D8A4E]" : "text-coral"}`}
                >
                  {s.trend === "up" ? "↑" : "↓"}
                </span>
              )}
            </div>
            <span className="font-mono text-[8px] tracking-wider text-text-tertiary">
              {s.label}
            </span>
            {s.label === "MILES" && (
              <svg
                viewBox="0 0 80 20"
                className="mt-1 h-4 w-full text-coral"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              >
                <polyline points="0,18 12,16 24,14 36,12 48,8 60,10 72,4 80,2" />
              </svg>
            )}
          </div>
        ))}
      </div>

      {/* Mini chart */}
      <div className="mt-4">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          Weekly Mileage
        </p>
        <div className="mt-2 flex items-end gap-1.5">
          {[35, 55, 42, 70, 60, 80, 65, 90].map((h, i) => (
            <div
              key={i}
              className="flex-1 rounded-sm bg-coral/30"
              style={{ height: `${h * 0.4}px` }}
            />
          ))}
        </div>
      </div>

      {/* Mood heatmap */}
      <div className="mt-4">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          Mood
        </p>
        <div className="mt-1.5 grid grid-cols-7 gap-[3px]">
          {[
            "#2D8A4E","#4A9E6B","#9B9590","#2D8A4E","#C4873A","#4A9E6B","#2D8A4E",
            "#4A9E6B","#C4873A","#2D8A4E","#9B9590","#2D8A4E","#C45A3A","#4A9E6B",
            "#9B9590","#2D8A4E","#4A9E6B","#C4873A","#2D8A4E","#4A9E6B","#2D8A4E",
          ].map((c, i) => (
            <div
              key={i}
              className="aspect-square rounded-[3px]"
              style={{ backgroundColor: c, opacity: 0.7 }}
            />
          ))}
        </div>
      </div>

      {/* Recent */}
      <div className="mt-4">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          Recent Runs
        </p>
        {[
          { date: "Mar 6", dist: "7.2 mi", pace: "9:22", type: "Long", mood: "#2D8A4E" },
          { date: "Mar 4", dist: "5.1 mi", pace: "9:48", type: "Easy", mood: "#4A9E6B" },
          { date: "Mar 2", dist: "6.3 mi", pace: "9:15", type: "Tempo", mood: "#C4873A" },
        ].map((r) => (
          <div
            key={r.date}
            className="mt-1.5 flex items-center gap-2 rounded-lg bg-white px-2.5 py-1.5 shadow-[0_1px_3px_rgba(0,0,0,0.04)]"
          >
            <span className="font-mono text-[8px] text-text-tertiary w-9">
              {r.date}
            </span>
            <span className="rounded bg-coral/10 px-1 py-0.5 font-mono text-[7px] font-medium text-coral">
              {r.type}
            </span>
            <span className="font-mono text-[9px] text-text-primary">
              {r.dist}
            </span>
            <span className="font-mono text-[8px] text-text-tertiary">
              {r.pace}
            </span>
            <span
              className="ml-auto h-2 w-2 rounded-full"
              style={{ backgroundColor: r.mood }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

/* ─── Voice Logging ─── */
function VoiceLoggingScreen() {
  return (
    <div className="flex h-full flex-col px-5 pt-14 pb-6">
      <p className="font-body text-[9px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
        Log Your Run
      </p>
      <p className="mt-1 font-display text-[20px] text-text-primary">
        How did it go?
      </p>

      {/* Workout type selector */}
      <div className="mt-4 flex gap-2">
        {["Easy", "Tempo", "Long", "Interval"].map((t, i) => (
          <span
            key={t}
            className={`rounded-full px-2.5 py-1 font-mono text-[8px] ${
              i === 0
                ? "bg-coral text-white"
                : "bg-bg-elevated text-text-secondary"
            }`}
          >
            {t}
          </span>
        ))}
      </div>

      {/* Big record button */}
      <div className="flex flex-1 flex-col items-center justify-center">
        <div className="relative">
          {/* Pulse rings */}
          <div className="absolute inset-0 animate-ping rounded-full bg-coral/20" style={{ animationDuration: "2s" }} />
          <div className="relative flex h-24 w-24 items-center justify-center rounded-full bg-coral shadow-[0_6px_24px_rgba(212,89,42,0.4)]">
            <div className="h-8 w-8 rounded-sm bg-white" />
          </div>
        </div>
        <p className="mt-5 font-mono text-2xl font-semibold text-text-primary">
          1:32
        </p>
        <p className="mt-1 font-body text-[10px] text-text-tertiary">
          Recording...
        </p>
      </div>

      {/* Transcript preview */}
      <div className="rounded-xl bg-white p-3 shadow-[0_1px_4px_rgba(0,0,0,0.06)]">
        <p className="font-body text-[9px] italic leading-relaxed text-text-secondary">
          &ldquo;Did five miles today on the river trail. Felt pretty good,
          averaged around 8:15 pace. Did some pickups in the middle...&rdquo;
        </p>
        <div className="mt-2 flex gap-2">
          <span className="rounded bg-[#2D8A4E]/10 px-1.5 py-0.5 font-mono text-[7px] text-[#2D8A4E]">
            5.0 mi
          </span>
          <span className="rounded bg-coral/10 px-1.5 py-0.5 font-mono text-[7px] text-coral">
            8:15/mi
          </span>
          <span className="rounded bg-[#C4873A]/10 px-1.5 py-0.5 font-mono text-[7px] text-[#C4873A]">
            Pickups
          </span>
        </div>
      </div>
    </div>
  );
}

/* ─── Coach Chat ─── */
function CoachScreen() {
  return (
    <div className="flex h-full flex-col px-4 pt-14 pb-4">
      <p className="text-center font-body text-[9px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
        Coach
      </p>
      <p className="text-center font-mono text-[8px] text-coral">3/5 today</p>

      {/* Chat messages */}
      <div className="mt-4 flex-1 space-y-3 overflow-hidden">
        {/* Coach message */}
        <div className="flex items-start gap-2">
          <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-coral/15">
            <span className="text-[10px]">&#127939;</span>
          </div>
          <div className="rounded-xl rounded-tl-sm bg-white p-2.5 shadow-[0_1px_3px_rgba(0,0,0,0.06)]">
            <p className="font-body text-[9px] leading-relaxed text-text-secondary">
              Great consistency this week! Your mileage is up 15% and your pace
              has improved on easy days. One thing to watch:
            </p>
            <p className="mt-1.5 font-body text-[9px] font-medium leading-relaxed text-text-primary">
              Your tempo run on Wednesday was faster than prescribed. Try holding
              back to 9:00-9:15/mi to keep the aerobic benefit without excess
              fatigue.
            </p>
          </div>
        </div>

        {/* User message */}
        <div className="flex items-start justify-end gap-2">
          <div className="rounded-xl rounded-tr-sm bg-coral p-2.5">
            <p className="font-body text-[9px] leading-relaxed text-white">
              Should I add a recovery day before my long run Saturday?
            </p>
          </div>
          <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-[#2D8A4E]/15">
            <span className="text-[9px]">&#128100;</span>
          </div>
        </div>

        {/* Coach reply */}
        <div className="flex items-start gap-2">
          <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-coral/15">
            <span className="text-[10px]">&#127939;</span>
          </div>
          <div className="rounded-xl rounded-tl-sm bg-white p-2.5 shadow-[0_1px_3px_rgba(0,0,0,0.06)]">
            <p className="font-body text-[9px] leading-relaxed text-text-secondary">
              Yes — given your 25+ mile week, take Friday completely off or do a
              very easy 2-mile shakeout. Your legs will thank you Saturday
              morning.
            </p>
            <p className="mt-1 font-mono text-[7px] text-text-tertiary">
              Based on: 4 recent logs, training plan
            </p>
          </div>
        </div>

        {/* Typing indicator */}
        <div className="flex items-start gap-2">
          <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-coral/15">
            <span className="text-[10px]">&#127939;</span>
          </div>
          <div className="flex gap-1 rounded-xl bg-white px-3 py-2 shadow-[0_1px_3px_rgba(0,0,0,0.06)]">
            <Dot color="bg-text-tertiary" />
            <Dot color="bg-text-tertiary" />
            <Dot color="bg-text-tertiary" />
          </div>
        </div>
      </div>

      {/* Input bar */}
      <div className="mt-3 flex items-center gap-2 rounded-full bg-white px-3 py-2 shadow-[0_2px_8px_rgba(0,0,0,0.08)]">
        <span className="flex-1 font-body text-[9px] text-text-tertiary">
          Ask your coach...
        </span>
        <div className="flex h-6 w-6 items-center justify-center rounded-full bg-coral">
          <span className="text-[10px] text-white">&#8593;</span>
        </div>
      </div>
    </div>
  );
}

/* ─── Analysis ─── */
function AnalysisScreen() {
  return (
    <div className="px-5 pt-14 pb-6">
      <p className="font-body text-[9px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
        Training Analysis
      </p>
      <p className="mt-0.5 font-display text-[20px] text-text-primary">
        March 2026
      </p>

      {/* Period tabs */}
      <div className="mt-3 flex gap-4 border-b border-divider">
        {["Week", "Month", "Year"].map((p, i) => (
          <button
            key={p}
            className={`pb-1.5 font-body text-[9px] tracking-wider ${
              i === 1
                ? "border-b-[1.5px] border-coral text-coral"
                : "text-text-tertiary"
            }`}
          >
            {p}
          </button>
        ))}
      </div>

      {/* Narrative stat */}
      <div className="mt-4">
        <p className="font-body text-[10px] leading-relaxed text-text-secondary">
          <span className="font-display text-[32px] font-bold leading-none text-text-primary">
            87.4
          </span>{" "}
          miles across{" "}
          <span className="font-mono text-xs font-semibold text-coral">
            14
          </span>{" "}
          runs
        </p>
        <p className="mt-1 font-body text-[10px] text-text-secondary">
          averaging{" "}
          <span className="font-mono text-xs font-semibold text-coral">
            6.2
          </span>{" "}
          mi at{" "}
          <span className="font-mono text-xs font-semibold text-coral">
            9:18
          </span>
          /mi.
        </p>
      </div>

      {/* Mileage chart */}
      <div className="mt-5">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          Weekly Mileage
        </p>
        <div className="relative mt-2 h-16">
          <svg viewBox="0 0 200 60" className="h-full w-full" fill="none">
            <defs>
              <linearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#D4592A" stopOpacity="0.3" />
                <stop offset="100%" stopColor="#D4592A" stopOpacity="0.02" />
              </linearGradient>
            </defs>
            <path
              d="M0,45 L25,38 50,42 75,30 100,28 125,22 150,18 175,15 200,10 200,60 0,60Z"
              fill="url(#areaGrad)"
            />
            <polyline
              points="0,45 25,38 50,42 75,30 100,28 125,22 150,18 175,15 200,10"
              stroke="#D4592A"
              strokeWidth="2"
              fill="none"
            />
          </svg>
        </div>
      </div>

      {/* Pace + Frequency side by side */}
      <div className="mt-4 grid grid-cols-2 gap-3">
        <div>
          <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
            Pace Trend
          </p>
          <div className="mt-1.5 h-14 rounded-lg bg-white p-2 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <svg viewBox="0 0 100 40" className="h-full w-full" fill="none">
              <polyline
                points="0,35 15,30 30,28 45,25 60,22 75,18 90,15 100,12"
                stroke="#D4592A"
                strokeWidth="1.5"
              />
              {[
                [0, 35], [30, 28], [60, 22], [100, 12],
              ].map(([x, y], i) => (
                <circle key={i} cx={x} cy={y} r="2.5" fill="#D4592A" stroke="white" strokeWidth="1" />
              ))}
            </svg>
          </div>
        </div>
        <div>
          <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
            Run Frequency
          </p>
          <div className="mt-1.5 flex h-14 items-end gap-1 rounded-lg bg-white p-2 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            {[20, 60, 45, 80, 30, 90, 15].map((h, i) => (
              <MiniBar key={i} h={`${h * 0.35}px`} color="bg-coral/40" />
            ))}
          </div>
        </div>
      </div>

      {/* Workout donut + ACWR */}
      <div className="mt-3 grid grid-cols-2 gap-3">
        <div>
          <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
            Workout Types
          </p>
          <div className="mt-1.5 flex items-center justify-center rounded-lg bg-white p-2 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <svg viewBox="0 0 40 40" className="h-10 w-10">
              <circle cx="20" cy="20" r="16" fill="none" stroke="#E8E4E0" strokeWidth="4" />
              <circle
                cx="20" cy="20" r="16" fill="none" stroke="#D4592A"
                strokeWidth="4" strokeDasharray="55 100" strokeDashoffset="0"
                transform="rotate(-90 20 20)"
              />
              <circle
                cx="20" cy="20" r="16" fill="none" stroke="#E8764A"
                strokeWidth="4" strokeDasharray="25 100" strokeDashoffset="-55"
                transform="rotate(-90 20 20)"
              />
              <circle
                cx="20" cy="20" r="16" fill="none" stroke="#C4873A"
                strokeWidth="4" strokeDasharray="12 100" strokeDashoffset="-80"
                transform="rotate(-90 20 20)"
              />
            </svg>
            <div className="ml-2 space-y-0.5">
              <div className="flex items-center gap-1">
                <Dot color="bg-coral" />
                <span className="font-mono text-[7px] text-text-tertiary">Easy 55%</span>
              </div>
              <div className="flex items-center gap-1">
                <Dot color="bg-[#E8764A]" />
                <span className="font-mono text-[7px] text-text-tertiary">Tempo 25%</span>
              </div>
              <div className="flex items-center gap-1">
                <Dot color="bg-[#C4873A]" />
                <span className="font-mono text-[7px] text-text-tertiary">Long 12%</span>
              </div>
            </div>
          </div>
        </div>
        <div>
          <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
            Training Load
          </p>
          <div className="mt-1.5 flex flex-col items-center rounded-lg bg-white p-2 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
            <svg viewBox="0 0 60 34" className="h-8 w-14">
              <path
                d="M6,30 A24,24 0 0,1 54,30"
                fill="none" stroke="#E8E4E0" strokeWidth="4" strokeLinecap="round"
              />
              <path
                d="M6,30 A24,24 0 0,1 42,10"
                fill="none" stroke="#2D8A4E" strokeWidth="4" strokeLinecap="round"
              />
            </svg>
            <span className="font-mono text-sm font-bold text-text-primary">
              1.12
            </span>
            <span className="font-mono text-[7px] text-[#2D8A4E]">
              Optimal
            </span>
          </div>
        </div>
      </div>

      {/* Coach notes preview */}
      <div className="mt-4 border-t border-divider pt-3">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-secondary">
          Coach&apos;s Notes
        </p>
        <p className="mt-1.5 font-body text-[9px] leading-relaxed text-text-secondary">
          <span className="float-left mr-1 font-display text-[28px] leading-[0.85] text-coral">
            Y
          </span>
          our mileage progression has been textbook — steady 10-12% increases
          with a deload every fourth week. Pace on easy days is well controlled...
        </p>
      </div>
    </div>
  );
}

/* ─── Training Plan ─── */
function PlanScreen() {
  return (
    <div className="px-5 pt-14 pb-6">
      <p className="font-body text-[9px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
        Training Plan
      </p>
      <div className="mt-1 flex items-center justify-between">
        <p className="font-display text-[18px] text-text-primary">
          Half Marathon Prep
        </p>
        <span className="rounded-full bg-coral/10 px-2 py-0.5 font-mono text-[8px] text-coral">
          Week 6 of 12
        </span>
      </div>

      {/* Compliance mini chart */}
      <div className="mt-4 rounded-xl bg-white p-3 shadow-[0_1px_4px_rgba(0,0,0,0.06)]">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          Plan Compliance
        </p>
        <div className="mt-2 flex items-end gap-2">
          {[
            { planned: 5, actual: 5 },
            { planned: 4, actual: 4 },
            { planned: 5, actual: 3 },
            { planned: 4, actual: 4 },
            { planned: 5, actual: 5 },
            { planned: 3, actual: 2 },
          ].map((w, i) => (
            <div key={i} className="flex flex-1 items-end gap-0.5">
              <div
                className="flex-1 rounded-sm bg-bg-elevated"
                style={{ height: `${w.planned * 6}px` }}
              />
              <div
                className="flex-1 rounded-sm bg-coral/60"
                style={{ height: `${w.actual * 6}px` }}
              />
            </div>
          ))}
        </div>
        <div className="mt-1.5 flex items-center gap-3 font-mono text-[7px] text-text-tertiary">
          <span className="flex items-center gap-1">
            <span className="h-1.5 w-1.5 rounded-sm bg-bg-elevated" /> Planned
          </span>
          <span className="flex items-center gap-1">
            <span className="h-1.5 w-1.5 rounded-sm bg-coral/60" /> Actual
          </span>
        </div>
      </div>

      {/* This week schedule */}
      <div className="mt-4">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          This Week
        </p>
        <div className="mt-2 grid grid-cols-7 gap-1.5">
          {[
            { day: "M", type: "Easy", dist: "4mi", done: true },
            { day: "T", type: null, dist: null, done: false },
            { day: "W", type: "Tempo", dist: "5mi", done: true },
            { day: "T", type: null, dist: null, done: false },
            { day: "F", type: "Easy", dist: "3mi", done: true },
            { day: "S", type: "Long", dist: "10mi", done: false },
            { day: "S", type: null, dist: null, done: false },
          ].map((d, i) => (
            <div
              key={i}
              className={`rounded-lg p-1.5 text-center ${
                d.type
                  ? d.done
                    ? "bg-[#2D8A4E]/8 ring-1 ring-[#2D8A4E]/20"
                    : i === 5
                      ? "bg-white ring-1 ring-coral/30 shadow-[0_1px_3px_rgba(0,0,0,0.04)]"
                      : "bg-white shadow-[0_1px_3px_rgba(0,0,0,0.04)]"
                  : "bg-bg-elevated/60"
              }`}
            >
              <span className="font-mono text-[7px] text-text-tertiary">
                {d.day}
              </span>
              {d.type ? (
                <>
                  <p className="mt-0.5 font-mono text-[7px] font-medium text-text-primary">
                    {d.type}
                  </p>
                  <p className="font-mono text-[6px] text-text-tertiary">
                    {d.dist}
                  </p>
                  {d.done && (
                    <span className="text-[8px] text-[#2D8A4E]">&#10003;</span>
                  )}
                </>
              ) : (
                <p className="mt-0.5 font-mono text-[7px] text-text-tertiary">
                  Rest
                </p>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Upcoming weeks */}
      <div className="mt-4">
        <p className="font-body text-[8px] font-medium tracking-[1.5px] uppercase text-text-tertiary">
          Upcoming
        </p>
        {[
          { week: "Week 7", focus: "Speed Work", miles: "28 mi" },
          { week: "Week 8", focus: "Deload", miles: "18 mi" },
          { week: "Week 9", focus: "Race Pace", miles: "30 mi" },
        ].map((w) => (
          <div
            key={w.week}
            className="mt-1.5 flex items-center justify-between rounded-lg bg-white px-3 py-2 shadow-[0_1px_3px_rgba(0,0,0,0.04)]"
          >
            <div>
              <span className="font-mono text-[8px] font-medium text-text-primary">
                {w.week}
              </span>
              <span className="ml-2 font-body text-[8px] text-text-tertiary">
                {w.focus}
              </span>
            </div>
            <span className="font-mono text-[8px] text-coral">{w.miles}</span>
          </div>
        ))}
      </div>

      {/* Race predictions */}
      <div className="mt-4 rounded-xl bg-white p-3 shadow-[0_1px_4px_rgba(0,0,0,0.06)]">
        <div className="flex items-center gap-1.5">
          <span className="text-[10px]">&#127942;</span>
          <span className="font-body text-[8px] font-medium tracking-[1px] uppercase text-text-secondary">
            Predicted Race Times
          </span>
        </div>
        <div className="mt-2 flex gap-3 text-center">
          {[
            { dist: "5K", time: "24:32" },
            { dist: "10K", time: "51:15" },
            { dist: "Half", time: "1:53:42" },
          ].map((p) => (
            <div key={p.dist} className="flex-1">
              <p className="font-mono text-[7px] text-text-tertiary">
                {p.dist}
              </p>
              <p className="font-mono text-sm font-bold text-text-primary">
                {p.time}
              </p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

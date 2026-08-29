import type { Metadata } from "next";
import Link from "next/link";

import { AppPreview } from "@/components/site/app-preview";
import {
  ActionLink,
  CoachQuote,
  EditorialRule,
  Eyebrow,
  PlateStrip,
} from "@/components/site/editorial";

export const metadata: Metadata = {
  title: "Post Run Drip — a training log for self-coached runners",
  description:
    "Voice-log the run, sync the watch, and get your training read back honestly — anchored to races you have actually run. No prescriptions, no diagnoses.",
};

/* ──────────────────────────────────────────────────────────────────────
   HOME — rebuilt around the wedge (see outputs/product-state-2026-05-28.md).

   The previous page sold "a running log" to nobody in particular. This one
   is written to Maya: the self-coached runner who journals her training,
   anchors on real race history, and wants observation without prescription.
   Every surface shown here matches the target 4-tab IA in CLAUDE.md.
   ────────────────────────────────────────────────────────────────────── */

export default function LandingPage() {
  return (
    <>
      <PlateStrip
        surface="Home · v1"
        fig="Fig. 00"
        right="Self-coached · 2026"
      />
      <Hero />
      <Surfaces />
      <Anchored />
      <Voice />
      <Niggles />
      <Roadmap />
      <Beta />
    </>
  );
}

/* ── HERO ────────────────────────────────────────────────────────────── */

function Hero() {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto grid max-w-[1180px] items-center gap-14 px-6 py-16 md:px-10 lg:grid-cols-[1.05fr_0.95fr] lg:py-24">
        <div>
          <Eyebrow coral>For runners coaching themselves</Eyebrow>
          <h1 className="mt-5 font-display text-[clamp(44px,8vw,76px)] font-bold leading-[0.98] tracking-[-0.02em] text-text-primary">
            Honest observation.
            <br />
            <em className="italic text-coral">No prescriptions.</em>
          </h1>
          <p className="mt-7 max-w-[46ch] font-body text-[17px] leading-[1.6] text-text-secondary">
            Talk into your phone after the run. The watch data lands on top of
            it. Post Run Drip keeps the record, reads the two together, and
            tells you what it sees — anchored to races you have actually run,
            not the time you are chasing.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-5">
            <Link
              href="/beta"
              className="rounded-[10px] bg-coral px-6 py-3.5 font-display text-[15px] font-semibold text-white shadow-[0_1px_0_var(--color-coral-dark)] transition-colors hover:bg-coral-dark"
            >
              Request an invite
            </Link>
            <ActionLink href="/how-it-works">See the four surfaces</ActionLink>
          </div>

          <div className="mt-10 flex flex-wrap items-baseline gap-x-6 gap-y-2 border-t border-divider pt-5">
            <Eyebrow>iOS · TestFlight</Eyebrow>
            <Eyebrow>HealthKit sync</Eyebrow>
            <Eyebrow>Voice-first logging</Eyebrow>
          </div>
        </div>

        <div>
          <AppPreview initialTab="log" />
          <p className="mt-4 text-center font-body text-[13px] italic text-text-tertiary">
            Tap a tab. This is the app, at rest.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── SURFACES ────────────────────────────────────────────────────────── */

const SURFACES = [
  {
    n: "01",
    title: "Log",
    body:
      "Voice memo at the top, six months of training scrolling below. Runs arrive from HealthKit; you supply the part a watch cannot record. No annotation, no scoring — a record you can read back.",
  },
  {
    n: "02",
    title: "Trends",
    body:
      "The 5-second view. Fitness as a range with a confidence, not a fake projection. Volume, load, and the niggles you keep mentioning, each one tappable down to the week it started.",
  },
  {
    n: "03",
    title: "Train",
    body:
      "This week, the calendar, and the longer arc in one place. Pace zones derive from your race history. If a coach issues you a plan, it layers in; if nobody does, the tab still works.",
  },
  {
    n: "04",
    title: "Coach",
    body:
      "A read of your training, on demand. Feeling first, then the workouts, then the mileage. It ends on a question rather than an instruction, and you can ask it to look again through a different lens.",
  },
];

function Surfaces() {
  return (
    <section id="surfaces" className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-6 py-20 md:px-10">
        <div className="max-w-[52ch]">
          <Eyebrow>The product</Eyebrow>
          <h2 className="mt-4 font-display text-[clamp(34px,5vw,52px)] font-bold leading-[1.02] tracking-[-0.015em] text-text-primary">
            Four surfaces.
          </h2>
          <p className="mt-4 font-body text-[16px] leading-[1.6] text-text-secondary">
            Input, overview, detail, synthesis. Nothing else earns a tab.
          </p>
        </div>

        <div className="mt-14 grid gap-x-10 gap-y-12 md:grid-cols-2 lg:grid-cols-4">
          {SURFACES.map((s) => (
            <div key={s.n}>
              <Eyebrow coral>{s.n}</Eyebrow>
              <h3 className="mt-3 font-display text-[32px] font-bold leading-tight tracking-[-0.01em] text-text-primary">
                {s.title}
              </h3>
              <p className="mt-3 font-body text-[15px] leading-[1.65] text-text-secondary">
                {s.body}
              </p>
            </div>
          ))}
        </div>

        <div className="mt-14">
          <ActionLink href="/how-it-works">
            Walk through each surface
          </ActionLink>
        </div>
      </div>
    </section>
  );
}

/* ── RACE-ANCHORED ───────────────────────────────────────────────────── */

function Anchored() {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto grid max-w-[1180px] items-center gap-14 px-6 py-20 md:px-10 lg:grid-cols-[1fr_0.85fr]">
        <div>
          <Eyebrow>Fitness</Eyebrow>
          <h2 className="mt-4 font-display text-[clamp(32px,4.6vw,48px)] font-bold leading-[1.04] tracking-[-0.015em] text-text-primary">
            Your 3:28 is the anchor.
            <br />
            Your 3:16 is the direction.
          </h2>
          <p className="mt-6 max-w-[52ch] font-body text-[16px] leading-[1.65] text-text-secondary">
            Most apps derive your training paces from the goal you typed in
            last week. That makes every zone a guess about a runner you are
            not yet. Post Run Drip anchors on what you have actually raced —
            marathons, halves, whatever sits in your history — and treats the
            goal as heading, not fact.
          </p>
          <p className="mt-4 max-w-[52ch] font-body text-[16px] leading-[1.65] text-text-secondary">
            Ten pace zones come out of that anchor. Easy, Moderate, Steady as
            efforts; MP, HMP, LT, 10K, 5K, 3K, Mile as race paces. A workout
            is named for its zone, so <em className="italic">MP 7 mi</em> means
            what it says.
          </p>
        </div>

        <div className="rounded-xl bg-bg-card p-6 shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
          <div className="flex items-baseline justify-between">
            <Eyebrow coral>Marathon · predicted</Eyebrow>
            <Eyebrow>91 days out</Eyebrow>
          </div>
          <div className="mt-4 font-mono text-[40px] font-semibold tabular-nums leading-none tracking-[-0.02em] text-text-primary">
            3:19–3:25
          </div>
          <div className="mt-3 font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-text-secondary">
            Midpoint 3:22 · high confidence
          </div>
          <p className="mt-4 font-body text-[13px] italic leading-[1.55] text-text-tertiary">
            Based on 4 MP workouts, a half in June, and 11 weeks above 40 mi.
          </p>

          <EditorialRule className="my-6" />

          <Eyebrow>What you will never see</Eyebrow>
          <div className="mt-3 font-mono text-[26px] font-semibold tabular-nums leading-none text-text-tertiary line-through decoration-coral decoration-1">
            3:21:47
          </div>
          <p className="mt-3 font-body text-[13px] italic leading-[1.55] text-text-tertiary">
            The seconds are a math artifact. Showing them would be a claim the
            data cannot support.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── VOICE ───────────────────────────────────────────────────────────── */

function Voice() {
  return (
    <section className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-6 py-20 md:px-10">
        <div className="max-w-[54ch]">
          <Eyebrow>The read</Eyebrow>
          <h2 className="mt-4 font-display text-[clamp(32px,4.6vw,48px)] font-bold leading-[1.04] tracking-[-0.015em] text-text-primary">
            It observes. You decide.
          </h2>
          <p className="mt-4 font-body text-[16px] leading-[1.65] text-text-secondary">
            The read starts with how the run felt, because that is what you
            said first. It carries your anchors and your goal silently, and it
            never explains its own arithmetic back to you.
          </p>
        </div>

        <div className="mt-12 grid gap-10 md:grid-cols-2">
          <div>
            <Eyebrow coral>What it sounds like</Eyebrow>
            <div className="mt-5 space-y-5">
              <CoachQuote>
                Easy paces are creeping down — 8:35 last week, 8:22 this week.
                Volume is holding at 42.
              </CoachQuote>
              <CoachQuote>
                Tempo locked in at 7:29 average. Four weeks ago that was 7:35.
              </CoachQuote>
              <CoachQuote>
                You are four weeks into the build. Last cycle the analogous
                week was 35 mi at slower tempos.
              </CoachQuote>
            </div>
          </div>

          <div>
            <Eyebrow>What it will not say</Eyebrow>
            <ul className="mt-5 space-y-4 font-body text-[15px] leading-[1.6] text-text-tertiary">
              {[
                ["“Based on your 3:28 and your goal of 3:16, you need to…”", "Explaining math you already know."],
                ["“That is a 12-minute PR — ambitious.”", "Not its call to make."],
                ["“You will qualify.”", "A certainty claim. Hard rule."],
                ["“Aim for 3:20 instead.”", "The goal is yours. It does not move."],
                ["“Rest this one, it is probably ITBS.”", "Not a diagnosis it is allowed to reach."],
              ].map(([line, why]) => (
                <li key={line} className="border-l border-divider pl-4">
                  <span className="block text-text-secondary line-through decoration-divider">
                    {line}
                  </span>
                  <span className="mt-1 block font-mono text-[9px] font-medium tracking-[0.10em] uppercase text-text-tertiary">
                    {why}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="mt-12">
          <ActionLink href="/principles">Read the principles</ActionLink>
        </div>
      </div>
    </section>
  );
}

/* ── NIGGLES ─────────────────────────────────────────────────────────── */

function Niggles() {
  return (
    <section className="border-b border-divider">
      <div className="mx-auto grid max-w-[1180px] gap-14 px-6 py-20 md:px-10 lg:grid-cols-[0.9fr_1.1fr]">
        <div>
          <Eyebrow>Niggles</Eyebrow>
          <h2 className="mt-4 font-display text-[clamp(32px,4.6vw,48px)] font-bold leading-[1.04] tracking-[-0.015em] text-text-primary">
            It reports what you said, and where.
          </h2>
          <p className="mt-6 max-w-[46ch] font-body text-[16px] leading-[1.65] text-text-secondary">
            When you mention a body part in a log, it gets recorded against a
            closed list of about thirty — foot, achilles, calf, IT band, the
            usual suspects. Your words are kept verbatim. Nothing is renamed
            into a condition, scored for severity, or turned into advice.
          </p>
          <p className="mt-4 font-body text-[13px] italic leading-[1.6] text-text-tertiary">
            Not medical advice. If anything gets sharper, see a clinician.
          </p>
        </div>

        <div className="rounded-xl bg-bg-card p-6 shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
          <div className="flex items-baseline justify-between border-b border-divider pb-3">
            <Eyebrow coral>Left achilles</Eyebrow>
            <Eyebrow>3 mentions · 22 days</Eyebrow>
          </div>
          <div className="divide-y divide-divider">
            {[
              ["Aug 26", "“Achilles was tight for the first mile again, went quiet after.”"],
              ["Aug 12", "“Bit of a grumble in the left achilles coming down the hill.”"],
              ["Aug 4", "“Left achilles sore stepping out of bed. Fine once I got going.”"],
            ].map(([date, quote]) => (
              <div key={date} className="py-4">
                <Eyebrow>{date}</Eyebrow>
                <p className="mt-2 font-body text-[14px] italic leading-[1.55] text-text-primary">
                  {quote}
                </p>
              </div>
            ))}
          </div>
          <p className="mt-4 font-body text-[13px] italic leading-[1.55] text-text-tertiary">
            — every mention within a day of a long run. That is the pattern;
            what it means is yours to decide. —
          </p>
        </div>
      </div>
    </section>
  );
}

/* ── ROADMAP ─────────────────────────────────────────────────────────── */

const PILLARS = [
  { n: "01", title: "Training", body: "What did I do? What am I supposed to do?", status: "Shipping" },
  { n: "02", title: "Understanding", body: "How am I doing? Where is this going?", status: "Shipping" },
  { n: "03", title: "Recovery", body: "How well did I rest? Push today, or pull?", status: "Next" },
  { n: "04", title: "Mobility", body: "Is the body moving the way it should?", status: "Later" },
  { n: "05", title: "Strength", body: "Am I doing the work that protects the running?", status: "Later" },
];

function Roadmap() {
  return (
    <section className="border-b border-divider bg-bg-elevated">
      <div className="mx-auto max-w-[1180px] px-6 py-20 md:px-10">
        <div className="max-w-[52ch]">
          <Eyebrow>Sequence</Eyebrow>
          <h2 className="mt-4 font-display text-[clamp(32px,4.6vw,48px)] font-bold leading-[1.04] tracking-[-0.015em] text-text-primary">
            Five questions, in order.
          </h2>
          <p className="mt-4 font-body text-[16px] leading-[1.65] text-text-secondary">
            Two of them are built. The rest are honest about being unbuilt.
          </p>
        </div>

        <div className="mt-12 border-t border-divider">
          {PILLARS.map((p) => (
            <div
              key={p.n}
              className="grid grid-cols-[auto_1fr] items-baseline gap-x-6 gap-y-1 border-b border-divider py-6 md:grid-cols-[auto_200px_1fr_auto]"
            >
              <Eyebrow>{p.n}</Eyebrow>
              <h3 className="font-display text-[24px] font-bold tracking-[-0.01em] text-text-primary">
                {p.title}
              </h3>
              <p className="col-span-2 font-body text-[15px] leading-[1.6] text-text-secondary md:col-span-1">
                {p.body}
              </p>
              <span
                className={`col-start-2 font-mono text-[9px] font-medium tracking-[0.12em] uppercase md:col-start-auto md:text-right ${
                  p.status === "Shipping" ? "text-coral" : "text-text-tertiary"
                }`}
              >
                {p.status}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ── BETA ────────────────────────────────────────────────────────────── */

function Beta() {
  return (
    <section id="beta" className="border-b border-divider">
      <div className="mx-auto max-w-[760px] px-6 py-24 text-center md:px-10">
        <Eyebrow coral>Closed beta</Eyebrow>
        <h2 className="mt-5 font-display text-[clamp(36px,6vw,56px)] font-bold leading-[1.02] tracking-[-0.015em] text-text-primary">
          Run a week with it.
          <br />
          <em className="italic text-coral">Then tell us what is wrong.</em>
        </h2>
        <p className="mx-auto mt-7 max-w-[46ch] font-body text-[16px] leading-[1.65] text-text-secondary">
          iOS, by TestFlight invite. Built for runners with a race on the
          calendar and a base under them.
        </p>
        <div className="mt-9">
          <Link
            href="/beta"
            className="inline-block rounded-[10px] bg-coral px-7 py-4 font-display text-[16px] font-semibold text-white shadow-[0_1px_0_var(--color-coral-dark)] transition-colors hover:bg-coral-dark"
          >
            Request an invite
          </Link>
        </div>
      </div>
    </section>
  );
}

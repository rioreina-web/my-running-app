import type { Metadata } from "next";
import Link from "next/link";

import {
  CoachQuote,
  EditorialRule,
  Eyebrow,
  PlateStrip,
} from "@/components/site/editorial";

export const metadata: Metadata = {
  title: "Principles",
  description:
    "Six rules Post Run Drip holds itself to: advise never act, detection over diagnosis, history over goal time, ranges over point estimates, observation over praise, and empty as a legitimate state.",
};

/* The principles page. Every rule here is enforced somewhere in the
 * codebase — see the hard rules in CLAUDE.md and docs/coaching/principles.md.
 * This page is the public statement of them, in the product's own voice. */

type Principle = {
  n: string;
  id: string;
  short: string;
  title: string;
  body: string[];
  quote?: string;
  quoteLabel?: string;
};

const PRINCIPLES: Principle[] = [
  {
    n: "01",
    id: "advise",
    short: "Advise, never act",
    title: "It advises. It never acts.",
    body: [
      "Nothing in the app moves a workout, changes a plan, or alters your training on your behalf. It surfaces what it noticed and hands the decision back — to you, or to your coach if you have one.",
      "This is a structural commitment, not a setting. Where the system suggests an adjustment, that suggestion is written down as a suggestion and waits for a human to accept it.",
    ],
  },
  {
    n: "02",
    id: "detection",
    short: "Detection, not diagnosis",
    title: "Detection, not diagnosis.",
    body: [
      "When you mention a body part, the app records which one and quotes you word for word. It does not name a condition, rate the severity, or tell you what to do about it.",
      "The vocabulary is closed — about thirty body parts. Say “subtalar joint” and it files it under ankle or leaves it alone. It will not invent a medical entity to sound authoritative.",
    ],
    quote: "Not medical advice. If anything gets sharper, see a clinician.",
    quoteLabel: "The whole of what it will say about pain",
  },
  {
    n: "03",
    id: "history",
    short: "History over goal time",
    title: "History is the foundation. The goal is the direction.",
    body: [
      "What you have actually raced is more trustworthy than what you are aiming for. Pace zones and fitness estimates anchor on your race history, validate against your current training, and use the goal time only as heading.",
      "A 3:28 marathon on file anchors your zones on the runner you are. The 3:16 you want stays where it belongs — in front of you.",
    ],
  },
  {
    n: "04",
    id: "range",
    short: "Ranges, not numbers",
    title: "A range, with a confidence. Never a number.",
    body: [
      "Fitness predictions ship as an interval with a stated confidence and the evidence behind them. The interval widens when the training thins out, because that is what honesty looks like on a chart.",
      "A single projected finish time to the second implies a precision the data does not have. The seconds are an artifact of the arithmetic, and showing them would be a small lie repeated daily.",
    ],
    quote: "3:19–3:25 · midpoint 3:22 · high confidence, on 4 MP workouts and a half in June.",
    quoteLabel: "What a prediction looks like",
  },
  {
    n: "05",
    id: "observation",
    short: "Observation, not praise",
    title: "Observation over congratulation.",
    body: [
      "No streaks, no badges, no exclamation marks. The read tells you what changed and what it noticed, in the register a good coach uses walking back to the car.",
      "It starts with how the run felt, because that is what you said first. It never explains its own arithmetic back to you, and it does not move your goalposts to make a nicer sentence.",
    ],
    quote:
      "Easy paces are creeping down — 8:35 last week, 8:22 this week. Volume is holding at 42.",
    quoteLabel: "The register",
  },
  {
    n: "06",
    id: "empty",
    short: "Empty is a state",
    title: "Empty is a state, not a failure.",
    body: [
      "Most training apps break when you are not following a plan. Not having one is the normal condition for a self-coached runner, so every surface works without it.",
      "The same goes for a new account. Where there is nothing to show yet, the app says what will fill the space and leaves it at that. No placeholder dashes pretending to be data.",
    ],
    quote: "No runs logged yet. When you do, your last entry lands here.",
    quoteLabel: "An empty state, in full",
  },
];

export default function PrinciplesPage() {
  return (
    <>
      <PlateStrip
        surface="Principles · v1"
        fig="Fig. 06"
        right="Six rules · 2026"
      />

      <section className="border-b border-divider">
        <div className="mx-auto grid max-w-[1180px] gap-12 px-6 py-16 md:px-10 lg:grid-cols-[1.15fr_0.85fr] lg:py-20">
          <div>
            <Eyebrow coral>What it holds itself to</Eyebrow>
            <h1 className="mt-5 max-w-[15ch] font-display text-[clamp(40px,7vw,68px)] font-bold leading-[1] tracking-[-0.02em] text-text-primary">
              Six rules, and what they cost.
            </h1>
            <p className="mt-7 max-w-[52ch] font-body text-[17px] leading-[1.6] text-text-secondary">
              Each of these rules removes something an app like this would
              normally do. That is the point. A training log earns trust by
              what it refuses to claim.
            </p>
          </div>

          <nav aria-label="Contents" className="lg:pt-3">
            <Eyebrow>Contents</Eyebrow>
            <ul className="mt-4 border-t border-divider">
              {PRINCIPLES.map((p) => (
                <li key={p.n} className="border-b border-divider">
                  <Link
                    href={`#${p.id}`}
                    className="group grid grid-cols-[36px_1fr] items-baseline gap-4 py-3.5"
                  >
                    <Eyebrow>{p.n}</Eyebrow>
                    <span className="font-display text-[18px] font-semibold tracking-[-0.01em] text-text-primary transition-colors group-hover:text-coral">
                      {p.short}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        </div>
      </section>

      <section className="border-b border-divider">
        <div className="mx-auto max-w-[900px] px-6 md:px-10">
          {PRINCIPLES.map((p, i) => (
            <article
              key={p.n}
              id={p.id}
              className={`grid scroll-mt-24 gap-x-10 gap-y-5 py-16 md:grid-cols-[80px_1fr] ${
                i > 0 ? "border-t border-divider" : ""
              }`}
            >
              <div className="font-display text-[44px] font-bold leading-none tracking-[-0.02em] text-divider">
                {p.n}
              </div>
              <div>
                <h2 className="font-display text-[clamp(28px,3.6vw,40px)] font-bold leading-[1.06] tracking-[-0.015em] text-text-primary">
                  {p.title}
                </h2>
                <div className="mt-5 space-y-4">
                  {p.body.map((para) => (
                    <p
                      key={para.slice(0, 24)}
                      className="max-w-[62ch] font-body text-[16px] leading-[1.7] text-text-secondary"
                    >
                      {para}
                    </p>
                  ))}
                </div>
                {p.quote && (
                  <div className="mt-7">
                    <Eyebrow>{p.quoteLabel}</Eyebrow>
                    <CoachQuote className="mt-3">{p.quote}</CoachQuote>
                  </div>
                )}
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="border-b border-divider bg-bg-elevated">
        <div className="mx-auto max-w-[900px] px-6 py-20 md:px-10">
          <Eyebrow>The short version</Eyebrow>
          <h2 className="mt-4 font-display text-[clamp(30px,4.4vw,44px)] font-bold leading-[1.05] tracking-[-0.015em] text-text-primary">
            Things it will never do.
          </h2>
          <EditorialRule className="my-8" />
          <ul className="grid gap-x-10 gap-y-5 md:grid-cols-2">
            {[
              "Tell you to stop training",
              "Name an injury",
              "Rate how bad your pain is",
              "Project a finish time to the second",
              "Move your goal to something safer",
              "Change your plan without a human saying so",
              "Congratulate you",
              "Guess at a body part you did not mention",
            ].map((item) => (
              <li
                key={item}
                className="border-b border-divider pb-4 font-body text-[16px] leading-[1.5] text-text-secondary"
              >
                {item}
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className="border-b border-divider">
        <div className="mx-auto max-w-[760px] px-6 py-24 text-center md:px-10">
          <h2 className="font-display text-[clamp(30px,4.6vw,44px)] font-bold leading-[1.05] tracking-[-0.015em] text-text-primary">
            If that sounds like the log you want.
          </h2>
          <div className="mt-8">
            <Link
              href="/beta"
              className="inline-block rounded-[10px] bg-coral px-7 py-4 font-display text-[16px] font-semibold text-white transition-colors hover:bg-coral-dark"
            >
              Request an invite
            </Link>
          </div>
        </div>
      </section>
    </>
  );
}

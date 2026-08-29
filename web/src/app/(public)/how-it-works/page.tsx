import type { Metadata } from "next";
import Link from "next/link";

import { AppScreenshot, type PreviewTab } from "@/components/site/app-preview";
import {
  ActionLink,
  Eyebrow,
  EditorialRule,
  PlateStrip,
} from "@/components/site/editorial";

export const metadata: Metadata = {
  title: "How it works",
  description:
    "Log, Trends, Train, Coach — the four surfaces of Post Run Drip, and what each one is for.",
};

/* Surface-by-surface walkthrough. The device screenshots are the same
 * components the landing hero uses, pinned to one tab each. */

type Surface = {
  n: string;
  tab: PreviewTab;
  title: string;
  question: string;
  lede: string;
  points: [string, string][];
};

const SURFACES: Surface[] = [
  {
    n: "01",
    tab: "log",
    title: "Log",
    question: "What did I do?",
    lede:
      "The front door. Press record and say how the run went, in the words you would use telling a training partner. The transcript is kept; so is the run your watch recorded. Below the record button, six months of training scrolls back.",
    points: [
      ["Voice or typed", "Talk after the run, or write it later. Both land in the same entry."],
      ["Runs arrive on their own", "HealthKit syncs distance, pace, splits and heart rate. Two years of history back-fill when you sign up."],
      ["Everything, not just runs", "Cross-training, strength and rest days sit in the journal alongside the miles."],
      ["No annotation", "The log is a record. Nothing scores it, grades it, or writes on top of it."],
    ],
  },
  {
    n: "02",
    tab: "trends",
    title: "Trends",
    question: "How am I doing?",
    lede:
      "The 5-second view. Open it, read four tiles, close it. Fitness comes back as a range with a confidence attached, plotted across 26 weeks with your races marked on the line.",
    points: [
      ["Race-anchored fitness", "Predictions build from races in your history first, and use your goal only as direction."],
      ["A range, never a number", "3:19–3:25, midpoint 3:22, high confidence. Seconds-precision projections are a math artifact and are not shown."],
      ["Volume and load", "Weekly mileage against a 4-week average, plus acute-to-chronic load, without the ceremony."],
      ["Niggles", "Body parts you have mentioned, how often, and when. Tap through to the timeline."],
    ],
  },
  {
    n: "03",
    tab: "train",
    title: "Train",
    question: "What am I supposed to do?",
    lede:
      "This week at the top, the calendar behind it, and the longer arc behind that. Three modes, one tab. It works whether or not anyone has issued you a plan.",
    points: [
      ["Current", "Today and the week around it. What is logged, what is planned, what is left."],
      ["Calendar", "Month view with past and planned together. A coach's plan layers in if you are working with one."],
      ["History", "Pace against volume over months, cycle-to-cycle overlays, and how this build compares to your last."],
      ["Ten pace zones", "Easy, Moderate and Steady as efforts; MP, HMP, LT, 10K, 5K, 3K and Mile as race paces. The zone is the workout name."],
    ],
  },
  {
    n: "04",
    tab: "coach",
    title: "Coach",
    question: "What does all of it add up to?",
    lede:
      "A read of your training, generated when you ask for one. It starts with how you said the running felt, then the workouts, then the mileage — and it finishes on a question rather than an instruction.",
    points: [
      ["On demand", "No daily push, no streak. You tap when you want a read."],
      ["It reads the whole record", "Voice logs and numbers together, plus the context you mentioned — bad sleep, a heat wave, a heavy week at work."],
      ["Anchors stay quiet", "Your PB and your goal sit underneath the read. They are never explained back to you."],
      ["Ask for another lens", "“How does this cycle compare to my last?” gets a different read of the same training."],
    ],
  },
];

export default function HowItWorksPage() {
  return (
    <>
      <PlateStrip
        surface="How it works · v1"
        fig="Fig. 05"
        right="Four surfaces · 2026"
      />

      <section className="border-b border-divider">
        <div className="mx-auto grid max-w-[1180px] gap-12 px-6 py-16 md:px-10 lg:grid-cols-[1.15fr_0.85fr] lg:py-20">
          <div>
            <Eyebrow coral>The walkthrough</Eyebrow>
            <h1 className="mt-5 max-w-[16ch] font-display text-[clamp(40px,7vw,68px)] font-bold leading-[1] tracking-[-0.02em] text-text-primary">
              Input. Overview. Detail. Synthesis.
            </h1>
            <p className="mt-7 max-w-[52ch] font-body text-[17px] leading-[1.6] text-text-secondary">
              Four tabs, in the order you actually use them. You put something
              in, you look at where you stand, you go find the detail, and then
              you ask what it all means.
            </p>
          </div>

          <nav aria-label="Contents" className="lg:pt-3">
            <Eyebrow>Contents</Eyebrow>
            <ul className="mt-4 border-t border-divider">
              {SURFACES.map((surface) => (
                <li key={surface.n} className="border-b border-divider">
                  <Link
                    href={`#${surface.tab}`}
                    className="group grid grid-cols-[36px_1fr_auto] items-baseline gap-4 py-4"
                  >
                    <Eyebrow>{surface.n}</Eyebrow>
                    <span className="font-display text-[20px] font-semibold tracking-[-0.01em] text-text-primary transition-colors group-hover:text-coral">
                      {surface.title}
                    </span>
                    <span className="font-body text-[13px] italic text-text-tertiary">
                      {surface.question}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        </div>
      </section>

      {SURFACES.map((surface, i) => (
        <section
          key={surface.n}
          id={surface.tab}
          className={`border-b border-divider scroll-mt-24 ${
            i % 2 === 1 ? "bg-bg-elevated" : ""
          }`}
        >
          <div
            className={`mx-auto grid max-w-[1180px] items-start gap-14 px-6 py-20 md:px-10 lg:grid-cols-2 ${
              i % 2 === 1 ? "lg:[&>*:first-child]:order-2" : ""
            }`}
          >
            <div className="lg:sticky lg:top-28">
              <AppScreenshot tab={surface.tab} />
            </div>

            <div>
              <div className="flex items-baseline gap-4">
                <Eyebrow coral>{surface.n}</Eyebrow>
                <Eyebrow>{surface.question}</Eyebrow>
              </div>
              <h2 className="mt-4 font-display text-[clamp(36px,5vw,52px)] font-bold leading-[1.02] tracking-[-0.015em] text-text-primary">
                {surface.title}
              </h2>
              <p className="mt-5 max-w-[52ch] font-body text-[16px] leading-[1.65] text-text-secondary">
                {surface.lede}
              </p>

              <EditorialRule className="my-8" />

              <dl className="space-y-6">
                {surface.points.map(([term, detail]) => (
                  <div key={term}>
                    <dt className="font-display text-[18px] font-semibold tracking-[-0.005em] text-text-primary">
                      {term}
                    </dt>
                    <dd className="mt-1.5 max-w-[52ch] font-body text-[15px] leading-[1.6] text-text-secondary">
                      {detail}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>
          </div>
        </section>
      ))}

      <section className="border-b border-divider">
        <div className="mx-auto max-w-[820px] px-6 py-24 text-center md:px-10">
          <Eyebrow>And if you have a coach</Eyebrow>
          <h2 className="mt-5 font-display text-[clamp(30px,4.6vw,44px)] font-bold leading-[1.05] tracking-[-0.015em] text-text-primary">
            The plan layers in. The read stays yours.
          </h2>
          <p className="mx-auto mt-6 max-w-[52ch] font-body text-[16px] leading-[1.65] text-text-secondary">
            A coach-issued plan appears inside Train, next to what you
            actually ran. What the app notices about your training goes to
            your coach as observation — never as an instruction it carried out
            on their behalf.
          </p>
          <div className="mt-9 flex flex-wrap items-center justify-center gap-6">
            <Link
              href="/beta"
              className="rounded-[10px] bg-coral px-6 py-3.5 font-display text-[15px] font-semibold text-white transition-colors hover:bg-coral-dark"
            >
              Request an invite
            </Link>
            <ActionLink href="/principles">Read the principles</ActionLink>
          </div>
        </div>
      </section>
    </>
  );
}

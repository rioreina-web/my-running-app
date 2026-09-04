import Link from "next/link";
import { EditorialRule, EmptyState, Eyebrow, PlateStrip, Section, SheetChrome, Spacer } from "@/components/mockup/primitives";
import { FITNESS, GOAL, RACES } from "@/components/mockup/data";

/* Goals · what you are chasing, and what you already caught. Kept short. */

const COMPLETED = [
  { title: "Brooklyn Half · sub-1:40", sub: "May 16 · ran 1:37:52. Negative split.", date: "MAY 16, 2026" },
  { title: "Houston Marathon · sub-3:30", sub: "Jan 18 · ran 3:28:14. The anchor.", date: "JAN 18, 2026" },
  { title: "Five runs a week, all of March", sub: "22 of 22. The habit that started this.", date: "MAR 31, 2026" },
];

export default async function GoalsPage({ searchParams }: { searchParams: Promise<{ day?: string }> }) {
  const dayOne = (await searchParams).day === "1";
  const anchor = RACES.find((r) => r.anchor)!;

  if (dayOne) {
    return (
      <>
        <PlateStrip surface="GOALS · ACTIVE" fig="FIG. 31" />
        <div className="m-body">
          <SheetChrome back="/mockup/trends?day=1" backLabel="Trends" surface="GOALS" />

          <div className="m-section m-mt-14">
            <Eyebrow coral>GOALS</Eyebrow>
            <h1 className="m-display m-display--l">What you&rsquo;re chasing.</h1>
            <p className="m-body-sm">Kept short. Two is the right number.</p>
          </div>

          <Spacer h={16} />
          <EditorialRule />

          <EmptyState
            eyebrow="ACTIVE"
            nudge="No goal set yet. Pick a race and your paces, plan and predictions line up behind it."
            cta={{ label: "Set a goal race", href: "#" }}
          />

          <div className="m-listrow m-listrow--2 is-link">
            <div>
              <span className="m-listrow__label">Your race history is already here</span>
              <span className="m-listrow__hint">
                {anchor.name}, {anchor.time}. It anchors the numbers whether or not you set a goal.
              </span>
            </div>
            <Link href="/mockup/races?day=1" className="m-listrow__value is-coral">
              RACES ↗
            </Link>
          </div>

          <Section eyebrow="COMPLETED · 0">
            <EmptyState nudge="Goals you finish move here." quiet />
          </Section>

          <Spacer h={24} />
          <p className="m-body-sm">A goal is direction. A race you ran is what the paces are built on.</p>
        </div>
      </>
    );
  }

  return (
    <>
      <PlateStrip surface="GOALS · ACTIVE" fig="FIG. 31" />
      <div className="m-body">
        <SheetChrome back="/mockup/trends" backLabel="Trends" surface="GOALS" action={{ label: "+ Add ↗", href: "#" }} />

        <div className="m-section m-mt-14">
          <Eyebrow coral>GOALS</Eyebrow>
          <h1 className="m-display m-display--l">What you&rsquo;re chasing.</h1>
          <p className="m-quote m-quote--sub">Kept short. Two is the right number.</p>
        </div>

        <Section eyebrow="ACTIVE · 2">
          <div className="m-goal">
            <Eyebrow coral>{GOAL.daysOut} DAYS OUT</Eyebrow>
            <div className="m-goal__title">
              {GOAL.race} · {GOAL.time}
            </div>
            <p className="m-quote m-quote--sub m-mt-6">{GOAL.why}</p>
            <div className="m-strip m-strip--3 m-mt-14">
              <div className="m-strip__cell"><span className="m-strip__l">GOAL PACE</span><span className="m-strip__v m-strip__v--sm">7:29</span><span className="m-strip__s">/ MI</span></div>
              <div className="m-strip__cell"><span className="m-strip__l">FITNESS NOW</span><span className="m-strip__v m-strip__v--sm">{FITNESS.rangeLow} – {FITNESS.rangeHigh}</span><span className="m-strip__s">{FITNESS.confidence} CONFIDENCE</span></div>
              <div className="m-strip__cell"><span className="m-strip__l">ANCHOR</span><span className="m-strip__v m-strip__v--sm">{anchor.time}</span><span className="m-strip__s">HOUSTON · JAN</span></div>
            </div>
            <div className="m-goal__meta">{GOAL.dateUpper} · DIRECTION, NOT A GRADE</div>
            <div className="m-flex m-gap-16 m-mt-12">
              <Link href="/mockup/races" className="m-link m-link--sm">
                Race plan ↗
              </Link>
              <span className="m-link m-link--quiet m-link--sm">Edit</span>
            </div>
          </div>

          <div className="m-goal">
            <Eyebrow coral>THROUGH OCTOBER</Eyebrow>
            <div className="m-goal__title">Hold 45 or more, most weeks.</div>
            <p className="m-quote m-quote--sub m-mt-6">Volume that absorbs, not volume that impresses. Recovery weeks count.</p>
            <div className="m-goal__meta">3 OF 3 WEEKS SO FAR · 44.6 THIS WEEK</div>
          </div>
        </Section>

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow={`COMPLETED · ${COMPLETED.length}`}>
          <div className="m-mt-4">
            {COMPLETED.map((g) => (
              <div key={g.title} className="m-listrow m-listrow--2">
                <div>
                  <span className="m-listrow__label">{g.title}</span>
                  <span className="m-listrow__hint">{g.sub}</span>
                </div>
                <span className="m-listrow__value is-pos">DONE</span>
              </div>
            ))}
          </div>
        </Section>

        <Spacer h={24} />
        <p className="m-quote m-quote--faint">Your stated goal is yours. Coach shows you what the training is doing; it never grades the goal.</p>
      </div>
    </>
  );
}

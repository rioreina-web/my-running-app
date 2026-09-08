/* Athlete-site mockup · day one.

   The four tabs the morning after onboarding. Same athlete, same
   imported history — but nothing has been said yet, so there is no
   mood, no niggle, no goal and no plan.

   Two repo rules shape what these surfaces may say:
     · `data_depth` is 1 here (runs, but no voice logs and no goal), so
       the register stays plain — no pull-quotes, no trend prose.
     · Every genuinely empty cell states the absence and says what will
       fill it, with an imperative CTA. Never an em-dash (hard rule #8).

   The fitness range is wider and its confidence lower than week 5's,
   because fewer signals agree. That is the honest read, not a
   placeholder (hard rule #7). */

import Link from "next/link";
import { EditorialRule, EmptyState, Eyebrow, PlateStrip, Section, Spacer, StatTile } from "./primitives";
import { FitnessArc, VolumeBars } from "./charts";
import {
  ACWR,
  DAY_ONE,
  DAY_ONE_FITNESS,
  DAY_ONE_VOLUME,
  FITNESS_ARC,
  FITNESS_ARC_LABELS,
  FITNESS_ARC_MARKERS,
  RACES,
  WEEKLY_MILES,
} from "./data";

/** Predictions off race history alone: same math, wider bands. */
const DAY_ONE_PREDICTIONS = [
  { dist: "5K", name: "5K", range: "20:50 – 21:40", confidence: "LOW", basis: "Jul 4 effort, unconfirmed" },
  { dist: "10K", name: "10K", range: "43:20 – 45:00", confidence: "MEDIUM", basis: "Turkey Trot, Nov 2025" },
  { dist: "HALF", name: "Half", range: "1:35 – 1:39", confidence: "MEDIUM", basis: "Brooklyn Half, May 2026" },
  { dist: "FULL", name: "Marathon", range: "3:21 – 3:31", confidence: "LOW", basis: "Houston, Jan 2026" },
];

/** A tile-shaped empty state: label, plain nudge, imperative CTA. */
function EmptyTile({ label, nudge, cta }: { label: string; nudge: string; cta: { label: string; href: string } }) {
  return (
    <div className="m-tile">
      <div className="m-tile__label">{label}</div>
      <p className="m-body-sm">{nudge}</p>
      <Link href={cta.href} className="m-link m-link--mono is-coral">
        {cta.label} ↗
      </Link>
    </div>
  );
}

export function TrendsDayOne() {
  const anchor = RACES.find((r) => r.anchor)!;
  return (
    <>
      <PlateStrip surface="TRENDS · THE JOURNEY AS ANALYTICS" fig="FIG. 01" />
      <div className="m-body">
        <div className="m-section m-section--first">
          <div className="m-row">
            <Eyebrow coral>OPENING FIGURE</Eyebrow>
            <div className="m-period">
              <span className="m-period__opt is-active">26 WK</span>
              <span className="m-period__opt">YEAR</span>
              <span className="m-period__opt">2 YR</span>
            </div>
          </div>
          <h1 className="m-display m-display--l">The 5-second view.</h1>
          <p className="m-body-sm">
            {DAY_ONE.imported.months} months imported, {DAY_ONE.imported.races} races confirmed. Nothing logged in your
            own words yet.
          </p>
        </div>

        <div className="m-tiles m-mt-14">
          <StatTile
            label="FITNESS · MARATHON"
            value={`${DAY_ONE_FITNESS.rangeLow} – ${DAY_ONE_FITNESS.rangeHigh}`}
            delta={`${DAY_ONE_FITNESS.confidence} CONFIDENCE`}
            href="/mockup/races?day=1"
          />
          <StatTile label="VOLUME · 7D" value={DAY_ONE_VOLUME.last7} unit="MI" delta={DAY_ONE_VOLUME.note} />
          <StatTile label="LOAD · ACWR" value={ACWR.value} unit="RATIO" delta={ACWR.label} />
          <EmptyTile
            label="NIGGLES"
            nudge="Nothing mentioned yet. Body-part mentions come out of your voice memos."
            cta={{ label: "RECORD A MEMO", href: "/mockup/log?day=1" }}
          />
        </div>
        <p className="m-body-sm m-mt-10">
          The range is {DAY_ONE_FITNESS.basis}. It narrows as the quality work and the memos come in.
        </p>

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow="THE ARC · 26 WEEKS" eyebrowRight="RACES AS ANCHORS">
          <div className="m-card m-card--tight m-mt-6">
            <div className="m-row">
              <span className="m-caption m-caption--faint m-eyebrow--sm">MARATHON-EQUIVALENT · WEEKLY</span>
              <span className="m-caption m-caption--faint m-eyebrow--sm">HIGHER IS FITTER</span>
            </div>
            <div className="m-mt-8">
              <FitnessArc data={FITNESS_ARC} markers={FITNESS_ARC_MARKERS} />
            </div>
            <div className="m-chart__axis">
              {FITNESS_ARC_LABELS.map((l) => (
                <span key={l} className="m-caption m-caption--faint m-eyebrow--sm">
                  {l}
                </span>
              ))}
            </div>
            {/* The GOAL line is where a goal gets entered, so with none set
                it becomes the invitation rather than an empty row. */}
            <Link href="/mockup/goals?day=1" className="m-row m-mt-12">
              <span className="m-caption m-caption--faint">NO GOAL SET</span>
              <span className="m-caption m-caption--coral">SET A GOAL RACE ↗</span>
            </Link>
          </div>
          <p className="m-body-sm m-mt-8">
            Anchored on {anchor.name}, {anchor.date}. Your races drew this line before you logged a single run here.
          </p>
        </Section>

        <Section eyebrow="FITNESS · RACE PREDICTIONS" eyebrowRight="FROM RACE HISTORY">
          <div className="m-mt-6">
            {DAY_ONE_PREDICTIONS.map((p) => (
              <div key={p.dist} className="m-listrow m-listrow--3">
                <span className="m-caption">{p.dist}</span>
                <div>
                  <span className="m-listrow__label m-listrow__label--lg">{p.name}</span>
                  <span className="m-listrow__hint">{p.basis}</span>
                </div>
                <div>
                  <div className="m-listrow__value m-listrow__value--lg">{p.range}</div>
                  <div className="m-listrow__sub">{p.confidence} CONFIDENCE</div>
                </div>
              </div>
            ))}
          </div>
          <p className="m-body-sm m-mt-10">Wider bands than they will be. Fewer signals agree at this point.</p>
        </Section>

        <Section eyebrow="LOAD · WEEKLY VOLUME × ACWR" eyebrowRight="12 WEEKS">
          <div className="m-card m-card--tight m-mt-6">
            <VolumeBars data={WEEKLY_MILES} highlightLast={false} />
            <div className="m-row m-mt-6">
              <span className="m-caption m-caption--faint m-eyebrow--sm">JUN → SEP · MILES · IMPORTED</span>
              <span className="m-caption m-caption--faint m-eyebrow--sm">ACWR {ACWR.value}</span>
            </div>
          </div>
        </Section>

        <Section eyebrow="DRILL DOWN">
          <div className="m-mt-4">
            <Link href="/mockup/races?day=1" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Race history</span>
                <span className="m-listrow__hint">{RACES.length} confirmed · 1 detected, needs you</span>
              </div>
              <span className="m-listrow__value">VIEW</span>
            </Link>
            <Link href="/mockup/pace-chart" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Pace chart</span>
                <span className="m-listrow__hint">Already anchored on your 3:28</span>
              </div>
              <span className="m-listrow__value">VIEW</span>
            </Link>
            <Link href="/mockup/train?day=1" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Training history</span>
                <span className="m-listrow__hint">Pace × volume across the back-fill</span>
              </div>
              <span className="m-listrow__value">VIEW</span>
            </Link>
          </div>
        </Section>

        <Spacer h={40} />
      </div>
    </>
  );
}

export function CoachDayOne() {
  return (
    <>
      <PlateStrip surface="COACH · THE READ" fig="FIG. 14" />
      <div className="m-body">
        <div className="m-section m-section--first">
          <div className="m-row">
            <Eyebrow>COACH · ON DEMAND</Eyebrow>
            <Eyebrow>THU · SEP 3</Eyebrow>
          </div>
          <h1 className="m-display m-display--l m-mt-4">The read.</h1>
          <p className="m-body-sm m-mt-4">Observation, never prescription. You own the call.</p>
        </div>

        <Spacer h={16} />
        <EditorialRule />

        <EmptyState
          eyebrow="THE READ"
          nudge="Coach reads your memos and your training data together. There are no memos yet."
          cta={{ label: "Record your first voice log", href: "/mockup/log?day=1" }}
        />

        <p className="m-body-sm m-center">
          The data half is ready: {DAY_ONE.imported.workouts} workouts and {DAY_ONE.imported.races} races. The half only
          you can give is what you say after a run.
        </p>

        <Spacer h={24} />
        <EditorialRule />
        <Spacer h={16} />

        <Eyebrow>WHAT IT WILL READ</Eyebrow>
        <div className="m-mt-4">
          {[
            { l: "Both streams together", h: "What you said and what you ran, in one read." },
            { l: "Your life context", h: "Sleep, weather, work — when you mention it, it counts." },
            { l: "Patterns you might miss", h: "Mood arcs, niggle clusters, paces settling." },
            { l: "Lenses you ask for", h: "Compare cycles, read a week for recovery, check a niggle." },
          ].map((r) => (
            <div key={r.l} className="m-listrow m-listrow--2">
              <div>
                <span className="m-listrow__label">{r.l}</span>
                <span className="m-listrow__hint">{r.h}</span>
              </div>
              <span className="m-listrow__value m-faint">SOON</span>
            </div>
          ))}
        </div>

        <Spacer h={24} />
        <p className="m-body-sm">Nothing arrives uninvited. Coach only reads when you ask it to.</p>
        <Spacer h={24} />
      </div>
    </>
  );
}

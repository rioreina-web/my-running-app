import Link from "next/link";
import { EditorialRule, Eyebrow, PlateStrip, Section, Spacer, StatTile } from "@/components/mockup/primitives";
import { FitnessArc, VolumeBars } from "@/components/mockup/charts";
import {
  ACWR,
  FITNESS,
  FITNESS_ARC,
  FITNESS_ARC_GOAL,
  FITNESS_ARC_LABELS,
  FITNESS_ARC_MARKERS,
  GOAL,
  NIGGLES,
  RACES,
  VOLUME,
  WEEKLY_MILES,
} from "@/components/mockup/data";

/* Trends · the journey as analytics. The 5-second view.
   Race-anchored fitness range with confidence, volume, ACWR, niggles,
   the 26-week arc with races plotted as anchors, and the tappable GOAL
   line. Predictions are always range + confidence (hard rule #7). */

export default function TrendsPage() {
  const active = NIGGLES.filter((n) => n.status === "ACTIVE");
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
          <p className="m-quote m-quote--faint">September 3 · twenty-six weeks logged, two races inside them.</p>
        </div>

        <div className="m-tiles m-mt-14">
          <StatTile
            label="FITNESS · MARATHON"
            value={`${FITNESS.rangeLow} – ${FITNESS.rangeHigh}`}
            delta={`${FITNESS.confidence} CONFIDENCE · ${FITNESS.direction}`}
            tone="pos"
            href="/mockup/races"
          />
          <StatTile label="VOLUME · 7D" value={VOLUME.last7} unit="MI" delta={`${VOLUME.deltaVsAvg}  VS 4-WK AVG`} tone="pos" href="/mockup/train" />
          <StatTile label="LOAD · ACWR" value={ACWR.value} unit="RATIO" delta={ACWR.label} />
          <StatTile
            label="NIGGLES"
            value={String(active.length)}
            unit={active.length === 1 ? "ACTIVE" : "ACTIVE"}
            delta={active.length ? `${active[0].side} ${active[0].part.toUpperCase()} · ${active[0].mentions} MENTIONS · 14D` : "NONE MENTIONED"}
            tone={active.length ? "watch" : "neutral"}
            href="/mockup/niggles"
          />
        </div>
        <p className="m-quote m-quote--faint m-mt-10">Fitness is {FITNESS.basis}. The range is the honest part.</p>

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow="THE ARC · 26 WEEKS" eyebrowRight="RACES AS ANCHORS">
          <div className="m-card m-card--tight m-mt-6">
            <div className="m-row">
              <span className="m-caption m-caption--faint m-eyebrow--sm">MARATHON-EQUIVALENT · WEEKLY</span>
              <span className="m-caption m-caption--faint m-eyebrow--sm">HIGHER IS FITTER</span>
            </div>
            <div className="m-mt-8">
              <FitnessArc data={FITNESS_ARC} markers={FITNESS_ARC_MARKERS} goal={FITNESS_ARC_GOAL} />
            </div>
            <div className="m-chart__axis">
              {FITNESS_ARC_LABELS.map((l) => (
                <span key={l} className="m-caption m-caption--faint m-eyebrow--sm">
                  {l}
                </span>
              ))}
            </div>
            <Link href="/mockup/goals" className="m-row m-mt-12">
              <span className="m-caption m-caption--coral">GOAL · {GOAL.short} · {GOAL.time} · {GOAL.dateUpper}</span>
              <span className="m-caption m-caption--coral">EDIT ↗</span>
            </Link>
          </div>
          <p className="m-quote m-quote--faint m-mt-8">
            Anchored on {anchor.name}, {anchor.date}. The half in May and the July 5K pull the line where a plan never could.
          </p>
        </Section>

        <Section eyebrow="FITNESS · RACE PREDICTIONS" eyebrowRight="UPDATED TODAY">
          <div className="m-mt-6">
            {FITNESS.predictions.map((p) => (
              <div key={p.dist} className={`m-listrow m-listrow--3${p.goal ? " is-goal" : ""}`}>
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
          <p className="m-quote m-quote--faint m-mt-10">Ranges, never a finish time to the second. The seconds are math, not signal.</p>
        </Section>

        <Section eyebrow="LOAD · WEEKLY VOLUME × ACWR" eyebrowRight="12 WEEKS">
          <div className="m-card m-card--tight m-mt-6">
            <VolumeBars data={WEEKLY_MILES} />
            <div className="m-row m-mt-6">
              <span className="m-caption m-caption--faint m-eyebrow--sm">JUN → SEP · MILES</span>
              <span className="m-caption m-caption--coral m-eyebrow--sm">ACWR {ACWR.value} · {VOLUME.weeksAbove40} WEEKS ABOVE 40</span>
            </div>
          </div>
        </Section>

        <Section eyebrow="DRILL DOWN">
          <div className="m-mt-4">
            <Link href="/mockup/workouts/w-0901" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Last quality session</span>
                <span className="m-listrow__hint">SEP 1 · MP 6 · 9.0 mi</span>
              </div>
              <span className="m-listrow__value m-listrow__value--lg">7:38</span>
            </Link>
            <Link href="/mockup/niggles" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Niggles</span>
                <span className="m-listrow__hint">1 active · right hamstring</span>
              </div>
              <span className="m-listrow__value is-watch">WATCH</span>
            </Link>
            <Link href="/mockup/races" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Race history</span>
                <span className="m-listrow__hint">5 confirmed · 1 detected</span>
              </div>
              <span className="m-listrow__value">VIEW</span>
            </Link>
            <Link href="/mockup/train" className="m-listrow m-listrow--2 is-link">
              <div>
                <span className="m-listrow__label">↗ &nbsp;Training history</span>
                <span className="m-listrow__hint">Pace × volume · this build vs. Houston</span>
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

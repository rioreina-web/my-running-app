import Link from "next/link";
import { EditorialRule, Eyebrow, PlateStrip, Section, SheetChrome, Spacer } from "@/components/mockup/primitives";
import { GOAL, PACE_ZONES, RACES } from "@/components/mockup/data";

/* Pace chart · ten zones (3 effort + 7 race-pace), derived from the race
   anchor. Aerobic zones are ranges, race-pace zones exact targets. The
   goal column is the same math run off 3:16, shown as direction. */

export default function PaceChartPage() {
  const anchor = RACES.find((r) => r.anchor)!;
  return (
    <>
      <PlateStrip surface="TARGETS · PACE CHART" fig="FIG. 12" />
      <div className="m-body">
        <SheetChrome back="/mockup/train" backLabel="Train" surface="PACE CHART" />

        <div className="m-section m-mt-14">
          <Eyebrow coral>ANCHORED · {anchor.name.toUpperCase()} · {anchor.time}</Eyebrow>
          <h1 className="m-display m-display--l">Ten zones.</h1>
          <p className="m-quote m-quote--sub">Three by effort, seven by race pace. Your real race sets them; the goal only points.</p>
        </div>

        <Spacer h={16} />
        <div className="m-row">
          <span className="m-caption">ZONE</span>
          <div className="m-flex m-gap-16">
            <span className="m-caption m-caption--ink">ANCHOR</span>
            <span className="m-caption m-caption--faint">AT GOAL</span>
          </div>
        </div>
        <div className="m-hairline m-mt-8" />

        {PACE_ZONES.map((z, i) => (
          <div key={z.zone}>
            {i === 3 ? (
              <div className="m-mt-12">
                <Eyebrow faint sm>RACE-PACE · EXACT TARGETS</Eyebrow>
              </div>
            ) : null}
            {i === 0 ? (
              <div className="m-mt-12">
                <Eyebrow faint sm>EFFORT · RANGES</Eyebrow>
              </div>
            ) : null}
            <div className="m-listrow m-listrow--2">
              <div>
                <span className="m-listrow__label">{z.zone}</span>
                <span className="m-listrow__hint">{z.hint}</span>
              </div>
              <div className="m-flex m-gap-16 m-items-baseline">
                <span className="m-listrow__value m-listrow__value--lg m-nowrap">{z.anchor}</span>
                <span className="m-listrow__value m-faint m-nowrap">{z.goal}</span>
              </div>
            </div>
          </div>
        ))}

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow="HOW THESE ARE MADE">
          <p className="m-body-sm m-mt-4">
            Race-pace zones come from race-equivalence ratios off the anchor. Effort zones are percentages of marathon-pace speed.
            LT is the one-hour race pace, interpolated between 10K and half. Same math on iOS and web.
          </p>
          <p className="m-quote m-quote--faint m-mt-10">
            Goal {GOAL.time} would move MP to 7:29. It gets there by racing, not by editing the chart.
          </p>
        </Section>

        <Spacer h={20} />
        <div className="m-row">
          <Link href="/mockup/races" className="m-link m-link--mono">
            CHANGE ANCHOR ↗
          </Link>
          <span className="m-link m-link--mono">MINUTES PER KM</span>
        </div>
      </div>
    </>
  );
}

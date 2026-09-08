import Link from "next/link";
import { EditorialRule, Eyebrow, PlateStrip, Section, SheetChrome, Spacer, StripCell } from "@/components/mockup/primitives";
import { PaceShape } from "@/components/mockup/charts";
import { DAY_DETAILS, PACE_ZONES, THIS_WEEK } from "@/components/mockup/data";

/* Day detail · Plate 22. Today's prescription step by step: hero stats,
   pace shape, steps with target pace + HR zone + RPE, the template's
   note, and the action strip. Targets come from the anchored pace table. */

export default async function DayDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const detail = DAY_DETAILS[id] ?? DAY_DETAILS.thu;
  const day = THIS_WEEK.find((d) => d.id === id) ?? THIS_WEEK.find((d) => d.id === "thu")!;
  const zone = PACE_ZONES.find((z) => z.zone === day.zone);

  return (
    <>
      <PlateStrip surface="PLAN · DAY DETAIL" fig="FIG. 22" />
      <div className="m-body">
        <SheetChrome back="/mockup/train" backLabel="Train" surface="DAY DETAIL" fig="PLATE 22" />

        <div className="m-section m-mt-14">
          <Eyebrow coral>{detail.eyebrow}</Eyebrow>
          <h1 className="m-display m-display--l">{detail.title}</h1>
          <p className="m-quote m-quote--faint">{detail.subtitle}</p>
        </div>

        <Spacer h={16} />
        <div className="m-strip m-strip--4">
          {detail.stats.map((s) => (
            <StripCell key={s.l} l={s.l} v={s.v} u={s.u} s={s.s} />
          ))}
        </div>

        <Section eyebrow="PACE SHAPE" eyebrowRight={zone ? `${zone.zone.toUpperCase()} · ${zone.anchor} / MI` : undefined}>
          <div className="m-mt-6">
            <PaceShape shape={detail.shape} />
          </div>
        </Section>

        <Section eyebrow="THE SESSION" eyebrowRight={`${detail.steps.length} STEPS`}>
          <div className="m-mt-4">
            {detail.steps.map((s) => (
              <div key={s.n} className={`m-step${s.key ? " is-key" : ""}`}>
                <span className="m-step__n">{s.n}</span>
                <div>
                  <div className="m-step__name">{s.name}</div>
                  <div className="m-step__hint">{s.hint}</div>
                  <div className="m-step__targets">
                    <span className="m-step__target is-pace">
                      <span className="k">PACE</span>
                      <span className="v">{s.pace}</span>
                    </span>
                    <span className="m-step__target">
                      <span className="k">HR</span>
                      <span className="v">{s.hr}</span>
                    </span>
                    <span className="m-step__target">
                      <span className="k">RPE</span>
                      <span className="v">{s.rpe}</span>
                    </span>
                  </div>
                </div>
                <div className="m-step__rhs">
                  <div className="m-step__dist">{s.dist}</div>
                  <div className="m-step__dur">{s.dur}</div>
                </div>
              </div>
            ))}
          </div>
        </Section>

        <Spacer h={16} />
        <EditorialRule />

        <Section eyebrow="FROM THE TEMPLATE">
          <p className="m-quote m-quote--sub m-mt-4">{detail.note}</p>
        </Section>

        <Spacer h={24} />
        <div className="m-flex m-gap-16 m-items-baseline m-wrap">
          <Link href="/mockup/log" className="m-link">
            Mark complete ↗
          </Link>
          <span className="m-link m-link--quiet m-link--sm">Move day</span>
          <span className="m-link m-link--quiet m-link--sm">Swap for easy</span>
        </div>
        <p className="m-quote m-quote--faint m-mt-14">Marking complete opens the log so the memo and the data land together.</p>
      </div>
    </>
  );
}

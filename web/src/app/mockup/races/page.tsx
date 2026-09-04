import Link from "next/link";
import { EditorialRule, EmptyState, Eyebrow, PlateStrip, Section, SheetChrome, Spacer, StripCell } from "@/components/mockup/primitives";
import { DETECTED_RACE, FITNESS, GOAL, RACES } from "@/components/mockup/data";

/* Races · race history (confirmed_races), the anchor, a detected race
   waiting for confirmation, and the race plan for the one still to run.
   Race anchor beats goal time: reality anchors the zones, goal is direction. */

const RACE_PLAN = [
  { n: "01", name: "Miles 1–6 · settle", meta: "7:34 – 7:38 / MI", note: "Slower than feels right. The crowd will pull; let it go." },
  { n: "02", name: "Miles 7–18 · rhythm", meta: "7:29 / MI · GOAL PACE", note: "Even. Fuel every 5 miles. Nothing heroic." },
  { n: "03", name: "Miles 19–24 · the work", meta: "7:27 – 7:31 / MI", note: "This is where Houston faded. Stay in the mile you are in." },
  { n: "04", name: "Miles 25–26.2 · home", meta: "WHATEVER IS LEFT", note: "Downhill into Sacramento. Empty it." },
];

export default async function RacesPage({ searchParams }: { searchParams: Promise<{ day?: string }> }) {
  const dayOne = (await searchParams).day === "1";
  return (
    <>
      <PlateStrip surface="RACES · HISTORY + THE NEXT ONE" fig="FIG. 33" />
      <div className="m-body">
        <SheetChrome
          back={dayOne ? "/mockup/trends?day=1" : "/mockup/trends"}
          backLabel="Trends"
          surface="RACES"
          action={{ label: "+ Add ↗", href: "#" }}
        />

        {dayOne ? (
          <>
            <div className="m-section m-mt-14">
              <Eyebrow coral>NOTHING ON THE CALENDAR</Eyebrow>
              <h1 className="m-display m-display--l">Your races.</h1>
              <p className="m-body-sm">Imported from Apple Health. Confirm the ones that were races.</p>
            </div>
            <Spacer h={16} />
            <EmptyState
              eyebrow="NEXT RACE"
              nudge="No upcoming race yet. Set one and your plan, paces and predictions line up behind it."
              cta={{ label: "Set a goal race", href: "#" }}
            />
          </>
        ) : (
          <>
            <div className="m-section m-mt-14">
              <Eyebrow coral>NEXT · {GOAL.daysOut} DAYS OUT</Eyebrow>
              <h1 className="m-display m-display--l">{GOAL.race}.</h1>
              <p className="m-quote m-quote--sub">
                {GOAL.date} · Folsom to Sacramento · goal {GOAL.time}.
              </p>
            </div>

            <Spacer h={16} />
            <div className="m-strip m-strip--4">
              <StripCell l="GOAL" v="3:16" s="7:29 / MI" center />
              <StripCell
                l="FITNESS NOW"
                v={`${FITNESS.rangeLow}–${FITNESS.rangeHigh}`}
                s={`${FITNESS.confidence} CONF.`}
                center
              />
              <StripCell l="WEEKS LEFT" v="13" s="OF 18" center />
              <StripCell l="LONG RUNS" v="9" s="16 MI +" center />
            </div>

            <Section eyebrow="RACE PLAN · A DRAFT TO EDIT" eyebrowRight="FROM THE TEMPLATE">
              <div className="m-mt-4">
                {RACE_PLAN.map((p) => (
                  <div key={p.n} className="m-step">
                    <span className="m-step__n">{p.n}</span>
                    <div>
                      <div className="m-step__name">{p.name}</div>
                      <div className="m-caption m-caption--faint m-mt-4">{p.meta}</div>
                      <div className="m-step__hint">{p.note}</div>
                    </div>
                    <span />
                  </div>
                ))}
              </div>
              <p className="m-quote m-quote--faint m-mt-8">Splits are the goal-time math. Nothing here is a prediction.</p>
            </Section>
          </>
        )}

        <Spacer h={20} />
        <EditorialRule />

        <Section eyebrow={`RACE HISTORY · ${RACES.length} CONFIRMED`} eyebrowRight="2 YEARS">
          <div className="m-mt-4">
            {RACES.map((r) => (
              <div key={r.id} className={`m-listrow m-listrow--3${r.anchor ? " is-goal" : ""}`}>
                <span className="m-caption">{r.distance.toUpperCase()}</span>
                <div>
                  <span className="m-listrow__label m-listrow__label--lg">{r.name}</span>
                  <span className="m-listrow__hint">
                    {r.dateUpper} · {r.pace}
                    {r.official ? " · OFFICIAL" : " · UNOFFICIAL"}
                    {r.anchor ? " · ANCHOR" : ""}
                  </span>
                  <span className="m-listrow__hint">{r.note}</span>
                </div>
                <div>
                  <div className="m-listrow__value m-listrow__value--lg">{r.time}</div>
                  {r.anchor ? <div className="m-listrow__sub">SETS YOUR ZONES</div> : null}
                </div>
              </div>
            ))}
          </div>
        </Section>

        <Section eyebrow="DETECTED · NEEDS YOU" eyebrowCoral>
          <div className="m-card m-mt-6">
            <div className="m-row">
              <span className="m-display m-display--s">{DETECTED_RACE.guess}.</span>
              <span className="m-listrow__value m-listrow__value--lg">{DETECTED_RACE.time}</span>
            </div>
            <div className="m-caption m-caption--faint m-mt-6">
              {DETECTED_RACE.dateUpper} · {DETECTED_RACE.pace} · FROM APPLE HEALTH
            </div>
            <p className="m-quote m-quote--sub m-mt-10">Was this a race? Confirmed races anchor your fitness read. Workouts do not.</p>
            <div className="m-flex m-gap-16 m-mt-12">
              <span className="m-link m-link--sm">Confirm as a race ↗</span>
              <span className="m-link m-link--quiet m-link--sm">Just a workout</span>
            </div>
          </div>
        </Section>

        <Spacer h={24} />
        <div className="m-row">
          <span className="m-caption m-caption--faint">ANCHOR PRIORITY · RACE BEATS GOAL</span>
          <Link href="/mockup/pace-chart" className="m-link m-link--mono">
            PACE CHART ↗
          </Link>
        </div>
      </div>
    </>
  );
}

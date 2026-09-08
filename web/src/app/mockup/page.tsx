import Link from "next/link";
import { EditorialRule, Eyebrow, PlateStrip, Spacer } from "@/components/mockup/primitives";
import { ATHLETE, GOAL, SITE_MAP, TODAY } from "@/components/mockup/data";

/* /mockup — the site map. Every athlete-facing surface in one index so a
   reviewer can walk the whole product without knowing the routes. */

export default function MockupIndex() {
  const offsets = SITE_MAP.map((_, gi) => SITE_MAP.slice(0, gi).reduce((sum, g) => sum + g.items.length, 0));
  return (
    <>
      <PlateStrip surface="SITE MAP · ATHLETE MOCKUP" fig="FIG. 00" />
      <div className="m-body">
        <div className="m-section m-section--first">
          <Eyebrow coral>ATHLETE SITE · MOCKUP</Eyebrow>
          <h1 className="m-display m-display--l">The athlete site, end to end.</h1>
          <p className="m-quote m-quote--sub">
            Every screen a self-coached runner touches, built to read like the app. Static data, one story.
          </p>
        </div>

        <Spacer h={20} />
        <EditorialRule />
        <Spacer h={16} />

        <div className="m-strip m-strip--3 m-strip--noborder-top">
          <div className="m-strip__cell">
            <span className="m-strip__l">THE ATHLETE</span>
            <span className="m-strip__v m-strip__v--sm">{ATHLETE.firstName}</span>
            <span className="m-strip__s">SELF-COACHED · 3:28 PB</span>
          </div>
          <div className="m-strip__cell">
            <span className="m-strip__l">TODAY</span>
            <span className="m-strip__v m-strip__v--sm">{TODAY.dateUpper}</span>
            <span className="m-strip__s">{TODAY.weekday} · WK 05 OF 18</span>
          </div>
          <div className="m-strip__cell">
            <span className="m-strip__l">CHASING</span>
            <span className="m-strip__v m-strip__v--sm">{GOAL.time}</span>
            <span className="m-strip__s">{GOAL.short} · {GOAL.daysOut} DAYS OUT</span>
          </div>
        </div>

        <Spacer h={24} />

        <div className="m-map">
          {SITE_MAP.map((g, gi) => (
            <div key={g.group}>
              <div className="m-rail__grouphead">
                <span>{g.group}</span>
                <span className="ln" />
              </div>
              {g.items.map((it, ii) => {
                const n = offsets[gi] + ii + 1;
                return (
                  <Link key={it.href} href={it.href} className="m-map__item">
                    <span className="m-rail__num">{String(n).padStart(2, "0")}</span>
                    <span>
                      <span className="m-menu__label m-block">{it.label}</span>
                      <span className="m-menu__hint m-block">{it.hint}</span>
                    </span>
                    <span className="m-rail__arrow">↗</span>
                  </Link>
                );
              })}
            </div>
          ))}
        </div>

        <Spacer h={32} />
        <EditorialRule />
        <Spacer h={16} />
        <Eyebrow faint>HOW TO READ THIS</Eyebrow>
        <p className="m-body-sm m-mt-8">
          Four tabs carry the product: Log is input, Trends is overview, Train is detail, Coach is synthesis. The
          index in the menu holds everything that is not a tab. Nothing here is wired to an account; the data module
          documents which table each surface would read from.
        </p>
        <Spacer h={12} />
        <div className="m-frame-note">Resize the window: under 900px the site collapses to the phone layout with a bottom tab bar.</div>
      </div>
    </>
  );
}

import { EditorialRule, Eyebrow, PlateStrip, Quoted, SheetChrome, Spacer } from "@/components/mockup/primitives";
import { NIGGLES } from "@/components/mockup/data";

/* Niggles · body-part mentions from voice memos. Closed vocabulary,
   quoted verbatim, surfaced never interpreted. Detection, not diagnosis. */

export default function NigglesPage() {
  const active = NIGGLES.filter((n) => n.status === "ACTIVE").length;
  return (
    <>
      <PlateStrip surface="NIGGLES · LIVING LOG" fig="FIG. 28" />
      <div className="m-body">
        <SheetChrome back="/mockup/trends" backLabel="Trends" surface="NIGGLES" action={{ label: "+ Add", href: "/mockup/log" }} />

        <div className="m-section m-mt-14">
          <Eyebrow coral>TRACKING NOW · {active}</Eyebrow>
          <h1 className="m-display m-display--l">Niggles.</h1>
          <p className="m-quote m-quote--sub">Not medical advice. If anything gets sharper, see a clinician.</p>
        </div>

        <Spacer h={16} />
        <EditorialRule />

        {NIGGLES.map((n) => (
          <div key={n.id} className="m-niggle">
            <div className="m-row">
              <span className="m-niggle__name">
                {n.side.charAt(0) + n.side.slice(1).toLowerCase()} {n.part.toLowerCase()}
              </span>
              <span className={`m-niggle__score${n.status === "QUIET" ? " is-quiet" : ""}`}>{n.mentions}× · {n.days}D</span>
            </div>
            <div className="m-niggle__meta">
              <span>{n.side}</span>
              <span>·</span>
              <span>{n.status}</span>
              <span>·</span>
              <span>LAST {n.lastDate}</span>
            </div>

            <div>
              <div className="m-caption m-eyebrow--sm m-mt-8">MENTIONS · LAST 14 DAYS</div>
              <div className="m-dotline">
                {n.dots14.map((on, i) => (
                  <span key={i} className={on ? "on" : ""} />
                ))}
              </div>
            </div>

            <div className="m-mt-4">
              <div className="m-caption m-eyebrow--sm">LAST MENTIONED</div>
              <p className="m-quote m-mt-4">
                <Quoted>{n.lastQuote}</Quoted>
              </p>
              <div className="m-caption m-caption--faint m-mt-6">{n.firstLine}</div>
            </div>

            <div className="m-mt-8">
              <div className="m-caption m-eyebrow--sm">TIMELINE · WHAT YOU SAID, AFTER WHAT</div>
              <div className="m-timeline">
                {n.timeline.map((t) => (
                  <div key={t.date} className="m-timeline__row">
                    <span className="m-caption m-caption--ink">{t.date}</span>
                    <div>
                      <div className="m-caption m-caption--faint">{t.after.toUpperCase()}</div>
                      <p className="m-quote m-quote--sub m-mt-4">
                        <Quoted>{t.quote}</Quoted>
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <div className="m-flex m-gap-16 m-mt-8">
              <span className="m-link m-link--quiet m-link--sm">Mark resolved</span>
              <span className="m-link m-link--quiet m-link--sm">Ask Coach about it</span>
            </div>
          </div>
        ))}

        <Spacer h={16} />
        <p className="m-quote m-quote--faint">
          The system reports what was said and where. It never says what that means.
        </p>
        <Spacer h={24} />
      </div>
    </>
  );
}

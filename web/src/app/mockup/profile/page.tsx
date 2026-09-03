import { EditorialRule, Eyebrow, PlateStrip, SheetChrome, Spacer } from "@/components/mockup/primitives";
import { ATHLETE, FITNESS, NIGGLES, PROFILE, RACES } from "@/components/mockup/data";

/* Profile · the athlete, derived nightly from the data. */

export default function ProfilePage() {
  const anchor = RACES.find((r) => r.anchor)!;
  const active = NIGGLES.filter((n) => n.status === "ACTIVE");
  return (
    <>
      <PlateStrip surface="PROFILE · ATHLETE" fig="FIG. 40" />
      <div className="m-body">
        <SheetChrome back="/mockup/log" backLabel="Back" surface="PROFILE" />

        <div className="m-section m-mt-14">
          <Eyebrow coral>YOUR PROFILE</Eyebrow>
          <h1 className="m-display m-display--l">{ATHLETE.firstName}.</h1>
          <p className="m-quote m-quote--faint">Derived from 168 runs across 26 weeks. Updates overnight.</p>
        </div>

        <Spacer h={16} />
        <EditorialRule />

        <div className="m-mt-18">
          <Eyebrow>VOLUME</Eyebrow>
          <div className="m-ptiles">
            <div className="m-ptile">
              <div className="m-ptile__label">WEEKLY AVG · 12W</div>
              <div className="m-ptile__value">{PROFILE.weeklyAvg}<span>MI</span></div>
              <div className="m-ptile__sub">{PROFILE.weeklyDelta}</div>
            </div>
            <div className="m-ptile">
              <div className="m-ptile__label">LONGEST RUN</div>
              <div className="m-ptile__value">{PROFILE.longest}<span>MI</span></div>
              <div className="m-ptile__sub">{PROFILE.longestWhen}</div>
            </div>
          </div>
        </div>

        <div className="m-mt-18">
          <Eyebrow>PACE PROFILE</Eyebrow>
          <div className="m-ptiles">
            <div className="m-ptile">
              <div className="m-ptile__label">EASY AVG</div>
              <div className="m-ptile__value">{PROFILE.easyAvg}<span>/ MI</span></div>
              <div className="m-ptile__sub">{PROFILE.easyHr}</div>
            </div>
            <div className="m-ptile">
              <div className="m-ptile__label">MP SESSIONS · AVG</div>
              <div className="m-ptile__value">{PROFILE.mpAvg}<span>/ MI</span></div>
              <div className="m-ptile__sub">{PROFILE.mpDelta}</div>
            </div>
          </div>
        </div>

        <div className="m-mt-18">
          <Eyebrow>FITNESS</Eyebrow>
          <div className="m-ptiles">
            <div className="m-ptile">
              <div className="m-ptile__label">MARATHON · RANGE</div>
              <div className="m-ptile__value">{FITNESS.rangeLow}–{FITNESS.rangeHigh}</div>
              <div className="m-ptile__sub">{FITNESS.confidence} CONFIDENCE</div>
            </div>
            <div className="m-ptile">
              <div className="m-ptile__label">ANCHOR RACE</div>
              <div className="m-ptile__value">{anchor.time}</div>
              <div className="m-ptile__sub">{anchor.dateUpper}</div>
            </div>
          </div>
        </div>

        <div className="m-mt-18">
          <Eyebrow>NIGGLES</Eyebrow>
          <div className="m-ptiles">
            <div className="m-ptile">
              <div className="m-ptile__label">ACTIVE</div>
              <div className="m-ptile__value">{active.length}</div>
              <div className="m-ptile__sub">{active.map((n) => `${n.side.charAt(0)} ${n.part}`).join(" · ").toUpperCase() || "NONE"}</div>
            </div>
            <div className="m-ptile">
              <div className="m-ptile__label">MENTIONS · 26W</div>
              <div className="m-ptile__value">5</div>
              <div className="m-ptile__sub">2 BODY PARTS</div>
            </div>
          </div>
        </div>

        <div className="m-mt-18">
          <Eyebrow>RECOVERY · PREFERENCES</Eyebrow>
          <div className="m-mt-4">
            {[
              { l: "Average sleep · 14d", h: "Synced from Apple Health.", v: PROFILE.sleep },
              { l: "Resting HR · 14d", h: "Median morning heart rate.", v: PROFILE.rhr },
              { l: "Long-run day", h: "Where the week anchors its volume.", v: ATHLETE.longRunDay.toUpperCase() },
              { l: "Surface", h: "Road / track / trail split.", v: PROFILE.surface },
            ].map((r) => (
              <div key={r.l} className="m-listrow m-listrow--2">
                <div>
                  <span className="m-listrow__label">{r.l}</span>
                  <span className="m-listrow__hint">{r.h}</span>
                </div>
                <span className="m-listrow__value">{r.v}</span>
              </div>
            ))}
          </div>
        </div>

        <Spacer h={24} />
        <p className="m-quote m-quote--faint">This profile is computed nightly. Edit a run and it catches up by morning.</p>
      </div>
    </>
  );
}

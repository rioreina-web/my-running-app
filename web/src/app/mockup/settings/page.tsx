import Link from "next/link";
import { Eyebrow, PlateStrip, SheetChrome, Spacer } from "@/components/mockup/primitives";
import { SETTINGS_SECTIONS } from "@/components/mockup/data";

/* Settings · every knob the app exposes. Nothing hidden in menus. */

export default function SettingsPage() {
  return (
    <>
      <PlateStrip surface="SETTINGS" fig="FIG. 41" />
      <div className="m-body">
        <SheetChrome back="/mockup/log" backLabel="Back" surface="SETTINGS" />

        <div className="m-section m-mt-14">
          <Eyebrow coral>PREFERENCES</Eyebrow>
          <h1 className="m-display m-display--l">Settings.</h1>
          <p className="m-quote m-quote--sub">Every knob the app exposes. Nothing hidden in menus.</p>
        </div>

        {SETTINGS_SECTIONS.map((s) => (
          <div key={s.title} className="m-mt-24">
            <Eyebrow>{s.title.toUpperCase()}</Eyebrow>
            <div className="m-mt-4">
              {s.rows.map((r) => (
                <div key={r.l} className="m-listrow m-listrow--2 is-link">
                  <div>
                    <span className="m-listrow__label">{r.l}</span>
                    <span className="m-listrow__hint">{r.hint}</span>
                  </div>
                  <span className={`m-listrow__value${"coral" in r && r.coral ? " is-coral" : ""}`}>{r.v}</span>
                </div>
              ))}
            </div>
          </div>
        ))}

        <Spacer h={32} />
        <div className="m-hairline" />
        <div className="m-center m-mt-18">
          <Link href="/mockup/sign-in" className="m-link m-link--quiet m-link--sm">
            Sign out
          </Link>
          <div className="m-caption m-caption--faint m-eyebrow--sm m-mt-18">POST RUN DRIP · ATHLETE SITE MOCKUP · SEP 2026</div>
        </div>
      </div>
    </>
  );
}

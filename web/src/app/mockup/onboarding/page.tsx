"use client";

import Link from "next/link";
import { useState } from "react";
import { EditorialRule, Eyebrow } from "@/components/mockup/primitives";
import { RACES } from "@/components/mockup/data";

/* Onboarding · four steps, editorial mode (OnboardingScreen.jsx).
     1 Welcome  ·  2 Connect data (2-year HealthKit back-fill)
     3 Your races (auto-detected, confirm) + optional goal  ·  4 Ready.
   Maya lands in a product that already knows her. */

const DISTANCES = ["MARATHON", "HALF", "10K", "5K"];

export default function OnboardingPage() {
  const [step, setStep] = useState(0);
  const [health, setHealth] = useState(false);
  const [strava, setStrava] = useState(false);
  const [confirmed, setConfirmed] = useState<Record<string, boolean>>({});
  const [distance, setDistance] = useState("MARATHON");
  const [hh, setHh] = useState("3");
  const [mm, setMm] = useState("16");

  const detected = RACES;
  const next = () => setStep((s) => Math.min(3, s + 1));
  const back = () => setStep((s) => Math.max(0, s - 1));

  return (
    <div className="m-onb">
      <div className="m-onb__progress" aria-label={`Step ${step + 1} of 4`}>
        {[0, 1, 2, 3].map((i) => (
          <span key={i} className={i <= step ? "is-on" : ""} />
        ))}
      </div>

      <div className="m-onb__body">
        {step === 0 ? (
          <>
            <Eyebrow coral>WELCOME · 1 OF 4</Eyebrow>
            <h1 className="m-display m-display--xl m-mt-6">A running log that reads like a story.</h1>
            <p className="m-quote m-quote--sub m-mt-12">
              Say how the run felt. The data fills itself in. Coach reads both together, and never tells you what to do.
            </p>
            <div className="m-mt-24">
              {[
                { n: "01", t: "Log by voice.", d: "Tap, talk, done. Mood and body mentions come out of your own words." },
                { n: "02", t: "See the arc.", d: "Fitness as a range with confidence, anchored on races you actually ran." },
                { n: "03", t: "Get a read, not a plan.", d: "Coach observes, asks a question or two, and hands the call back to you." },
              ].map((f) => (
                <div key={f.n} className="m-onb__feature">
                  <span className="m-onb__num">{f.n}</span>
                  <div>
                    <div className="m-onb__ftitle">{f.t}</div>
                    <div className="m-onb__fdesc">{f.d}</div>
                  </div>
                </div>
              ))}
            </div>
          </>
        ) : null}

        {step === 1 ? (
          <>
            <Eyebrow coral>CONNECT · 2 OF 4</Eyebrow>
            <h1 className="m-display m-display--xl m-mt-6">Bring the last two years.</h1>
            <p className="m-quote m-quote--sub m-mt-12">
              Runs, sleep, strength sessions, cross-training. The back-fill runs once, then everything stays in sync.
            </p>
            <div className="m-mt-24">
              <button type="button" className="m-onb__row" onClick={() => setHealth((v) => !v)}>
                <span>
                  <span className="m-listrow__label m-block">Apple Health</span>
                  <span className="m-listrow__hint">Two-year back-fill. Races get detected from it.</span>
                </span>
                <span className={`m-onb__action${health ? " is-on" : ""}`}>{health ? "Connected" : "Connect"}</span>
              </button>
              <button type="button" className="m-onb__row" onClick={() => setStrava((v) => !v)}>
                <span>
                  <span className="m-listrow__label m-block">Strava</span>
                  <span className="m-listrow__hint">Optional. For runs that live there instead.</span>
                </span>
                <span className={`m-onb__action${strava ? " is-on" : ""}`}>{strava ? "Connected" : "Connect"}</span>
              </button>
            </div>
            {health ? (
              <p className="m-quote m-quote--faint m-mt-14">Importing 24 months · 412 workouts · 5 races found.</p>
            ) : null}
          </>
        ) : null}

        {step === 2 ? (
          <>
            <Eyebrow coral>YOUR RACES · 3 OF 4</Eyebrow>
            <h1 className="m-display m-display--xl m-mt-6">Five efforts look like races.</h1>
            <p className="m-quote m-quote--sub m-mt-12">
              Confirm the ones that were. They anchor your pace zones and your fitness read. Goal time is direction; a race is reality.
            </p>
            <div className="m-mt-18">
              {detected.map((r) => {
                const on = confirmed[r.id];
                return (
                  <button
                    type="button"
                    key={r.id}
                    className="m-onb__row"
                    onClick={() => setConfirmed((c) => ({ ...c, [r.id]: !c[r.id] }))}
                  >
                    <span>
                      <span className="m-listrow__label m-block">
                        {r.name} · {r.time}
                      </span>
                      <span className="m-listrow__hint">
                        {r.dateUpper} · {r.distance} · {r.pace}
                      </span>
                    </span>
                    <span className={`m-onb__action${on ? " is-on" : ""}`}>{on ? "Confirmed" : "Confirm"}</span>
                  </button>
                );
              })}
            </div>

            <div className="m-mt-24">
              <EditorialRule />
            </div>
            <div className="m-mt-18">
              <Eyebrow>A GOAL · OPTIONAL</Eyebrow>
              <div className="m-chips m-mt-12">
                {DISTANCES.map((d) => (
                  <button type="button" key={d} className={`m-chip${distance === d ? " is-active" : ""}`} onClick={() => setDistance(d)}>
                    {d}
                  </button>
                ))}
              </div>
              <div className="m-time">
                <label className="m-time__col">
                  <select value={hh} onChange={(e) => setHh(e.target.value)} aria-label="Hours">
                    {["2", "3", "4", "5"].map((h) => (
                      <option key={h} value={h}>{h}</option>
                    ))}
                  </select>
                  <span>H</span>
                </label>
                <span className="m-time__sep">:</span>
                <label className="m-time__col">
                  <select value={mm} onChange={(e) => setMm(e.target.value)} aria-label="Minutes">
                    {Array.from({ length: 12 }, (_, i) => String(i * 5).padStart(2, "0")).map((m) => (
                      <option key={m} value={m}>{m}</option>
                    ))}
                  </select>
                  <span>MIN</span>
                </label>
                <span className="m-time__sep">:</span>
                <div className="m-time__col">
                  <select defaultValue="00" aria-label="Seconds">
                    <option value="00">00</option>
                  </select>
                  <span>SEC</span>
                </div>
              </div>
            </div>
          </>
        ) : null}

        {step === 3 ? (
          <>
            <Eyebrow coral>READY · 4 OF 4</Eyebrow>
            <h1 className="m-display m-display--xl m-mt-6">Everything is here.</h1>
            <p className="m-quote m-quote--sub m-mt-12">
              Two years of running, five races confirmed, a {hh}:{mm} {distance.toLowerCase()} in December. Log opens on the record button. Talk after your next run.
            </p>
            <div className="m-mt-24">
              <div className="m-strip m-strip--3">
                <div className="m-strip__cell"><span className="m-strip__l">WORKOUTS</span><span className="m-strip__v">412</span><span className="m-strip__s">24 MONTHS</span></div>
                <div className="m-strip__cell"><span className="m-strip__l">RACES</span><span className="m-strip__v">{Object.values(confirmed).filter(Boolean).length || 5}</span><span className="m-strip__s">CONFIRMED</span></div>
                <div className="m-strip__cell"><span className="m-strip__l">ANCHOR</span><span className="m-strip__v">3:28</span><span className="m-strip__s">HOUSTON · JAN</span></div>
              </div>
            </div>
          </>
        ) : null}
      </div>

      <div className="m-onb__foot">
        {step < 3 ? (
          <button type="button" className="m-btn m-btn--primary" onClick={next}>
            {step === 0 ? "Get started" : step === 1 ? (health ? "Continue" : "Continue without connecting") : "Continue"}
          </button>
        ) : (
          <Link href="/mockup/log" className="m-btn m-btn--primary">
            Open the log
          </Link>
        )}
        <div className="m-row">
          {step > 0 ? (
            <button type="button" className="m-link m-link--quiet m-link--sm" onClick={back}>
              Back
            </button>
          ) : (
            <Link href="/mockup/sign-in" className="m-link m-link--quiet m-link--sm">
              I have an account
            </Link>
          )}
          {step < 3 ? (
            <Link href="/mockup/log" className="m-link m-link--quiet m-link--sm">
              Skip for now
            </Link>
          ) : (
            <span />
          )}
        </div>
      </div>
    </div>
  );
}

"use client";

import { useState } from "react";
import { EditorialRule, Eyebrow, Spacer } from "@/components/mockup/primitives";
import { COACH_LENSES, COACH_LENS_ANSWERS, COACH_READ, PAST_READS } from "@/components/mockup/data";

/* Coach · The Read, on demand. Minimal format: eyebrow date + headline +
   2–4 observation sentences + italic soft questions. Feeling first,
   warm encouragement, life context read, anchors carried silently,
   never a directive. Maya can ask for a specific lens. */

type Read = { eyebrow: string; headline: string; paragraph: string; questions: string[]; sources: string };

const FALLBACK: Omit<Read, "eyebrow" | "sources"> = {
  headline: "Reading that lens.",
  paragraph:
    "Coach would read your last fourteen days through that question here, memos and workouts together. In this mockup the four suggested lenses carry sample reads; anything else lands on this placeholder.",
  questions: ["What made you ask that today?"],
};

export function CoachRead() {
  const [state, setState] = useState<"idle" | "reading" | "done">("idle");
  const [read, setRead] = useState<Read | null>(null);
  const [input, setInput] = useState("");

  const generate = (lens?: string) => {
    setState("reading");
    setTimeout(() => {
      const base = lens ? COACH_LENS_ANSWERS[lens] ?? FALLBACK : COACH_READ;
      setRead({
        eyebrow: lens ? `THURSDAY · SEP 3 · THROUGH A LENS` : COACH_READ.eyebrow,
        headline: base.headline,
        paragraph: base.paragraph,
        questions: base.questions,
        sources: COACH_READ.sources,
      });
      setState("done");
    }, 900);
  };

  return (
    <>
      {state === "idle" ? (
        <div className="m-generate">
          <h2 className="m-display m-display--m m-center">Ready when you are.</h2>
          <p className="m-quote m-quote--sub m-center">
            Coach reads the last two weeks, memos and workouts together, and hands you a few observations. Nothing arrives uninvited.
          </p>
          <button className="m-generate__btn" onClick={() => generate()}>
            Generate today&rsquo;s read
          </button>
          <span className="m-caption m-caption--faint">{COACH_READ.sources}</span>
        </div>
      ) : null}

      {state === "reading" ? (
        <div className="m-generate">
          <span className="m-caption m-caption--coral">READING · 14 DAYS · 9 RUNS · 7 MEMOS</span>
          <p className="m-quote m-quote--faint m-center">Feeling first. Then the workouts. Then the mileage.</p>
        </div>
      ) : null}

      {state === "done" && read ? (
        <div className="m-read">
          <Eyebrow coral>{read.eyebrow}</Eyebrow>
          <h2 className="m-display m-display--l m-mt-8">{read.headline}</h2>
          <p className="m-read__para">{read.paragraph}</p>
          {read.questions.map((q) => (
            <p key={q} className="m-read__q">
              {q}
            </p>
          ))}
          <div className="m-row m-mt-18">
            <span className="m-caption m-caption--faint">{read.sources}</span>
            <button className="m-link m-link--mono" onClick={() => generate()}>
              READ AGAIN ↗
            </button>
          </div>
        </div>
      ) : null}

      <Spacer h={24} />
      <EditorialRule />
      <Spacer h={16} />

      <Eyebrow>ASK FOR A LENS</Eyebrow>
      <div className="m-chips m-mt-10">
        {COACH_LENSES.map((l) => (
          <button key={l} className="m-chip m-chip--serif" onClick={() => generate(l)}>
            {l}
          </button>
        ))}
      </div>
      <form
        className="m-coach-input m-mt-12"
        onSubmit={(e) => {
          e.preventDefault();
          if (!input.trim()) return;
          generate(input.trim());
          setInput("");
        }}
      >
        <input className="m-field m-field--pill" placeholder="Read my journey through…" value={input} onChange={(e) => setInput(e.target.value)} />
        <button type="submit" className="m-send" aria-label="Ask">
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M2 8L13 2.5L9.5 8L13 13.5L2 8Z" />
          </svg>
        </button>
      </form>
      <p className="m-quote m-quote--faint m-mt-10">Coach observes and asks. It never prescribes, diagnoses, or tells you to stop.</p>

      <Spacer h={24} />
      <EditorialRule />
      <Spacer h={16} />

      <Eyebrow>PAST READS</Eyebrow>
      <div className="m-mt-4">
        {PAST_READS.map((r) => (
          <div key={r.date} className="m-listrow m-listrow--2 is-link">
            <div>
              <span className="m-listrow__label">{r.headline}</span>
              <span className="m-listrow__hint">Read on {r.date.charAt(0) + r.date.slice(1).toLowerCase()}.</span>
            </div>
            <span className="m-listrow__value">OPEN ↗</span>
          </div>
        ))}
      </div>
    </>
  );
}

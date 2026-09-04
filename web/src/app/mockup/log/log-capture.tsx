"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Eyebrow } from "@/components/mockup/primitives";
import { THIS_WEEK } from "@/components/mockup/data";

/* Log · the voice-first front door (LogScreen.jsx hero).
   Mode toggle, the pulsing record button (the one loud accent in the
   system), a linked-workout row, and the typed-notes fallback.
   Recording is simulated: the timer runs, nothing is stored. */

const MOODS = ["energized", "positive", "neutral", "tired", "struggling"] as const;

const fmt = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

export function LogCapture({ dayOne = false }: { dayOne?: boolean }) {
  const [mode, setMode] = useState<"run" | "checkin">("run");
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [notes, setNotes] = useState("");
  const [mood, setMood] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const today = THIS_WEEK.find((d) => d.state === "today");

  useEffect(() => {
    if (!recording) return;
    const t = setInterval(() => setSeconds((s) => s + 1), 1000);
    return () => clearInterval(t);
  }, [recording]);

  const toggle = () => {
    if (recording) {
      setRecording(false);
      setSeconds(0);
      setSaved(true);
    } else {
      setSeconds(0);
      setSaved(false);
      setRecording(true);
    }
  };

  const checkin = mode === "checkin";

  return (
    <>
      <div className="m-mode m-mt-14">
        <button className={`m-mode__btn${!checkin ? " is-active" : ""}`} onClick={() => setMode("run")}>
          Log run
          <div className="m-mode__rail" />
        </button>
        <button className={`m-mode__btn${checkin ? " is-active" : ""}`} onClick={() => setMode("checkin")}>
          Check in
          <div className="m-mode__rail" />
        </button>
      </div>

      <div className="m-pad m-center">
        <div className="m-sp-32" />
        {recording ? (
          <div className="m-timer">{fmt(seconds)}</div>
        ) : (
          <h1 className="m-display m-display--xl">{checkin ? "How are you feeling?" : "Log your run."}</h1>
        )}
        <p className="m-quote m-quote--sub m-mt-14">
          {recording
            ? checkin
              ? "Speak your status. Tap the button to stop."
              : "Recording. Tap the button to stop."
            : saved
              ? "Saved. Transcribing now; it lands in the journal in a minute."
              : checkin
                ? "Tap the button to record a quick check-in."
                : "Tap the button to start your voice memo."}
        </p>
        <div className="m-sp-24" />
      </div>

      {!checkin && dayOne ? (
        /* No plan on day one, so the row offers the most recent synced run
           instead of today's prescription. */
        <div className="m-hlsection m-hlsection--top is-link">
          <div className="m-row">
            <Eyebrow>LINKED TO</Eyebrow>
            <span className="m-caption">CHANGE ↗</span>
          </div>
          <div className="m-display m-display--s m-mt-8">SEP 2 · EASY 5.5 MI · 56:50</div>
          <div className="m-caption m-caption--faint m-mt-4">APPLE HEALTH · YOUR MOST RECENT RUN</div>
        </div>
      ) : !checkin && today ? (
        <Link href={`/mockup/train/day/${today.id}`} className="m-hlsection m-hlsection--top is-link m-block">
          <div className="m-row">
            <Eyebrow>LINKED TO</Eyebrow>
            <span className="m-caption">CHANGE ↗</span>
          </div>
          <div className="m-display m-display--s m-mt-8">
            {today.dateUpper} · {today.title.replace(/\.$/, "")} · PLANNED
          </div>
          <div className="m-caption m-caption--faint m-mt-4">{today.structure} · NOT YET SYNCED FROM APPLE WATCH</div>
        </Link>
      ) : null}

      {checkin ? (
        <div className="m-hlsection m-hlsection--top">
          <Eyebrow>OR · PICK A MOOD</Eyebrow>
          <div className="m-moodradio m-mt-8">
            {MOODS.map((m) => (
              <button key={m} className={`m-moodradio__opt${mood === m ? " is-active" : ""}`} onClick={() => setMood(m)}>
                <span className="m-moodradio__dot" />
                <span className="m-moodradio__name">{m}</span>
              </button>
            ))}
          </div>
        </div>
      ) : null}

      <div className="m-col m-items-center m-gap-16">
        <div className="m-sp-40" />
        <button
          className={`m-record${recording ? " is-recording" : ""}`}
          onClick={toggle}
          aria-label={recording ? "Stop recording" : "Start voice memo"}
        >
          <span className="m-record__ring" />
          <span className="m-record__disc">
            <span className="m-record__inner" />
          </span>
        </button>
        <div className="m-eyebrow">{recording ? "Tap to stop" : "Tap to record"}</div>
        <div className="m-sp-32" />
      </div>

      <div className="m-hlsection m-hlsection--top">
        <div className="m-row">
          <Eyebrow>OR · TYPE NOTES</Eyebrow>
          <button
            className={`m-link--mono m-link${notes.trim() ? " is-coral" : ""}`}
            disabled={!notes.trim()}
            onClick={() => {
              setNotes("");
              setSaved(true);
            }}
          >
            {notes.trim() ? "SAVE ↗" : "SAVE"}
          </button>
        </div>
        <textarea
          className="m-textarea"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder={checkin ? "Anything on your mind today?" : "How did your run feel today?"}
        />
      </div>
    </>
  );
}

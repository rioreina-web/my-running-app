import Link from "next/link";
import { Eyebrow, PlateStrip, Quoted } from "@/components/mockup/primitives";
import { JOURNAL, JOURNAL_TOTAL_ENTRIES, JOURNAL_WINDOW, type MockEntry } from "@/components/mockup/data";
import { LogCapture } from "./log-capture";

/* Log tab · voice-first front door on top, six months of journal below.
   Pure record. No AI annotation inline. Workouts auto-populated from
   HealthKit sit alongside runs (strength, cross-training) so the
   journal is the whole week, not just the runs. */

function metaLine(e: MockEntry) {
  const parts = [e.dateUpper, e.zone.toUpperCase()];
  if (e.miles) parts.push(`${e.miles} MI`);
  else if (e.duration) parts.push(e.duration.toUpperCase());
  if (e.pace) parts.push(e.pace.toUpperCase());
  return parts.join("  ·  ");
}

function JournalRow({ entry }: { entry: MockEntry }) {
  const hasBody = Boolean(entry.body);
  return (
    <Link href={`/mockup/log/${entry.id}`} className="m-jrow">
      <span className="m-rail-mood" data-mood={entry.mood ?? undefined} />
      <div>
        <div className="m-row">
          <div className="m-jrow__day">{entry.dow}</div>
          <span className={`m-jrow__ind${entry.kind === "voice" ? " is-voice" : ""}`}>
            {entry.kind === "voice" ? (
              <>
                <svg width="9" height="9" viewBox="0 0 9 9" aria-hidden="true">
                  <polygon points="1.5,0.8 8,4.5 1.5,8.2" fill="currentColor" />
                </svg>
                VOICE · {entry.voiceLength}
              </>
            ) : entry.kind === "text" ? (
              "TEXT ONLY"
            ) : (
              "SYNCED"
            )}
          </span>
        </div>
        <div className="m-jrow__meta">{metaLine(entry)}</div>
        {hasBody ? (
          <div className="m-jrow__body">
            <Quoted>{entry.body}</Quoted>
          </div>
        ) : (
          <div className="m-jrow__quiet">No memo on this one. Synced from {entry.source}.</div>
        )}
        <div className="m-jrow__foot">
          {entry.mood ? (
            <span className="m-moodtext" data-mood={entry.mood}>
              {entry.mood}
            </span>
          ) : null}
          {entry.niggles?.map((n) => (
            <span key={n.part} className="m-chip m-chip--niggle">
              {n.side ? `${n.side} ` : ""}
              {n.part}
            </span>
          ))}
          {entry.life?.map((l) => (
            <span key={l} className="m-chip m-chip--life">
              {l}
            </span>
          ))}
        </div>
      </div>
    </Link>
  );
}

export default function LogPage() {
  return (
    <>
      <PlateStrip surface="LOG · VOICE LOG + JOURNAL" fig="FIG. 09" />
      <div className="m-body m-body--flush">
        <LogCapture />

        <div className="m-sp-20" />
        <div className="m-row m-pad m-hlsection m-hlsection--top">
          <Eyebrow>
            JOURNAL · {JOURNAL_WINDOW} · {JOURNAL_TOTAL_ENTRIES} ENTRIES
          </Eyebrow>
          <span className="m-caption m-caption--faint">NEWEST FIRST</span>
        </div>
        {JOURNAL.map((e) => (
          <JournalRow key={e.id} entry={e} />
        ))}

        <div className="m-pad m-center m-mt-24">
          <span className="m-link m-link--mono">LOAD OLDER · MAR – AUG ↗</span>
          <p className="m-quote m-quote--faint m-mt-12">Six months load by default. Scroll for the rest of the two years.</p>
        </div>
      </div>
    </>
  );
}

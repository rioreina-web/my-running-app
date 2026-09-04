/* Athlete-site mockup · one journal row.
   Shared by the Log tab and its day-one variant. Pure record: the
   entry's own words, its mood, its niggles, its life context. No AI
   annotation here — that belongs to Coach. */

import Link from "next/link";
import type { MockEntry } from "./data";
import { Quoted } from "./primitives";

export function metaLine(e: MockEntry) {
  const parts = [e.dateUpper, e.zone.toUpperCase()];
  if (e.miles) parts.push(`${e.miles} MI`);
  else if (e.duration) parts.push(e.duration.toUpperCase());
  if (e.pace) parts.push(e.pace.toUpperCase());
  return parts.join("  ·  ");
}

export function JournalRow({ entry }: { entry: MockEntry }) {
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

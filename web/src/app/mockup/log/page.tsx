import { Eyebrow, PlateStrip } from "@/components/mockup/primitives";
import { JournalRow } from "@/components/mockup/journal-row";
import {
  DAY_ONE,
  DAY_ONE_JOURNAL,
  JOURNAL,
  JOURNAL_TOTAL_ENTRIES,
  JOURNAL_WINDOW,
} from "@/components/mockup/data";
import { LogCapture } from "./log-capture";

/* Log tab · voice-first front door on top, six months of journal below.
   Pure record. No AI annotation inline. Workouts auto-populated from
   HealthKit sit alongside runs (strength, cross-training) so the
   journal is the whole week, not just the runs.

   `?day=1` renders the same tab the morning after onboarding: the
   back-fill is in, nothing has been said yet. */

export default async function LogPage({ searchParams }: { searchParams: Promise<{ day?: string }> }) {
  const dayOne = (await searchParams).day === "1";
  const entries = dayOne ? DAY_ONE_JOURNAL : JOURNAL;

  return (
    <>
      <PlateStrip surface="LOG · VOICE LOG + JOURNAL" fig="FIG. 09" />
      <div className="m-body m-body--flush">
        <LogCapture dayOne={dayOne} />

        <div className="m-sp-20" />
        <div className="m-row m-pad m-hlsection m-hlsection--top">
          <Eyebrow>
            {dayOne
              ? `JOURNAL · IMPORTED · ${DAY_ONE.imported.workouts} WORKOUTS`
              : `JOURNAL · ${JOURNAL_WINDOW} · ${JOURNAL_TOTAL_ENTRIES} ENTRIES`}
          </Eyebrow>
          <span className="m-caption m-caption--faint">NEWEST FIRST</span>
        </div>

        {dayOne ? (
          <div className="m-pad m-mt-14">
            {/* data_depth 1 — plain prose, no pull-quotes. */}
            <p className="m-body-sm">
              {DAY_ONE.imported.months} months of workouts came in from Apple Health. Record after your next run and your
              own words land here beside them.
            </p>
          </div>
        ) : null}

        {entries.map((e) => (
          <JournalRow key={e.id} entry={e} />
        ))}

        <div className="m-pad m-center m-mt-24">
          <span className="m-link m-link--mono">LOAD OLDER · MAR – AUG ↗</span>
          <p className={`m-mt-12 ${dayOne ? "m-body-sm" : "m-quote m-quote--faint"}`}>
            Six months load by default. Scroll for the rest of the two years.
          </p>
        </div>
      </div>
    </>
  );
}

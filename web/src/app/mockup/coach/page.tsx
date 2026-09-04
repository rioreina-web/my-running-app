import { Eyebrow, PlateStrip } from "@/components/mockup/primitives";
import { TODAY } from "@/components/mockup/data";
import { CoachDayOne } from "@/components/mockup/day-one";
import { CoachRead } from "./coach-read";

/* Coach tab · the AI Daily Read as observation, on demand. */

export default async function CoachPage({ searchParams }: { searchParams: Promise<{ day?: string }> }) {
  if ((await searchParams).day === "1") return <CoachDayOne />;
  return (
    <>
      <PlateStrip surface="COACH · THE READ" fig="FIG. 14" />
      <div className="m-body">
        <div className="m-section m-section--first">
          <div className="m-row">
            <Eyebrow>COACH · ON DEMAND</Eyebrow>
            <Eyebrow>
              {TODAY.short} · {TODAY.dateUpper}
            </Eyebrow>
          </div>
          <h1 className="m-display m-display--l m-mt-4">The read.</h1>
          <p className="m-quote m-quote--sub m-mt-4">Observation, never prescription. You own the call.</p>
        </div>
        <CoachRead />
      </div>
    </>
  );
}

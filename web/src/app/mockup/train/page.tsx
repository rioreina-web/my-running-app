import Link from "next/link";
import { Eyebrow, PlateStrip } from "@/components/mockup/primitives";
import { GOAL, TODAY, WEEK_TOTALS } from "@/components/mockup/data";
import { TrainViews } from "./train-views";

/* Train · the journey as plan and history. Header is shared across the
   three modes; the modes live in the client segmenter. */

export default async function TrainPage({ searchParams }: { searchParams: Promise<{ day?: string }> }) {
  const dayOne = (await searchParams).day === "1";
  return (
    <>
      <PlateStrip surface="TRAINING · CIM BUILD" fig="FIG. 06" />
      <div className="m-body">
        <div className="m-section m-section--first">
          <div className="m-row">
            <Eyebrow>{dayOne ? "TRAINING · LAST 4 WEEKS" : `TRAINING · ${WEEK_TOTALS.label}`}</Eyebrow>
            <Eyebrow>
              {TODAY.short} · {TODAY.dateUpper}
            </Eyebrow>
          </div>
          {/* Without a plan the header describes her training, not a block.
              `activePlan == nil` is a state, not an empty state. */}
          <h1 className="m-display m-display--l m-mt-4">{dayOne ? "Your training." : `${GOAL.planName}.`}</h1>
          {dayOne ? (
            <p className="m-body-sm m-mt-4">No plan yet. Everything below is what you have already run.</p>
          ) : (
            <p className="m-quote m-quote--sub m-mt-4">
              {GOAL.time} · {GOAL.date} · {GOAL.daysOut} days out.{" "}
              <Link href="/mockup/races" className="m-link m-link--mono">
                RACE PLAN ↗
              </Link>
            </p>
          )}
        </div>
        <TrainViews dayOne={dayOne} />
      </div>
    </>
  );
}

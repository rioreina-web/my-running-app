import Link from "next/link";
import { Eyebrow, PlateStrip } from "@/components/mockup/primitives";
import { GOAL, TODAY, WEEK_TOTALS } from "@/components/mockup/data";
import { TrainViews } from "./train-views";

/* Train · the journey as plan and history. Header is shared across the
   three modes; the modes live in the client segmenter. */

export default function TrainPage() {
  return (
    <>
      <PlateStrip surface="TRAINING · CIM BUILD" fig="FIG. 06" />
      <div className="m-body">
        <div className="m-section m-section--first">
          <div className="m-row">
            <Eyebrow>TRAINING · {WEEK_TOTALS.label}</Eyebrow>
            <Eyebrow>
              {TODAY.short} · {TODAY.dateUpper}
            </Eyebrow>
          </div>
          <h1 className="m-display m-display--l m-mt-4">{GOAL.planName}.</h1>
          <p className="m-quote m-quote--sub m-mt-4">
            {GOAL.time} · {GOAL.date} · {GOAL.daysOut} days out.{" "}
            <Link href="/mockup/races" className="m-link m-link--mono">
              RACE PLAN ↗
            </Link>
          </p>
        </div>
        <TrainViews />
      </div>
    </>
  );
}

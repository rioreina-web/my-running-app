import type { ReactNode } from "react";
import type { AthleteHeader } from "@/lib/coach-dashboard/types";
import { Rich } from "./rich-text";
import { ProfileEditor } from "./profile-editor";

/**
 * AnchorHeader — the athlete hero. Name, plan, week N of M, and the anchor line
 * (goal · the race the paces are anchored on · derived MP) when those exist.
 * All anchor pieces are optional, so an athlete with no goal/plan renders a
 * clean header with just name + status. Read-only; "Adjust paces" is Phase 2.
 */
export function AnchorHeader({ header }: { header: AthleteHeader }) {
  const blocks: ReactNode[] = [];
  if (header.goalTime) {
    blocks.push(<AnchorBlock key="goal" k="Goal" v={header.goalTime} m={header.goalNote ?? ""} />);
  }
  if (header.anchorTime) {
    blocks.push(
      <AnchorBlock key="anchor" k="Paces anchored on" v={header.anchorTime} m={header.anchorRace ?? ""} />,
    );
  }
  if (header.marathonPace) {
    blocks.push(
      <AnchorBlock
        key="mp"
        k="Marathon pace"
        v={
          <>
            {header.marathonPace}
            <span className="text-[12px] text-text-tertiary">/mi</span>
          </>
        }
        m="10 zones derived from anchor"
      />,
    );
  }

  return (
    <div className="border-b border-divider py-6">
      <div className="flex items-center gap-4">
        <div className="min-w-0 flex-1">
          <div className="font-display text-[30px] font-bold leading-none tracking-[-0.01em] text-text-primary">
            {header.name}
          </div>
          <div className="mt-1.5 font-mono text-[11.5px] uppercase tracking-[0.06em] text-text-secondary">
            {header.planName}
          </div>
          {header.athleteId ? (
            <div className="mt-2">
              <ProfileEditor
                athleteId={header.athleteId}
                initialName={header.profileName ?? ""}
                initialBio={header.bio ?? ""}
              />
            </div>
          ) : null}
        </div>
        {header.totalWeeks > 0 ? (
          <span className="drip-eyebrow self-start whitespace-nowrap">
            Week {header.weekNumber} of {header.totalWeeks}
          </span>
        ) : null}
      </div>

      {header.bio ? (
        <p className="mt-4 border-t border-divider pt-4 font-body text-[14px] leading-relaxed text-text-secondary">
          {header.bio}
        </p>
      ) : null}

      {blocks.length ? (
        <div className="mt-5 flex flex-wrap items-start gap-x-6 gap-y-3 border-t border-divider pt-4">
          {blocks.flatMap((b, i) =>
            i === 0
              ? [b]
              : [
                  <span key={`sep-${i}`} className="self-center font-mono text-lg text-text-tertiary">
                    ·
                  </span>,
                  b,
                ],
          )}
        </div>
      ) : null}

      {header.newRaceNudge ? (
        <div className="mt-4 flex items-start gap-2.5 rounded-lg border border-divider border-l-2 border-l-text-tertiary bg-bg-elevated px-3.5 py-2.5">
          <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-text-tertiary" />
          <p className="font-body text-[13.5px] leading-snug text-text-primary">
            <Rich text={header.newRaceNudge.text} />
          </p>
        </div>
      ) : null}
    </div>
  );
}

function AnchorBlock({ k, v, m }: { k: string; v: ReactNode; m: string }) {
  return (
    <div>
      <div className="font-mono text-[9.5px] uppercase tracking-[0.14em] text-text-tertiary">{k}</div>
      <div className="mt-1.5 font-mono text-[19px] font-semibold tabular-nums text-text-primary">{v}</div>
      {m ? <div className="mt-0.5 font-body text-[12.5px] text-text-secondary">{m}</div> : null}
    </div>
  );
}

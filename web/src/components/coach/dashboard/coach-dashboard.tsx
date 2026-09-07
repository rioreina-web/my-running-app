"use client";

import { useMemo } from "react";
import { EmptyState } from "@/components/ui/empty-state";
import { PlateStrip } from "@/components/ui/plate-strip";
import type { DashboardData } from "@/lib/coach-dashboard/types";
import { AnchorHeader } from "./anchor-header";
import { BlockStrip } from "./block-strip";
import { ContentsRail, type RailItem } from "./contents-rail";
import { DailyOverlay } from "./daily-overlay";
import { DrawerProvider } from "./drawer-context";
import { Band } from "./editorial";
import { KeySessionsStrip } from "./key-sessions-strip";
import { LoadBand } from "./load-band";
import { MoodStrip } from "./mood-strip";
import { NigglesPanel } from "./niggles-panel";
import { ProgressionBand } from "./progression-band";
import { Rich } from "./rich-text";
import { SignalBand } from "./signal-band";
import { TrainSection } from "./train-section";
import { WorkoutSheet } from "./workout-sheet";

/**
 * CoachAthleteDashboard — the athlete deep-dive, v3 (training first, shaped
 * for an athlete with no active plan — CLAUDE.md, `activePlan == nil` is
 * first-class).
 *
 * v2 ran Latest → Key sessions → Against the plan → Body & mind → Load →
 * Analytics — three of those six assumed a prescription to measure against,
 * which the canonical athlete (self-coached, 0 active plans) doesn't have.
 * v3 follows the design mockup (`design-system/Coach Portal Athlete.html`):
 *
 *   01 The workout   the last run they logged, in full
 *   02 Train         the timeline, one week at a time, and every keyed
 *                    session against the athlete's own pace zones — the iOS
 *                    TRAIN tab's shape, not a plan-adherence table
 *   03 Niggles & mood  every verbatim body mention, and how they've felt
 *   04 Load          volume and stress load
 *   05 Analytics     projection, watch list, machine observations — kept
 *                    from v2 (the apply doc's phases don't touch it), moved
 *                    last because this is where you go looking, not landing
 *
 * A contents rail tracks position. Sections with no data drop out of BOTH the
 * page and the rail: a contents column that points at an empty band is worse
 * than no column.
 */
export function CoachAthleteDashboard({ data }: { data: DashboardData }) {
  const hasKeys = data.days.some((d) => d.key);
  const hasAnalytics =
    Boolean(data.progression) || data.watchList.length > 0 || data.moments.length > 0;
  const hasNigglesMood = data.niggles.length > 0 || data.mood.strip.length > 0;

  const rail = useMemo<RailItem[]>(() => {
    const items: RailItem[] = [];
    if (data.latest) items.push({ id: "band-workout", n: "01", label: "The workout" });
    if (data.days.length) items.push({ id: "band-train", n: "02", label: "Train" });
    if (hasNigglesMood) items.push({ id: "band-niggles", n: "03", label: "Niggles & mood" });
    items.push({ id: "band-load", n: "04", label: "Load" });
    if (hasAnalytics) items.push({ id: "band-analytics", n: "05", label: "Analytics" });
    return items;
  }, [data.latest, data.days.length, hasNigglesMood, hasAnalytics]);

  const num = (id: string) => rail.find((r) => r.id === id)?.n ?? "";

  const weekMeta = data.block
    ? `Wk ${data.block.weekNumber} · ${data.block.milesThisWeek.toFixed(1)} mi · ${data.block.sessionsRun} of ${data.block.sessionsPlanned || "?"}`
    : undefined;

  return (
    <DrawerProvider days={data.days} athleteId={data.header.athleteId}>
      <div className="mx-auto max-w-[1180px] px-6 pb-24">
        <PlateStrip surface="Coach · The Athlete" padded={false} className="mb-0" />

        <div className="grid gap-x-10 lg:grid-cols-[186px_1fr]">
          <ContentsRail
            items={rail}
            who={data.header.name}
            meta={weekMeta}
            flag={
              data.block && data.block.sessionsRun < data.block.sessionsPlanned
                ? `${data.block.sessionsPlanned - data.block.sessionsRun} sessions left this week`
                : undefined
            }
          />

          <div className="min-w-0">
            <AnchorHeader header={data.header} />

            {/* 01 — the workout */}
            {data.latest ? (
              <>
                <Band
                  id="band-workout"
                  n={num("band-workout")}
                  title="The workout"
                  note="The last run they logged, in full."
                />
                <WorkoutSheet latest={data.latest} detail={data.latestDetail} />
              </>
            ) : (
              <>
                <Band id="band-workout" n="01" title="The workout" />
                <EmptyState
                  variant="data-pending"
                  eyebrow="The workout"
                  title="No logged runs yet. This fills in with the first session the athlete records."
                />
              </>
            )}

            {/* 02 — train */}
            {data.days.length ? (
              <>
                <Band
                  id="band-train"
                  n={num("band-train")}
                  title="Train"
                  note="The timeline, one week at a time."
                />
                <div className="py-5">
                  <DailyOverlay days={data.days} paceKey={data.paceKey} />
                  <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 font-mono text-[10px] uppercase tracking-[0.04em] text-text-secondary">
                    <span className="inline-flex items-center gap-1.5">
                      <span className="h-[11px] w-[11px] bg-pace-mp" /> Workout load
                    </span>
                    <span className="inline-flex items-center gap-1.5">
                      <span className="h-[11px] w-[11px] bg-mood-positive" /> Mood
                    </span>
                    <span className="inline-flex items-center gap-1.5">
                      <span className="h-[11px] w-[11px] bg-coral" /> Niggle mentioned
                    </span>
                    {hasKeys ? (
                      <span className="inline-flex items-center gap-1.5 text-text-primary">
                        Key session — click to drill in
                      </span>
                    ) : null}
                  </div>
                  {data.overlayRead ? (
                    <div className="mt-4 border-t border-divider pt-3.5">
                      <p className="drip-ai text-[12.5px] leading-relaxed">
                        <Rich text={data.overlayRead.body} strongClassName="font-semibold" />
                      </p>
                      <p className="drip-ai mt-2 text-[12px] text-text-secondary">
                        {data.overlayRead.question}
                      </p>
                    </div>
                  ) : null}
                </div>

                <TrainSection days={data.days} />

                {data.keySessions.length ? (
                  <div className="border-t border-divider py-5">
                    <span className="drip-eyebrow mb-1.5 block text-text-tertiary">
                      Keyed sessions · last 6 weeks
                    </span>
                    <KeySessionsStrip sessions={data.keySessions} />
                  </div>
                ) : null}

                {data.block ? <BlockStrip block={data.block} /> : null}
              </>
            ) : null}

            {/* 03 — niggles & mood */}
            {hasNigglesMood ? (
              <>
                <Band
                  id="band-niggles"
                  n={num("band-niggles")}
                  title="Niggles & mood"
                  note="Only what they said, and when they said it."
                />
                <div className="grid gap-x-8 md:grid-cols-2">
                  <NigglesPanel niggles={data.niggles} />
                  <MoodStrip mood={data.mood} />
                </div>
              </>
            ) : null}

            {/* 04 — load */}
            <Band
              id="band-load"
              n={num("band-load")}
              title="Load"
              note="How much, and how hard."
            />
            <LoadBand
              weeks={data.weeklyVolume}
              acwr={data.acwr}
              stress={data.stress}
              milesThisWeek={data.block?.milesThisWeek}
              milesPlanned={data.block?.milesPlanned}
            />

            {/* 05 — analytics, last on purpose */}
            {hasAnalytics ? (
              <>
                <Band
                  id="band-analytics"
                  n={num("band-analytics")}
                  title="Analytics"
                  note="Where the block has room, and what the system noticed."
                />
                {data.progression ? <ProgressionBand progression={data.progression} /> : null}
                <SignalBand watchList={data.watchList} moments={data.moments} />
              </>
            ) : null}

            <p className="drip-dek mt-12 border-t border-divider pt-4 text-[12.5px]">
              Every number on this page traces to a logged session. Nothing here is inferred from a
              plan the athlete did not run.
            </p>
          </div>
        </div>
      </div>
    </DrawerProvider>
  );
}

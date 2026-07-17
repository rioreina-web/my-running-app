"use client";

import { EmptyState } from "@/components/ui/empty-state";
import { PlateStrip } from "@/components/ui/plate-strip";
import type { DashboardData } from "@/lib/coach-dashboard/types";
import { AnchorHeader } from "./anchor-header";
import { BandHead } from "./band-head";
import { DailyOverlay } from "./daily-overlay";
import { DrawerProvider } from "./drawer-context";
import { KeySessionRail } from "./key-session-rail";
import { LoadBand } from "./load-band";
import { LogFeed } from "./log-feed";
import { MoodStrip } from "./mood-strip";
import { NigglesPanel } from "./niggles-panel";
import { ProgressionBand } from "./progression-band";
import { Rich } from "./rich-text";
import { SignalBand } from "./signal-band";

/**
 * CoachAthleteDashboard — the full Phase 1 read-only surface. A client
 * orchestrator that owns the drill-down drawer state (via DrawerProvider) and
 * composes the bands from a `DashboardData` payload. Source-agnostic: the same
 * view renders fixtures (design preview) or live Supabase data (real route).
 * Every band degrades to an empty state when its data is missing.
 */
export function CoachAthleteDashboard({ data }: { data: DashboardData }) {
  const hasKeys = data.days.some((d) => d.key);

  return (
    <DrawerProvider days={data.days} athleteId={data.header.athleteId}>
      <div className="mx-auto max-w-[1060px] px-4 pb-24 pt-6">
        <PlateStrip surface="Athlete Detail · Coach Portal" figure="Phase 1" padded={false} className="mb-4" />

        <AnchorHeader header={data.header} />

        <BandHead n="01" title="Signal" />
        <SignalBand watchList={data.watchList} moments={data.moments} />

        <BandHead n="02" title="Daily overlay — workouts · mood · niggles, one axis" />
        <div className="rounded-xl border border-divider bg-bg-card p-5 md:p-6">
          {data.days.length ? (
            <>
              <div className="mb-1 flex items-baseline justify-between gap-3">
                <div className="font-display text-[19px] font-bold text-text-primary">
                  The training, day by day.
                </div>
                <div className="shrink-0 font-mono text-[10px] uppercase tracking-[0.06em] text-text-tertiary">
                  {data.days.length} days · how they landed
                </div>
              </div>

              <DailyOverlay days={data.days} paceKey={data.paceKey} />

              <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 font-mono text-[10px] uppercase tracking-[0.04em] text-text-secondary">
                <span className="inline-flex items-center gap-1.5">
                  <span className="h-[11px] w-[11px] rounded-sm bg-pace-mp" /> Workout load
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="h-[11px] w-[11px] rounded-sm bg-mood-positive" /> Mood
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="h-[11px] w-[11px] rounded-sm bg-coral" /> Niggle mentioned
                </span>
                {hasKeys ? (
                  <span className="inline-flex items-center gap-1.5 text-text-primary">
                    ★ Key session — click to drill in
                  </span>
                ) : null}
              </div>

              {data.overlayRead ? (
                <div className="mt-4 border-t border-divider pt-3.5">
                  <p className="font-body text-[14.5px] leading-relaxed text-text-primary">
                    <Rich text={data.overlayRead.body} strongClassName="font-bold text-coral-dark" />
                  </p>
                  <p className="mt-2 font-display text-[14px] italic text-text-secondary">
                    {data.overlayRead.question}
                  </p>
                </div>
              ) : null}

              {hasKeys ? (
                <>
                  <div className="mb-3 mt-5 flex flex-wrap items-center gap-2.5">
                    <span className="font-mono text-[11px] uppercase tracking-[0.12em] text-text-secondary">
                      ★ Key sessions
                    </span>
                    <span className="font-display text-[13px] italic text-text-tertiary">
                      the ones that matter — click any card to drill in
                    </span>
                  </div>
                  <KeySessionRail days={data.days} />
                </>
              ) : null}
            </>
          ) : (
            <EmptyState
              variant="data-pending"
              eyebrow="Daily overlay"
              title="No logged runs in this window yet. The overlay fills in as the athlete logs training."
            />
          )}
        </div>

        <BandHead n="03" title="Progression — is the training working?" />
        {data.progression ? (
          <ProgressionBand progression={data.progression} />
        ) : (
          <div className="rounded-xl border border-divider bg-bg-card p-5">
            <EmptyState
              variant="data-pending"
              eyebrow="Progression"
              title="A fitness read needs an active plan or a confirmed race to anchor on. Once one is set, the prediction and curve appear here."
            />
          </div>
        )}

        <BandHead n="04" title="Load — how much, how hard" />
        <LoadBand weeks={data.weeklyVolume} acwr={data.acwr} />

        <BandHead n="05" title="Body & mind" />
        <div className="grid gap-3.5 md:grid-cols-2">
          <NigglesPanel niggles={data.niggles} />
          <MoodStrip mood={data.mood} />
        </div>

        <BandHead n="06" title="Training log — prescribed vs. actual" />
        <LogFeed days={data.days} />

        <div className="mt-8 text-center font-mono text-[10px] uppercase leading-relaxed tracking-[0.1em] text-text-tertiary">
          Phase 1 · read-only dashboard · re-anchor tool is Phase 2
        </div>
      </div>
    </DrawerProvider>
  );
}

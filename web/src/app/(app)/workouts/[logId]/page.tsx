import Link from "next/link";
import { notFound } from "next/navigation";
import {
  buildAthleteWorkoutDetail,
  type AthleteWorkoutDetail,
  type WorkoutNiggle,
} from "@/lib/workout-detail";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { Eyebrow } from "@/components/ui/eyebrow";
import { MoodBadge } from "@/components/ui/mood-badge";
import { EmptyState } from "@/components/ui/empty-state";
import { CollapsibleAct } from "./collapsible-act";
import { PaceTrace } from "./pace-trace";

// The athlete's own workout, in three acts (design system §6):
//
//   Act 1 — no scroll: eyebrow, display date, source line, 4-stat strip,
//           conditions plate. Conditions frame the run before any chart.
//   Act 2 — the story: mood + verbatim memo, then Workouts & Reps as the
//           hero table.
//   Act 3 — collapsed: pace trace, climb, HR. Eyebrow + mono summary +
//           chevron; only the type-relevant section default-expands.
//
// No AI narration on this surface yet. The design calls for a THE READ
// paragraph atop Act 2; generating one is an LLM call that doesn't exist for
// this route, and inventing a stand-in would violate the no-fabrication rule.
// Act 2 leads with the athlete's own words instead, which is the honest
// version of "feeling before data."

export default async function WorkoutDetailPage({
  params,
}: {
  params: Promise<{ logId: string }>;
}) {
  const { logId } = await params;
  const detail = await buildAthleteWorkoutDetail(logId);
  if (!detail) notFound();

  const date = parseLocalDate(detail.date);
  const displayDate = date.toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <Link
        href="/log"
        className="font-mono text-[11px] uppercase tracking-[0.08em] text-text-secondary transition-colors hover:text-coral"
      >
        ← Back to log
      </Link>

      {/* ── Act 1 ───────────────────────────────────────────────────────── */}
      <header className="mt-6">
        <Eyebrow>{detail.eyebrow}</Eyebrow>
        <h1 className="mt-3 font-display text-[44px] leading-[1.05] text-text-primary">
          {displayDate}
          <span className="text-coral">.</span>
        </h1>
        <p className="mt-2 font-body text-sm italic text-text-tertiary">
          {sourceLine(detail.source)}
        </p>
        <p className="mt-4 font-display text-2xl text-text-primary">{detail.title}</p>
      </header>

      <StatStrip kpis={detail.kpis} />

      {detail.conditions && <ConditionsPlate conditions={detail.conditions} />}

      {/* ── Act 2 ───────────────────────────────────────────────────────── */}
      <EditorialDivider className="my-10" />

      <section>
        <div className="flex flex-wrap items-center gap-2">
          {detail.mood && <MoodBadge mood={detail.mood} />}
          {detail.niggles.map((n, i) => (
            <NiggleChip key={`${n.body_area}-${i}`} niggle={n} />
          ))}
        </div>

        {detail.note ? (
          <blockquote className="mt-5 border-l-2 border-coral/40 pl-4 font-body text-[17px] italic leading-8 text-text-primary/90">
            {detail.note}
          </blockquote>
        ) : (
          <p className="mt-5 font-body text-sm text-text-tertiary">
            No note on this run.
          </p>
        )}

        {detail.niggles.some((n) => n.verbatim_quote) && (
          <div className="mt-5 space-y-2">
            {detail.niggles
              .filter((n) => n.verbatim_quote)
              .map((n, i) => (
                <p key={i} className="font-body text-sm italic text-text-secondary">
                  &ldquo;{n.verbatim_quote}&rdquo;
                </p>
              ))}
          </div>
        )}
      </section>

      <section className="mt-10">
        <Eyebrow>{detail.splitLabel}</Eyebrow>
        {detail.splits.length > 0 ? (
          <SplitsTable splits={detail.splits} />
        ) : (
          <div className="mt-4">
            <EmptyState
              variant="data-pending"
              title="No per-lap splits on this run."
            />
          </div>
        )}
      </section>

      {/* ── Act 3 ───────────────────────────────────────────────────────── */}
      {(detail.chart || detail.conditions) && (
        <section className="mt-12">
          {detail.chart && (
            <CollapsibleAct
              eyebrow="Pace trace"
              summary={`${detail.chart.laps.length} points`}
              defaultOpen={detail.hasLaps}
            >
              <PaceTrace chart={detail.chart} />
            </CollapsibleAct>
          )}

          {detail.conditions && detail.conditions.climbFt > 0 && (
            <CollapsibleAct
              eyebrow="Elevation"
              summary={`+${detail.conditions.climbFt.toLocaleString()} ft`}
            >
              <p className="font-body text-sm text-text-secondary">
                {detail.conditions.climbFt.toLocaleString()} ft of climb, summed from
                per-lap gain. We store gain rather than an altitude stream, so
                this is a total, not a profile.
              </p>
            </CollapsibleAct>
          )}

          {detail.conditions && detail.conditions.hrAvg > 0 && (
            <CollapsibleAct
              eyebrow="Heart rate"
              summary={`${detail.conditions.hrAvg} bpm avg`}
            >
              <p className="font-body text-sm text-text-secondary">
                Distance-weighted average across the laps that recorded heart
                rate.
              </p>
            </CollapsibleAct>
          )}
        </section>
      )}
    </div>
  );
}

// ── Act 1 pieces ───────────────────────────────────────────────────────────

function StatStrip({ kpis }: { kpis: AthleteWorkoutDetail["kpis"] }) {
  return (
    <div className="mt-8 grid grid-cols-2 gap-x-6 gap-y-5 border-y border-divider py-5 sm:grid-cols-4">
      {kpis.map((k) => (
        <div key={k.k}>
          <p className="font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
            {k.k}
          </p>
          <p
            className={`mt-1 font-display text-2xl tabular-nums ${
              k.accent ? "text-pace-lt" : "text-text-primary"
            }`}
          >
            {k.v}
          </p>
          {k.sub && (
            <p className="mt-0.5 font-mono text-[10px] tabular-nums text-text-tertiary">
              {stripEmphasis(k.sub)}
            </p>
          )}
        </div>
      ))}
    </div>
  );
}

function ConditionsPlate({
  conditions,
}: {
  conditions: NonNullable<AthleteWorkoutDetail["conditions"]>;
}) {
  const cells: Array<{ label: string; value: string; hot?: boolean }> = [];
  if (conditions.tempF > 0) cells.push({ label: "Temp", value: `${conditions.tempF}°` });
  if (conditions.dewPointF > 0)
    cells.push({
      label: "Dew point",
      value: `${conditions.dewPointF}°`,
      hot: conditions.dewHot,
    });
  if (conditions.climbFt > 0)
    cells.push({ label: "Climb", value: `+${conditions.climbFt.toLocaleString()} ft` });
  if (conditions.hrAvg > 0) cells.push({ label: "Avg HR", value: `${conditions.hrAvg}` });

  if (cells.length === 0) return null;

  return (
    <div className="mt-6 rounded-lg bg-bg-elevated px-5 py-4">
      <div className="flex flex-wrap gap-x-8 gap-y-3">
        {cells.map((c) => (
          <div key={c.label}>
            <p className="font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
              {c.label}
            </p>
            <p
              className={`mt-0.5 font-display text-lg tabular-nums ${
                c.hot ? "text-coral" : "text-text-primary"
              }`}
            >
              {c.value}
            </p>
          </div>
        ))}
      </div>
      {conditions.caption && (
        <p className="mt-3 font-body text-sm italic text-text-secondary">
          {conditions.caption}
        </p>
      )}
    </div>
  );
}

// ── Act 2 pieces ───────────────────────────────────────────────────────────

function SplitsTable({ splits }: { splits: AthleteWorkoutDetail["splits"] }) {
  const anyAdj = splits.some((s) => s.adj);

  return (
    <div className="mt-4 overflow-x-auto">
      <table className="w-full min-w-[420px] border-collapse">
        <thead>
          <tr className="border-b border-divider">
            <th className="pb-2 text-left font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
              Segment
            </th>
            <th className="pb-2 text-right font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
              Pace
            </th>
            {anyAdj && (
              <th className="pb-2 text-right font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
                Heat-adj
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {splits.map((s, i) => (
            <tr key={`${s.name}-${i}`} className="border-b border-divider-soft last:border-0">
              <td className="py-2.5 font-body text-sm text-text-primary">{s.name}</td>
              <td
                className={`py-2.5 text-right font-mono text-sm tabular-nums ${
                  s.pace === null
                    ? "text-text-tertiary"
                    : s.onTarget
                      ? "text-pace-lt"
                      : "text-text-secondary"
                }`}
              >
                {s.pace ?? "not run"}
              </td>
              {anyAdj && (
                <td className="py-2.5 text-right font-mono text-sm tabular-nums text-text-secondary">
                  {s.adj ?? ""}
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function NiggleChip({ niggle }: { niggle: WorkoutNiggle }) {
  // Detection, not diagnosis: area and side only. Neutral ink, no severity.
  const label = niggle.side ? `${niggle.side} ${niggle.body_area}` : niggle.body_area;
  return (
    <span className="rounded-full bg-coral/10 px-2.5 py-1 font-mono text-[10px] uppercase tracking-[0.1em] text-coral">
      {label}
    </span>
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────

const SOURCE_LINE: Record<string, string> = {
  voice_log: "Recorded as a voice memo",
  manual: "Logged by hand",
  strava: "Synced from Strava",
  auto_sync: "Synced automatically",
  healthkit: "Synced from HealthKit",
  check_in: "Logged as a check-in",
};

function sourceLine(source: string | null): string {
  if (!source) return "Logged";
  return SOURCE_LINE[source] ?? "Logged";
}

// The enrichment helpers mark emphasis with **bold** for the coach drawer's
// markdown-ish renderer. This surface renders plain text, so strip it rather
// than print literal asterisks.
function stripEmphasis(s: string): string {
  return s.replace(/\*\*/g, "");
}

function parseLocalDate(iso: string): Date {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Date(y, m - 1, d);
}

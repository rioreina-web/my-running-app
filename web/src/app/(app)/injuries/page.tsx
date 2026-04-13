import { createClient } from "@/lib/supabase/server";
import { daysSince } from "@/lib/utils";
import type { Injury } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { MoodBadge } from "@/components/ui/mood-badge";
import { InjuryTimeline } from "@/components/charts/injury-timeline";

export default async function InjuriesPage() {
  const supabase = await createClient();

  const { data } = await supabase
    .from("injuries")
    .select(
      "id, body_area, side, severity, status, first_reported_at, source_text, ai_analysis"
    )
    .order("first_reported_at", { ascending: false });

  const injuries: Injury[] = data || [];
  const active = injuries.filter(
    (i) => i.status === "active" || i.status === "monitoring"
  );
  const resolved = injuries.filter((i) => i.status === "resolved");

  // Timeline data
  const timelineData = injuries.map((i) => ({
    id: i.id,
    bodyArea: `${i.side !== "unknown" ? capitalize(i.side) + " " : ""}${capitalize(i.body_area)}`,
    severity: i.severity,
    startDate: i.first_reported_at,
    status: i.status,
  }));

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <h1 className="font-display text-3xl text-text-primary">Injuries</h1>

      {/* Injury Timeline */}
      {timelineData.length > 0 && (
        <Card>
          <h3 className="mb-3 font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
            Timeline
          </h3>
          <InjuryTimeline injuries={timelineData} />
        </Card>
      )}

      <EditorialDivider />

      {/* Active */}
      <div>
        <SectionHeader title={`Active (${active.length})`} />
        {active.length === 0 ? (
          <Card className="mt-4">
            <p className="text-center text-sm italic text-text-tertiary">
              No active injuries. Keep it up!
            </p>
          </Card>
        ) : (
          <div className="mt-4 space-y-4">
            {active.map((injury) => (
              <InjuryCard key={injury.id} injury={injury} />
            ))}
          </div>
        )}
      </div>

      {/* Resolved */}
      {resolved.length > 0 && (
        <>
          <EditorialDivider />
          <div>
            <SectionHeader title={`Resolved (${resolved.length})`} />
            <div className="mt-4 space-y-2">
              {resolved.map((injury) => (
                <Card key={injury.id} padding="sm">
                  <div className="flex items-center gap-3 text-sm">
                    <span className="w-1 h-4 rounded-full bg-mood-positive" />
                    <span className="text-text-secondary">
                      {injury.side !== "unknown"
                        ? `${capitalize(injury.side)} `
                        : ""}
                      {capitalize(injury.body_area)}
                    </span>
                    <span className="ml-auto font-mono text-xs text-text-tertiary">
                      {daysSince(injury.first_reported_at)} days ago
                    </span>
                    <MoodBadge mood="positive" />
                  </div>
                </Card>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function InjuryCard({ injury }: { injury: Injury }) {
  const days = daysSince(injury.first_reported_at);
  const analysis = injury.ai_analysis as Record<string, unknown> | null;

  return (
    <Card accent>
      {/* Header */}
      <div className="flex items-center gap-3">
        <span className="w-1 h-8 rounded-full bg-mood-injured" />
        <div>
          <div className="font-display text-lg text-text-primary">
            {injury.side !== "unknown"
              ? `${capitalize(injury.side)} `
              : ""}
            {capitalize(injury.body_area)}
          </div>
          <div className="font-mono text-xs text-text-tertiary">
            {days} days &middot;{" "}
            <span
              className={
                injury.status === "active"
                  ? "text-mood-injured"
                  : "text-mood-tired"
              }
            >
              {capitalize(injury.status)}
            </span>
          </div>
        </div>
        <div className="ml-auto text-right">
          <div className="font-mono text-2xl font-semibold text-text-primary">
            {injury.severity}
            <span className="text-sm text-text-tertiary">/10</span>
          </div>
          <div className="font-mono text-[10px] text-text-tertiary">
            severity
          </div>
        </div>
      </div>

      {/* Source text */}
      {injury.source_text && (
        <p className="mt-3 text-sm italic text-text-tertiary">
          &ldquo;{injury.source_text}&rdquo;
        </p>
      )}

      {/* AI Analysis */}
      {analysis && Object.keys(analysis).length > 0 && (
        <div className="mt-4">
          <AnalysisSection analysis={analysis} />
        </div>
      )}
    </Card>
  );
}

function AnalysisSection({
  analysis,
}: {
  analysis: Record<string, unknown>;
}) {
  const riskLevel = analysis.risk_level as string | undefined;
  const likelyCauses = analysis.likely_causes as string[] | undefined;
  const recoveryTimeline = analysis.recovery_timeline as Record<
    string,
    unknown
  > | undefined;
  const immediateActions = analysis.immediate_actions as string[] | undefined;
  const shortTermActions = analysis.short_term_actions as string[] | undefined;
  const ongoingActions = analysis.ongoing_actions as string[] | undefined;
  const overview = analysis.overview as string | undefined;

  return (
    <div>
      <h3 className="mb-2 font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
        AI Analysis
      </h3>
      <div className="rounded-lg bg-bg-elevated p-4 space-y-3">
        {riskLevel && (
          <div className="flex items-center gap-2 text-sm">
            <span className="text-text-tertiary">Risk:</span>
            <span
              className={`font-medium ${
                riskLevel.toLowerCase().includes("high")
                  ? "text-mood-injured"
                  : riskLevel.toLowerCase().includes("moderate")
                    ? "text-mood-tired"
                    : "text-mood-positive"
              }`}
            >
              {riskLevel.toUpperCase()}
            </span>
          </div>
        )}

        {overview && (
          <p className="text-sm leading-relaxed text-text-secondary">
            {overview}
          </p>
        )}

        {likelyCauses && likelyCauses.length > 0 && (
          <div className="text-sm">
            <span className="text-text-tertiary">Likely causes: </span>
            <span className="text-text-secondary">
              {likelyCauses.join(", ")}
            </span>
          </div>
        )}

        {recoveryTimeline && (
          <div className="flex gap-3">
            {recoveryTimeline.best_case != null && (
              <div className="rounded-lg bg-bg-card px-3 py-2 text-center">
                <div className="font-mono text-sm font-bold text-mood-positive">
                  {String(recoveryTimeline.best_case)}d
                </div>
                <div className="text-[10px] text-text-tertiary">best</div>
              </div>
            )}
            {recoveryTimeline.typical != null && (
              <div className="rounded-lg bg-bg-card px-3 py-2 text-center">
                <div className="font-mono text-sm font-bold text-text-primary">
                  {String(recoveryTimeline.typical)}d
                </div>
                <div className="text-[10px] text-text-tertiary">typical</div>
              </div>
            )}
            {recoveryTimeline.conservative != null && (
              <div className="rounded-lg bg-bg-card px-3 py-2 text-center">
                <div className="font-mono text-sm font-bold text-mood-tired">
                  {String(recoveryTimeline.conservative)}d
                </div>
                <div className="text-[10px] text-text-tertiary">conserv.</div>
              </div>
            )}
          </div>
        )}

        {immediateActions && immediateActions.length > 0 && (
          <div className="space-y-1">
            {immediateActions.map((action, i) => (
              <div key={i} className="flex items-start gap-2 text-xs">
                <span className="mt-0.5 text-mood-injured">●</span>
                <span className="text-text-secondary">{action}</span>
              </div>
            ))}
          </div>
        )}
        {shortTermActions && shortTermActions.length > 0 && (
          <div className="space-y-1">
            {shortTermActions.map((action, i) => (
              <div key={i} className="flex items-start gap-2 text-xs">
                <span className="mt-0.5 text-mood-tired">●</span>
                <span className="text-text-secondary">{action}</span>
              </div>
            ))}
          </div>
        )}
        {ongoingActions && ongoingActions.length > 0 && (
          <div className="space-y-1">
            {ongoingActions.map((action, i) => (
              <div key={i} className="flex items-start gap-2 text-xs">
                <span className="mt-0.5 text-mood-positive">●</span>
                <span className="text-text-secondary">{action}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

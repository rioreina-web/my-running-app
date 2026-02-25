import { createClient } from "@/lib/supabase/server";
import { daysSince } from "@/lib/utils";

interface Injury {
  id: string;
  body_area: string;
  side: string;
  severity: number;
  status: string;
  first_reported_at: string;
  source_text: string | null;
  ai_analysis: Record<string, unknown> | null;
}

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

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        INJURIES
      </h1>

      {/* Active */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          ACTIVE ({active.length})
        </h2>
        {active.length === 0 ? (
          <div className="rounded-xl border border-bg-elevated bg-bg-card p-8 text-center text-sm text-text-tertiary">
            No active injuries. Keep it up!
          </div>
        ) : (
          <div className="space-y-4">
            {active.map((injury) => (
              <InjuryCard key={injury.id} injury={injury} />
            ))}
          </div>
        )}
      </div>

      {/* Resolved */}
      {resolved.length > 0 && (
        <div>
          <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
            RESOLVED ({resolved.length})
          </h2>
          <div className="space-y-2">
            {resolved.map((injury) => (
              <div
                key={injury.id}
                className="flex items-center gap-3 rounded-xl border border-bg-elevated bg-bg-card px-4 py-3 text-sm"
              >
                <span className="text-text-tertiary">🩹</span>
                <span className="text-text-secondary">
                  {injury.side !== "unknown"
                    ? `${capitalize(injury.side)} `
                    : ""}
                  {capitalize(injury.body_area)}
                </span>
                <span className="ml-auto font-mono text-xs text-text-tertiary">
                  {daysSince(injury.first_reported_at)} days ago
                </span>
                <span className="rounded-full bg-mood-positive/10 px-2 py-0.5 font-mono text-[10px] text-mood-positive">
                  Resolved
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function InjuryCard({ injury }: { injury: Injury }) {
  const days = daysSince(injury.first_reported_at);
  const analysis = injury.ai_analysis as Record<string, unknown> | null;

  return (
    <div className="rounded-xl border border-mood-injured/30 bg-bg-card p-5 space-y-4">
      {/* Header */}
      <div className="flex items-center gap-3">
        <span className="text-lg">🩹</span>
        <div>
          <div className="font-medium text-text-primary">
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
          <div className="font-mono text-2xl font-bold text-text-primary">
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
        <p className="text-sm italic text-text-tertiary">
          &ldquo;{injury.source_text}&rdquo;
        </p>
      )}

      {/* AI Analysis */}
      {analysis && Object.keys(analysis).length > 0 && (
        <AnalysisSection analysis={analysis} />
      )}
    </div>
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
      <h3 className="mb-2 font-mono text-[10px] tracking-widest text-text-tertiary">
        ✨ AI ANALYSIS
      </h3>
      <div className="rounded-lg bg-bg-elevated p-4 space-y-3">
        {/* Risk level */}
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

        {/* Overview */}
        {overview && (
          <p className="text-sm leading-relaxed text-text-secondary">
            {overview}
          </p>
        )}

        {/* Likely causes */}
        {likelyCauses && likelyCauses.length > 0 && (
          <div className="text-sm">
            <span className="text-text-tertiary">Likely causes: </span>
            <span className="text-text-secondary">
              {likelyCauses.join(", ")}
            </span>
          </div>
        )}

        {/* Recovery timeline */}
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

        {/* Actions */}
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

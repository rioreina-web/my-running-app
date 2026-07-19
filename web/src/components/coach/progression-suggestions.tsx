"use client";

/**
 * "Suggested progressions" strip for the duplicate-workout flow.
 *
 * Candidates are generated CLIENT-SIDE by the pure, deterministic
 * `generateProgressionCandidates` (workout-helpers.ts) — a closed move set
 * that never changes the pace zone. The optional LLM layer
 * (`/api/suggest-progression` → suggest-workout-progression edge function)
 * only reorders the candidates and attaches a one-sentence advisory note to
 * each; if it's unreachable or returns anything invalid, the deterministic
 * candidates render without notes (graceful degradation).
 *
 * AI advises, never acts: selecting a card pre-fills the step editor; the
 * coach can still edit everything and must save explicitly.
 *
 * Design-system note: coral is punctuation — only the selected card carries
 * it, one accent per cluster.
 */

import { useEffect, useMemo, useState } from "react";
import {
  generateProgressionCandidates,
  describeWorkoutLine,
  type ProgressionCandidate,
  type WorkoutStep,
} from "./workout-helpers";

interface SuggestionAnnotation {
  id: string;
  note?: string;
}

export function ProgressionSuggestions({
  sourceName,
  sourceSteps,
  onApply,
}: {
  sourceName: string;
  sourceSteps: WorkoutStep[];
  /** Replace the step editor's contents. `null` id = back to the original. */
  onApply: (steps: WorkoutStep[], candidateId: string | null) => void;
}) {
  const candidates = useMemo(
    () => generateProgressionCandidates(sourceSteps),
    [sourceSteps],
  );
  const sourceDetail = useMemo(
    () => describeWorkoutLine(sourceSteps),
    [sourceSteps],
  );

  const [selectedId, setSelectedId] = useState<string | null>(null);
  // Notes + ordering from the advisory LLM layer. Null until (and unless)
  // the fetch succeeds — the deterministic order renders either way.
  const [annotations, setAnnotations] = useState<SuggestionAnnotation[] | null>(null);
  const [loadingNotes, setLoadingNotes] = useState(false);

  useEffect(() => {
    if (candidates.length === 0) return;
    let cancelled = false;
    setLoadingNotes(true);
    (async () => {
      try {
        const res = await fetch("/api/suggest-progression", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            sourceWorkout: { name: sourceName, summary: sourceDetail },
            candidates: candidates.map((c) => ({
              id: c.id,
              label: c.label,
              detail: c.detail,
            })),
          }),
        });
        if (!res.ok) return; // deterministic fallback
        const data = (await res.json()) as {
          annotated?: boolean;
          suggestions?: SuggestionAnnotation[];
        };
        if (cancelled || !data.annotated || !Array.isArray(data.suggestions)) return;
        // Belt-and-braces: only accept ids we generated. The edge function
        // validates too, but the client never trusts unvalidated ids.
        const known = new Set(candidates.map((c) => c.id));
        const valid = data.suggestions.filter((s) => known.has(s.id));
        if (valid.length > 0) setAnnotations(valid);
      } catch {
        // Unreachable edge function → deterministic candidates, no notes.
      } finally {
        if (!cancelled) setLoadingNotes(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // candidates derive purely from sourceSteps; sourceDetail likewise.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sourceSteps]);

  if (candidates.length === 0) return null;

  // Apply the advisory ordering (annotated first, in the LLM's order;
  // anything it skipped keeps deterministic order after), and attach notes.
  const ordered: Array<ProgressionCandidate & { note?: string }> = (() => {
    if (!annotations) return candidates;
    const byId = new Map(candidates.map((c) => [c.id, c]));
    const seen = new Set<string>();
    const result: Array<ProgressionCandidate & { note?: string }> = [];
    for (const a of annotations) {
      const c = byId.get(a.id);
      if (!c || seen.has(a.id)) continue;
      seen.add(a.id);
      result.push({ ...c, note: a.note });
    }
    for (const c of candidates) {
      if (!seen.has(c.id)) result.push(c);
    }
    return result;
  })();

  const select = (candidate: ProgressionCandidate | null) => {
    const id = candidate?.id ?? null;
    setSelectedId(id);
    // Deep-clone on apply — WorkoutStep is plain JSON data, and cloning
    // guarantees later editor mutations can never reach back into the
    // memoized candidate (or the source) by shared reference.
    const steps = candidate ? candidate.steps : sourceSteps;
    onApply(JSON.parse(JSON.stringify(steps)) as WorkoutStep[], id);
  };

  const cardBase =
    "text-left rounded-lg border px-3 py-2.5 transition-colors flex flex-col gap-1 min-w-[180px] max-w-[240px] shrink-0";
  const cardIdle =
    "border-[var(--color-divider)] bg-white hover:border-[var(--color-text-tertiary)]";
  const cardSelected = "border-[var(--color-coral)] bg-white";

  return (
    <div className="space-y-2">
      <div className="flex items-baseline gap-2 flex-wrap">
        <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
          Suggested progressions
        </span>
        <span className="text-[11px] text-[var(--color-text-secondary)]">
          Advisory only — pick one to pre-fill the editor, then adjust anything.
        </span>
        {loadingNotes && (
          <span className="text-[10px] italic text-[var(--color-text-tertiary)]">
            fetching notes…
          </span>
        )}
      </div>

      <div className="flex gap-2 overflow-x-auto pb-1">
        {/* Original — always first, always available to return to. */}
        <button
          type="button"
          onClick={() => select(null)}
          className={`${cardBase} ${selectedId === null ? cardSelected : cardIdle}`}
        >
          <span className="text-[12px] font-semibold text-[var(--color-text-primary)]">
            As written
          </span>
          {sourceDetail && (
            <span className="font-mono text-[10px] text-[var(--color-text-tertiary)]">
              {sourceDetail}
            </span>
          )}
        </button>

        {ordered.map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => select(c)}
            className={`${cardBase} ${selectedId === c.id ? cardSelected : cardIdle}`}
          >
            <span className="text-[12px] font-semibold text-[var(--color-text-primary)]">
              {c.label}
            </span>
            {c.detail && (
              <span className="font-mono text-[10px] text-[var(--color-text-tertiary)]">
                {c.detail}
              </span>
            )}
            {c.note && (
              <span className="text-[11px] leading-snug text-[var(--color-text-secondary)] italic">
                {c.note}
              </span>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}

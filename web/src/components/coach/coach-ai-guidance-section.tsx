"use client";

import { useState } from "react";

/**
 * Coach AI guidance — the "rules & guardrails" the assistant reasons inside.
 * (adaptive-plan-builder-opus-buildplan-2026-07-05.md, Phase 2.)
 *
 * The coach writes hard rules (constraints the assistant won't violate),
 * softer guidelines (preferences), and a silent context note. The
 * reschedule-plan assistant reads them when it proposes changes. It proposes;
 * the athlete/coach decides. Nothing here auto-applies.
 *
 * Stored on plan_templates.coach_ai_guidance (JSONB). Ports the "Rules,
 * guidelines & notes" section of prototypes/adaptive-plan-builder.html,
 * verbatim in tone.
 */

export type RuleStrength = "hard" | "guide";

export interface CoachRule {
  on: boolean;
  strength: RuleStrength;
  text: string;
}

export interface CoachAiGuidance {
  rules: CoachRule[];
  note: string;
}

export const EMPTY_COACH_GUIDANCE: CoachAiGuidance = { rules: [], note: "" };

/** Hydrate the stored JSONB into a well-formed CoachAiGuidance, dropping any
 *  malformed rows so the editor never renders garbage. */
export function normalizeCoachGuidance(raw: unknown): CoachAiGuidance {
  if (!raw || typeof raw !== "object") return { ...EMPTY_COACH_GUIDANCE, rules: [] };
  const obj = raw as Record<string, unknown>;
  const rules: CoachRule[] = Array.isArray(obj.rules)
    ? (obj.rules as unknown[]).flatMap((r) => {
        if (!r || typeof r !== "object") return [];
        const row = r as Record<string, unknown>;
        const text = typeof row.text === "string" ? row.text : "";
        if (!text.trim()) return [];
        return [
          {
            on: row.on !== false, // default on
            strength: row.strength === "guide" ? "guide" : "hard",
            text,
          },
        ];
      })
    : [];
  const note = typeof obj.note === "string" ? obj.note : "";
  return { rules, note };
}

/** Drop empty-text rules before persisting so a half-typed row never saves. */
export function serializeCoachGuidance(g: CoachAiGuidance): CoachAiGuidance | null {
  const rules = g.rules.filter((r) => r.text.trim().length > 0);
  const note = g.note.trim();
  if (rules.length === 0 && note === "") return null; // nothing to store
  return { rules, note };
}

export function CoachAiGuidanceSection({
  guidance,
  onChange,
}: {
  guidance: CoachAiGuidance;
  onChange: (next: CoachAiGuidance) => void;
}) {
  const [open, setOpen] = useState(false);

  const setRule = (i: number, patch: Partial<CoachRule>) => {
    onChange({
      ...guidance,
      rules: guidance.rules.map((r, idx) => (idx === i ? { ...r, ...patch } : r)),
    });
  };
  const addRule = () => {
    onChange({
      ...guidance,
      rules: [...guidance.rules, { on: true, strength: "hard", text: "" }],
    });
  };
  const removeRule = (i: number) => {
    onChange({ ...guidance, rules: guidance.rules.filter((_, idx) => idx !== i) });
  };

  const activeCount = guidance.rules.filter((r) => r.on && r.text.trim()).length;
  const summary =
    activeCount > 0
      ? `${activeCount} rule${activeCount === 1 ? "" : "s"}${guidance.note.trim() ? " · note" : ""}`
      : guidance.note.trim()
        ? "note only"
        : "none set";

  return (
    <div className="border border-divider rounded-lg bg-bg-base">
      <button
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-4 py-2.5 text-left"
      >
        <div className="flex items-baseline gap-3">
          <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
            Rules &amp; guardrails
          </span>
          <span className="text-xs text-text-secondary">{summary}</span>
        </div>
        <span className="text-xs text-text-tertiary">{open ? "Hide" : "Edit"}</span>
      </button>

      {open && (
        <div className="px-4 pb-4 space-y-4 border-t border-divider pt-4">
          <p className="text-[11px] text-text-secondary leading-relaxed max-w-[52ch]">
            The assistant reasons inside these lines when it proposes a
            reschedule. Hard rules it won&rsquo;t cross; guidelines it bends only
            when it must, and says which one and why. It proposes&nbsp;— you
            decide. Nothing is applied until you confirm.
          </p>

          {/* Rules */}
          <div className="space-y-2">
            {guidance.rules.map((r, i) => (
              <div key={i} className={`flex items-center gap-2 ${r.on ? "" : "opacity-50"}`}>
                <label className="flex items-center cursor-pointer" title={r.on ? "Active" : "Muted"}>
                  <input
                    type="checkbox"
                    checked={r.on}
                    onChange={(e) => setRule(i, { on: e.target.checked })}
                    className="accent-[var(--color-coral,#E8764A)]"
                  />
                </label>
                <select
                  value={r.strength}
                  onChange={(e) => setRule(i, { strength: e.target.value as RuleStrength })}
                  className="text-[11px] font-mono uppercase tracking-wider bg-transparent border-b border-divider text-text-secondary focus:outline-none focus:border-coral cursor-pointer py-1"
                >
                  <option value="hard">hard rule</option>
                  <option value="guide">guideline</option>
                </select>
                <input
                  type="text"
                  value={r.text}
                  placeholder="e.g. never schedule quality on Mondays"
                  onChange={(e) => setRule(i, { text: e.target.value })}
                  className="flex-1 min-w-0 text-xs bg-transparent border-b border-divider focus:outline-none focus:border-coral py-1"
                />
                <button
                  onClick={() => removeRule(i)}
                  className="text-text-tertiary hover:text-coral transition-colors px-1"
                  title="Remove"
                >
                  ×
                </button>
              </div>
            ))}
            <button
              onClick={addRule}
              className="text-xs text-text-secondary hover:text-text-primary border border-divider rounded-md px-2.5 py-1 transition-colors"
            >
              + Add a rule
            </button>
          </div>

          {/* Silent note */}
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary mb-1.5">
              Silent note
            </p>
            <textarea
              value={guidance.note}
              placeholder="e.g. Maya tends to overcook rep one — bias her toward controlled starts."
              onChange={(e) => onChange({ ...guidance, note: e.target.value })}
              rows={2}
              className="w-full text-xs bg-bg-elevated border border-divider rounded-md px-2.5 py-2 focus:outline-none focus:border-coral resize-y leading-relaxed"
            />
            <p className="text-[11px] text-text-tertiary mt-1">
              Never shown to the athlete. It shapes how the assistant reasons,
              quietly.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

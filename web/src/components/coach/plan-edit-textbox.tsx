"use client";

// Free-text plan adjustments — "make Tuesday an easy day", "cut the long run
// to 14", "swap Saturday for something shorter". Calls the deployed
// `plan-edit` edge function, which reads the athlete's real scheduled week
// and returns either a resolved diff (ready to approve) or a question with
// real, tappable options (never a guess) — see
// `supabase/functions/plan-edit/index.ts` for the full contract.
//
// PREVIEW ONLY. `plan-edit` never writes to scheduled_workouts — there is no
// apply button here on purpose, because there is nowhere for "apply" to send
// a proposed change yet (that wiring is the next piece, through
// edit-scheduled-workout / shift-day once a diff is approved). This is
// useful today as exactly what it says: a preview of what an instruction
// would do, weighed against the athlete's real week.
//
// Tapping a question's option doesn't resolve anything client-side — the
// resolution logic is intentionally not duplicated here. It fills a follow-up
// into the box ("For 'Tuesday': threshold") so the coach can send it back
// through the same round trip that already answered the rest.

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

interface PlanEditOp {
  kind: string;
  targetHint: string;
  [key: string]: unknown;
}

interface ResolvedDiff {
  workoutId: string;
  day: string;
  before: string;
  after: string;
  op: PlanEditOp;
}

interface PlanEditOption {
  label: string;
  value: string;
}

interface PlanEditQuestion {
  id: string;
  question: string;
  op: PlanEditOp;
  options: PlanEditOption[];
}

interface PlanEditResponse {
  resolved: ResolvedDiff[];
  questions: PlanEditQuestion[];
  notFound: PlanEditOp[];
  warnings: string[];
  unparsed: string[];
  note?: string;
  error?: string;
}

function todayPlus(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export function PlanEditTextBox({ athleteUserId }: { athleteUserId: string }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<PlanEditResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submit = async (overrideText?: string) => {
    const query = (overrideText ?? text).trim();
    if (!query || busy) return;
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const { data, error: fnError } = await supabase.functions.invoke<PlanEditResponse>(
        "plan-edit",
        {
          body: {
            text: query,
            start_date: todayPlus(0),
            end_date: todayPlus(13), // next two weeks — matches this coach's usual planning horizon
            athlete_user_id: athleteUserId,
          },
        },
      );
      if (fnError) {
        setError("Couldn't reach the plan editor. Try again in a moment.");
        setResult(null);
      } else {
        setResult(data ?? null);
      }
    } finally {
      setBusy(false);
    }
  };

  const tapOption = (q: PlanEditQuestion, o: PlanEditOption) => {
    setText(`For "${q.op.targetHint}": ${o.label}`);
  };

  return (
    <div className="border border-divider rounded-xl p-4 bg-bg-elevated space-y-3">
      <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
        Adjust the plan
      </p>

      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => {
          if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
            e.preventDefault();
            submit();
          }
        }}
        rows={2}
        placeholder={'"make Tuesday an easy day", "cut the long run to 14 miles", "swap Saturday for something shorter"'}
        className="w-full px-3 py-2 text-sm font-mono border border-divider rounded-lg bg-bg-card focus:outline-none focus:border-coral transition-colors placeholder:text-text-secondary resize-y"
      />

      <div className="flex items-center justify-between gap-3">
        <p className="text-[11px] italic text-text-secondary leading-snug">
          Preview only — nothing saves until you apply it by hand below.
        </p>
        <button
          type="button"
          onClick={() => submit()}
          disabled={!text.trim() || busy}
          className="shrink-0 px-3 py-1.5 text-xs font-medium border border-divider rounded-lg text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors disabled:opacity-40"
        >
          {busy ? "Reading…" : "Preview"}
        </button>
      </div>

      {error && <p className="text-[11px] text-[var(--color-danger)]">{error}</p>}

      {result?.note && (
        <p className="text-[11px] text-text-secondary italic">{result.note}</p>
      )}

      {result && result.resolved.length > 0 && (
        <div className="space-y-1.5 pt-1">
          {result.resolved.map((d, i) => (
            <div key={i} className="text-[12px] leading-snug border-l-2 border-divider pl-2.5">
              <span className="font-mono text-[10px] text-text-tertiary uppercase tracking-wide mr-1.5">
                {d.day}
              </span>
              <span className="text-text-secondary line-through mr-1.5">{d.before}</span>
              <span className="text-text-primary">→ {d.after}</span>
            </div>
          ))}
        </div>
      )}

      {result && result.questions.length > 0 && (
        <div className="space-y-2 pt-1">
          {result.questions.map((q) => (
            <div key={q.id} className="space-y-1.5">
              <p className="text-[11px] text-text-primary leading-snug">{q.question}</p>
              <div className="flex flex-wrap gap-1">
                {q.options.map((o) => (
                  <button
                    key={o.value}
                    type="button"
                    onClick={() => tapOption(q, o)}
                    className="px-2 py-0.5 text-[11px] rounded-full border border-divider text-text-secondary hover:border-coral hover:text-text-primary transition-colors"
                  >
                    {o.label}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {result && result.notFound.length > 0 && (
        <p className="text-[11px] text-[var(--color-warning)] leading-snug">
          Couldn&apos;t find a workout matching:{" "}
          {result.notFound.map((op) => `"${op.targetHint}"`).join(", ")}.
        </p>
      )}

      {result && result.unparsed.length > 0 && (
        <p className="text-[11px] text-[var(--color-warning)] leading-snug">
          Didn&apos;t understand: {result.unparsed.join(" · ")}
        </p>
      )}

      {result && result.warnings.length > 0 && (
        <ul className="text-[11px] text-text-secondary leading-snug list-none space-y-0.5">
          {result.warnings.map((w, i) => (
            <li key={i}>{w}</li>
          ))}
        </ul>
      )}

      {result &&
        result.resolved.length === 0 &&
        result.questions.length === 0 &&
        result.notFound.length === 0 &&
        result.unparsed.length === 0 &&
        result.warnings.length === 0 && (
          <p className="text-[11px] text-text-secondary italic">
            Nothing scheduled in the next two weeks to adjust.
          </p>
        )}
    </div>
  );
}

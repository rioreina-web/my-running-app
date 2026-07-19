"use client";

import Link from "next/link";
import { useState } from "react";
import { Check, Copy, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

interface PlanTemplate {
  id: string;
  name: string;
  description?: string;
  target_distance: string;
  duration_weeks: number;
  is_published: boolean;
  join_code?: string;
  subscriber_count: number;
  created_at: string;
}

const DISTANCE_LABELS: Record<string, string> = {
  marathon: "Marathon",
  half_marathon: "Half Marathon",
  "10k": "10K",
  "5k": "5K",
};

// Columns NOT carried onto a duplicate — the copy is a fresh draft:
//   id / created_at / updated_at  → let the DB regenerate
//   join_code                     → UNIQUE; a duplicate has no code until published
//   is_published                  → duplicates start as drafts
//   subscriber_count              → the copy has no athletes
// Everything else (coach_id, name, weeks, phase_config, day_structure,
// weekly_mileage_targets, doubles_config, coach_ai_guidance, …) is copied
// verbatim, so the swap survives future column additions.
const DUP_OMIT = new Set([
  "id",
  "created_at",
  "updated_at",
  "join_code",
  "is_published",
  "subscriber_count",
]);

export function PlanTemplateRow({
  plan,
  isLast,
}: {
  plan: PlanTemplate;
  isLast: boolean;
}) {
  const [copiedCode, setCopiedCode] = useState(false);
  const [busy, setBusy] = useState<null | "dup" | "del">(null);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const supabase = createClient();

  const copyJoinCode = async () => {
    if (plan.join_code) {
      await navigator.clipboard.writeText(plan.join_code);
      setCopiedCode(true);
      setTimeout(() => setCopiedCode(false), 2000);
    }
  };

  const publishPlan = async () => {
    const code = generateJoinCode();
    await supabase
      .from("plan_templates")
      .update({ is_published: true, join_code: code })
      .eq("id", plan.id);
    window.location.reload();
  };

  // Duplicate — copy the full row into a fresh draft. Coach ownership
  // (coach_id) is copied through, so the RLS insert check passes.
  const duplicatePlan = async () => {
    setNotice(null);
    setBusy("dup");
    const { data: full, error } = await supabase
      .from("plan_templates")
      .select("*")
      .eq("id", plan.id)
      .single();
    if (error || !full) {
      setBusy(null);
      setNotice("Couldn't read this plan to duplicate it.");
      return;
    }
    const copy: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(full)) {
      if (!DUP_OMIT.has(k)) copy[k] = v;
    }
    copy.name = `${plan.name} (copy)`;
    const { error: insErr } = await supabase.from("plan_templates").insert(copy);
    if (insErr) {
      setBusy(null);
      setNotice(`Couldn't duplicate: ${insErr.message}`);
      return;
    }
    window.location.reload();
  };

  // Delete is blocked by the DB (ON DELETE RESTRICT) whenever an athlete is
  // subscribed, so guard on that first and give the coach a clear reason.
  const requestDelete = () => {
    setNotice(null);
    if (plan.subscriber_count > 0) {
      setNotice(
        `${plan.subscriber_count} athlete${plan.subscriber_count === 1 ? "" : "s"} subscribed — remove them before deleting.`,
      );
      return;
    }
    setConfirmingDelete(true);
  };

  const confirmDelete = async () => {
    setBusy("del");
    // Authoritative re-check at action time (any status counts, matching the
    // RESTRICT foreign key) so a stale count can't cause a silent FK error.
    const { count } = await supabase
      .from("athlete_plan_subscriptions")
      .select("id", { count: "exact", head: true })
      .eq("plan_template_id", plan.id);
    if ((count ?? 0) > 0) {
      setBusy(null);
      setConfirmingDelete(false);
      setNotice(
        `${count} athlete${count === 1 ? "" : "s"} subscribed — remove them before deleting.`,
      );
      return;
    }
    const { data: deleted, error } = await supabase
      .from("plan_templates")
      .delete()
      .eq("id", plan.id)
      .select("id");
    if (error) {
      setBusy(null);
      setConfirmingDelete(false);
      setNotice(`Couldn't delete: ${error.message}`);
      return;
    }
    if (!deleted || deleted.length === 0) {
      setBusy(null);
      setConfirmingDelete(false);
      setNotice("Couldn't delete this plan (permission).");
      return;
    }
    window.location.reload();
  };

  const btnBase =
    "text-xs px-2.5 py-1 border border-[var(--color-divider)] rounded-md text-[var(--color-text-secondary)] transition-colors disabled:opacity-50 disabled:pointer-events-none";

  return (
    <div
      className={`bg-white ${!isLast ? "border-b border-[var(--color-divider)]" : ""}`}
    >
      <div className="flex items-center gap-4 px-5 py-4 hover:bg-[var(--color-bg-elevated)] transition-colors">
        {/* Status dot */}
        <div
          className={`w-2 h-2 rounded-full flex-shrink-0 ${
            plan.is_published ? "bg-[#4A9E6B]" : "bg-[#9B9590]"
          }`}
        />

        {/* Plan info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h3 className="font-semibold text-[var(--color-text-primary)] text-sm truncate">
              {plan.name}
            </h3>
            {plan.is_published ? (
              <span className="text-[10px] font-semibold text-white bg-[#4A9E6B] px-1.5 py-0.5 rounded-full">
                LIVE
              </span>
            ) : (
              <span className="text-[10px] font-semibold text-[var(--color-text-tertiary)] bg-[var(--color-divider)] px-1.5 py-0.5 rounded-full">
                DRAFT
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 mt-0.5 text-xs text-[var(--color-text-secondary)]">
            <span className="text-[var(--color-coral)]">
              {DISTANCE_LABELS[plan.target_distance] ?? plan.target_distance}
            </span>
            <span>·</span>
            <span>{plan.duration_weeks} weeks</span>
            {plan.subscriber_count > 0 && (
              <>
                <span>·</span>
                <span>
                  {plan.subscriber_count} athlete{plan.subscriber_count !== 1 ? "s" : ""}
                </span>
              </>
            )}
            {plan.join_code && (
              <>
                <span>·</span>
                <span className="font-mono text-[var(--color-text-tertiary)]">
                  {plan.join_code}
                </span>
              </>
            )}
          </div>
        </div>

        {/* Actions */}
        {confirmingDelete ? (
          <div className="flex items-center gap-2 flex-shrink-0">
            <span className="text-xs text-[var(--color-text-secondary)]">Delete plan?</span>
            <button
              onClick={confirmDelete}
              disabled={busy !== null}
              className="text-xs px-2.5 py-1 rounded-md bg-danger text-white hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {busy === "del" ? "Deleting…" : "Delete"}
            </button>
            <button
              onClick={() => setConfirmingDelete(false)}
              disabled={busy !== null}
              className={btnBase + " hover:text-[var(--color-text-primary)]"}
            >
              Cancel
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-2 flex-shrink-0">
            {plan.join_code && (
              <button
                onClick={copyJoinCode}
                className={btnBase + " hover:text-[var(--color-coral)] hover:border-[var(--color-coral)] inline-flex items-center gap-1"}
              >
                {copiedCode ? (
                  <>
                    <Check size={12} strokeWidth={2.5} aria-hidden /> Copied
                  </>
                ) : (
                  "Copy Code"
                )}
              </button>
            )}
            {!plan.is_published && (
              <button
                onClick={publishPlan}
                className="text-xs px-2.5 py-1 bg-[#4A9E6B] text-white rounded-md hover:opacity-90 transition-opacity"
              >
                Publish
              </button>
            )}
            <button
              onClick={duplicatePlan}
              disabled={busy !== null}
              className={btnBase + " hover:text-[var(--color-coral)] hover:border-[var(--color-coral)] inline-flex items-center gap-1"}
            >
              <Copy size={12} strokeWidth={2} aria-hidden />
              {busy === "dup" ? "Duplicating…" : "Duplicate"}
            </button>
            <Link
              href={`/coach-portal/plans/${plan.id}/builder`}
              className={btnBase + " hover:text-[var(--color-coral)] hover:border-[var(--color-coral)]"}
            >
              Edit
            </Link>
            <button
              onClick={requestDelete}
              disabled={busy !== null}
              aria-label="Delete plan"
              title="Delete plan"
              className="text-xs p-1.5 rounded-md text-text-tertiary hover:text-danger hover:bg-danger/10 transition-colors disabled:opacity-50"
            >
              <Trash2 size={14} strokeWidth={2} aria-hidden />
            </button>
          </div>
        )}
      </div>

      {notice && (
        <div className="px-5 pb-3 -mt-1 text-xs text-[var(--color-text-secondary)]">
          {notice}
        </div>
      )}
    </div>
  );
}

function generateJoinCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () =>
    chars[Math.floor(Math.random() * chars.length)]
  ).join("");
}

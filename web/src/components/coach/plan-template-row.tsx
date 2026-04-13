"use client";

import Link from "next/link";
import { useState } from "react";
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

export function PlanTemplateRow({
  plan,
  isLast,
}: {
  plan: PlanTemplate;
  isLast: boolean;
}) {
  const [copiedCode, setCopiedCode] = useState(false);
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

  return (
    <div
      className={`flex items-center gap-4 px-5 py-4 bg-white hover:bg-[var(--color-bg-elevated)] transition-colors ${
        !isLast ? "border-b border-[var(--color-divider)]" : ""
      }`}
    >
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
      <div className="flex items-center gap-2 flex-shrink-0">
        {plan.join_code && (
          <button
            onClick={copyJoinCode}
            className="text-xs px-2.5 py-1 border border-[var(--color-divider)] rounded-md text-[var(--color-text-secondary)] hover:text-[var(--color-coral)] hover:border-[var(--color-coral)] transition-colors"
          >
            {copiedCode ? "✓ Copied" : "Copy Code"}
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
        <Link
          href={`/coach-portal/plans/${plan.id}/builder`}
          className="text-xs px-2.5 py-1 border border-[var(--color-divider)] rounded-md text-[var(--color-text-secondary)] hover:text-[var(--color-coral)] hover:border-[var(--color-coral)] transition-colors"
        >
          Edit
        </Link>
      </div>
    </div>
  );
}

function generateJoinCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () =>
    chars[Math.floor(Math.random() * chars.length)]
  ).join("");
}

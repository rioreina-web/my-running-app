// Shared structure renderer used by the workout library card, the
// edit-page preview, and the plan-builder picker. Takes a flat steps
// array and groups it into warmup / blocks / cooldown via the
// `groupStepsIntoSections` helper. Renders each block as a row with a
// colored stripe, primary label, and pace zone + range.
//
// Two density variants:
//   - "compact"  — for cards in the library grid. Tighter spacing,
//                  smaller type, suppresses notes.
//   - "detailed" — for full pages. Roomier, shows notes, larger type.
//
// Pace rendering uses the safe* helpers so missing-paceZone steps from
// old workouts render as "(no pace)" rather than "NaN:NaN-NaN:NaN/mi".

import {
  groupStepsIntoSections,
  formatStepDuration,
  safePaceLabel,
  safePaceRangeLabel,
  type WorkoutStep,
  type WorkoutStepBlock,
  type AthletePaceTable,
  type PaceZone,
} from "./workout-helpers";

interface Props {
  steps: WorkoutStep[];
  /// Optional athlete pace table for resolving zone → actual sec/mile.
  /// When absent, falls back to REFERENCE_PACE_SEC_PER_MILE inside the
  /// helper.
  athletePaces?: AthletePaceTable;
  /// Density preset. "compact" for cards, "detailed" for full pages.
  variant?: "compact" | "detailed";
  /// When supplied, used to color the active-step stripe. Defaults to
  /// the coral active color so the card's header chip and its main set
  /// don't need to coordinate.
  activeColor?: string;
}

// Step type → stripe color. Matches the existing WORKOUT_TYPES palette
// from workout-template-form. Keeping these as inline hex for now;
// design-system follow-up moves them to CSS vars.
const STRIPE_COLOR: Record<string, string> = {
  warmup:   "#C0DD97",
  cooldown: "#C0DD97",
  active:   "#D85A30",
  recovery: "#9B9590",
  rest:     "#9B9590",
};

function StepRow({
  primaryLabel,
  paceLabel,
  paceRange,
  stripeColor,
  recoveryLabel,
  recoveryPace,
  repsBadge,
  variant,
  highlighted,
  notes,
}: {
  primaryLabel: string;
  paceLabel: string | null;
  paceRange: string | null;
  stripeColor: string;
  recoveryLabel?: string;
  recoveryPace?: string | null;
  repsBadge?: string;
  variant: "compact" | "detailed";
  highlighted?: boolean;
  notes?: string;
}) {
  const isCompact = variant === "compact";
  const rowPadding = isCompact ? "py-1" : "py-2";
  const primaryFont = isCompact ? "text-[13px]" : "text-sm";
  const paceFont = isCompact ? "text-[11px]" : "text-xs";

  return (
    <div
      className={`grid grid-cols-[4px_1fr_auto] gap-2.5 items-stretch ${rowPadding} ${
        highlighted ? "bg-[#FAECE7] rounded-md px-2 -mx-1" : ""
      }`}
    >
      <span
        className="rounded-sm min-h-[26px]"
        style={{ backgroundColor: stripeColor }}
      />
      <div className="flex flex-col justify-center min-w-0">
        <div className={`${primaryFont} text-[var(--color-text-primary)] truncate`}>
          {primaryLabel}
        </div>
        {(paceLabel || paceRange) && (
          <div className={`${paceFont} text-[var(--color-text-tertiary)] font-mono truncate`}>
            {paceLabel}
            {paceLabel && paceRange && (
              <span className="text-[var(--color-border-secondary)]"> · </span>
            )}
            {paceRange}
          </div>
        )}
        {recoveryLabel && (
          <div
            className={`${paceFont} text-[var(--color-text-tertiary)] mt-0.5 truncate flex items-center gap-1`}
          >
            <span aria-hidden>↳</span>
            <span>
              {recoveryLabel}
              {recoveryPace && (
                <>
                  {" "}
                  <span className="font-mono">·</span>{" "}
                  <span className="font-mono">{recoveryPace}</span>
                </>
              )}
            </span>
          </div>
        )}
        {!isCompact && notes && (
          <div className="text-xs text-[var(--color-text-secondary)] italic mt-0.5 truncate">
            {notes}
          </div>
        )}
      </div>
      {repsBadge && (
        <span className="font-mono text-[11px] text-[var(--color-text-tertiary)] self-center">
          {repsBadge}
        </span>
      )}
    </div>
  );
}

function describeBlock(
  block: WorkoutStepBlock,
  athletePaces: AthletePaceTable | undefined,
): {
  primaryLabel: string;
  paceLabel: string | null;
  paceRange: string | null;
  stripeColor: string;
  recoveryLabel?: string;
  recoveryPace?: string | null;
  repsBadge?: string;
  highlighted?: boolean;
  notes?: string;
} {
  const { step } = block;
  const dur = formatStepDuration(step.durationType, step.durationValue);
  const stripeColor = STRIPE_COLOR[step.stepType] ?? STRIPE_COLOR.active;
  const paceLabel = safePaceLabel(
    step.paceZone,
    step.paceAdjustment,
    step.exactPaceSecPerMile,
  );
  const paceRange = safePaceRangeLabel(
    step.paceZone,
    step.paceAdjustment,
    step.exactPaceSecPerMile,
    athletePaces,
  );

  if (block.kind === "reps") {
    const reps = block.repeats ?? 2;
    let recoveryLabel: string | undefined;
    let recoveryPace: string | null | undefined;
    if (block.recovery) {
      const rdur = formatStepDuration(
        block.recovery.durationType,
        block.recovery.durationValue,
      );
      recoveryLabel = `${rdur} recovery`;
      recoveryPace = safePaceRangeLabel(
        block.recovery.paceZone,
        block.recovery.paceAdjustment,
        block.recovery.exactPaceSecPerMile,
        athletePaces,
      );
    }
    return {
      primaryLabel: `${reps} × ${dur}`,
      paceLabel,
      paceRange,
      stripeColor,
      recoveryLabel,
      recoveryPace,
      repsBadge: `×${reps}`,
      highlighted: true,
      notes: step.notes || undefined,
    };
  }

  // Single step
  return {
    primaryLabel: dur,
    paceLabel,
    paceRange,
    stripeColor,
    notes: step.notes || undefined,
  };
}

export function WorkoutStructure({
  steps,
  athletePaces,
  variant = "compact",
}: Props) {
  const { warmup, blocks, cooldown } = groupStepsIntoSections(steps);

  if (warmup.length === 0 && blocks.length === 0 && cooldown.length === 0) {
    return (
      <div className="text-xs text-[var(--color-text-tertiary)] italic">
        No steps
      </div>
    );
  }

  const gapClass = variant === "compact" ? "gap-1.5" : "gap-2.5";

  // Warmup and cooldown render as single rows with a combined duration
  // when they're all the same duration type — otherwise each step gets
  // its own row. Most coaches author one warmup step per workout, so the
  // combined-row path is the common case.
  function renderSectionAsOneRow(
    section: WorkoutStep[],
    fallbackZone: PaceZone | string | undefined,
  ) {
    if (section.length === 0) return null;
    if (section.length === 1) {
      const s = section[0];
      return (
        <StepRow
          primaryLabel={`${s.stepType === "warmup" ? "Warmup" : "Cooldown"} · ${formatStepDuration(
            s.durationType,
            s.durationValue,
          )}`}
          paceLabel={safePaceLabel(
            s.paceZone ?? fallbackZone,
            s.paceAdjustment,
            s.exactPaceSecPerMile,
          )}
          paceRange={safePaceRangeLabel(
            s.paceZone ?? fallbackZone,
            s.paceAdjustment,
            s.exactPaceSecPerMile,
            athletePaces,
          )}
          stripeColor={STRIPE_COLOR[s.stepType] ?? STRIPE_COLOR.warmup}
          variant={variant}
          notes={s.notes || undefined}
        />
      );
    }
    return (
      <>
        {section.map((s, idx) => (
          <StepRow
            key={s.id ?? idx}
            primaryLabel={`${s.stepType === "warmup" ? "Warmup" : "Cooldown"} · ${formatStepDuration(
              s.durationType,
              s.durationValue,
            )}`}
            paceLabel={safePaceLabel(
              s.paceZone ?? fallbackZone,
              s.paceAdjustment,
              s.exactPaceSecPerMile,
            )}
            paceRange={safePaceRangeLabel(
              s.paceZone ?? fallbackZone,
              s.paceAdjustment,
              s.exactPaceSecPerMile,
              athletePaces,
            )}
            stripeColor={STRIPE_COLOR[s.stepType] ?? STRIPE_COLOR.warmup}
            variant={variant}
          />
        ))}
      </>
    );
  }

  return (
    <div className={`flex flex-col ${gapClass}`}>
      {renderSectionAsOneRow(warmup, "easy")}
      {blocks.map((block, idx) => {
        const props = describeBlock(block, athletePaces);
        return <StepRow key={block.step.id ?? `b-${idx}`} variant={variant} {...props} />;
      })}
      {renderSectionAsOneRow(cooldown, "easy")}
    </div>
  );
}

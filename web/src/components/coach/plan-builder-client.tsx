"use client";

import { useState, useCallback, useMemo } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { WorkoutStepEditor, type WorkoutStep } from "./workout-step-editor";
import {
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  formatPaceSecPerMile,
  weekZoneMiles,
  totalZoneMiles,
  describeWorkoutLine,
  paceShort,
  stepZones,
  headlineZone,
  zoneLabelShort,
  PACE_ZONE_COLORS,
  type ZoneMiles,
  type PaceZone,
} from "./workout-helpers";
import { parseShorthand } from "./workout-shorthand-client";
import { buildClarifications, applyClarification, type Clarification } from "./workout-clarify";
import { PaceReferenceEditor, resolvePaceTable, type PaceAnchor } from "./pace-reference-editor";
import {
  PlanSetupSection,
  buildPhaseRanges,
  phasesToWeekMap,
  type DayStructureEntry,
  type Phase,
} from "./plan-setup-section";
import {
  AthletePreviewRail,
  type PreviewAthlete,
  type PreviewWorkout,
} from "./athlete-preview-rail";
import {
  CoachAiGuidanceSection,
  normalizeCoachGuidance,
  serializeCoachGuidance,
  type CoachAiGuidance,
} from "./coach-ai-guidance-section";
import { PlateStrip } from "@/components/ui/plate-strip";
import { EmptyState } from "@/components/ui/empty-state";
import { DailyVolumeChart, type DayVolume } from "./daily-volume-chart";

interface WorkoutTemplate {
  id: string;
  name: string;
  workout_type: string;
  estimated_distance_miles?: number;
  estimated_duration_minutes?: number;
  tags?: string[];
  workout_data: Record<string, unknown>;
  // Coach-pinned templates sort to the top of the library rail. Column
  // added by migration 20260706*_workout_templates_pinned (authored, pending
  // push); absent = not pinned, so this is inert until the column lands.
  pinned?: boolean;
}

interface PlanTemplateWorkout {
  dayOfWeek: number;
  /** AM is the day's main session; PM is the second run of a 2×-a-day
   *  double. Absent = "am" — backward compatible with every existing
   *  plan blob, and the materializer treats unknown fields as inert. */
  session?: "am" | "pm";
  workoutTemplateId?: string;
  workoutType?: string;
  workoutData?: Record<string, unknown>;
  notes: string;
}

type SessionKey = "am" | "pm";

function sessOf(w: PlanTemplateWorkout): SessionKey {
  return w.session ?? "am";
}

/** Real sessions only — unset placeholder rows and rest days don't count. */
function countSessions(week: PlanTemplateWeek | undefined): number {
  if (!week) return 0;
  return week.workouts.filter((w) => w.workoutType && w.workoutType !== "rest").length;
}

interface PlanTemplateWeek {
  weekNumber: number;
  theme: string;
  notes: string;
  targetMilesMin?: number;
  targetMilesMax?: number;
  workouts: PlanTemplateWorkout[];
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const DISTANCES = ["marathon", "half_marathon", "10k", "5k", "custom"];

// The pace an unqualified offset in the describe-it box is relative to. The
// plan states its race; this is that race's pace, so "+5%" has a declared base
// rather than an invented one. "custom" is absent deliberately — with no race
// there is no anchor to bind to, and a bare offset should stay unresolved.
const ANCHOR_ZONE_FOR_DISTANCE: Record<string, PaceZone | undefined> = {
  marathon: "mp",
  half_marathon: "hm",
  "10k": "tenK",
  "5k": "fiveK",
};
const DISTANCE_LABELS: Record<string, string> = {
  marathon: "Marathon",
  half_marathon: "Half Marathon",
  "10k": "10K",
  "5k": "5K",
  custom: "Custom",
};
const DURATIONS = [8, 10, 12, 14, 16, 18, 20];

// Pace/intensity = single-hue blue depth ramp (source of truth:
// RunningLog/Workouts/PaceSpectrum.swift). Blue = pace, warm = mood,
// coral = alert; the three palettes never share hues.
const WORKOUT_COLORS: Record<string, string> = {
  easy: "#93B9D6",
  recovery: "#B4ADA4",    // warm gray — below Easy
  long_run: "#578FC0",    // steady
  progression: "#3F7CB5", // MP
  tempo: "#27549B",       // LT
  intervals: "#1A3679",   // 5K
  strides: "#142964",     // 3K
  race: "#0E1D4E",        // navy — hardest
  rest: "#9B9590",        // neutral gray
};

const QUICK_TYPES = ["easy", "tempo", "intervals", "long_run", "progression", "recovery", "strides"];

// Section order for the grouped library rail (unknown types fall to the end).
const LIBRARY_TYPE_ORDER = [
  "intervals", "tempo", "threshold", "progression", "fartlek",
  "strides", "race", "long_run", "easy", "recovery", "rest",
];

function libraryTypeLabel(type: string): string {
  const map: Record<string, string> = {
    intervals: "Intervals", tempo: "Tempo", threshold: "Threshold",
    progression: "Progression", fartlek: "Fartlek", strides: "Strides",
    race: "Race", long_run: "Long", easy: "Easy", recovery: "Recovery",
    rest: "Rest", other: "Other",
  };
  return map[type] ?? type.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

// Map a parsed workout's headline pace zone to the legacy workout_type chip,
// so "Describe it" can pre-select a sensible type. (workout_type is legacy
// storage; the 10-zone label is what actually renders on cards.)
const WORKOUT_TYPE_FOR_ZONE: Partial<Record<PaceZone, string>> = {
  recovery: "recovery",
  easy: "easy",
  longRun: "long_run",
  moderate: "easy",
  steady: "easy",
  mp: "progression",
  hm: "progression",
  threshold: "tempo",
  tenK: "intervals",
  fiveK: "intervals",
  threeK: "intervals",
  mile: "intervals",
};

const QUALITY_TYPES = new Set(["tempo", "intervals", "long_run", "progression", "race"]);

function isQualityWorkout(w: PlanTemplateWorkout): boolean {
  if (w.workoutTemplateId) return true;
  if (w.workoutType && QUALITY_TYPES.has(w.workoutType)) return true;
  return false;
}

function workoutMiles(w: PlanTemplateWorkout): number {
  const data = w.workoutData as Record<string, number> | undefined;
  if (data?.total_distance_km) return data.total_distance_km / 1.60934;
  return 0;
}

/**
 * Translate the iOS/server `pace_reference` field (easy|marathon|half|10K|5K|mile)
 * into the web editor's `paceZone` field (easy|mp|hm|tenK|fiveK|mile). Without
 * this, plans uploaded or LLM-parsed by iOS land in the web editor with every
 * step showing the default pace zone instead of the coach's intent.
 */
const PACE_REFERENCE_TO_ZONE: Record<string, string> = {
  easy: "easy",
  marathon: "mp",
  half: "hm",
  "10K": "tenK",
  "10k": "tenK",
  "5K": "fiveK",
  "5k": "fiveK",
  mile: "mile",
};

// Zones a warmup or cooldown may legitimately use. Anything faster (mp/hm/
// threshold/tenK/fiveK/threeK/mile) is never a valid warmup — you don't warm
// up at race pace — so we coerce those back to easy/recovery on load.
const AEROBIC_ZONES = new Set(["recovery", "easy", "moderate", "steady", "longRun"]);

// Map % of MP to the nearest named zone. Mirrors the server's
// `inferZoneFromPercent` (recompute-plan-paces) so generated/adaptive steps
// that only carry a `pacePercentage` still land on a real zone in the editor.
function inferZoneFromPercent(pct: number): string {
  if (pct >= 110) return "fiveK";
  if (pct >= 105) return "tenK";
  if (pct >= 102) return "threshold";
  if (pct >= 99)  return "mp";
  if (pct >= 92)  return "steady";
  if (pct >= 87)  return "moderate";
  if (pct >= 78)  return "longRun";
  if (pct >= 70)  return "easy";
  return "recovery";
}

// Best-effort paceZone for a step, in priority order: explicit paceZone →
// legacy `pace_reference` → deterministic-builder `pacePercentage`.
function resolveStepZone(s: Record<string, unknown>): string | undefined {
  if (typeof s.paceZone === "string" && s.paceZone) return s.paceZone;
  const ref = s.pace_reference as string | undefined;
  if (ref && PACE_REFERENCE_TO_ZONE[ref]) return PACE_REFERENCE_TO_ZONE[ref];
  const pct = typeof s.pacePercentage === "number" ? s.pacePercentage : null;
  if (pct && pct > 0) return inferZoneFromPercent(pct);
  return undefined;
}

// Resolve every step's paceZone and enforce that warmups/cooldowns stay
// aerobic. Applied at every point a workout enters the plan (existing-plan
// load AND library assignment), so no source can slip a mile-pace warmup in.
function normalizeSteps(steps: Record<string, unknown>[]): Record<string, unknown>[] {
  return steps.map((s) => {
    const stepType = s.stepType as string | undefined;
    let zone = resolveStepZone(s);
    // Warmups/cooldowns are always aerobic — coerce a missing or too-fast
    // zone (never a valid warmup) to easy/recovery. A deliberate easy or
    // moderate warmup is left untouched.
    if (stepType === "warmup" && (!zone || !AEROBIC_ZONES.has(zone))) zone = "easy";
    if (stepType === "cooldown" && (!zone || !AEROBIC_ZONES.has(zone))) zone = "recovery";
    if (zone && zone !== s.paceZone) return { ...s, paceZone: zone };
    return s;
  });
}

function normalizeWeeks(weeks: PlanTemplateWeek[]): PlanTemplateWeek[] {
  return weeks.map((week) => ({
    ...week,
    workouts: (week.workouts ?? []).map((w) => {
      const data = w.workoutData as Record<string, unknown> | null | undefined;
      const steps = data?.steps as Record<string, unknown>[] | undefined;
      if (!steps || steps.length === 0) return w;
      const patched = normalizeSteps(steps);
      return {
        ...w,
        workoutData: { ...(data ?? {}), steps: patched },
      };
    }),
  }));
}

function buildBlankWeeks(count: number): PlanTemplateWeek[] {
  return Array.from({ length: count }, (_, i) => ({
    weekNumber: i + 1,
    theme: i === count - 1 ? "Race Week" : `Week ${i + 1}`,
    notes: "",
    targetMilesMin: 0,
    targetMilesMax: 0,
    workouts: Array.from({ length: 7 }, (_, d) => ({
      dayOfWeek: d,
      // workoutType undefined = unset (initial state)
      // workoutType "rest" = explicitly chosen rest day (set via picker)
      notes: "",
    })),
  }));
}

export function PlanBuilderClient({
  coachId,
  workoutTemplates,
  existingPlan,
  previewAthletes = [],
}: {
  coachId: string;
  workoutTemplates: WorkoutTemplate[];
  existingPlan: Record<string, unknown> | null;
  // The coach's linked athletes, for the read-only Phase 5 preview rail.
  // Defaults to empty so callers that don't pass it degrade to an empty state.
  previewAthletes?: PreviewAthlete[];
}) {
  const router = useRouter();
  const supabase = createClient();

  // Plate-strip caption — MM.YYYY, e.g. "07.2026".
  const planDateLabel = new Date()
    .toLocaleDateString("en-US", { month: "2-digit", year: "numeric" })
    .replace("/", ".");

  const [planType, setPlanType] = useState<"fixed" | "adaptive">(
    (existingPlan?.plan_type as "fixed" | "adaptive") ?? "fixed"
  );
  const [planName, setPlanName] = useState((existingPlan?.name as string) ?? "");
  const [targetDistance, setTargetDistance] = useState(
    (existingPlan?.target_distance as string) ?? "marathon"
  );
  const [durationWeeks, setDurationWeeks] = useState(
    (existingPlan?.duration_weeks as number) ?? 16
  );

  const initialAnchor: PaceAnchor =
    ((existingPlan?.phase_config as Record<string, unknown> | undefined)?.paceAnchor as PaceAnchor | undefined) ?? {
      goalRaceSeconds: null,
      goalRaceDistance: null,
      overrides: {},
    };
  const [paceAnchor, setPaceAnchor] = useState<PaceAnchor>(initialAnchor);
  const paceTable = resolvePaceTable(paceAnchor, targetDistance);

  // Plan setup (adaptive skeleton) — day_structure, shape flags, phases.
  // See plan-setup-section.tsx and the Phase A spec.
  const [dayStructure, setDayStructure] = useState<DayStructureEntry[]>(
    Array.isArray(existingPlan?.day_structure)
      ? (existingPlan!.day_structure as DayStructureEntry[])
      : []
  );
  const [autoStrides, setAutoStrides] = useState<boolean>(
    (existingPlan?.auto_strides_on_pre_quality as boolean | undefined) ?? true
  );
  const [recoveryAfterLong, setRecoveryAfterLong] = useState<boolean>(
    (existingPlan?.recovery_after_long_run as boolean | undefined) ?? true
  );
  const [weekPhases, setWeekPhases] = useState<Record<number, Phase>>(
    phasesToWeekMap(
      (existingPlan?.phase_config as Record<string, unknown> | undefined)?.phases
    )
  );

  // Coach AI guidance (Phase 2) — hard rules / guidelines / silent note the
  // reschedule assistant reasons inside. Stored on plan_templates.coach_ai_guidance.
  const [coachGuidance, setCoachGuidance] = useState<CoachAiGuidance>(
    normalizeCoachGuidance(existingPlan?.coach_ai_guidance)
  );

  const [weeks, setWeeks] = useState<PlanTemplateWeek[]>(
    existingPlan
      ? normalizeWeeks((existingPlan.weeks as PlanTemplateWeek[]) ?? buildBlankWeeks(16))
      : buildBlankWeeks(16)
  );
  const [selectedWeekIdx, setSelectedWeekIdx] = useState(0);

  // Placed quality miles per zone, per week — feeds the pace-colored ramp
  // in Plan setup. Recomputes whenever a workout is placed or removed, so
  // the bars restack live. Bucketed against the reference runner (no athlete
  // is selected in the builder; per-athlete paces arrive with the Phase 5
  // preview rail), which is honest for a coach-side "shape of the block" view.
  const zoneMilesByWeek = useMemo(() => {
    const out: Record<number, ZoneMiles> = {};
    for (const wk of weeks) {
      const stepGroups = wk.workouts
        .filter((w) => w.workoutType && w.workoutType !== "rest")
        .map(
          (w) =>
            ((w.workoutData as Record<string, unknown> | undefined)?.steps as
              | WorkoutStep[]
              | undefined) ?? [],
        )
        .filter((steps) => steps.length > 0);
      out[wk.weekNumber] = weekZoneMiles(stepGroups);
    }
    return out;
  }, [weeks]);
  // The slot the right panel is editing: a day plus AM (main session) or
  // PM (the second run of a double). null = panel shows the library.
  const [picker, setPicker] = useState<{ day: number; session: SessionKey } | null>(null);
  const [dragOverSlot, setDragOverSlot] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [searchText, setSearchText] = useState("");
  const [localTemplates, setLocalTemplates] = useState<WorkoutTemplate[]>([]);
  // Optimistic pinned overrides (id → pinned). Server templates arrive as a
  // prop we can't mutate, so pin toggles overlay here and sync to the DB.
  const [pinnedOverrides, setPinnedOverrides] = useState<Record<string, boolean>>({});
  // Optimistically-hidden template ids. Server templates arrive as an
  // immutable prop; deleting removes the DB row and hides it here so the rail
  // updates without a refetch. Reverted if the delete errors.
  const [deletedIds, setDeletedIds] = useState<Set<string>>(new Set());
  const [savingTemplate, setSavingTemplate] = useState(false);
  const [templateSaveMsg, setTemplateSaveMsg] = useState<string | null>(null);
  const [builderOpen, setBuilderOpen] = useState(false);
  const [builderName, setBuilderName] = useState("");
  const [builderType, setBuilderType] = useState("tempo");
  const [builderSteps, setBuilderSteps] = useState<WorkoutStep[]>([]);
  const [builderError, setBuilderError] = useState<string | null>(null);
  // "Describe it" natural-language box → parsed steps.
  const [builderNL, setBuilderNL] = useState("");
  const [builderNLUnparsed, setBuilderNLUnparsed] = useState<string[]>([]);
  // Steps that WERE built but rest on a guess (missing pace, dropped set
  // rest). Distinct from `unparsed` — these look complete in the editor, so
  // they need their own, louder callout.
  const [builderNLWarnings, setBuilderNLWarnings] = useState<string[]>([]);
  // One-line summary of what the last parse understood, and which layer
  // answered. The visibility every silent defect of 2026-08-28 was missing.
  const [builderNLReadback, setBuilderNLReadback] = useState<string | null>(null);
  // Open questions from the last parse. Answering one writes straight to the
  // step, so this shrinks as the coach taps through it.
  const [builderNLQuestions, setBuilderNLQuestions] = useState<Clarification[]>([]);
  const [builderNLBusy, setBuilderNLBusy] = useState(false);
  // When set, the builder modal is editing this existing library workout in
  // place (Save updates the row) rather than creating a new one.
  const [editingTemplateId, setEditingTemplateId] = useState<string | null>(null);
  // Full-row overrides for templates edited in place. Server templates arrive
  // as an immutable prop, so edits overlay here the way pinnedOverrides do.
  const [templateEdits, setTemplateEdits] = useState<Record<string, WorkoutTemplate>>({});

  const openBuilder = () => {
    setEditingTemplateId(null);
    setBuilderName("");
    setBuilderType("tempo");
    setBuilderSteps([]);
    setBuilderError(null);
    setBuilderNL("");
    setBuilderNLUnparsed([]);
    setBuilderOpen(true);
  };

  // Open the builder pre-filled with an existing library workout, to adapt it
  // (e.g. 8 reps → 6). Saving updates the same row.
  const openBuilderForEdit = (t: WorkoutTemplate) => {
    const steps =
      ((t.workout_data as Record<string, unknown> | undefined)?.steps as
        | WorkoutStep[]
        | undefined) ?? [];
    setEditingTemplateId(t.id);
    setBuilderName(t.name);
    setBuilderType(t.workout_type);
    setBuilderSteps(steps);
    setBuilderError(null);
    setBuilderNL("");
    setBuilderNLUnparsed([]);
    setBuilderOpen(true);
  };

  // Clone a library workout into a new row ("… (copy)"), so a coach can build
  // a variant (fewer reps, different pace) without touching the original.
  const duplicateTemplate = async (t: WorkoutTemplate) => {
    const data = (t.workout_data as Record<string, unknown>) ?? {};
    const copyName = `${t.name} (copy)`;
    const { data: inserted, error } = await supabase
      .from("workout_templates")
      .insert({
        coach_id: coachId,
        name: copyName,
        workout_type: t.workout_type,
        description: null,
        tags: t.tags ?? [],
        workout_data: { ...data, name: copyName },
        estimated_distance_miles: t.estimated_distance_miles ?? null,
        estimated_duration_minutes: t.estimated_duration_minutes ?? null,
      })
      .select()
      .single();
    if (error) {
      setTemplateSaveMsg("Error: " + error.message);
      return;
    }
    if (inserted) {
      setLocalTemplates((prev) => [...prev, inserted as WorkoutTemplate]);
      setTemplateSaveMsg("Duplicated to library");
      setTimeout(() => setTemplateSaveMsg(null), 2000);
    }
  };

  // Delete a saved workout from the library. Confirms first (destructive,
  // no undo), hides it optimistically, then removes the row. Existing plans
  // keep their own copy of the workout_data, so deleting the library entry
  // never mutates a plan that already used it.
  const deleteTemplate = async (t: WorkoutTemplate) => {
    if (!window.confirm(`Delete "${t.name}" from your library? This can't be undone.`)) return;
    setDeletedIds((prev) => new Set(prev).add(t.id));
    const { error } = await supabase
      .from("workout_templates")
      .delete()
      .eq("id", t.id);
    if (error) {
      setDeletedIds((prev) => {
        const next = new Set(prev);
        next.delete(t.id);
        return next;
      });
      setTemplateSaveMsg("Error deleting: " + error.message);
      setTimeout(() => setTemplateSaveMsg(null), 3000);
      return;
    }
    // Drop any local/edited copies so overlay state can't resurrect it.
    setLocalTemplates((prev) => prev.filter((x) => x.id !== t.id));
    setTemplateSaveMsg("Deleted from library");
    setTimeout(() => setTemplateSaveMsg(null), 2000);
  };

  // Parse the coach's shorthand and append the resulting steps to the editor.
  // Appending (not replacing) lets a coach build up a workout in pieces and
  // never destroys hand-edited steps. Unparseable fragments are surfaced, not
  // dropped silently.
  const applyDescribeIt = async () => {
    const text = builderNL.trim();
    if (!text || builderNLBusy) return;
    setBuilderNLBusy(true);
    try {
      // Local grammar first; only escalates to the server when it left
      // something unresolved, and falls back to it on any failure.
      //
      // `baseZone` is what lets a coach write "16 x k alternating +5% and -3%"
      // without retyping MP in front of every number. The plan already states
      // the race, so an unqualified offset has a stated base rather than a
      // guessed one; without this the grammar cannot hang the offset on
      // anything and the whole session collapses to one easy step.
      const { steps, unparsed, warnings, unresolved, source } = await parseShorthand(text, {
        baseZone: ANCHOR_ZONE_FOR_DISTANCE[targetDistance],
      });
      if (steps.length > 0) {
        setBuilderSteps((prev) => [...prev, ...steps]);
        const zone = headlineZone(steps);
        if (zone) setBuilderType(WORKOUT_TYPE_FOR_ZONE[zone] ?? builderType);
      }
      // The readback. Every parser defect found on 2026-08-28 was silent — the
      // wrong answer rendered as a finished-looking step list and nothing said
      // which layer produced it or what it understood. One line closes that:
      // the coach sees "16 steps · MP-3%, MP+5% · read by model" and a wrong
      // read is visible BEFORE saving, not after the athlete runs it.
      setBuilderNLReadback(
        steps.length > 0
          ? `Read as ${steps.length} step${steps.length === 1 ? "" : "s"} · ` +
            [...new Set(
              steps.map((s) => {
                if (s.exactPaceSecPerMile) {
                  const m = Math.floor(s.exactPaceSecPerMile / 60);
                  const sec = Math.round(s.exactPaceSecPerMile % 60);
                  return `${m}:${String(sec).padStart(2, "0")}/mi`;
                }
                const adj = s.paceAdjustment
                  ? `${s.paceAdjustment.value > 0 ? "+" : ""}${s.paceAdjustment.value}${s.paceAdjustment.type === "percent" ? "%" : "s"}`
                  : "";
                return `${paceShort(s.paceZone)}${adj}`;
              }),
            )].join(", ") +
            ` · by ${source === "model" ? "the model" : "the grammar"}`
          : null,
      );
      setBuilderNLUnparsed(unparsed);
      setBuilderNLWarnings(warnings);
      setBuilderNLQuestions(buildClarifications(steps, unresolved));
      if (steps.length > 0) setBuilderNL("");
    } finally {
      setBuilderNLBusy(false);
    }
  };

  // Answering resolves the step in place — no re-parse, so the coach's own
  // edits survive and the parse cannot drift on a second pass.
  const answerClarification = (c: Clarification, value: string) => {
    setBuilderSteps((prev) => applyClarification(prev, c, value));
    setBuilderNLQuestions((prev) => prev.filter((q) => q.id !== c.id));
  };

  const saveBuilderTemplate = async () => {
    if (!builderName.trim()) { setBuilderError("Name is required"); return; }
    if (builderSteps.length === 0) { setBuilderError("Add at least one step"); return; }
    setSavingTemplate(true);
    setBuilderError(null);

    const miles = totalWorkoutMiles(builderSteps);
    const mins = totalWorkoutDurationMinutes(builderSteps);
    const fields = {
      name: builderName.trim(),
      workout_type: builderType,
      description: null,
      tags: [],
      workout_data: {
        schema_version: "v3",
        name: builderName.trim(),
        steps: builderSteps,
        total_distance_km: miles * 1.60934,
      },
      estimated_distance_miles: miles > 0 ? miles : null,
      estimated_duration_minutes: mins > 0 ? Math.round(mins) : null,
    };

    // Edit-in-place: update the existing row and overlay the result.
    if (editingTemplateId) {
      const { data: updated, error } = await supabase
        .from("workout_templates")
        .update(fields)
        .eq("id", editingTemplateId)
        .select()
        .single();
      setSavingTemplate(false);
      if (error) { setBuilderError(error.message); return; }
      if (updated) {
        const row = updated as WorkoutTemplate;
        setTemplateEdits((prev) => ({ ...prev, [row.id]: row }));
        setLocalTemplates((prev) => prev.map((x) => (x.id === row.id ? row : x)));
        setBuilderOpen(false);
        setEditingTemplateId(null);
      }
      return;
    }

    const { data: inserted, error } = await supabase
      .from("workout_templates")
      .insert({ coach_id: coachId, ...fields })
      .select()
      .single();

    setSavingTemplate(false);
    if (error) { setBuilderError(error.message); return; }
    if (inserted) {
      const tmpl = inserted as WorkoutTemplate;
      setLocalTemplates((prev) => [...prev, tmpl]);
      // With a slot picked, assign there too; otherwise it just joins the library.
      if (picker) {
        assignWorkout(picker.day, picker.session, templateToWorkout(tmpl, picker.day, picker.session), true);
      }
      setBuilderOpen(false);
    }
  };

  const allTemplates = [...workoutTemplates, ...localTemplates]
    .filter((base) => !deletedIds.has(base.id))
    .map((base) => {
      const t = templateEdits[base.id] ?? base;
      return pinnedOverrides[t.id] !== undefined ? { ...t, pinned: pinnedOverrides[t.id] } : t;
    });

  // Toggle a template's pinned flag (sorts it to the top of the library rail).
  // Optimistic: flip the overlay immediately, persist to the DB, revert on error.
  const togglePin = async (t: WorkoutTemplate) => {
    const next = !(t.pinned ?? false);
    setPinnedOverrides((prev) => ({ ...prev, [t.id]: next }));
    const { error } = await supabase
      .from("workout_templates")
      .update({ pinned: next })
      .eq("id", t.id);
    if (error) {
      setPinnedOverrides((prev) => ({ ...prev, [t.id]: !next }));
      console.error("Failed to toggle template pin:", error.message);
    }
  };

  const saveCurrentAsTemplate = async () => {
    if (!picker) return;
    const workout = getWorkout(picker.day, picker.session);
    const data = (workout.workoutData as Record<string, unknown>) || {};
    const steps = (data.steps as WorkoutStep[]) || [];
    if (steps.length === 0) {
      setTemplateSaveMsg("Add at least one step before saving");
      return;
    }
    const defaultName = (data.name as string) || workout.workoutType?.replace("_", " ") || "Workout";
    const name = window.prompt("Template name:", defaultName);
    if (!name || !name.trim()) return;

    setSavingTemplate(true);
    setTemplateSaveMsg(null);
    const miles = totalWorkoutMiles(steps);
    const mins = totalWorkoutDurationMinutes(steps);
    const payload = {
      coach_id: coachId,
      name: name.trim(),
      workout_type: workout.workoutType ?? "easy",
      description: null,
      tags: [],
      workout_data: {
        schema_version: "v3",
        name: name.trim(),
        steps,
        total_distance_km: miles * 1.60934,
      },
      estimated_distance_miles: miles > 0 ? miles : null,
      estimated_duration_minutes: mins > 0 ? Math.round(mins) : null,
    };

    const { data: inserted, error } = await supabase
      .from("workout_templates")
      .insert(payload)
      .select()
      .single();

    setSavingTemplate(false);
    if (error) {
      setTemplateSaveMsg("Error: " + error.message);
      return;
    }
    if (inserted) {
      setLocalTemplates((prev) => [...prev, inserted as WorkoutTemplate]);
      setTemplateSaveMsg("Saved to library");
      setTimeout(() => setTemplateSaveMsg(null), 2500);
    }
  };

  const selectedWeek = weeks[selectedWeekIdx];

  // Phase 5 — athlete preview. The coach's plan anchor wins for everyone when
  // it's set (absolute targets read the same on every athlete's card); when
  // the coach leaves paces to each athlete, this is null and the rail resolves
  // each athlete against their own anchor.
  const coachAnchorSet =
    typeof paceAnchor.goalRaceSeconds === "number" && paceAnchor.goalRaceSeconds > 0;
  const coachPaceTable = coachAnchorSet ? paceTable : null;

  // The selected week flattened into the shape the preview rail consumes.
  const previewWeek = useMemo(() => {
    const wk = weeks[selectedWeekIdx];
    if (!wk) return undefined;
    const workouts: PreviewWorkout[] = wk.workouts
      .filter((w) => w.workoutType && w.workoutType !== "rest")
      .map((w) => {
        const data = (w.workoutData as Record<string, unknown> | undefined) ?? {};
        return {
          dayOfWeek: w.dayOfWeek,
          session: sessOf(w),
          workoutType: w.workoutType,
          name: (data.name as string | undefined) ?? undefined,
          notes: w.notes || undefined,
          steps: ((data.steps as WorkoutStep[] | undefined) ?? []),
        };
      });
    return {
      weekNumber: wk.weekNumber,
      phase: weekPhases[wk.weekNumber],
      targetMilesMin: wk.targetMilesMin,
      targetMilesMax: wk.targetMilesMax,
      workouts,
    };
  }, [weeks, selectedWeekIdx, weekPhases]);

  // Projected per-day volume split by pace zone for the selected week. Quality
  // days come from their real steps; adaptive easy-fill days get an even share
  // of the week's remaining mileage (mid of the range − placed quality), which
  // is how subscribe-to-plan sizes them per athlete. Rest days stay empty.
  const dayVolumes: DayVolume[] = useMemo(() => {
    const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const wk = weeks[selectedWeekIdx];
    if (!wk) return [];
    const perDay: ZoneMiles[] = labels.map(() => ({}));
    const easyDays: number[] = [];
    let placedTotal = 0;
    for (let dow = 0; dow < 7; dow++) {
      const dayWos = wk.workouts.filter(
        (w) => w.dayOfWeek === dow && w.workoutType && w.workoutType !== "rest"
      );
      const isRest = wk.workouts.some(
        (w) => w.dayOfWeek === dow && w.workoutType === "rest"
      );
      if (dayWos.length > 0) {
        const stepGroups = dayWos
          .map(
            (w) =>
              ((w.workoutData as Record<string, unknown> | undefined)?.steps as
                | WorkoutStep[]
                | undefined) ?? []
          )
          .filter((s) => s.length > 0);
        const zm = weekZoneMiles(stepGroups);
        perDay[dow] = zm;
        placedTotal += totalZoneMiles(zm);
      } else if (!isRest) {
        easyDays.push(dow); // adaptive auto-fill (or an unfilled fixed day)
      }
    }
    if (planType === "adaptive" && easyDays.length > 0) {
      const mid = ((wk.targetMilesMin ?? 0) + (wk.targetMilesMax ?? 0)) / 2;
      const perEasy = Math.max(0, mid - placedTotal) / easyDays.length;
      for (const dow of easyDays) {
        perDay[dow] = { ...perDay[dow], easy: (perDay[dow].easy ?? 0) + perEasy };
      }
    }
    return labels.map((label, dow) => ({
      label,
      zoneMiles: perDay[dow],
      estimated: planType === "adaptive" && easyDays.includes(dow),
    }));
  }, [weeks, selectedWeekIdx, planType]);

  const getWorkout = useCallback(
    (day: number, session: SessionKey = "am"): PlanTemplateWorkout => {
      return (
        selectedWeek?.workouts.find(
          (w) => w.dayOfWeek === day && sessOf(w) === session
        ) ?? {
          dayOfWeek: day,
          session,
          // workoutType undefined means unset
          notes: "",
        }
      );
    },
    [selectedWeek]
  );

  const assignWorkout = (
    day: number,
    session: SessionKey,
    workout: PlanTemplateWorkout,
    closePicker = true
  ) => {
    const stamped = { ...workout, dayOfWeek: day, session };
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        const existing = week.workouts.findIndex(
          (w) => w.dayOfWeek === day && sessOf(w) === session
        );
        if (existing >= 0) {
          const updated = [...week.workouts];
          updated[existing] = stamped;
          return { ...week, workouts: updated };
        }
        return { ...week, workouts: [...week.workouts, stamped] };
      })
    );
    if (closePicker) setPicker(null);
  };

  /** Clears whatever is assigned to a slot — reverts it to the "Tap to add"
   *  unset state. Different from assigning rest: unset days can be re-filled
   *  by adaptive plans, rest days are explicit. PM slots simply disappear. */
  const removeWorkout = (day: number, session: SessionKey) => {
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        return {
          ...week,
          workouts: week.workouts.filter(
            (w) => !(w.dayOfWeek === day && sessOf(w) === session)
          ),
        };
      })
    );
    setPicker(null);
  };

  /** Move a placed workout from one slot to another within the selected week.
   *  If the destination already holds a real workout the two swap; otherwise
   *  the source slot is cleared. Dropping onto the same slot is a no-op. Done
   *  in a single setWeeks so the swap is atomic. */
  const moveWorkout = (
    fromDay: number,
    fromSession: SessionKey,
    toDay: number,
    toSession: SessionKey
  ) => {
    if (fromDay === toDay && fromSession === toSession) return;
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        const src = week.workouts.find(
          (w) => w.dayOfWeek === fromDay && sessOf(w) === fromSession
        );
        if (!src || !src.workoutType) return week;
        const dst = week.workouts.find(
          (w) => w.dayOfWeek === toDay && sessOf(w) === toSession
        );
        const rest = week.workouts.filter(
          (w) =>
            !(w.dayOfWeek === fromDay && sessOf(w) === fromSession) &&
            !(w.dayOfWeek === toDay && sessOf(w) === toSession)
        );
        const next = [...rest, { ...src, dayOfWeek: toDay, session: toSession }];
        // Occupied destination → swap the displaced workout back to the source.
        if (dst && dst.workoutType) {
          next.push({ ...dst, dayOfWeek: fromDay, session: fromSession });
        }
        return { ...week, workouts: next };
      })
    );
    setPicker(null);
  };

  function templateToWorkout(
    t: WorkoutTemplate,
    day: number,
    session: SessionKey
  ): PlanTemplateWorkout {
    const data = t.workout_data as Record<string, unknown> | null | undefined;
    const steps = data?.steps as Record<string, unknown>[] | undefined;
    const workoutData =
      steps && steps.length > 0
        ? { ...data, steps: normalizeSteps(steps) }
        : t.workout_data;
    return {
      dayOfWeek: day,
      session,
      workoutTemplateId: t.id,
      workoutType: t.workout_type,
      workoutData,
      notes: "",
    };
  }

  /** One-tap add from the library rail: first open AM day of the selected
   *  week (Mon→Sun); if every day is taken, the first open PM slot on a
   *  non-rest day — the add becomes a double. */
  const quickAddTemplate = (template: WorkoutTemplate) => {
    for (let d = 0; d < 7; d++) {
      const am = getWorkout(d);
      if (!am.workoutType) {
        assignWorkout(d, "am", templateToWorkout(template, d, "am"), false);
        return;
      }
    }
    for (let d = 0; d < 7; d++) {
      if (getWorkout(d).workoutType !== "rest" && !getWorkout(d, "pm").workoutType) {
        assignWorkout(d, "pm", templateToWorkout(template, d, "pm"), false);
        return;
      }
    }
    // Week is completely full — the coach can still drag onto a slot to replace.
  };

  const handleTemplateDrop = (day: number, session: SessionKey, templateId: string) => {
    const t = allTemplates.find((x) => x.id === templateId);
    if (!t) return;
    assignWorkout(day, session, templateToWorkout(t, day, session), false);
  };

  const copyFromPreviousWeek = () => {
    if (selectedWeekIdx === 0) return;
    const prevWorkouts = weeks[selectedWeekIdx - 1].workouts;
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        return {
          ...week,
          workouts: prevWorkouts.map((w) => ({ ...w })),
        };
      })
    );
  };

  const adjustDuration = (newDuration: number) => {
    setDurationWeeks(newDuration);
    if (newDuration > weeks.length) {
      const extra = buildBlankWeeks(newDuration - weeks.length).map((w) => ({
        ...w,
        weekNumber: weeks.length + w.weekNumber,
      }));
      setWeeks((prev) => [...prev, ...extra]);
    } else {
      setWeeks((prev) => prev.slice(0, newDuration));
    }
  };

  const setWeekTargetRange = (field: "targetMilesMin" | "targetMilesMax", value: number) => {
    setWeeks((prev) =>
      prev.map((week, idx) =>
        idx === selectedWeekIdx ? { ...week, [field]: value } : week
      )
    );
  };

  /** Bulk mileage-range writer for the Plan setup ramp tools. */
  const applyBulkRanges = (
    ranges: Array<{ weekNumber: number; min: number; max: number }>
  ) => {
    const byWeek = new Map(ranges.map((r) => [r.weekNumber, r]));
    setWeeks((prev) =>
      prev.map((week) => {
        const r = byWeek.get(week.weekNumber);
        if (!r) return week;
        return { ...week, targetMilesMin: r.min, targetMilesMax: r.max };
      })
    );
  };

  // Note: in adaptive mode, the smart-fill of easy days happens at subscribe
  // time (in the subscribe-to-plan edge function), not here. The template only
  // stores quality workouts + the weekly mileage range.

  const handleSave = async (publish: boolean) => {
    // Force-blur the focused element + yield a tick before reading state.
    //
    // Inputs in the right-panel step editor (NumberCell, duration text)
    // commit on blur, not on every keystroke — see the comment in
    // workout-step-editor.tsx NumberCell. If the user types "10" into a
    // reps field and clicks Save Draft directly, the click handler races
    // the blur event: the blur queues a setWeeks() update, but handleSave
    // reads `weeks` synchronously before React flushes the update. Result:
    // we serialize stale state and the user's last edit is lost.
    //
    // Forcing blur here, then yielding via setTimeout(0), gives the queued
    // state update one microtask to flush before we touch `weeks`.
    if (typeof document !== "undefined") {
      (document.activeElement as HTMLElement | null)?.blur?.();
      await new Promise((resolve) => setTimeout(resolve, 0));
    }

    if (!planName.trim()) return;
    setIsSaving(true);
    setSaveError(null);

    const existingPhaseConfig =
      (existingPlan?.phase_config as Record<string, unknown> | undefined) ?? {};

    // Plan-level ramp: mirror the per-week ranges into weekly_mileage_targets
    // so the materializer (buildWeekTargets) and future tooling can read the
    // ramp without parsing the weeks blob.
    const weeklyMileageTargets = weeks
      .filter((w) => (w.targetMilesMax ?? 0) > 0)
      .map((w) => ({
        weekNumber: w.weekNumber,
        targetMilesMin: w.targetMilesMin ?? 0,
        targetMilesMax: w.targetMilesMax ?? 0,
        phase: weekPhases[w.weekNumber] ?? null,
      }));

    // Legacy mirror: older readers look at rest_day_of_week; keep it in sync
    // with the skeleton's first rest day.
    const skeletonRestDow =
      dayStructure.find((d) => d.role === "rest")?.dayOfWeek ?? null;

    const payload: Record<string, unknown> = {
      coach_id: coachId,
      name: planName,
      target_distance: targetDistance,
      duration_weeks: durationWeeks,
      plan_type: planType,
      weeks,
      is_published: publish,
      join_code: publish ? generateJoinCode() : null,
      phase_config: {
        ...existingPhaseConfig,
        paceAnchor,
        phases: buildPhaseRanges(weekPhases, durationWeeks),
      },
      day_structure: dayStructure,
      weekly_mileage_targets: weeklyMileageTargets,
      rest_day_of_week: skeletonRestDow,
      auto_strides_on_pre_quality: autoStrides,
      recovery_after_long_run: recoveryAfterLong,
      // Null when the coach set nothing, so an empty editor doesn't persist an
      // empty envelope. Column added by 20260712*_plan_templates_coach_ai_guidance
      // (authored, pending push) — inert until then.
      coach_ai_guidance: serializeCoachGuidance(coachGuidance),
    };

    const { error } = existingPlan?.id
      ? await supabase
          .from("plan_templates")
          .update(payload)
          .eq("id", existingPlan.id as string)
      : await supabase.from("plan_templates").insert(payload);

    setIsSaving(false);

    if (error) {
      setSaveError(error.message);
      return;
    }

    router.push("/coach-portal/plans");
    router.refresh();
  };

  // Pinned templates float to the top; Array.prototype.sort is stable, so
  // ties keep their existing order.
  const filteredTemplates = allTemplates
    .filter(
      (t) =>
        searchText === "" ||
        t.name.toLowerCase().includes(searchText.toLowerCase()) ||
        (t.tags ?? []).some((tag) => tag.toLowerCase().includes(searchText.toLowerCase()))
    )
    .sort((a, b) => Number(b.pinned ?? false) - Number(a.pinned ?? false));

  // Grouped view: pinned first, then a section per workout type in a fixed
  // order. Search filtering already happened above.
  const librarySections: { key: string; label: string; items: WorkoutTemplate[] }[] = (() => {
    const pinned = filteredTemplates.filter((t) => t.pinned);
    const rest = filteredTemplates.filter((t) => !t.pinned);
    const byType = new Map<string, WorkoutTemplate[]>();
    for (const t of rest) {
      const k = t.workout_type || "other";
      const arr = byType.get(k);
      if (arr) arr.push(t);
      else byType.set(k, [t]);
    }
    const typeKeys = [...byType.keys()].sort((a, b) => {
      const ia = LIBRARY_TYPE_ORDER.indexOf(a);
      const ib = LIBRARY_TYPE_ORDER.indexOf(b);
      return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });
    const out: { key: string; label: string; items: WorkoutTemplate[] }[] = [];
    if (pinned.length) out.push({ key: "__pinned__", label: "Pinned", items: pinned });
    for (const k of typeKeys) out.push({ key: k, label: libraryTypeLabel(k), items: byType.get(k)! });
    return out;
  })();

  // One library card. Shared by every section so grouping doesn't fork the
  // markup. Edit/Duplicate live in the action column; the card body still
  // assigns on tap and drags onto a day.
  const renderTemplateCard = (template: WorkoutTemplate) => {
    const steps =
      ((template.workout_data as Record<string, unknown> | undefined)
        ?.steps as WorkoutStep[] | undefined) ?? [];
    const zone = headlineZone(steps);
    const stripeColor = zone
      ? PACE_ZONE_COLORS[zone]
      : WORKOUT_COLORS[template.workout_type] ?? "#9B9590";
    const estLine = describeWorkoutLine(steps);
    const dotZones = stepZones(steps);
    return (
      <div
        key={template.id}
        role="button"
        tabIndex={0}
        draggable
        onDragStart={(e) => {
          e.dataTransfer.setData("text/plain", template.id);
          e.dataTransfer.effectAllowed = "copy";
        }}
        onClick={() =>
          picker
            ? assignWorkout(
                picker.day,
                picker.session,
                templateToWorkout(template, picker.day, picker.session)
              )
            : quickAddTemplate(template)
        }
        onKeyDown={(e) => {
          if (e.key !== "Enter" && e.key !== " ") return;
          e.preventDefault();
          if (picker) {
            assignWorkout(
              picker.day,
              picker.session,
              templateToWorkout(template, picker.day, picker.session)
            );
          } else {
            quickAddTemplate(template);
          }
        }}
        className="w-full flex items-start gap-3 px-5 py-3 border-b border-divider hover:bg-bg-elevated transition-colors text-left cursor-grab active:cursor-grabbing"
        title={picker ? "Assign to the picked slot" : "Tap to add to this week, or drag onto a day"}
      >
        <span
          className="w-1 rounded-full mt-1 flex-shrink-0 self-stretch"
          style={{ backgroundColor: stripeColor, minHeight: 24 }}
        />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-text-primary truncate">
            {template.name}
          </p>
          {estLine ? (
            <p className="text-xs text-text-secondary font-mono mt-0.5 truncate">
              {estLine}
            </p>
          ) : template.estimated_distance_miles ? (
            <p className="text-xs text-text-secondary font-mono tabular-nums mt-0.5">
              {template.estimated_distance_miles.toFixed(1)} mi
            </p>
          ) : null}
          {dotZones.length > 0 && (
            <div className="flex items-center gap-2 mt-1">
              {dotZones.map((z) => (
                <span key={z} className="flex items-center gap-1">
                  <span
                    className="w-1.5 h-1.5 rounded-full"
                    style={{ background: PACE_ZONE_COLORS[z] }}
                  />
                  <span className="font-mono text-[10px] text-text-secondary">
                    {zoneLabelShort(z)}
                  </span>
                </span>
              ))}
            </div>
          )}
        </div>
        <div className="ml-auto flex flex-col items-end gap-1 flex-shrink-0">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                openBuilderForEdit(template);
              }}
              className="font-mono text-[10px] uppercase tracking-wider text-text-secondary hover:text-text-primary transition-colors"
              title="Edit this saved workout"
            >
              edit
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                duplicateTemplate(template);
              }}
              className="font-mono text-[10px] uppercase tracking-wider text-text-secondary hover:text-text-primary transition-colors"
              title="Duplicate into a new variant"
            >
              dup
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                togglePin(template);
              }}
              aria-pressed={template.pinned ?? false}
              className={`font-mono text-[10px] uppercase tracking-wider transition-colors ${
                template.pinned
                  ? "text-coral-dark"
                  : "text-text-secondary hover:text-text-primary"
              }`}
              title={
                template.pinned
                  ? "Pinned to top — tap to unpin"
                  : "Pin to top of library"
              }
            >
              {template.pinned ? "pinned" : "pin"}
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                deleteTemplate(template);
              }}
              className="font-mono text-[10px] uppercase tracking-wider text-text-secondary hover:text-coral-dark transition-colors"
              title="Delete this saved workout"
            >
              del
            </button>
          </div>
          <span className="text-coral text-sm">+</span>
        </div>
      </div>
    );
  };

  return (
    <div className="flex flex-col h-[calc(100vh-80px)] -m-4 md:-m-6 bg-bg-base">
      {/* Plate strip — frames the whole surface as a page in the running log,
          the single most identifiable PRD gesture. */}
      <PlateStrip
        surface="Plan Builder · Coach Portal"
        figure={existingPlan?.id ? "Fig. — edit" : "Fig. — new"}
        right={planDateLabel}
        className="border-b border-divider flex-shrink-0"
      />

      <div className="flex flex-1 min-h-0">
      {/* Left: Week selector + day grid. Scrolls as a single column: the
          header block (pace reference + adaptive plan setup) can grow taller
          than the viewport when expanded, so it has to participate in the
          scroll rather than sit pinned above a shorter scroller — otherwise
          its lower rows clip with no way to reach them. */}
      <div className="flex-1 flex flex-col overflow-y-auto min-h-0">
        {/* Plan header — editorial title block.
            Sits directly on the warm paper (bg-base) — no near-white slab;
            the page reads as one warm field with white cards on it. Plan
            name uses Crimson Pro for editorial weight; metadata (distance,
            weeks, pace ref) reads as a quiet kicker beneath. */}
        <div className="px-6 md:px-8 pt-7 pb-6 border-b border-divider bg-bg-base space-y-5">
          <div className="flex items-start gap-6">
            <div className="flex-1 min-w-0">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary mb-1.5">
                {existingPlan?.id ? "Editing plan" : "New plan"}
              </p>
              <input
                type="text"
                placeholder="Name this plan"
                value={planName}
                onChange={(e) => setPlanName(e.target.value)}
                className="w-full font-display text-4xl md:text-5xl font-semibold tracking-tight leading-[1.05] text-text-primary border-none outline-none bg-transparent placeholder:text-text-secondary placeholder:font-display placeholder:font-normal placeholder:italic"
              />
            </div>
            <div className="flex items-center gap-2 pt-5 flex-shrink-0">
              <button
                onClick={() => handleSave(false)}
                disabled={!planName.trim() || isSaving}
                className="px-3.5 py-1.5 text-sm border border-divider rounded-lg text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Save draft
              </button>
              {/* Publish — the header cluster's ONE coral element. Disabled
                  is a neutral paper-deep chip (not coral at 50% opacity,
                  which read as an illegible pale-salmon button). */}
              <button
                onClick={() => handleSave(true)}
                disabled={!planName.trim() || isSaving}
                className="px-3.5 py-1.5 text-sm font-semibold bg-coral text-white rounded-lg hover:bg-coral-dark transition-colors disabled:bg-bg-calendar disabled:text-text-secondary disabled:cursor-not-allowed"
              >
                {isSaving ? "Saving…" : "Publish"}
              </button>
            </div>
          </div>

          {saveError && (
            <p className="text-xs font-mono text-[var(--color-danger)]">
              Save failed: {saveError}
            </p>
          )}

          {/* Configuration row — distance, length, type. Reads left to right
              like a sentence: "{distance} · {N} weeks · {fixed|adaptive}." */}
          <div className="flex items-start gap-x-10 gap-y-4 flex-wrap">
            {/* Distance picker — race target reads first because it's the
                anchor for every pace in the plan. Selected chip is ink on
                paper text (selection = ink; coral stays reserved for the
                header's Publish). */}
            <div className="flex flex-col items-start gap-2.5">
              <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-text-secondary">
                Race
              </span>
              <div className="flex items-center gap-1 flex-wrap">
                {DISTANCES.map((d) => {
                  const isCustom = d === "custom";
                  const isFixedKnown = !isCustom && targetDistance === d;
                  const isCustomSelected = isCustom && !["marathon", "half_marathon", "10k", "5k"].includes(targetDistance);
                  const selected = isFixedKnown || isCustomSelected;
                  return (
                    <button
                      key={d}
                      onClick={() => setTargetDistance(isCustom ? "" : d)}
                      className={`px-3 py-1 text-xs rounded-full transition-colors ${
                        selected
                          ? "bg-text-primary text-white"
                          : "text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                      }`}
                    >
                      {DISTANCE_LABELS[d]}
                    </button>
                  );
                })}
                {!["marathon", "half_marathon", "10k", "5k"].includes(targetDistance) && (
                  <input
                    type="text"
                    placeholder="e.g., 50K"
                    value={targetDistance}
                    onChange={(e) => setTargetDistance(e.target.value)}
                    className="ml-1 px-2 py-1 text-xs border border-divider rounded-md focus:outline-none focus:border-coral w-20"
                  />
                )}
              </div>
            </div>

            {/* Duration — editorial number, underline-only, with the unit
                set after it like running prose ("16 weeks"). */}
            <div className="flex flex-col items-start gap-2.5">
              <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-text-secondary">
                Length
              </span>
              <div className="flex items-baseline gap-2">
                <input
                  type="number"
                  min={1}
                  max={24}
                  value={durationWeeks}
                  onChange={(e) => {
                    const n = parseInt(e.target.value, 10);
                    if (!isNaN(n) && n >= 1 && n <= 24) adjustDuration(n);
                  }}
                  className="w-12 font-display text-xl text-text-primary border-b border-divider bg-transparent focus:outline-none focus:border-coral text-center tabular-nums"
                />
                <span className="text-xs text-text-secondary">weeks</span>
              </div>
            </div>

            {/* Plan type — verbs the coach reads as a setting, not a tab.
                Quiet pill group; the active one earns the color. */}
            <div className="flex flex-col items-start gap-2.5 ml-auto">
              <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-text-secondary">
                Mode
              </span>
              <div className="flex gap-0 rounded-full border border-divider overflow-hidden bg-bg-elevated">
                <button
                  onClick={() => setPlanType("fixed")}
                  className={`px-3 py-1 text-xs font-medium transition-colors ${
                    planType === "fixed"
                      ? "bg-text-primary text-white"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                  title="Coach plans every day explicitly"
                >
                  Fixed
                </button>
                <button
                  onClick={() => setPlanType("adaptive")}
                  className={`px-3 py-1 text-xs font-medium transition-colors ${
                    planType === "adaptive"
                      ? "bg-text-primary text-white"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                  title="Coach sets quality days + mileage range; easy days auto-fill per athlete"
                >
                  Adaptive
                </button>
              </div>
            </div>
          </div>

          {/* Pace reference — race effort is folded into the expanded zone table */}
          <PaceReferenceEditor
            anchor={paceAnchor}
            onChange={setPaceAnchor}
            planDistance={targetDistance}
          />

          {/* Plan setup — adaptive-only skeleton: day roles, mileage ramp,
              shape flags. Fixed plans spell out every day, so none of this
              applies there. */}
          {planType === "adaptive" && (
            <PlanSetupSection
              dayStructure={dayStructure}
              onDayStructureChange={setDayStructure}
              weeks={weeks}
              onBulkRange={applyBulkRanges}
              autoStrides={autoStrides}
              onAutoStridesChange={setAutoStrides}
              recoveryAfterLong={recoveryAfterLong}
              onRecoveryAfterLongChange={setRecoveryAfterLong}
              weekPhases={weekPhases}
              onWeekPhasesChange={setWeekPhases}
              zoneMilesByWeek={zoneMilesByWeek}
              selectedWeekNumber={weeks[selectedWeekIdx]?.weekNumber}
              onSelectWeek={(weekNumber) => {
                const idx = weeks.findIndex((w) => w.weekNumber === weekNumber);
                if (idx >= 0) setSelectedWeekIdx(idx);
              }}
            />
          )}

          {/* Athlete preview rail (Phase 5) — read-only; resolves the selected
              week in a chosen athlete's paces and on their preferred days. */}
          {planType === "adaptive" && (
            <AthletePreviewRail
              athletes={previewAthletes}
              week={previewWeek}
              coachPaceTable={coachPaceTable}
            />
          )}

          {/* Coach AI guidance (Phase 2) — rules/guidelines/note the reschedule
              assistant reasons inside. Applies to fixed and adaptive plans. */}
          <CoachAiGuidanceSection guidance={coachGuidance} onChange={setCoachGuidance} />
        </div>

        {/* Week selector — one "Week" label, then numbered pills reading
            like tabs in a magazine TOC. The label sits once at the left
            instead of being repeated on every pill, so the row reads as
            clean numbers rather than a wall of "W"s. Active week is ink
            (selection = ink, like the race chips and Mode toggle); the
            coral dot marks weeks that already have workouts — this
            cluster's one coral, punctuation not paint. */}
        <div className="px-6 md:px-8 py-3 border-b border-divider bg-bg-base">
          <div className="flex items-center gap-3">
            <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary flex-shrink-0">
              Week
            </span>
            <div className="flex gap-2 overflow-x-auto min-w-0 py-0.5">
              {weeks.map((week, idx) => {
                const hasWorkouts = week.workouts.some((w) => w.workoutType && w.workoutType !== "rest");
                const active = selectedWeekIdx === idx;
                return (
                  <button
                    key={idx}
                    onClick={() => setSelectedWeekIdx(idx)}
                    className={`relative flex items-center justify-center w-10 h-10 rounded-lg font-display text-base tabular-nums leading-none transition-colors flex-shrink-0 ${
                      active
                        ? "bg-text-primary text-white"
                        : "text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                    }`}
                    aria-label={`Week ${week.weekNumber}`}
                    aria-current={active ? "true" : undefined}
                  >
                    {week.weekNumber}
                    {hasWorkouts && (
                      <span
                        className={`w-1 h-1 rounded-full absolute bottom-1 left-1/2 -translate-x-1/2 ${
                          active ? "bg-white/70" : "bg-coral"
                        }`}
                      />
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* Week meta — like a chapter header in the plan. Week theme in
            editorial display, week stats in a quiet kicker, planned vs.
            range mileage on the right. */}
        <div className="px-6 md:px-8 py-5 bg-bg-base border-b border-divider flex items-center justify-between gap-6 flex-wrap">
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
              Week {selectedWeek?.weekNumber ?? ""}
            </p>
            <div className="flex items-baseline gap-3 mt-0.5">
              <h2 className="font-display text-2xl text-text-primary leading-none">
                {(() => {
                  // A default "Week N" label must track the real weekNumber —
                  // changing plan length re-numbers weekNumber but not the
                  // theme, so a stale "Week 1" can land on week 2. Custom
                  // labels (e.g. "Race Week", "Build") pass through untouched.
                  const t = selectedWeek?.theme;
                  return !t || /^Week \d+$/.test(t)
                    ? `Week ${selectedWeek?.weekNumber ?? ""}`
                    : t;
                })()}
              </h2>
              {(() => {
                const n = countSessions(selectedWeek);
                // Session counter: up to 7 a week (doubles included) reads
                // neutral; past 7 earns coral — the one alert color.
                return (
                  <span className={`text-xs ${n > 7 ? "text-coral-dark font-medium" : "text-text-secondary"}`}>
                    {n} {n === 1 ? "session" : "sessions"}
                    {n > 7 ? " · over 7" : ""}
                  </span>
                );
              })()}
            </div>
          </div>

          <div className="flex items-center gap-5">
            {/* ADAPTIVE-ONLY: Weekly mileage range — coach sets the band,
                runner's easy days fill it. */}
            {planType === "adaptive" && (
              <div className="flex items-baseline gap-2">
                <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
                  Range
                </span>
                <div className="flex items-baseline gap-1 font-mono text-sm text-text-primary">
                  <input
                    type="number"
                    min={0}
                    placeholder="min"
                    value={selectedWeek?.targetMilesMin || ""}
                    onChange={(e) => setWeekTargetRange("targetMilesMin", parseInt(e.target.value) || 0)}
                    className="w-10 text-center bg-transparent border-b border-divider focus:outline-none focus:border-coral placeholder:text-text-secondary placeholder:text-[10px] placeholder:italic tabular-nums"
                  />
                  <span className="text-text-secondary">to</span>
                  <input
                    type="number"
                    min={0}
                    placeholder="max"
                    value={selectedWeek?.targetMilesMax || ""}
                    onChange={(e) => setWeekTargetRange("targetMilesMax", parseInt(e.target.value) || 0)}
                    className="w-10 text-center bg-transparent border-b border-divider focus:outline-none focus:border-coral placeholder:text-text-secondary placeholder:text-[10px] placeholder:italic tabular-nums"
                  />
                </div>
                <span className="text-[10px] text-text-secondary">mpw</span>
              </div>
            )}

            {/* Planned mileage — the headline number on this row. */}
            {(() => {
              if (!selectedWeek) return null;
              const planned = selectedWeek.workouts.reduce((s, w) => s + workoutMiles(w), 0);

              if (planType === "adaptive") {
                // In adaptive mode, planned = quality miles only; color against range
                const max = selectedWeek.targetMilesMax ?? 0;
                const hasRange = max > 0;
                // Three-palette rule: within range is neutral (confident ink,
                // never green); over range earns coral as the one alert.
                // coral-dark for AA at display size against warm paper.
                let color = "text-text-secondary";
                if (hasRange) {
                  color = planned > max ? "text-coral-dark" : "text-text-primary";
                }
                return (
                  <div className="text-right">
                    <span className={`font-display text-2xl tabular-nums ${color}`}>
                      {planned.toFixed(1)}
                    </span>
                    <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary ml-1.5">
                      quality
                    </span>
                  </div>
                );
              }

              return (
                <div className="text-right">
                  <span className="font-display text-2xl tabular-nums text-text-primary">
                    {planned.toFixed(1)}
                  </span>
                  <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary ml-1.5">
                    mi
                  </span>
                </div>
              );
            })()}

            {selectedWeekIdx > 0 && (
              <button
                onClick={copyFromPreviousWeek}
                className="text-xs text-text-secondary hover:text-coral-dark transition-colors underline-offset-4 hover:underline"
              >
                Copy from W{selectedWeekIdx}
              </button>
            )}
          </div>
        </div>

        {/* Day grid — the week as seven rows. Each row is the workout in
            plain prose: name, miles, pace. Quality days earn a confident
            white card and a thicker color rule; easy/rest days stay quiet.
            Empty days use the empty-state pattern (eyebrow + nudge), never
            an em-dash — see CLAUDE.md hard rules. The daily-volume chart lives
            INSIDE this scroller (first child) so it scrolls with the week and
            never eats the day list's scroll viewport. The whole left pane is
            the scroller now, so this block flows normally within it. */}
        <div className="flex-1 px-6 md:px-8 py-6 space-y-2">
          {/* Projected daily volume by pace zone for the selected week. */}
          <div className="pb-3 mb-3 border-b border-divider">
            <div className="flex items-baseline justify-between mb-2">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
                Daily volume · by pace
              </p>
              {planType === "adaptive" && (
                <span className="text-[11px] italic text-text-secondary">
                  easy days projected from the weekly range
                </span>
              )}
            </div>
            <DailyVolumeChart days={dayVolumes} />
          </div>
          {planType === "adaptive" && (
            <p className="coach-note text-sm mb-4">
              Mark the quality days. Easy and recovery fill in once an athlete
              subscribes.
            </p>
          )}
          {DAYS.map((dayName, dayIdx) => {
            const am = getWorkout(dayIdx);
            const pm = getWorkout(dayIdx, "pm");
            const hasPm = !!pm.workoutType;
            const pmPickerOpen = picker?.day === dayIdx && picker.session === "pm";
            // AM row always renders; the PM row appears once a double exists
            // (or while its picker is open, so the slot the coach just asked
            // for is visible).
            const rows: Array<{ session: SessionKey; workout: PlanTemplateWorkout }> = [
              { session: "am" as const, workout: am },
              ...(hasPm || pmPickerOpen ? [{ session: "pm" as const, workout: pm }] : []),
            ];

            return (
              <div key={dayIdx} className="space-y-1">
                {rows.map(({ session, workout }) => {
                  const isUnset = !workout.workoutType;
                  const isRest = workout.workoutType === "rest";
                  const isQuality = isQualityWorkout(workout);
                  const color = WORKOUT_COLORS[workout.workoutType ?? "rest"] ?? "#9B9590";
                  const miles = workoutMiles(workout);
                  const isPickerOpen = picker?.day === dayIdx && picker.session === session;
                  const slotId = `${dayIdx}:${session}`;
                  const isDragOver = dragOverSlot === slotId;

                  return (
                    <button
                      key={session}
                      onClick={() =>
                        setPicker(isPickerOpen ? null : { day: dayIdx, session })
                      }
                      draggable={!isUnset && !isRest}
                      onDragStart={(e) => {
                        if (isUnset || isRest) return;
                        // A placed workout drags itself; the payload is tagged
                        // so onDrop can tell a move from a library-card copy.
                        e.dataTransfer.setData("text/plain", `move:${dayIdx}:${session}`);
                        e.dataTransfer.effectAllowed = "move";
                      }}
                      onDragOver={(e) => {
                        e.preventDefault();
                        if (dragOverSlot !== slotId) setDragOverSlot(slotId);
                      }}
                      onDragLeave={() =>
                        setDragOverSlot((s) => (s === slotId ? null : s))
                      }
                      onDrop={(e) => {
                        e.preventDefault();
                        setDragOverSlot(null);
                        const payload = e.dataTransfer.getData("text/plain");
                        if (payload.startsWith("move:")) {
                          const [, d, s] = payload.split(":");
                          moveWorkout(Number(d), s as SessionKey, dayIdx, session);
                        } else {
                          handleTemplateDrop(dayIdx, session, payload);
                        }
                      }}
                      className={`group w-full flex items-stretch gap-4 px-5 rounded-xl text-left transition-all ${
                        isQuality ? "py-4" : "py-2.5"
                      } ${
                        isDragOver
                          ? "bg-bg-card ring-1 ring-coral shadow-[0_2px_8px_rgba(0,0,0,0.05)]"
                          : isPickerOpen
                          ? "bg-bg-card ring-1 ring-coral/40 shadow-[0_2px_8px_rgba(0,0,0,0.05)]"
                          : isQuality
                          ? "bg-bg-card hover:bg-white border border-divider-soft shadow-[0_2px_8px_rgba(0,0,0,0.05)]"
                          : isUnset
                          ? "bg-transparent hover:bg-bg-elevated border border-dashed border-divider"
                          : isRest
                          ? "bg-transparent hover:bg-bg-elevated"
                          : "bg-bg-elevated hover:bg-bg-card"
                      }`}
                    >
                      {/* Day label — uppercase mono kicker. PM rows read as
                          the second line of a double. */}
                      <span
                        className={`font-mono text-[10px] uppercase tracking-[0.18em] w-8 pt-1 flex-shrink-0 ${
                          isQuality ? "text-text-primary" : "text-text-secondary"
                        }`}
                      >
                        {session === "pm" ? "· PM" : dayName}
                      </span>

                      {/* Color rule — present only for actual workouts. */}
                      {!isUnset && !isRest && (
                        <span
                          className={`rounded-full flex-shrink-0 self-center ${
                            isQuality ? "w-1 h-10" : "w-0.5 h-5"
                          }`}
                          style={{ backgroundColor: color }}
                        />
                      )}

                      <div className="flex-1 min-w-0 flex items-center">
                        {isUnset ? (
                          session === "pm" ? (
                            <span className="text-sm italic text-text-secondary">
                              PM double · pick from the library
                            </span>
                          ) : planType === "adaptive" ? (
                            <span className="text-sm italic text-text-secondary">
                              Auto · easy run, sized per athlete
                            </span>
                          ) : (
                            <span className="text-sm italic text-text-secondary group-hover:text-text-primary transition-colors">
                              Add a workout
                            </span>
                          )
                        ) : isRest ? (
                          <span className="text-sm italic text-text-secondary">
                            Rest
                          </span>
                        ) : (
                          <div className="flex-1 min-w-0 flex items-baseline justify-between gap-3">
                            <p
                              className={`truncate ${
                                isQuality
                                  ? "font-display text-lg text-text-primary leading-tight"
                                  : "text-sm text-text-secondary"
                              }`}
                            >
                              {(workout.workoutData as Record<string, string>)?.name ??
                                workout.workoutType?.replace("_", " ")}
                            </p>
                            {miles > 0 && (
                              <p
                                className={`font-mono tabular-nums flex-shrink-0 ${
                                  isQuality
                                    ? "text-sm text-text-secondary"
                                    : "text-xs text-text-secondary"
                                }`}
                              >
                                {miles.toFixed(1)} mi
                              </p>
                            )}
                          </div>
                        )}
                      </div>

                      {/* Affordance — quiet plus, close glyph when open. */}
                      <span
                        className={`flex-shrink-0 self-center font-mono text-base transition-colors ${
                          isPickerOpen
                            ? "text-coral"
                            : "text-text-tertiary group-hover:text-text-primary"
                        }`}
                        aria-hidden="true"
                      >
                        {isPickerOpen ? "×" : "+"}
                      </span>
                    </button>
                  );
                })}

                {/* Doubles — quiet affordance under any day carrying a real
                    workout. Two runs a day, the coach's call. */}
                {!hasPm && !pmPickerOpen && am.workoutType && am.workoutType !== "rest" && (
                  <button
                    onClick={() => setPicker({ day: dayIdx, session: "pm" })}
                    className="ml-[52px] font-mono text-[10px] uppercase tracking-[0.14em] text-text-secondary hover:text-coral-dark transition-colors"
                  >
                    + PM double
                  </button>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Right: library rail — always present. With a slot picked it becomes
          that slot's editor (steps, rest, replace); without one it's the
          saved-workout library: drag a card onto a day, or tap to drop it
          into the first open slot of the selected week. */}
      {(() => {
        const current = picker ? getWorkout(picker.day, picker.session) : null;
        const hasAssignment = !!current?.workoutType;
        const isActiveWorkout = !!current && hasAssignment && current.workoutType !== "rest";
        return (
        <div className="w-80 border-l border-divider bg-bg-card flex flex-col overflow-hidden max-md:hidden">
          <div className="flex-shrink-0 px-5 py-4 border-b border-divider flex items-baseline justify-between">
            <div>
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
                {picker ? (hasAssignment ? "Edit" : "Assign") : "Library"}
              </p>
              <p className="font-display text-lg text-text-primary leading-tight mt-0.5">
                {picker
                  ? DAYS[picker.day] + (picker.session === "pm" ? " · PM" : "")
                  : "Saved workouts"}
              </p>
            </div>
            {picker ? (
              hasAssignment ? (
                <button
                  type="button"
                  onClick={() => removeWorkout(picker.day, picker.session)}
                  className="font-mono text-[10px] uppercase tracking-wider font-medium text-text-secondary hover:text-[var(--color-danger)] transition-colors"
                  title="Clear this slot (reverts to unset / auto-fill)"
                >
                  Remove
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => setPicker(null)}
                  className="font-mono text-[10px] uppercase tracking-wider font-medium text-text-secondary hover:text-text-primary transition-colors"
                >
                  Close
                </button>
              )
            ) : null}
          </div>

          {/* Scrollable content — everything below the header scrolls as
              one unit so a long step editor can't clip the library below.
              min-h-0 lets this flex child shrink below its content height so
              the scroller actually engages (without it, a tall step editor
              pushes the library cards off the bottom with no way to reach). */}
          <div className="flex-1 overflow-y-auto min-h-0">

          {/* Inline step editor — shown first when a workout is already
              assigned so editing is the primary affordance. */}
          {picker && isActiveWorkout && current && (
            <div className="px-5 py-4 border-b border-divider">
              <div className="flex items-center justify-between mb-3">
                <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
                  Steps
                </p>
                <button
                  type="button"
                  onClick={saveCurrentAsTemplate}
                  disabled={savingTemplate}
                  className="px-2.5 py-1 text-[10px] font-medium rounded-full border border-divider text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors disabled:opacity-50"
                >
                  {savingTemplate ? "Saving…" : "Save to library"}
                </button>
              </div>
              {templateSaveMsg && (
                <p className="text-[10px] text-text-secondary mb-2">{templateSaveMsg}</p>
              )}
              <WorkoutStepEditor
                steps={((current.workoutData as Record<string, unknown>)?.steps as WorkoutStep[]) || []}
                athletePaces={paceTable}
                onChange={(newSteps) => {
                  assignWorkout(
                    picker.day,
                    picker.session,
                    {
                      ...current,
                      workoutData: {
                        ...(current.workoutData || {}),
                        name: (current.workoutData as Record<string, string>)?.name || current.workoutType?.replace("_", " "),
                        steps: newSteps,
                      },
                    },
                    false
                  );
                }}
              />
            </div>
          )}

          {/* Rest option — only offered on a picked AM slot; a PM rest
              isn't a thing, you just remove the double. */}
          {picker && picker.session === "am" && (
            <button
              onClick={() =>
                assignWorkout(picker.day, "am", { dayOfWeek: picker.day, workoutType: "rest", notes: "" })
              }
              className="flex items-center gap-3 px-5 py-3 border-b border-divider hover:bg-bg-elevated transition-colors text-left w-full"
            >
              <span
                className="w-0.5 h-5 rounded-full flex-shrink-0"
                style={{ backgroundColor: WORKOUT_COLORS.rest }}
              />
              <span className="text-sm italic text-text-secondary">
                {hasAssignment ? "Replace with rest" : "Rest day"}
              </span>
            </button>
          )}

          {/* Build a new workout — ink, not coral: the rail's coral budget
              stays with the small "+" punctuation on the cards, and the
              page's one big coral stays Publish. */}
          <div className="px-5 py-4 border-b border-divider">
            <button
              type="button"
              onClick={openBuilder}
              className="w-full px-3 py-2 text-sm font-medium bg-text-primary text-white rounded-lg hover:bg-text-primary/90 transition-colors"
            >
              {picker
                ? hasAssignment
                  ? "Replace with a new workout"
                  : "Build a new workout"
                : "Build a new workout"}
            </button>
          </div>

          {/* Template library */}
          <div className="px-5 py-4 border-b border-divider">
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary mb-2">
              {picker ? (hasAssignment ? "Replace from library" : "From library") : "From library"}
            </p>
            <input
              type="text"
              placeholder="Search workouts"
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="w-full px-3 py-2 text-sm border border-divider rounded-lg bg-bg-elevated focus:outline-none focus:border-coral focus:bg-bg-card transition-colors placeholder:text-text-secondary"
            />
            {!picker && (
              <p className="text-[11px] italic text-text-secondary leading-relaxed mt-2">
                Drag a card onto a day, or tap one to drop it into the first
                open day of this week.
              </p>
            )}
          </div>

          <div>
            {filteredTemplates.length === 0 ? (
              <EmptyState
                variant="optional-empty"
                eyebrow={allTemplates.length === 0 ? "Empty library" : "No matches"}
                title={
                  allTemplates.length === 0
                    ? "Build a workout above. It'll be ready next time."
                    : "Nothing matches that search."
                }
              />
            ) : (
              librarySections.map((section) => (
                <div key={section.key}>
                  <p className="px-5 pt-3 pb-1 font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary sticky top-0 bg-bg-card/95 z-10 border-b border-divider-soft">
                    {section.label}
                  </p>
                  {section.items.map((template) => renderTemplateCard(template))}
                </div>
              ))
            )}
          </div>
          </div>
        </div>
        );
      })()}
      </div>{/* end inner flex row (left + right panes) */}

      {/* Workout Builder Modal — editorial dialog. Title in Crimson Pro,
          name field becomes the headline as the coach types. */}
      {builderOpen && (
        <div
          className="fixed inset-0 z-50 bg-text-primary/40 flex items-center justify-center p-4"
          onClick={() => setBuilderOpen(false)}
        >
          <div
            className="bg-bg-card rounded-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-7 space-y-5 shadow-[0_12px_40px_rgba(0,0,0,0.12)]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between">
              <div>
                <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
                  Workout
                </p>
                <h2 className="font-display text-2xl text-text-primary mt-0.5 leading-none">
                  {editingTemplateId ? "Edit" : "New"}
                </h2>
              </div>
              <button
                onClick={() => setBuilderOpen(false)}
                className="text-text-secondary hover:text-text-primary text-2xl leading-none -mt-1"
                aria-label="Close"
              >
                ×
              </button>
            </div>

            <input
              type="text"
              placeholder="6×800m at 5K pace"
              value={builderName}
              onChange={(e) => setBuilderName(e.target.value)}
              className="w-full font-display text-2xl text-text-primary border-b border-divider pb-2 outline-none bg-transparent placeholder:text-text-secondary placeholder:italic focus:border-coral transition-colors"
            />

            {/* Type chips — selected is a 12% wash of the zone blue with ink
                text (the design system's pill treatment), never a full color
                fill with white text: the pale zone blues can't carry white. */}
            <div className="flex flex-wrap gap-1.5">
              {QUICK_TYPES.map((type) => (
                <button
                  key={type}
                  onClick={() => setBuilderType(type)}
                  className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                    builderType === type
                      ? "text-text-primary font-medium"
                      : "text-text-secondary border-divider hover:border-text-tertiary"
                  }`}
                  style={{
                    backgroundColor: builderType === type ? `${WORKOUT_COLORS[type]}1F` : "transparent",
                    borderColor: builderType === type ? WORKOUT_COLORS[type] : undefined,
                  }}
                >
                  {type.replace("_", " ")}
                </button>
              ))}
            </div>

            {/* Describe it — natural-language shorthand → structured steps.
                Appends to the editor below; unparsed fragments are surfaced. */}
            <div className="border border-divider rounded-xl p-4 bg-bg-elevated space-y-2">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-secondary">
                Describe it
              </p>
              <textarea
                value={builderNL}
                onChange={(e) => setBuilderNL(e.target.value)}
                onKeyDown={(e) => {
                  // Cmd/Ctrl+Enter builds steps without leaving the box.
                  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
                    e.preventDefault();
                    applyDescribeIt();
                  }
                }}
                rows={2}
                placeholder="2mi wu, 6x800 @ 5k w/ 400m jog, 2mi cd"
                className="w-full px-3 py-2 text-sm font-mono border border-divider rounded-lg bg-bg-card focus:outline-none focus:border-coral transition-colors placeholder:text-text-secondary resize-y"
              />
              <div className="flex items-center justify-between gap-3">
                <p className="text-[11px] italic text-text-secondary leading-snug">
                  Reps, paces, zones (MP, LT, 5K), offsets (MP−10), recovery
                  (w/ 400m jog). Builds onto the steps below.
                </p>
                <button
                  type="button"
                  onClick={applyDescribeIt}
                  disabled={!builderNL.trim() || builderNLBusy}
                  className="shrink-0 px-3 py-1.5 text-xs font-medium border border-divider rounded-lg text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors disabled:opacity-40"
                >
                  {builderNLBusy ? "Reading…" : "Build steps"}
                </button>
              </div>
              {/* Questions come before the warnings: these are the ones the
                  coach can close with a tap, and closing them removes the
                  reason most of the warnings exist. */}
              {builderNLQuestions.length > 0 && (
                <div className="space-y-2 pt-1">
                  {builderNLQuestions.map((q) => (
                    <div key={q.id} className="space-y-1.5">
                      <p className="text-[11px] text-text-primary leading-snug">{q.question}</p>
                      <div className="flex flex-wrap gap-1">
                        {q.options.map((o) => (
                          <button
                            key={o.value}
                            type="button"
                            onClick={() => answerClarification(q, o.value)}
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
              {builderNLReadback && (
                <p className="text-[11px] text-text-secondary leading-snug">
                  {builderNLReadback}
                </p>
              )}
              {builderNLUnparsed.length > 0 && (
                <p className="text-[11px] text-[var(--color-warning)] leading-snug">
                  Couldn&apos;t parse: {builderNLUnparsed.join(" · ")}. Add these
                  by hand below.
                </p>
              )}
              {/* Louder than `unparsed` on purpose. A dropped fragment is
                  visibly missing from the editor; a guessed pace is not —
                  the step sits there looking finished. Coral is the alert
                  palette and this is exactly an alert. */}
              {builderNLWarnings.length > 0 && (
                <ul className="text-[11px] text-[var(--color-danger)] leading-snug list-none space-y-0.5">
                  {builderNLWarnings.map((w, i) => (
                    <li key={i}>Check before saving: {w}</li>
                  ))}
                </ul>
              )}
            </div>

            <div className="border border-divider rounded-xl p-4 bg-bg-elevated">
              <WorkoutStepEditor steps={builderSteps} onChange={setBuilderSteps} athletePaces={paceTable} />
            </div>

            {builderError && (
              <p className="text-xs text-[var(--color-danger)]">{builderError}</p>
            )}

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                onClick={() => setBuilderOpen(false)}
                className="px-4 py-1.5 text-sm text-text-secondary hover:text-text-primary transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={saveBuilderTemplate}
                disabled={savingTemplate}
                className="px-4 py-1.5 text-sm font-medium bg-coral text-white rounded-lg hover:bg-coral-dark transition-colors disabled:opacity-50"
              >
                {savingTemplate
                  ? "Saving…"
                  : editingTemplateId
                  ? "Save changes"
                  : "Save & assign"}
              </button>
            </div>
          </div>
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


"use client";

import { useState, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";

interface Athlete {
  id: string;
  athlete_user_id: string;
  status: string;
}

interface PlanAssignmentModalProps {
  planId: string;
  planName: string;
  planType: "fixed" | "adaptive";
  onClose: () => void;
  onAssigned: () => void;
}

export function PlanAssignmentModal({
  planId,
  planName,
  planType,
  onClose,
  onAssigned,
}: PlanAssignmentModalProps) {
  const [athletes, setAthletes] = useState<Athlete[]>([]);
  const [selectedAthlete, setSelectedAthlete] = useState<string | null>(null);
  const [assignToSelf, setAssignToSelf] = useState(true);
  const [startDate, setStartDate] = useState(getNextMonday());
  const [raceDate, setRaceDate] = useState("");
  const [isAssigning, setIsAssigning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const supabase = createClient();

  useEffect(() => {
    loadAthletes();
  }, []);

  async function loadAthletes() {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const { data: profile } = await supabase
      .from("coach_profiles")
      .select("id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!profile) return;

    const { data } = await supabase
      .from("coach_athlete_relationships")
      .select("id, athlete_user_id, status")
      .eq("coach_id", profile.id)
      .eq("status", "active");

    setAthletes(data || []);
  }

  async function handleAssign() {
    setIsAssigning(true);
    setError(null);

    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("Not authenticated");

      const athleteUserId = assignToSelf ? user.id : selectedAthlete;
      if (!athleteUserId) {
        setError("Please select an athlete");
        setIsAssigning(false);
        return;
      }

      const res = await fetch("/api/assign-plan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          planTemplateId: planId,
          athleteUserId,
          startDate,
          raceDate: raceDate || null,
        }),
      });

      const data = await res.json();
      if (data.error) throw new Error(data.error);

      setSuccess(true);
      setTimeout(() => onAssigned(), 1500);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Assignment failed");
    }

    setIsAssigning(false);
  }

  if (success) {
    return (
      <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
        <div className="bg-white rounded-2xl p-8 max-w-md w-full mx-4 text-center" onClick={(e) => e.stopPropagation()}>
          <div className="text-4xl mb-3">✓</div>
          <h3 className="text-lg font-semibold text-[var(--color-text-primary)]">Plan Assigned</h3>
          <p className="text-sm text-[var(--color-text-secondary)] mt-2">
            {planName} is now active. It will appear on the Training tab.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-2xl p-6 max-w-md w-full mx-4 space-y-5" onClick={(e) => e.stopPropagation()}>
        <div>
          <h3 className="text-lg font-semibold text-[var(--color-text-primary)]">Assign Plan</h3>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{planName}</p>
          {planType === "adaptive" && (
            <p className="text-[10px] text-[var(--color-mood-positive)] mt-1">
              Adaptive — workouts will be personalized based on the athlete's fitness
            </p>
          )}
        </div>

        {/* Assign to */}
        <div className="space-y-2">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
            Assign to
          </span>
          <div className="flex gap-2">
            <button
              onClick={() => { setAssignToSelf(true); setSelectedAthlete(null); }}
              className={`flex-1 py-2.5 text-sm rounded-lg border transition-colors ${
                assignToSelf
                  ? "border-[var(--color-coral)] bg-[var(--color-coral)]/5 text-[var(--color-coral)] font-medium"
                  : "border-[var(--color-divider)] text-[var(--color-text-secondary)]"
              }`}
            >
              Myself
            </button>
            <button
              onClick={() => setAssignToSelf(false)}
              disabled={athletes.length === 0}
              className={`flex-1 py-2.5 text-sm rounded-lg border transition-colors disabled:opacity-40 ${
                !assignToSelf
                  ? "border-[var(--color-coral)] bg-[var(--color-coral)]/5 text-[var(--color-coral)] font-medium"
                  : "border-[var(--color-divider)] text-[var(--color-text-secondary)]"
              }`}
            >
              Athlete {athletes.length > 0 ? `(${athletes.length})` : ""}
            </button>
          </div>

          {!assignToSelf && athletes.length > 0 && (
            <select
              value={selectedAthlete || ""}
              onChange={(e) => setSelectedAthlete(e.target.value || null)}
              className="w-full text-sm border border-[var(--color-divider)] rounded-lg px-3 py-2"
            >
              <option value="">Select athlete...</option>
              {athletes.map((a) => (
                <option key={a.id} value={a.athlete_user_id}>
                  {a.athlete_user_id.slice(0, 8)}...
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Dates */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
              Start Date
            </span>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full mt-1 text-sm border border-[var(--color-divider)] rounded-lg px-3 py-2"
            />
          </div>
          <div>
            <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
              Race Date (optional)
            </span>
            <input
              type="date"
              value={raceDate}
              onChange={(e) => setRaceDate(e.target.value)}
              className="w-full mt-1 text-sm border border-[var(--color-divider)] rounded-lg px-3 py-2"
            />
          </div>
        </div>

        {error && (
          <p className="text-sm text-[var(--color-mood-struggling)]">{error}</p>
        )}

        {/* Actions */}
        <div className="flex gap-2">
          <button
            onClick={onClose}
            className="flex-1 py-2.5 text-sm rounded-lg border border-[var(--color-divider)] text-[var(--color-text-secondary)]"
          >
            Cancel
          </button>
          <button
            onClick={handleAssign}
            disabled={isAssigning || (!assignToSelf && !selectedAthlete)}
            className="flex-1 py-2.5 text-sm rounded-lg bg-[var(--color-coral)] text-white font-medium disabled:opacity-50"
          >
            {isAssigning ? "Assigning..." : "Assign Plan"}
          </button>
        </div>
      </div>
    </div>
  );
}

function getNextMonday(): string {
  const d = new Date();
  const day = d.getDay();
  const diff = day === 0 ? 1 : 8 - day;
  d.setDate(d.getDate() + diff);
  return d.toISOString().split("T")[0];
}

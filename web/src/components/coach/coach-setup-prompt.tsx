"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Card } from "@/components/ui/card";

const SPECIALIZATIONS = [
  "Marathon",
  "Half Marathon",
  "10K",
  "5K",
  "Trail",
  "Track",
  "Ultra",
  "Triathlon",
];

export function CoachSetupPrompt() {
  const router = useRouter();
  const supabase = createClient();

  const [displayName, setDisplayName] = useState("");
  const [bio, setBio] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [isSaving, setIsSaving] = useState(false);

  const toggleSpec = (spec: string) => {
    const next = new Set(selected);
    if (next.has(spec)) {
      next.delete(spec);
    } else {
      next.add(spec);
    }
    setSelected(next);
  };

  const handleCreate = async () => {
    if (!displayName.trim()) return;
    setIsSaving(true);
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setIsSaving(false); return; }

    await supabase.from("coach_profiles").insert({
      user_id: user.id,
      display_name: displayName.trim(),
      bio: bio.trim() || null,
      specializations: Array.from(selected),
    });

    setIsSaving(false);
    router.refresh();
  };

  return (
    <div className="max-w-lg mx-auto pt-8">
      <Card className="p-8">
        <div className="text-center mb-8">
          <div className="text-5xl mb-4">🏃‍♂️</div>
          <h2 className="text-xl font-semibold text-[var(--color-text-primary)]">
            Set Up Your Coach Profile
          </h2>
          <p className="text-sm text-[var(--color-text-secondary)] mt-2">
            Create your profile to start building training plans and working with athletes.
          </p>
        </div>

        <div className="space-y-5">
          {/* Name */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)] mb-2">
              Your Name
            </label>
            <input
              type="text"
              placeholder="e.g. Alex Smith"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="w-full px-4 py-3 border border-[var(--color-divider)] rounded-lg text-sm focus:outline-none focus:border-[var(--color-coral)]"
            />
          </div>

          {/* Bio */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)] mb-2">
              Bio (optional)
            </label>
            <textarea
              placeholder="Tell athletes about your coaching background..."
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              rows={3}
              className="w-full px-4 py-3 border border-[var(--color-divider)] rounded-lg text-sm focus:outline-none focus:border-[var(--color-coral)] resize-none"
            />
          </div>

          {/* Specializations */}
          <div>
            <label className="block text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)] mb-2">
              Specializations
            </label>
            <div className="flex flex-wrap gap-2">
              {SPECIALIZATIONS.map((spec) => (
                <button
                  key={spec}
                  onClick={() => toggleSpec(spec)}
                  className={`px-3 py-1.5 text-sm rounded-full border transition-colors ${
                    selected.has(spec)
                      ? "bg-[var(--color-coral)] text-white border-[var(--color-coral)]"
                      : "bg-white text-[var(--color-text-primary)] border-[var(--color-divider)] hover:border-[var(--color-coral)]"
                  }`}
                >
                  {spec}
                </button>
              ))}
            </div>
          </div>

          {/* Submit */}
          <button
            onClick={handleCreate}
            disabled={!displayName.trim() || isSaving}
            className="w-full py-3 bg-[var(--color-coral)] text-white font-semibold rounded-lg hover:bg-[var(--color-coral-dark)] transition-colors disabled:opacity-50"
          >
            {isSaving ? "Creating..." : "Create Profile"}
          </button>
        </div>
      </Card>
    </div>
  );
}

"use client";

import { useState, useTransition } from "react";
import { DripButton } from "@/components/ui/drip-button";
import { updateAthleteProfileAction } from "@/app/(app)/coach-portal/athletes/[id]/actions";

// Mirror the DB CHECK limits (migration 20260716140000) client-side so the
// counters and guards match what the server will accept.
const NAME_MAX = 80;
const BIO_MAX = 600;

/**
 * ProfileEditor — inline name + bio editor for the athlete detail header.
 *
 * Renders an "Edit profile" toggle; when open, a small form writes the two
 * fields via the gated server action. On success the App Router revalidates
 * the page, so the header re-renders with the new values and the form closes.
 * Only mounted on the live route (needs a real athleteId).
 */
export function ProfileEditor({
  athleteId,
  initialName,
  initialBio,
}: {
  athleteId: string;
  initialName: string;
  initialBio: string;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(initialName);
  const [bio, setBio] = useState(initialBio);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function reset() {
    setName(initialName);
    setBio(initialBio);
    setError(null);
  }

  function save() {
    setError(null);
    startTransition(async () => {
      const res = await updateAthleteProfileAction(athleteId, { displayName: name, bio });
      if (res.ok) {
        setOpen(false);
      } else {
        setError(res.error);
      }
    });
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => {
          reset();
          setOpen(true);
        }}
        className="inline-flex items-center gap-1.5 rounded-full border border-coral/40 bg-coral/5 px-3 py-1 font-mono text-[10.5px] uppercase tracking-[0.08em] text-coral transition-colors hover:bg-coral/10"
      >
        <span aria-hidden className="text-[13px] leading-none">
          {initialName ? "✎" : "+"}
        </span>
        {initialName ? "Edit profile" : "Add name"}
      </button>
    );
  }

  return (
    <div className="mt-4 rounded-lg border border-divider bg-bg-elevated p-4">
      <div className="font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
        Athlete profile
      </div>

      <label className="mt-3 block">
        <span className="font-body text-[12.5px] text-text-secondary">Display name</span>
        <input
          type="text"
          value={name}
          maxLength={NAME_MAX}
          placeholder="e.g. Maya Chen"
          onChange={(e) => setName(e.target.value)}
          className="mt-1 w-full rounded-md border border-divider bg-bg-card px-3 py-2 font-body text-[15px] text-text-primary outline-none focus:border-coral"
        />
      </label>

      <label className="mt-3 block">
        <span className="font-body text-[12.5px] text-text-secondary">
          Notes <span className="text-text-tertiary">(goals, context — optional)</span>
        </span>
        <textarea
          value={bio}
          maxLength={BIO_MAX}
          rows={3}
          placeholder="BQ hopeful, ~40 mpw base, hates hills…"
          onChange={(e) => setBio(e.target.value)}
          className="mt-1 w-full resize-y rounded-md border border-divider bg-bg-card px-3 py-2 font-body text-[14px] leading-relaxed text-text-primary outline-none focus:border-coral"
        />
        <span className="mt-1 block text-right font-mono text-[10px] text-text-tertiary">
          {bio.length}/{BIO_MAX}
        </span>
      </label>

      {error ? (
        <p className="mt-2 font-body text-[12.5px] text-coral-dark">{error}</p>
      ) : null}

      <div className="mt-3 flex items-center gap-2">
        <DripButton
          variant="primary"
          onClick={save}
          isLoading={pending}
          className="!px-4 !py-2 !text-[13px]"
        >
          Save
        </DripButton>
        <DripButton
          variant="ghost"
          onClick={() => {
            reset();
            setOpen(false);
          }}
          disabled={pending}
          className="!px-4 !py-2 !text-[13px]"
        >
          Cancel
        </DripButton>
      </div>
    </div>
  );
}

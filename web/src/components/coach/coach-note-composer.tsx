"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

// Compact note composer that lives at the top of the coach's athlete
// deep-dive page. Editorial style — quiet textarea with a single
// "Send" affordance, no chrome. Disabled when empty.
//
// The athlete sees the most-recent unread note as a "From your coach"
// card on their iOS home. Threading, edit, and notification routing
// are deliberate follow-ups — this is the minimum viable channel.

export function CoachNoteComposer({
  athleteUserId,
  coachId,
  athleteFirstName,
}: {
  athleteUserId: string;
  coachId: string;
  athleteFirstName: string;
}) {
  const [body, setBody] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function send() {
    const trimmed = body.trim();
    if (!trimmed || status === "sending") return;
    setStatus("sending");
    setErrorMessage(null);
    const supabase = createClient();
    const { error } = await supabase
      .from("coach_notes")
      .insert({
        coach_id: coachId,
        athlete_user_id: athleteUserId,
        body: trimmed,
      });
    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
      return;
    }
    setBody("");
    setStatus("sent");
    // Brief confirmation, then return to idle so they can write another.
    setTimeout(() => setStatus("idle"), 2200);
  }

  const disabled = body.trim().length === 0 || status === "sending";

  return (
    <section>
      <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
        Send a note
      </p>
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        placeholder={`Write something to ${athleteFirstName}…`}
        rows={3}
        className="mt-3 w-full resize-y bg-transparent border-0 border-l-2 border-coral/30 pl-4 py-1 font-body text-[15px] leading-7 text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-coral"
        style={{ borderRadius: 0 }}
      />
      <div className="mt-2 flex items-center justify-between">
        <p className="font-body text-[11px] text-text-tertiary">
          {status === "sent"
            ? "Sent — they'll see it on their home."
            : status === "error"
              ? errorMessage ?? "Couldn't send. Try again."
              : "Lands on their iOS home as a card."}
        </p>
        <button
          type="button"
          onClick={send}
          disabled={disabled}
          className="px-4 py-1.5 rounded-full text-[12px] font-medium bg-coral text-white disabled:bg-text-tertiary disabled:cursor-not-allowed transition-colors"
        >
          {status === "sending" ? "Sending…" : "Send"}
        </button>
      </div>
    </section>
  );
}

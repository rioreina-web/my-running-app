"use client";

import { useState } from "react";

import { Eyebrow } from "@/components/site/editorial";

const CONTACT_EMAIL =
  process.env.NEXT_PUBLIC_BETA_CONTACT_EMAIL || "hello@postrundrip.com";

const MILEAGE = [
  { value: "under-20", label: "Under 20" },
  { value: "20-40", label: "20 – 40" },
  { value: "40-60", label: "40 – 60" },
  { value: "60-plus", label: "60 +" },
];

const COACHING = [
  { value: "self-coached", label: "Self-coached" },
  { value: "have-a-coach", label: "I have a coach" },
  { value: "i-coach", label: "I coach others" },
];

type Status = "idle" | "sending" | "sent" | "fallback" | "error";

export function BetaForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [email, setEmail] = useState("");
  const [race, setRace] = useState("");
  const [recent, setRecent] = useState("");
  const [mileage, setMileage] = useState("20-40");
  const [coaching, setCoaching] = useState("self-coached");

  async function onSubmit(event: React.FormEvent) {
    event.preventDefault();
    setStatus("sending");

    try {
      const res = await fetch("/api/beta-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, race, recent, mileage, coaching }),
      });

      if (res.ok) {
        setStatus("sent");
      } else if (res.status === 503) {
        // Nothing wired up on the backend yet — say so, offer the inbox.
        setStatus("fallback");
      } else {
        setStatus("error");
      }
    } catch {
      setStatus("error");
    }
  }

  if (status === "sent") {
    return (
      <div className="rounded-xl bg-bg-card p-8 shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
        <Eyebrow coral>On the list</Eyebrow>
        <h2 className="mt-4 font-display text-[30px] font-bold leading-[1.1] tracking-[-0.01em] text-text-primary">
          That is all we need.
        </h2>
        <p className="mt-4 max-w-[46ch] font-body text-[15px] leading-[1.6] text-text-secondary">
          Invites go out in small batches so the feedback stays readable. When
          yours lands it will come from TestFlight, to {email || "your inbox"}.
        </p>
      </div>
    );
  }

  return (
    <form
      onSubmit={onSubmit}
      className="rounded-xl bg-bg-card p-6 shadow-[0_2px_8px_rgba(0,0,0,0.06)] md:p-8"
    >
      <Eyebrow coral>Request an invite</Eyebrow>

      <div className="mt-6 space-y-6">
        <Field label="Email" htmlFor="email" required>
          <input
            id="email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            className="w-full rounded-lg border border-divider bg-bg-base px-3.5 py-2.5 font-body text-[15px] text-text-primary outline-none transition-colors placeholder:text-text-tertiary focus:border-coral focus:outline-2 focus:outline-offset-2 focus:outline-coral"
          />
        </Field>

        <Field label="Goal race" htmlFor="race" hint="Optional">
          <input
            id="race"
            type="text"
            value={race}
            onChange={(e) => setRace(e.target.value)}
            placeholder="Chicago, October — going for 3:16"
            className="w-full rounded-lg border border-divider bg-bg-base px-3.5 py-2.5 font-body text-[15px] text-text-primary outline-none transition-colors placeholder:text-text-tertiary focus:border-coral focus:outline-2 focus:outline-offset-2 focus:outline-coral"
          />
        </Field>

        <Field label="Most recent race" htmlFor="recent" hint="Optional">
          <input
            id="recent"
            type="text"
            value={recent}
            onChange={(e) => setRecent(e.target.value)}
            placeholder="3:28 marathon, two years ago"
            className="w-full rounded-lg border border-divider bg-bg-base px-3.5 py-2.5 font-body text-[15px] text-text-primary outline-none transition-colors placeholder:text-text-tertiary focus:border-coral focus:outline-2 focus:outline-offset-2 focus:outline-coral"
          />
        </Field>

        <ChipGroup
          legend="Weekly mileage"
          options={MILEAGE}
          value={mileage}
          onChange={setMileage}
        />

        <ChipGroup
          legend="How you train"
          options={COACHING}
          value={coaching}
          onChange={setCoaching}
        />
      </div>

      <button
        type="submit"
        disabled={status === "sending"}
        className="mt-8 w-full rounded-[10px] bg-coral px-6 py-3.5 font-display text-[16px] font-semibold text-white transition-colors hover:bg-coral-dark disabled:opacity-50"
      >
        {status === "sending" ? "Sending…" : "Request an invite"}
      </button>

      <p className="mt-4 font-body text-[13px] italic leading-[1.55] text-text-tertiary">
        One email when your invite is ready, and nothing else. No list, no
        drip sequence.
      </p>

      {status === "fallback" && (
        <p className="mt-5 border-t border-divider pt-5 font-body text-[14px] leading-[1.6] text-text-secondary">
          The invite list is not wired up on this deploy yet. Send a note to{" "}
          <a
            href={`mailto:${CONTACT_EMAIL}?subject=TestFlight%20invite`}
            className="text-coral underline underline-offset-4 hover:text-coral-dark"
          >
            {CONTACT_EMAIL}
          </a>{" "}
          and it goes on the list by hand.
        </p>
      )}

      {status === "error" && (
        <p className="mt-5 border-t border-divider pt-5 font-body text-[14px] leading-[1.6] text-text-secondary">
          That did not go through. Try again, or email{" "}
          <a
            href={`mailto:${CONTACT_EMAIL}?subject=TestFlight%20invite`}
            className="text-coral underline underline-offset-4 hover:text-coral-dark"
          >
            {CONTACT_EMAIL}
          </a>
          .
        </p>
      )}
    </form>
  );
}

function Field({
  label,
  htmlFor,
  hint,
  required,
  children,
}: {
  label: string;
  htmlFor: string;
  hint?: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label
        htmlFor={htmlFor}
        className="flex items-baseline justify-between pb-2"
      >
        <Eyebrow className="!text-text-secondary">{label}</Eyebrow>
        {hint && !required && <Eyebrow>{hint}</Eyebrow>}
      </label>
      {children}
    </div>
  );
}

function ChipGroup({
  legend,
  options,
  value,
  onChange,
}: {
  legend: string;
  options: { value: string; label: string }[];
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <fieldset>
      <legend className="pb-2">
        <Eyebrow className="!text-text-secondary">{legend}</Eyebrow>
      </legend>
      <div className="flex flex-wrap gap-2">
        {options.map((option) => {
          const active = option.value === value;
          return (
            <button
              key={option.value}
              type="button"
              onClick={() => onChange(option.value)}
              aria-pressed={active}
              className={`rounded-full px-3.5 py-2 font-display text-[14px] font-medium transition-colors ${
                active
                  ? "border-[1.5px] border-coral text-coral"
                  : "border border-divider text-text-secondary hover:text-text-primary"
              }`}
            >
              {option.label}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}

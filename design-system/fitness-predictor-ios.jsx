/* global React */
/* ════════════════════════════════════════════════════════════════════
   POST RUN DRIP · iOS · FITNESS PREDICTOR
   The mobile cousin of fitness-predictor.jsx (web, forward read).
   Built against ui_kits/ios_app primitives (Eyebrow, MoodPill, etc.)
   and tokens.css.

   Voice rules (per brand-voice.md):
   - Numbers over adjectives. Half-sentences where a full one works.
   - One coral. UPPERCASE mono labels w/ `·` separators.
   - Headlines end in a period.
   - Coach copy admits uncertainty; never crushes / grinds / journeys.
   ════════════════════════════════════════════════════════════════════ */

const { useState } = React;

/* ── time helpers ────────────────────────────────────────────────── */
const sec = (m, s = 0) => m * 60 + s;
const fmt = (t) => {
  const a = Math.abs(Math.round(t));
  const h = Math.floor(a / 3600);
  const m = Math.floor((a % 3600) / 60);
  const s = a % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  return `${m}:${String(s).padStart(2, "0")}`;
};
const fmtDelta = (t) => {
  if (Math.abs(t) < 1) return "—";
  const sign = t < 0 ? "−" : "+";
  return sign + fmt(Math.abs(t));
};

/* ── state badge color ───────────────────────────────────────────── */
const STATE = {
  tight:    { lbl: "TIGHT",    color: "var(--mood-energized)" },
  moderate: { lbl: "MODERATE", color: "var(--ink-2)" },
  wide:     { lbl: "WIDE",     color: "var(--coral)" },
};

Object.assign(window, { sec, fmt, fmtDelta, STATE });

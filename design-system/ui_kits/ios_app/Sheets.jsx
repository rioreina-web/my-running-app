// Post Run Drip · iOS UI kit · Sheet primitives + general sheets
//
// Provides:
//   <Sheet>              — bottom-sheet shell with drag indicator, plate strip,
//                          back/close link, body scroll.
//   DayDetailSheet       — Plate 22 day-of-plan detail
//   WorkoutPickerSheet   — pick a HealthKit workout to link a voice memo to
//   ManualWorkoutSheet   — manual entry of a workout
//   HistoryDetailSheet   — read/edit a journal entry

const SHEETS_CSS = `
.prd-sheet {
  background: var(--paper);
  width: 100%; height: 100%;
  display: flex; flex-direction: column;
  border-radius: 12px 12px 0 0;
  overflow: hidden;
  position: relative;
}
.prd-sheet__grabber {
  width: 36px; height: 4px; border-radius: 999px;
  background: var(--ink-3);
  opacity: 0.35;
  margin: 8px auto 0 auto;
  flex: 0 0 auto;
}
.prd-sheet__chrome {
  display: flex; justify-content: space-between; align-items: center;
  padding: 10px 24px 0 24px;
  font-family: var(--font-mono);
  font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
  flex: 0 0 auto;
}
.prd-sheet__close, .prd-sheet__act {
  cursor: pointer;
  color: var(--coral);
}
.prd-sheet__close { color: var(--ink-2); }
.prd-sheet__close:hover { color: var(--coral); }

.prd-sheet__body {
  flex: 1; overflow-y: auto;
  padding: 14px 24px 32px 24px;
  scroll-behavior: smooth;
}
.prd-sheet__body::-webkit-scrollbar { display: none; }

/* Field-row used in many sheets */
.prd-fieldrow {
  display: flex; flex-direction: column; gap: 8px;
  padding: 16px 0;
  border-bottom: 1px solid var(--rule);
}
.prd-fieldrow__label {
  font-family: var(--font-mono);
  font-size: 10px; font-weight: 500;
  letter-spacing: 0.14em; color: var(--ink-3);
  text-transform: uppercase;
}
.prd-fieldrow__big {
  font-family: var(--font-mono);
  font-weight: 600; font-size: 32px; color: var(--ink);
  font-variant-numeric: tabular-nums;
  background: transparent; border: 0; outline: 0; padding: 0;
  width: 100%;
}

/* Generic chip cluster */
.prd-chip-cluster { display: flex; flex-wrap: wrap; gap: 8px; }
.prd-chip {
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.12em;
  padding: 8px 14px; border-radius: 999px;
  border: 1px solid var(--rule); background: var(--card);
  color: var(--ink-2);
  cursor: pointer;
  text-transform: uppercase;
}
.prd-chip.is-active {
  background: transparent; color: var(--coral); border-color: var(--coral);
}

/* Day-detail step row */
.prd-step-row {
  display: grid;
  grid-template-columns: 28px 1fr 80px;
  gap: 12px;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
  align-items: baseline;
}
.prd-step-row__n {
  font-family: var(--font-mono); font-size: 10px; font-weight: 600;
  letter-spacing: 0.10em; color: var(--coral);
}
.prd-step-row__name {
  font-family: var(--font-display); font-size: 15px; font-weight: 600; color: var(--ink);
}
.prd-step-row__hint {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3);
  display: block; margin-top: 2px;
}
.prd-step-row__rhs {
  font-family: var(--font-mono); font-size: 13px; font-weight: 600;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
  text-align: right;
}

/* Workout picker row */
.prd-pick-row {
  display: grid;
  grid-template-columns: 1fr 80px;
  gap: 12px;
  padding: 16px 0;
  border-bottom: 1px solid var(--rule);
  align-items: center;
  cursor: pointer;
}
.prd-pick-row:hover { background: rgba(0,0,0,0.015); }
.prd-pick-row__date {
  font-family: var(--font-mono); font-size: 10px; font-weight: 500;
  letter-spacing: 0.10em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-pick-row__name {
  font-family: var(--font-display); font-size: 18px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
  margin-top: 4px;
}
.prd-pick-row__meta {
  font-family: var(--font-mono); font-size: 10px;
  color: var(--ink-3); letter-spacing: 0.08em;
  margin-top: 2px;
}
.prd-pick-row__add {
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  letter-spacing: 0.14em; color: var(--coral);
  text-transform: uppercase; text-align: right;
}
`;

// ---- Sheet shell --------------------------------------------------------
const Sheet = ({ surface, fig, onClose, action, actionLabel, children }) => (
  <div className="prd-sheet">
    <style>{SHEETS_CSS}</style>
    <div className="prd-sheet__grabber"></div>
    <div className="prd-sheet__chrome">
      <span className="prd-sheet__close" onClick={onClose}>← Close</span>
      <span style={{ flex: 1, textAlign: "center", color: "var(--ink-2)" }}>{surface}</span>
      {action ? (
        <span className="prd-sheet__act" onClick={action}>{actionLabel || "Save"}</span>
      ) : (
        <span style={{ color: "var(--ink-3)" }}>{fig || ""}</span>
      )}
    </div>
    <div className="prd-sheet__body">{children}</div>
  </div>
);

// ---- DayDetailSheet (Plate 22) — workout breakdown ---------------------
//
// Beefed-up workout prescription: hero stats, prescribed-pace ladder,
// per-step structure with target pace + HR zone + RPE, splits preview,
// fueling notes, coach note, action strip.

const WORKOUT_BREAKDOWN_CSS = `
.prd-wb__statgrid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  padding: 14px 0;
  border-top: 1px solid var(--rule);
  border-bottom: 1px solid var(--rule);
}
.prd-wb__stat {
  display: flex; flex-direction: column; gap: 4px;
  border-right: 1px solid var(--rule);
  padding: 0 10px;
}
.prd-wb__stat:last-child { border-right: 0; }
.prd-wb__stat-l {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.12em; color: var(--ink-2);
  text-transform: uppercase;
}
.prd-wb__stat-v {
  font-family: var(--font-mono); font-weight: 600; font-size: 20px;
  color: var(--ink); font-variant-numeric: tabular-nums;
  display: flex; align-items: baseline; gap: 4px;
}
.prd-wb__stat-v span {
  font-size: 10px; color: var(--ink-2); font-weight: 500;
}
.prd-wb__stat-s {
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.08em; color: var(--ink-3);
  text-transform: uppercase;
}

.prd-wb__step {
  display: grid;
  grid-template-columns: 24px 1fr auto;
  gap: 12px;
  padding: 14px 0;
  border-bottom: 1px solid var(--rule);
  align-items: start;
}
.prd-wb__step:last-child { border-bottom: 0; }
.prd-wb__step-n {
  font-family: var(--font-mono); font-size: 10px; font-weight: 600;
  letter-spacing: 0.10em; color: var(--coral);
  padding-top: 2px;
}
.prd-wb__step-name {
  font-family: var(--font-display); font-size: 16px; font-weight: 700;
  color: var(--ink); letter-spacing: -0.01em;
}
.prd-wb__step-hint {
  font-family: var(--font-body); font-style: italic;
  font-size: 12px; color: var(--ink-3); line-height: 1.4;
  margin-top: 4px;
}
.prd-wb__step-targets {
  display: flex; gap: 10px; flex-wrap: wrap;
  margin-top: 6px;
}
.prd-wb__step-target {
  font-family: var(--font-mono); font-size: 10px;
  font-weight: 500; letter-spacing: 0.10em;
  color: var(--ink-2); text-transform: uppercase;
  font-variant-numeric: tabular-nums;
  display: inline-flex; align-items: center; gap: 6px;
}
.prd-wb__step-target span.k {
  color: var(--ink-3);
}
.prd-wb__step-target span.v {
  color: var(--ink); font-weight: 600;
}
.prd-wb__step-target.is-coral span.v { color: var(--coral); }

.prd-wb__step-rhs {
  font-family: var(--font-mono); font-variant-numeric: tabular-nums;
  text-align: right;
}
.prd-wb__step-dist {
  font-size: 15px; font-weight: 600; color: var(--ink);
}
.prd-wb__step-dur {
  font-size: 9px; color: var(--ink-3); letter-spacing: 0.10em;
  text-transform: uppercase; margin-top: 4px;
}

.prd-wb__paceshape {
  height: 56px;
  display: flex; align-items: stretch;
  gap: 4px;
  padding: 10px 0 14px 0;
}
.prd-wb__paceshape-bar {
  flex: 1;
  background: var(--ink-3);
  opacity: 0.4;
  border-radius: 2px;
  align-self: end;
}
.prd-wb__paceshape-bar.is-mp { background: var(--coral); opacity: 1; }
.prd-wb__paceshape-bar.is-wu { background: var(--ink-3); opacity: 0.4; }
.prd-wb__paceshape-bar.is-cd { background: var(--ink-3); opacity: 0.4; }
.prd-wb__paceshape-bar.is-rest { background: var(--ink-3); opacity: 0.25; }
.prd-wb__paceshape-labels {
  display: flex; justify-content: space-between;
  font-family: var(--font-mono); font-size: 9px;
  letter-spacing: 0.10em; color: var(--ink-3);
  text-transform: uppercase;
}

/* Interval reps strip */
.prd-wb__reps {
  display: grid;
  grid-template-columns: 32px repeat(6, 1fr);
  column-gap: 6px;
  row-gap: 6px;
  padding: 10px 0 4px 0;
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
}
.prd-wb__reps-rowlbl {
  font-size: 9px; letter-spacing: 0.12em;
  color: var(--ink-3); text-transform: uppercase;
  display: flex; align-items: center;
}
.prd-wb__reps-num {
  font-size: 10px; font-weight: 600;
  color: var(--coral); text-align: center;
  letter-spacing: 0.10em;
}
.prd-wb__reps-pip {
  height: 28px;
  background: var(--coral);
  border-radius: 2px;
}
.prd-wb__reps-val {
  font-size: 12px; font-weight: 600;
  color: var(--ink); text-align: center;
}
.prd-wb__reps-rest {
  font-size: 9px; color: var(--ink-3);
  letter-spacing: 0.08em; text-align: center;
  text-transform: uppercase;
}

.prd-wb__fuel {
  display: grid; grid-template-columns: 60px 1fr;
  gap: 12px;
  padding: 10px 0;
  border-bottom: 1px solid var(--rule);
  align-items: baseline;
}
.prd-wb__fuel:last-child { border-bottom: 0; }
.prd-wb__fuel-when {
  font-family: var(--font-mono); font-size: 11px; font-weight: 600;
  letter-spacing: 0.10em; color: var(--coral);
  text-transform: uppercase;
}
.prd-wb__fuel-what {
  font-family: var(--font-body); font-size: 13px;
  color: var(--ink); line-height: 1.4;
}
`;

// Workout breakdown templates — keyed by day.id from PlanScreen.
// Each template covers a single prescribed session; fueling is optional
// (omit the key entirely for easy / recovery runs).
const WORKOUT_TEMPLATES = {
  // MON · Easy 6 — recovery, no fuel needed
  d1: {
    eyebrow: "MONDAY  ·  PLAN  ·  WK 17  ·  DONE",
    title: "Easy 6.",
    subtitle: "— May 4 · aerobic recovery from yesterday's long. —",
    stats: [
      { l: "DISTANCE", v: "6",   u: "mi",   s: "RECOVERY"   },
      { l: "DURATION", v: "46",  u: "min",  s: "EST."        },
      { l: "TARGET",   v: "7:38", u: "/mi", s: "EASY"        },
      { l: "LOAD",     v: "42",  u: "",     s: "LIGHT"       },
    ],
    pace: [
      { kind: "wu", flex: 1, h: "40%", label: "EASY · 6 MI" },
    ],
    steps: [
      { n: "01", name: "Easy 6", hint: "Conversational throughout. HR under 145. If it isn't easy, slow down.",
        pace: "7:38 / mi", hr: "Z1 · 130–145", rpe: "3",
        dist: "6.0 mi", dur: "46 min", coral: false },
    ],
    coach: "Real easy day. Resist the urge to push. The MP block Tuesday is what matters this week — protect it.",
  },

  // TUE · MP rhythm session
  d2: {
    eyebrow: "TUESDAY  ·  PLAN  ·  WK 17",
    title: "MP rhythm.",
    subtitle: "— May 5 · second of three MP blocks this cycle. —",
    stats: [
      { l: "DISTANCE", v: "11",   u: "mi",   s: "+1 VS BASE" },
      { l: "DURATION", v: "78",   u: "min",  s: "EST."        },
      { l: "TARGET",   v: "7:15", u: "/mi",  s: "MP BLOCK"    },
      { l: "LOAD",     v: "94",   u: "",     s: "+12 VS TYP"  },
    ],
    pace: [
      { kind: "wu", flex: 2.0, h: "30%", label: "WARM-UP" },
      { kind: "wu", flex: 0.5, h: "55%", label: "STRIDES" },
      { kind: "mp", flex: 7.0, h: "80%", label: "MP · 7 MI" },
      { kind: "cd", flex: 1.5, h: "20%", label: "CD" },
    ],
    steps: [
      { n: "01", name: "Warm-up", hint: "Easy aerobic to settle. Drills last block.",
        pace: "8:00 / mi", hr: "Z1 · 125–140", rpe: "3",
        dist: "2.0 mi", dur: "16 min", coral: false },
      { n: "02", name: "Strides", hint: "Open up. 4 × 20s @ 5K effort, full recovery.",
        pace: "5:45 / mi", hr: "Z2–3", rpe: "6",
        dist: "0.5 mi", dur: "4 min", coral: false },
      { n: "03", name: "MP block", hint: "Hold splits within 2s. Negative is fine — positive is not.",
        pace: "7:15 / mi", hr: "Z3 · 155–162", rpe: "7",
        dist: "7.0 mi", dur: "51 min", coral: true },
      { n: "04", name: "Cool-down", hint: "Float home. Breathe through the nose if you can.",
        pace: "8:30 / mi", hr: "Z1", rpe: "2",
        dist: "1.5 mi", dur: "13 min", coral: false },
    ],
    fueling: [
      { when: "−3 H",  what: "Oatmeal + banana + black coffee. ~400 cal." },
      { when: "−45 M", what: "8oz water + electrolyte. Light pre-run pee." },
      { when: "MI 4",  what: "Caffeinated gel. Sip water at start of MP block." },
      { when: "POST",  what: "Recovery shake + protein within 30min. Salt." },
    ],
    coach: "Second of three MP blocks. Hold splits — don't chase. Negative is fine, positive is not. If the knee speaks up in the warm-up, swap for an easy 8 and text me.",
  },

  // WED · Easy 7 — no fuel
  d3: {
    eyebrow: "WEDNESDAY  ·  PLAN  ·  WK 17",
    title: "Easy 7.",
    subtitle: "— May 6 · between MP and VO2. Conversational only. —",
    stats: [
      { l: "DISTANCE", v: "7",   u: "mi",   s: "BASE"     },
      { l: "DURATION", v: "53",  u: "min",  s: "EST."      },
      { l: "TARGET",   v: "7:35", u: "/mi", s: "EASY"      },
      { l: "LOAD",     v: "48",  u: "",     s: "LIGHT"     },
    ],
    pace: [
      { kind: "wu", flex: 6.5, h: "40%", label: "EASY · 6.5 MI" },
      { kind: "wu", flex: 0.5, h: "65%", label: "STRIDES" },
    ],
    steps: [
      { n: "01", name: "Easy 6.5", hint: "Truly conversational. Resist any urge to push.",
        pace: "7:35 / mi", hr: "Z1 · 130–145", rpe: "3",
        dist: "6.5 mi", dur: "49 min", coral: false },
      { n: "02", name: "Strides", hint: "4 × 20s, full recovery between. Form work.",
        pace: "5:45 / mi", hr: "—", rpe: "6",
        dist: "0.5 mi", dur: "4 min", coral: false },
    ],
    coach: "Easy day. The strides keep the legs lively without adding load. VO2 tomorrow — sleep early.",
  },

  // THU · VO2 6 × 800m — the intervals template
  d4: {
    eyebrow: "THURSDAY  ·  PLAN  ·  WK 17",
    title: "VO2 surge.",
    subtitle: "— May 7 · first VO2 session of the block. —",
    stats: [
      { l: "DISTANCE", v: "9",    u: "mi",   s: "INTERVALS"   },
      { l: "DURATION", v: "65",   u: "min",  s: "EST."        },
      { l: "TARGET",   v: "5:42", u: "/mi",  s: "5K PACE"     },
      { l: "LOAD",     v: "112",  u: "",     s: "+30 VS TYP"  },
    ],
    // Pace shape: WU low → 6 coral spikes with gaps → CD low
    pace: [
      { kind: "wu",   flex: 2.0, h: "30%", label: "WU" },
      { kind: "wu",   flex: 0.5, h: "55%", label: "ST" },
      { kind: "mp",   flex: 0.5, h: "100%" },
      { kind: "rest", flex: 0.3, h: "20%"  },
      { kind: "mp",   flex: 0.5, h: "100%" },
      { kind: "rest", flex: 0.3, h: "20%"  },
      { kind: "mp",   flex: 0.5, h: "100%" },
      { kind: "rest", flex: 0.3, h: "20%"  },
      { kind: "mp",   flex: 0.5, h: "100%" },
      { kind: "rest", flex: 0.3, h: "20%"  },
      { kind: "mp",   flex: 0.5, h: "100%" },
      { kind: "rest", flex: 0.3, h: "20%"  },
      { kind: "mp",   flex: 0.5, h: "100%", label: "6 × 800M" },
      { kind: "cd",   flex: 2.0, h: "20%", label: "CD" },
    ],
    steps: [
      { n: "01", name: "Warm-up", hint: "Easy aerobic + drills. Get HR settled, hips open.",
        pace: "8:00 / mi", hr: "Z1 · 125–140", rpe: "3",
        dist: "2.0 mi", dur: "16 min", coral: false },
      { n: "02", name: "Strides", hint: "4 × 20s @ rep pace. Prep the gears.",
        pace: "5:30 / mi", hr: "Z3", rpe: "7",
        dist: "0.5 mi", dur: "4 min", coral: false },
      { n: "03", name: "Main set · 6 × 800m", hint: "Even effort across all 6. Last two should feel hard — not desperate.",
        pace: "5:42 / mi", hr: "Z4 · 168–175", rpe: "8.5",
        dist: "3.0 mi", dur: "17 min", coral: true },
      { n: "04", name: "Cool-down", hint: "Long and easy. Walk if you need to.",
        pace: "8:30 / mi", hr: "Z1", rpe: "2",
        dist: "3.5 mi", dur: "28 min", coral: false },
    ],
    // Interval reps — 6 × 800m
    reps: {
      title: "REPS  ·  6 × 800M",
      meta: "TARGET 2:51  ·  90S JOG RECOVERY",
      rows: [
        { id: "tgt",  label: "TARGET", values: ["2:51","2:51","2:51","2:51","2:51","2:51"] },
        { id: "rest", label: "REST",   values: ["90s","90s","90s","90s","90s","—"] },
      ],
    },
    fueling: [
      { when: "−2 H",  what: "Toast + jam + coffee. Light. ~300 cal." },
      { when: "−30 M", what: "Half-bottle electrolyte. Open the legs in the warm-up." },
      { when: "POST",  what: "20g protein within 30min. The session was glycogen-heavy." },
    ],
    coach: "First VO2 of the block. Even is better than fast — 2:51 across the board beats 2:46-2:46-2:50-2:53-2:58-3:02 every time. Cap it at 6 even if you feel great.",
  },

  // FRI · Recovery shakeout — no fuel
  d5: {
    eyebrow: "FRIDAY  ·  PLAN  ·  WK 17",
    title: "Shakeout.",
    subtitle: "— May 8 · loosen up from VO2. Watch off if you can. —",
    stats: [
      { l: "DISTANCE", v: "4",   u: "mi",   s: "RECOVERY" },
      { l: "DURATION", v: "34",  u: "min",  s: "EST."     },
      { l: "TARGET",   v: "8:30", u: "/mi", s: "VERY EASY" },
      { l: "LOAD",     v: "22",  u: "",     s: "MINIMAL"  },
    ],
    pace: [
      { kind: "wu", flex: 1, h: "30%", label: "EASY · 4 MI" },
    ],
    steps: [
      { n: "01", name: "Recovery 4", hint: "Slowest pace you can run without it being a walk. Watch off, no metrics.",
        pace: "8:30 / mi", hr: "Z1 · <140", rpe: "2",
        dist: "4.0 mi", dur: "34 min", coral: false },
    ],
    coach: "Float. The goal is movement, not training. If you feel a niggle, stop — it's just a shakeout.",
  },

  // SUN · Long run with MP segment
  d7: {
    eyebrow: "SUNDAY  ·  PLAN  ·  WK 17  ·  KEY",
    title: "Long with MP.",
    subtitle: "— May 10 · the workout of the week. Practice race-day fueling. —",
    stats: [
      { l: "DISTANCE", v: "20",   u: "mi",   s: "LONG RUN"   },
      { l: "DURATION", v: "2:30", u: "",     s: "EST."        },
      { l: "TARGET",   v: "7:30", u: "/mi",  s: "PROGRESSIVE" },
      { l: "LOAD",     v: "168",  u: "",     s: "+45 VS TYP"  },
    ],
    pace: [
      { kind: "wu", flex: 14, h: "40%", label: "EASY · 14 MI" },
      { kind: "mp", flex: 6,  h: "75%", label: "MP · 6 MI" },
    ],
    steps: [
      { n: "01", name: "Easy section", hint: "Conversational. HR under 150 for the full 14.",
        pace: "7:40 / mi", hr: "Z1–2 · 135–150", rpe: "4",
        dist: "14.0 mi", dur: "1:47", coral: false },
      { n: "02", name: "MP finish", hint: "Drop into goal pace. Hold it. Practice fueling under fatigue.",
        pace: "7:15 / mi", hr: "Z3 · 155–162", rpe: "7",
        dist: "6.0 mi", dur: "43 min", coral: true },
    ],
    fueling: [
      { when: "−3 H",  what: "Oatmeal + banana + black coffee. Eat what you'd eat on race day." },
      { when: "MI 6",  what: "First gel. Note the flavor — you'll have it again at race day." },
      { when: "MI 11", what: "Second gel + electrolyte." },
      { when: "MI 16", what: "Caffeine gel — the one you'll take at mile 18 on race day." },
      { when: "POST",  what: "Big recovery meal. Sleep. The supercompensation happens tonight." },
    ],
    coach: "Workout of the week. The MP at the end matters more than the total miles — that's the race-day finish in miniature. Run the easy section easy enough to do the MP well.",
  },
};

// Pull a template by day.id with a sensible fallback to the MP session.
const getWorkout = (day) => {
  if (day && day.id && WORKOUT_TEMPLATES[day.id]) return WORKOUT_TEMPLATES[day.id];
  return WORKOUT_TEMPLATES.d2;
};

const DayDetailSheet = ({ onClose, onMarkComplete, day }) => {
  const w = getWorkout(day);
  return (
  <Sheet surface="PLAN · DAY DETAIL · FIG. 22" onClose={onClose}>
    <style>{WORKOUT_BREAKDOWN_CSS}</style>

    {/* Title */}
    <Eyebrow coral>{w.eyebrow}</Eyebrow>
    <h1 className="h-display" style={{ fontSize: 36, marginTop: 4 }}>{w.title}</h1>
    <div style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 14, color: "var(--ink-2)", marginTop: 4 }}>
      {w.subtitle}
    </div>

    {/* Stat grid */}
    <div style={{ marginTop: 18 }}>
      <div className="prd-wb__statgrid">
        {w.stats.map((s, i) => (
          <div key={i} className="prd-wb__stat">
            <span className="prd-wb__stat-l">{s.l}</span>
            <span className="prd-wb__stat-v">{s.v}{s.u && <span>{s.u}</span>}</span>
            <span className="prd-wb__stat-s">{s.s}</span>
          </div>
        ))}
      </div>
    </div>

    {/* Pace shape — only when multi-segment */}
    {w.pace && w.pace.length > 1 && (
      <div style={{ paddingTop: 18 }}>
        <Eyebrow>PACE SHAPE  ·  HEIGHT = EFFORT</Eyebrow>
        <div className="prd-wb__paceshape">
          {w.pace.map((seg, i) => (
            <div
              key={i}
              className={"prd-wb__paceshape-bar is-" + seg.kind}
              style={{ flex: seg.flex, height: seg.h }}
            />
          ))}
        </div>
        <div className="prd-wb__paceshape-labels">
          {w.pace.filter(p => p.label).map((p, i) => (
            <span key={i}>{p.label}</span>
          ))}
        </div>
      </div>
    )}

    {/* Structure */}
    <div style={{ paddingTop: w.pace && w.pace.length > 1 ? 8 : 18 }}>
      <Eyebrow>STRUCTURE  ·  {w.steps.length} {w.steps.length === 1 ? "STEP" : "STEPS"}</Eyebrow>
      <div style={{ marginTop: 4 }}>
        {w.steps.map(s => (
          <div key={s.n} className="prd-wb__step">
            <span className="prd-wb__step-n">{s.n}</span>
            <div>
              <div className="prd-wb__step-name">{s.name}</div>
              <div className="prd-wb__step-hint">{s.hint}</div>
              <div className="prd-wb__step-targets">
                <span className={"prd-wb__step-target" + (s.coral ? " is-coral" : "")}>
                  <span className="k">PACE</span><span className="v">{s.pace}</span>
                </span>
                <span className="prd-wb__step-target">
                  <span className="k">HR</span><span className="v">{s.hr}</span>
                </span>
                <span className="prd-wb__step-target">
                  <span className="k">RPE</span><span className="v">{s.rpe}</span>
                </span>
              </div>
            </div>
            <div className="prd-wb__step-rhs">
              <div className="prd-wb__step-dist">{s.dist}</div>
              <div className="prd-wb__step-dur">{s.dur}</div>
            </div>
          </div>
        ))}
      </div>
    </div>

    {/* Reps — intervals only */}
    {w.reps && (
      <div style={{ paddingTop: 20 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <Eyebrow>{w.reps.title}</Eyebrow>
          <Eyebrow>{w.reps.meta}</Eyebrow>
        </div>
        <div className="prd-wb__reps">
          {/* Row 1: rep numbers */}
          <span className="prd-wb__reps-rowlbl">REP</span>
          {w.reps.values && null}
          {[1,2,3,4,5,6].map(n => (
            <span key={"n"+n} className="prd-wb__reps-num">{n}</span>
          ))}
          {/* Row 2: coral pip bars */}
          <span />
          {[1,2,3,4,5,6].map(n => (
            <div key={"p"+n} className="prd-wb__reps-pip" />
          ))}
          {/* Row 3+: data rows */}
          {w.reps.rows.map(row => (
            <React.Fragment key={row.id}>
              <span className="prd-wb__reps-rowlbl">{row.label}</span>
              {row.values.map((v, i) => (
                <span key={row.id + i}
                  className={row.id === "tgt" ? "prd-wb__reps-val" : "prd-wb__reps-rest"}
                >{v}</span>
              ))}
            </React.Fragment>
          ))}
        </div>
        <p className="quote" style={{ fontSize: 13, marginTop: 10, marginBottom: 0 }}>
          "Even across all six. The last two should feel hard — not desperate."
        </p>
      </div>
    )}

    {/* Fueling — only when present on template */}
    {w.fueling && (
      <div style={{ paddingTop: 22 }}>
        <Eyebrow>FUELING  ·  GAME PLAN</Eyebrow>
        <div style={{ marginTop: 4 }}>
          {w.fueling.map((f, i) => (
            <div key={i} className="prd-wb__fuel">
              <span className="prd-wb__fuel-when">{f.when}</span>
              <span className="prd-wb__fuel-what">{f.what}</span>
            </div>
          ))}
        </div>
      </div>
    )}

    {/* Coach note */}
    <div style={{ paddingTop: 22 }}>
      <Eyebrow coral>FROM YOUR COACH</Eyebrow>
      <div style={{ marginTop: 8 }}>
        <CoachQuote>{w.coach}</CoachQuote>
      </div>
    </div>

    {/* Action strip */}
    <div style={{ paddingTop: 24, display: "flex", flexDirection: "column", gap: 12 }}>
      <button className="btn btn--primary" onClick={onMarkComplete}>Start workout ↗</button>
      <button className="btn btn--secondary" onClick={onMarkComplete}>Mark complete</button>
      <div style={{ display: "flex", justifyContent: "space-around", gap: 12, paddingTop: 4 }}>
        <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Reschedule</span>
        <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Swap workout</span>
        <span className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Skip day</span>
      </div>
    </div>
  </Sheet>
  );
};

// ---- WorkoutPickerSheet ------------------------------------------------
const PICKER_WORKOUTS = [
  { id: "p1", date: "MAY 7  ·  FRIDAY",  dist: "5.01 mi", time: "35:59", pace: "7:11", src: "STRAVA" },
  { id: "p2", date: "MAY 5  ·  TUESDAY", dist: "11.0 mi", time: "1:09:18", pace: "6:18", src: "GARMIN" },
  { id: "p3", date: "MAY 3  ·  SUNDAY",  dist: "18.0 mi", time: "2:15:36", pace: "7:32", src: "APPLE WATCH" },
  { id: "p4", date: "MAY 2  ·  SATURDAY", dist: "4.0 mi",  time: "32:56", pace: "8:14", src: "APPLE WATCH" },
  { id: "p5", date: "APR 30 ·  THURSDAY", dist: "8.6 mi",  time: "57:35", pace: "6:42", src: "GARMIN" },
];

const WorkoutPickerSheet = ({ onClose, onPick }) => {
  const [search, setSearch] = React.useState("");
  const [tab, setTab] = React.useState("recent");
  const visible = PICKER_WORKOUTS.filter(w =>
    !search || (w.date + w.dist + w.src).toLowerCase().includes(search.toLowerCase())
  );

  return (
    <Sheet surface="WORKOUT PICKER · LINK RUN" onClose={onClose}>
      <Eyebrow coral>LINK A RUN</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 26, marginTop: 4 }}>Pick a recent workout.</h1>
      <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
        — pulled from Apple Health, Strava, Garmin. Last 30 days. —
      </p>

      <div style={{ display: "flex", gap: 0, marginTop: 16, borderBottom: "1px solid var(--rule)" }}>
        {[
          { id: "recent", l: "RECENT" },
          { id: "manual", l: "QUICK ADD" },
          { id: "none",   l: "REST DAY" },
        ].map(t => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            style={{
              flex: 1, padding: "12px 0",
              background: "transparent", border: 0,
              fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
              letterSpacing: "0.12em",
              color: tab === t.id ? "var(--coral)" : "var(--ink-2)",
              borderBottom: tab === t.id ? "1.5px solid var(--coral)" : "1.5px solid transparent",
              marginBottom: -1, cursor: "pointer",
              textTransform: "uppercase",
            }}
          >
            {t.l}
          </button>
        ))}
      </div>

      {tab === "recent" && (
        <React.Fragment>
          <div style={{ marginTop: 12 }}>
            <input
              className="field"
              placeholder="Search workouts…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <div style={{ marginTop: 4 }}>
            {visible.map(w => (
              <div key={w.id} className="prd-pick-row" onClick={() => onPick && onPick(w)}>
                <div>
                  <div className="prd-pick-row__date">{w.date}</div>
                  <div className="prd-pick-row__name">{w.dist}</div>
                  <div className="prd-pick-row__meta">{w.time}  ·  {w.pace} / mi  ·  {w.src}</div>
                </div>
                <span className="prd-pick-row__add">LINK ↗</span>
              </div>
            ))}
            {visible.length === 0 && (
              <div style={{ padding: "32px 0", fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 14, color: "var(--ink-3)", textAlign: "center" }}>
                No matches.
              </div>
            )}
          </div>
        </React.Fragment>
      )}

      {tab === "manual" && (
        <div style={{ paddingTop: 12 }}>
          <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-3)" }}>
            — type a distance and we'll save a bare workout you can fill in later. —
          </p>
          <div className="prd-fieldrow">
            <span className="prd-fieldrow__label">DISTANCE · MI</span>
            <input className="prd-fieldrow__big" defaultValue="0.0" />
          </div>
          <div className="prd-fieldrow">
            <span className="prd-fieldrow__label">WORKOUT TYPE</span>
            <div className="prd-chip-cluster" style={{ paddingTop: 4 }}>
              {["EASY", "TEMPO", "INTERVALS", "LONG RUN", "RECOVERY", "RACE"].map((t, i) => (
                <span key={t} className={"prd-chip" + (i === 0 ? " is-active" : "")}>{t}</span>
              ))}
            </div>
          </div>
          <button className="btn btn--primary" style={{ marginTop: 16 }}>Add workout</button>
        </div>
      )}

      {tab === "none" && (
        <div style={{ paddingTop: 28, textAlign: "center" }}>
          <h2 className="h-display" style={{ fontSize: 22 }}>Mark as a rest day.</h2>
          <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-3)", marginTop: 6 }}>
            — no workout linked. The memo stays in your journal. —
          </p>
          <button className="btn btn--primary" style={{ marginTop: 18 }}>Mark rest day</button>
        </div>
      )}
    </Sheet>
  );
};

// ---- ManualWorkoutSheet ------------------------------------------------
const ManualWorkoutSheet = ({ onClose }) => {
  const [distance, setDistance] = React.useState("");
  const [hh, setHh] = React.useState("");
  const [mm, setMm] = React.useState("");
  const [ss, setSs] = React.useState("");
  const [date, setDate] = React.useState("MAY 8");
  const [mood, setMood] = React.useState(null);
  const [notes, setNotes] = React.useState("");

  const distNum = parseFloat(distance) || 0;
  const durMin = (parseInt(hh) || 0) * 60 + (parseInt(mm) || 0) + (parseInt(ss) || 0) / 60;
  const paceSecs = distNum > 0 && durMin > 0 ? Math.round((durMin / distNum) * 60) : null;
  const paceStr = paceSecs ? `${Math.floor(paceSecs / 60)}:${String(paceSecs % 60).padStart(2, "0")}` : "—";

  const moods = ["energized", "positive", "neutral", "tired", "struggling"];

  return (
    <Sheet
      surface="MANUAL WORKOUT · ENTRY"
      onClose={onClose}
      action={distNum > 0 ? onClose : null}
      actionLabel="Save ↗"
    >
      <Eyebrow coral>MANUAL ENTRY</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 26, marginTop: 4 }}>Log a workout by hand.</h1>
      <p style={{ fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>
        — for runs the watch missed, or the ones you logged on paper. —
      </p>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">DISTANCE  ·  MI</span>
        <input
          className="prd-fieldrow__big"
          placeholder="0.0"
          inputMode="decimal"
          value={distance}
          onChange={(e) => setDistance(e.target.value)}
        />
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">DURATION</span>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 8px 1fr 8px 1fr", gap: 8, alignItems: "baseline" }}>
          <input className="prd-fieldrow__big" placeholder="0" value={hh} onChange={(e) => setHh(e.target.value)} style={{ textAlign: "center" }} />
          <span style={{ textAlign: "center", color: "var(--ink-3)" }}>:</span>
          <input className="prd-fieldrow__big" placeholder="00" value={mm} onChange={(e) => setMm(e.target.value)} style={{ textAlign: "center" }} />
          <span style={{ textAlign: "center", color: "var(--ink-3)" }}>:</span>
          <input className="prd-fieldrow__big" placeholder="00" value={ss} onChange={(e) => setSs(e.target.value)} style={{ textAlign: "center" }} />
        </div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em", marginTop: 6 }}>
          PACE  ·  {paceStr} / MI
        </div>
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">DATE</span>
        <div style={{ display: "flex", gap: 8, paddingTop: 4 }}>
          {["MAY 8", "MAY 7", "MAY 6", "MAY 5", "EARLIER"].map(d => (
            <span
              key={d}
              className={"prd-chip" + (date === d ? " is-active" : "")}
              onClick={() => setDate(d)}
            >
              {d}
            </span>
          ))}
        </div>
      </div>

      <div className="prd-fieldrow">
        <span className="prd-fieldrow__label">MOOD</span>
        <MoodRadio value={mood} onChange={setMood} />
      </div>

      <div className="prd-fieldrow" style={{ borderBottom: 0 }}>
        <span className="prd-fieldrow__label">NOTES  ·  OPTIONAL</span>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder="How did it feel?"
          style={{
            width: "100%", minHeight: 84,
            background: "transparent", border: 0, outline: "none", resize: "none",
            fontFamily: "var(--font-body)", fontStyle: notes ? "normal" : "italic",
            fontSize: 15, color: "var(--ink)", padding: 0,
          }}
        />
      </div>

      <button
        className="btn btn--primary"
        style={{ marginTop: 18, opacity: distNum > 0 ? 1 : 0.5 }}
        onClick={onClose}
      >
        Save workout
      </button>
    </Sheet>
  );
};

// ---- HistoryDetailSheet ------------------------------------------------
const MOCK_HISTORY_ENTRY = {
  day: "TUESDAY", date: "May 5",
  type: "TEMPO", dist: "11.0 mi", time: "1:09:18", pace: "6:18 / mi",
  mood: "positive",
  cleaned: "Second MP block. Hit splits within two seconds either way through five miles, then wind picked up on the back stretch and pace drifted to 6:24. Calf was quiet — the rolling has been doing its job. Confidence is building.",
  raw: "MP block today. Felt smooth through 5 then wind. Splits within 2s. Calf good. Confident.",
  audio: "VOICE  ·  2:34",
  coach: "Hit your splits with margin. The drift on the back half was wind, not fatigue — your HR stayed in band. Build on this Wednesday.",
};

const HistoryDetailSheet = ({ entry = MOCK_HISTORY_ENTRY, onClose, onDelete }) => {
  const moodCfg = MOOD_COLORS[(entry.mood || "neutral").toLowerCase()] || {};
  return (
    <Sheet surface="JOURNAL · ENTRY DETAIL" onClose={onClose}>
      <Eyebrow coral>{entry.day}  ·  {entry.date.toUpperCase()}</Eyebrow>
      <h1 className="h-display" style={{ fontSize: 30, marginTop: 4 }}>{entry.type.toLowerCase().replace(/^./, c => c.toUpperCase())}, {entry.dist}.</h1>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)", letterSpacing: "0.10em", marginTop: 6 }}>
        {entry.time}  ·  {entry.pace.toUpperCase()}  ·  {entry.audio}
      </div>

      <div style={{ marginTop: 14 }}>
        <span className="mood-pill" style={{ color: moodCfg.c, background: moodCfg.bg }}>
          {entry.mood.toUpperCase()}
        </span>
      </div>

      {/* AI cleaned summary */}
      <div style={{ marginTop: 22 }}>
        <Eyebrow coral>SUMMARY  ·  AI CLEANED</Eyebrow>
        <p className="quote" style={{ marginTop: 8, fontSize: 14 }}>"{entry.cleaned}"</p>
      </div>

      {/* Coach insight */}
      <div style={{ marginTop: 22 }}>
        <Eyebrow coral>FROM YOUR COACH</Eyebrow>
        <div style={{ marginTop: 8 }}>
          <CoachQuote>{entry.coach}</CoachQuote>
        </div>
      </div>

      {/* Original transcript */}
      <div style={{ marginTop: 22 }}>
        <Eyebrow>ORIGINAL  ·  RAW TRANSCRIPT</Eyebrow>
        <p style={{
          fontFamily: "var(--font-body)", fontSize: 13,
          color: "var(--ink-2)", lineHeight: 1.5, marginTop: 6,
        }}>
          {entry.raw}
        </p>
      </div>

      {/* Action row */}
      <div style={{ marginTop: 24, display: "flex", justifyContent: "space-between", paddingTop: 14, borderTop: "1px solid var(--rule)" }}>
        <span className="link" style={{ fontSize: 12 }}>Edit ↗</span>
        <span className="link" style={{ fontSize: 12 }}>Replay audio ↗</span>
        <span className="link" style={{ fontSize: 12, color: "var(--mood-injured, #B83A4A)", borderColor: "var(--mood-injured, #B83A4A)" }} onClick={onDelete}>Delete</span>
      </div>
    </Sheet>
  );
};

window.Sheet = Sheet;
window.DayDetailSheet = DayDetailSheet;
window.WorkoutPickerSheet = WorkoutPickerSheet;
window.ManualWorkoutSheet = ManualWorkoutSheet;
window.HistoryDetailSheet = HistoryDetailSheet;

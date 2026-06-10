// Post Run Drip · Logo redesign — 9 directions on a canvas

// =====================================================================
// Logo marks — each takes a `color` (foreground) and optional `bg` for context.
// All marks are square 240×240 viewBox so they swap into any size.
// =====================================================================

// The signature drop shape — used across most directions.
// `x,y` is the top of the neck. `h` = full drop height. `w` = bulb width.
const DripDrop = ({ x = 0, y = 0, h = 60, w = 24, color = "currentColor", neck = 3 }) => {
  const bulbR = w / 2;
  const neckBottom = y + h - w + 2;
  // Path: thin neck widening into a bulb; the bulb is a near-circle
  // with a tiny pinch at the top.
  const d = `
    M ${x - neck/2} ${y}
    L ${x - neck/2} ${neckBottom - 6}
    C ${x - bulbR} ${neckBottom - 2}, ${x - bulbR} ${y + h}, ${x} ${y + h}
    C ${x + bulbR} ${y + h}, ${x + bulbR} ${neckBottom - 2}, ${x + neck/2} ${neckBottom - 6}
    L ${x + neck/2} ${y}
    Z
  `;
  return <path d={d} fill={color} />;
};

// ─── A · Reference / current ──────────────────────────────────────────
const LogoA_Current = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#1A1815" />
    <g fill="#fff" style={{ fontFamily: "'Archivo Black', system-ui, sans-serif" }}>
      <text x="120" y="86"  textAnchor="middle" fontSize="46" letterSpacing="-0.5">post</text>
      <text x="120" y="132" textAnchor="middle" fontSize="46" letterSpacing="-0.5">run</text>
      <text x="120" y="178" textAnchor="middle" fontSize="46" letterSpacing="-0.5">drip</text>
      <g transform="translate(140, 168)">
        <DripDrop x={0} y={0} h={42} w={14} color="#fff" neck={2.4} />
      </g>
    </g>
  </svg>
);

// ─── B · Drip · refined stack on coral ─────────────────────────────────
const LogoB_StackCoral = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#D4592A" />
    <g fill="#1A1815" style={{ fontFamily: "'Archivo Black', system-ui, sans-serif" }}>
      <text x="120" y="86"  textAnchor="middle" fontSize="48" letterSpacing="-1">post</text>
      <text x="120" y="132" textAnchor="middle" fontSize="48" letterSpacing="-1">run</text>
      <text x="120" y="178" textAnchor="middle" fontSize="48" letterSpacing="-1">drip</text>
      <g transform="translate(140, 170)">
        <DripDrop x={0} y={0} h={48} w={16} color="#1A1815" neck={2.8} />
      </g>
    </g>
  </svg>
);

// ─── C · "drip." — the word, drip-as-period ───────────────────────────
const LogoC_Period = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#1A1815" />
    <g fill="#fff" style={{ fontFamily: "'Archivo Black', system-ui, sans-serif" }}>
      <text x="120" y="148" textAnchor="middle" fontSize="78" letterSpacing="-2.5">drip</text>
      <g transform="translate(184, 132)">
        <DripDrop x={0} y={0} h={60} w={22} color="#D4592A" neck={4} />
      </g>
    </g>
  </svg>
);

// ─── D · Lowercase monogram "prd" w/ drip on the p ─────────────────────
const LogoD_Monogram = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#1A1815" />
    <g fill="#fff" style={{ fontFamily: "'Archivo Black', system-ui, sans-serif" }}>
      <text x="120" y="148" textAnchor="middle" fontSize="106" letterSpacing="-4">prd</text>
      {/* drip hangs from the bowl of the "p" — leftmost char */}
      <g transform="translate(72, 152)">
        <DripDrop x={0} y={0} h={70} w={26} color="#fff" neck={5} />
      </g>
    </g>
  </svg>
);

// ─── E · Just the drop, confident ──────────────────────────────────────
const LogoE_DropOnly = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#D4592A" />
    <g transform="translate(120, 60)">
      <DripDrop x={0} y={0} h={120} w={70} color="#1A1815" neck={14} />
    </g>
  </svg>
);

// ─── F · Editorial serif "prd." — Crimson Pro, drip as period dot ─────
const LogoF_Serif = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#F5F3F0" />
    <g fill="#1A1815" style={{ fontFamily: "'Crimson Pro', Georgia, serif", fontWeight: 700 }}>
      <text x="120" y="148" textAnchor="middle" fontSize="92" letterSpacing="-1">prd</text>
      {/* The drip replaces the period after "prd" */}
      <g transform="translate(193, 130)">
        <DripDrop x={0} y={0} h={32} w={14} color="#D4592A" neck={2.6} />
      </g>
    </g>
  </svg>
);

// ─── G · Negative-space drop on coral square (icon-first) ─────────────
const LogoG_NegSpace = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <defs>
      <mask id="cut-drop">
        <rect width="240" height="240" fill="#fff" />
        <g transform="translate(120, 60)">
          <DripDrop x={0} y={0} h={120} w={70} color="#000" neck={14} />
        </g>
      </mask>
    </defs>
    <rect width="240" height="240" fill="#D4592A" mask="url(#cut-drop)" />
  </svg>
);

// ─── H · "post.run.drip." horizontal — periods are drips ──────────────
const LogoH_Horizontal = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#F5F3F0" />
    <g fill="#1A1815" style={{ fontFamily: "'Archivo Black', system-ui, sans-serif" }}>
      <text x="36" y="132" fontSize="28" letterSpacing="-0.5">post</text>
      <g transform="translate(91, 134)"><DripDrop x={0} y={0} h={12} w={5} color="#D4592A" neck={1.2} /></g>
      <text x="100" y="132" fontSize="28" letterSpacing="-0.5">run</text>
      <g transform="translate(142, 134)"><DripDrop x={0} y={0} h={12} w={5} color="#D4592A" neck={1.2} /></g>
      <text x="151" y="132" fontSize="28" letterSpacing="-0.5">drip</text>
      <g transform="translate(207, 134)"><DripDrop x={0} y={0} h={12} w={5} color="#D4592A" neck={1.2} /></g>
    </g>
  </svg>
);

// ─── I · Drop with running figure inside (negative space) ─────────────
const LogoI_DropRunner = ({ size = 240 }) => (
  <svg viewBox="0 0 240 240" width={size} height={size}>
    <rect width="240" height="240" fill="#1A1815" />
    <defs>
      <mask id="runner-cut">
        <g transform="translate(120, 60)">
          <DripDrop x={0} y={0} h={120} w={70} color="#fff" neck={14} />
        </g>
        {/* simple runner silhouette - cut out from drop */}
        <g fill="#000" transform="translate(120, 130)">
          {/* head */}
          <circle cx="6" cy="-22" r="6" />
          {/* torso - leaning forward */}
          <path d="M 4 -16 L 12 4 L 2 6 Z" />
          {/* front leg striding */}
          <path d="M 10 4 L 22 22 L 18 28 L 6 8 Z" />
          {/* back leg kicked up */}
          <path d="M 4 4 L -12 18 L -8 24 L 8 6 Z" />
          {/* arms */}
          <path d="M 8 -10 L 18 -2 L 16 4 L 6 -6 Z" />
          <path d="M 4 -10 L -8 -4 L -6 2 L 6 -8 Z" />
        </g>
      </mask>
    </defs>
    <rect width="240" height="240" fill="#D4592A" mask="url(#runner-cut)" />
  </svg>
);

window.LogoA_Current = LogoA_Current;
window.LogoB_StackCoral = LogoB_StackCoral;
window.LogoC_Period = LogoC_Period;
window.LogoD_Monogram = LogoD_Monogram;
window.LogoE_DropOnly = LogoE_DropOnly;
window.LogoF_Serif = LogoF_Serif;
window.LogoG_NegSpace = LogoG_NegSpace;
window.LogoH_Horizontal = LogoH_Horizontal;
window.LogoI_DropRunner = LogoI_DropRunner;

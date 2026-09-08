/* global React, window */
/* ════════════════════════════════════════════════════════════════════
   COACH · iOS · shared pieces used across all three directions
   ════════════════════════════════════════════════════════════════════ */

/* ── EvidenceChip ──────────────────────────────────────────────────
   Inline reference to a workout. Coral wash, ◆ mark, mono.
   ───────────────────────────────────────────────────────────────── */
const EvidenceChip = ({ w, inline }) => {
  if (!w) return null;
  if (inline) {
    return (
      <span style={{
        display: "inline-flex", alignItems: "baseline", gap: 4,
        padding: "0 6px",
        borderRadius: 4,
        background: "var(--coral-wash)",
        whiteSpace: "nowrap",
        fontFamily: "var(--font-mono)",
        fontSize: 11, color: "var(--coral)", letterSpacing: "0.06em",
        verticalAlign: "baseline",
        cursor: "pointer",
      }}>
        ◆ {w.type} {w.day.split(" · ")[0]}
      </span>
    );
  }
  return (
    <div style={{
      display: "flex", justifyContent: "space-between", alignItems: "baseline",
      padding: "8px 10px",
      border: "1px solid var(--rule)",
      borderRadius: 6, background: "var(--paper-elevated)",
      cursor: "pointer",
    }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
          letterSpacing: "0.14em", color: "var(--coral)",
        }}>{w.day} · {w.type}</span>
        <span style={{
          fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 14,
          color: "var(--ink)",
        }}>{w.title}</span>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-2)",
          letterSpacing: "0.06em",
        }}>{w.meta}</span>
      </div>
      <span style={{
        fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-3)",
      }}>↗</span>
    </div>
  );
};

/* ── DocChip ───────────────────────────────────────────────────────
   Inline reference to a RAG knowledge-base doc. Ink underline, §
   mark, mono — visually distinct from workout chips (coral wash, ◆)
   so the reader can tell at a glance whether the coach is citing
   YOUR data or the LIBRARY.
   ───────────────────────────────────────────────────────────────── */
const DocChip = ({ d, inline }) => {
  if (!d) return null;
  if (inline) {
    return (
      <span style={{
        display: "inline-flex", alignItems: "baseline", gap: 4,
        padding: "0 6px",
        borderRadius: 4,
        background: "transparent",
        border: "1px solid var(--rule)",
        whiteSpace: "nowrap",
        fontFamily: "var(--font-mono)",
        fontSize: 11, color: "var(--ink)", letterSpacing: "0.04em",
        verticalAlign: "baseline",
        cursor: "pointer",
      }}>
        § {d.title}
      </span>
    );
  }
  return (
    <div style={{
      display: "flex", flexDirection: "column", gap: 4,
      padding: "8px 10px",
      border: "1px solid var(--rule)",
      borderRadius: 6, background: "var(--paper)",
      cursor: "pointer",
    }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, fontWeight: 600,
          letterSpacing: "0.14em", color: "var(--ink-2)",
        }}>§ {d.category} · KNOWLEDGE</span>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-3)",
        }}>↗</span>
      </div>
      <span style={{
        fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 14,
        color: "var(--ink)",
      }}>{d.title}</span>
      <span style={{
        fontFamily: "var(--font-body)", fontStyle: "italic", fontSize: 12,
        color: "var(--ink-2)", lineHeight: 1.4,
      }}>{d.excerpt}</span>
    </div>
  );
};

/* ── ProseSegment ──────────────────────────────────────────────────
   Render an array of mixed strings + workout/doc references as a
   single paragraph with inline chips kerned into the prose.
   ───────────────────────────────────────────────────────────────── */
const ProseSegment = ({ segments, workouts, docs }) => (
  <>
    {segments.map((seg, i) => {
      if (typeof seg === "string") return <span key={i}>{seg}</span>;
      if (seg.workout || seg.chip) {
        return <EvidenceChip key={i} w={workouts[seg.workout || seg.chip]} inline />;
      }
      if (seg.doc) {
        return <DocChip key={i} d={docs[seg.doc]} inline />;
      }
      return null;
    })}
  </>
);

/* ── CoachByline ──────────────────────────────────────────────────
   Eyebrow + a small "coach" presence cue (initial in a coral mark).
   No avatar photo, no "AI" word anywhere.
   ───────────────────────────────────────────────────────────────── */
const CoachByline = ({ eyebrow }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
    <div style={{
      width: 28, height: 28, borderRadius: 999,
      background: "var(--ink)", color: "var(--paper)",
      display: "grid", placeItems: "center",
      fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 13,
      letterSpacing: 0,
      border: "1.5px solid var(--coral)",
      boxSizing: "border-box",
    }}>C</div>
    <span style={{
      fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 500,
      letterSpacing: "0.14em", color: "var(--coral)", textTransform: "uppercase",
    }}>{eyebrow}</span>
  </div>
);

/* ── ConfidenceBar ─────────────────────────────────────────────────
   Small "how much we trust this read" indicator. Honesty marker.
   ───────────────────────────────────────────────────────────────── */
const ConfidenceBar = ({ label, level, sub }) => {
  const filled = level === "HIGH" ? 3 : level === "MED" ? 2 : 1;
  return (
    <div style={{
      display: "grid", gridTemplateColumns: "1fr auto",
      gap: 6, alignItems: "baseline",
    }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 9, color: "var(--ink-2)",
          letterSpacing: "0.14em",
        }}>{label}</span>
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-3)",
          letterSpacing: "0.06em",
        }}>{sub}</span>
      </div>
      <div style={{ display: "flex", gap: 3, alignItems: "center" }}>
        {[1, 2, 3].map(i => (
          <span key={i} style={{
            display: "inline-block", width: 14, height: 4,
            background: i <= filled ? "var(--coral)" : "var(--rule)",
            borderRadius: 1,
          }} />
        ))}
        <span style={{
          fontFamily: "var(--font-mono)", fontSize: 10, fontWeight: 600,
          color: "var(--coral)", letterSpacing: "0.14em", marginLeft: 4,
        }}>{level}</span>
      </div>
    </div>
  );
};

/* ── AskBar ────────────────────────────────────────────────────────
   Bottom input. Shared across directions.
   ───────────────────────────────────────────────────────────────── */
const AskBar = ({ placeholder = "Write to your coach…", chips }) => {
  const [val, setVal] = React.useState("");
  return (
    <div style={{
      borderTop: "1px solid var(--rule)",
      background: "var(--paper)",
      padding: "10px 20px 14px 20px",
      display: "flex", flexDirection: "column", gap: 8,
    }}>
      {chips && chips.length > 0 && (
        <div style={{
          display: "flex", gap: 6, overflowX: "auto",
          paddingBottom: 2,
        }}>
          {chips.map((c, i) => (
            <span key={i}
              onClick={() => setVal(typeof c === "string" ? c : c.text)}
              style={{
                fontFamily: "var(--font-display)", fontSize: 12, fontWeight: 500,
                color: "var(--ink)",
                border: "1px solid var(--rule)",
                background: "var(--card)",
                borderRadius: 999,
                padding: "5px 10px",
                whiteSpace: "nowrap",
                cursor: "pointer",
              }}>
              {typeof c === "string" ? c : c.text}
            </span>
          ))}
        </div>
      )}
      <div style={{
        display: "grid", gridTemplateColumns: "1fr 32px", gap: 8,
        alignItems: "center",
      }}>
        <input
          value={val}
          onChange={(e) => setVal(e.target.value)}
          placeholder={placeholder}
          style={{
            background: "var(--card)",
            borderRadius: 999,
            padding: "9px 14px",
            fontFamily: "var(--font-body)", fontSize: 13,
            color: "var(--ink)", border: "1px solid var(--rule)",
            outline: "none", width: "100%", boxSizing: "border-box",
          }}
        />
        <div style={{
          width: 32, height: 32, borderRadius: 999,
          background: val.trim() ? "var(--coral)" : "var(--ink-3)",
          display: "grid", placeItems: "center", cursor: "pointer",
          transition: "background .15s",
        }}>
          <svg viewBox="0 0 16 16" style={{ width: 14, height: 14 }}>
            <path d="M2 8L13 2.5L9.5 8L13 13.5L2 8Z" fill="#fff" />
          </svg>
        </div>
      </div>
    </div>
  );
};

window.EvidenceChip = EvidenceChip;
window.DocChip = DocChip;
window.ProseSegment = ProseSegment;
window.CoachByline = CoachByline;
window.ConfidenceBar = ConfidenceBar;
window.AskBar = AskBar;

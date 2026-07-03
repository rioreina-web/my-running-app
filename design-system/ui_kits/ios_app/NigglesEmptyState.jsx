// Post Run Drip · iOS UI kit · niggles empty state
// Empty-state pattern: state the absence, then say what will fill it.
// Italic, secondary color, no illustration, no CTA. Layout only — no data.
// Uses Eyebrow + Section from Primitives.jsx (exposed on window).

const NigglesEmptyState = ({ bodyPart }) => (
  <Section eyebrow={bodyPart.toUpperCase()}>
    <p
      style={{
        fontStyle: "italic",
        color: "var(--ink-2)",
        margin: 0,
      }}
    >
      No mentions of {bodyPart} yet. When one comes up in a voice log, it lands here.
    </p>
  </Section>
);

// Expose to window so other Babel scripts can use it
Object.assign(window, { NigglesEmptyState });

import { Fragment, type ReactNode } from "react";

/**
 * Rich — renders a plain string with `**emphasis**` spans as <strong>.
 *
 * The dashboard's observation / trend / caption copy carries the editorial
 * habit of bolding the one number that matters ("**16s/mi faster**"). Storing
 * that as `**…**` in the data keeps fixtures (and, later, AI output) readable
 * while avoiding dangerouslySetInnerHTML — we split on the markers and render
 * text nodes only.
 */
export function Rich({
  text,
  strongClassName = "font-bold text-text-primary",
}: {
  text: string;
  strongClassName?: string;
}): ReactNode {
  // Capture group → odd indices are the emphasized segments.
  const parts = text.split(/\*\*(.+?)\*\*/g);
  return (
    <>
      {parts.map((part, i) =>
        i % 2 === 1 ? (
          <strong key={i} className={strongClassName}>
            {part}
          </strong>
        ) : (
          <Fragment key={i}>{part}</Fragment>
        ),
      )}
    </>
  );
}

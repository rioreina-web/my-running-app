import * as React from "react";

export type Mood = "energized" | "positive" | "neutral" | "tired" | "struggling" | "injured";

export interface MoodPillProps {
  mood?: Mood;
  style?: React.CSSProperties;
}

/** How the run felt. Tracked uppercase, 12% wash, pill radius — no faces, no emoji. */
export declare function MoodPill(props: MoodPillProps): React.ReactElement;

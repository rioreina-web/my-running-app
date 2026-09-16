import * as React from "react";

export interface EyebrowProps {
  /** Label text. Rendered uppercase via CSS. */
  children?: React.ReactNode;
  /** Coral treatment — reserved for the one active section per screen. */
  coral?: boolean;
  style?: React.CSSProperties;
}

/** Tracked monospace section label — TUESDAY, FROM YOUR COACH, ZONE SHIFTS. */
export declare function Eyebrow(props: EyebrowProps): React.ReactElement;

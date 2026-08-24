import * as React from "react";

export interface PlateStripProps {
  /** Surface name, right of the em-dash. */
  surface?: string;
  /** Figure number, e.g. "Fig. 23". */
  fig?: string;
  /** Second right-hand line — usually a date or release tag. */
  right?: string;
  style?: React.CSSProperties;
}

/** Plate header strip — the single most identifiable gesture in the system. */
export declare function PlateStrip(props: PlateStripProps): React.ReactElement;

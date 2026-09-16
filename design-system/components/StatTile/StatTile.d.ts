import * as React from "react";

export interface StatTileProps {
  /** Tracked uppercase label, e.g. "Avg pace". Set in the label face. */
  label?: React.ReactNode;
  /** The numeral. Inter, tabular, so columns stay rectangular. */
  value?: React.ReactNode;
  /** Small trailing unit, e.g. "/mi", "bpm". */
  unit?: React.ReactNode;
  /** Optional change line beneath the value. */
  delta?: React.ReactNode;
  deltaTone?: "pos" | "neg";
  /** Red numeral — one per visual cluster, maximum. */
  accent?: boolean;
  /** @deprecated use accent. */
  coral?: boolean;
  /** Right-align for the last tile in a ruled row. */
  align?: "start" | "end";
  style?: React.CSSProperties;
}

/** The system's stat primitive: tracked label, tabular numeral, optional delta. */
export declare function StatTile(props: StatTileProps): React.ReactElement;

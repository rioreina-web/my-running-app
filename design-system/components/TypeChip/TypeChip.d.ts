import * as React from "react";

export interface TypeChipProps {
  /** The session name, e.g. "Intervals", "Easy", "Long run". */
  children?: React.ReactNode;
  /** Solid blue: this was the keyed session of the week. */
  keyed?: boolean;
  style?: React.CSSProperties;
}

/** Session-type chip. Blue fill for keyed work, hairline outline for everything else. */
export declare function TypeChip(props: TypeChipProps): React.ReactElement;

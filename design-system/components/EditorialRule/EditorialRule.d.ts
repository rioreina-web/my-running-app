import * as React from "react";

export interface EditorialRuleProps {
  style?: React.CSSProperties;
}

/** The canonical section break: thin rule, 3px dot, thin rule. Never a plain <hr>. */
export declare function EditorialRule(props: EditorialRuleProps): React.ReactElement;

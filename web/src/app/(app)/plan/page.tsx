import { redirect } from "next/navigation";

// Plan folded into Train (2026-05-28 IA decision: the plan is a subset of
// Train, not its own surface). Redirect kept for old links.
export default function PlanPage() {
  redirect("/train");
}

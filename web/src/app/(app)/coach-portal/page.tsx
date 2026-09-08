import { redirect } from "next/navigation";

// The desk, not the filing cabinet. This used to land on /plans.
export default function CoachPortalPage() {
  redirect("/coach-portal/athletes");
}

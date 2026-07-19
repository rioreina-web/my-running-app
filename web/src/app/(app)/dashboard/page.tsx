import { redirect } from "next/navigation";

// Dashboard became Trends (Log · Trends · Train IA — mirrors the iOS
// 4-tab flow). Kept as a redirect so old links and the login flow land
// somewhere real.
export default function DashboardPage() {
  redirect("/trends");
}

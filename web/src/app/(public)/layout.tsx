import { SiteHeader } from "@/components/site/site-header";
import { SiteFooter } from "@/components/site/site-footer";

/* Public route group layout — owns the site chrome for every public route
 * (landing, how-it-works, principles, beta, blog). Individual pages render
 * their own plate strip; none of them render a header or footer.
 */
export default function PublicLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen flex-col bg-bg-base text-text-primary">
      <SiteHeader />
      <main className="flex-1">{children}</main>
      <SiteFooter />
    </div>
  );
}

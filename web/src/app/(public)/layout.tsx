/* Public route group layout — passthrough.
 * Each route in (public)/ now owns its own chrome:
 *   - / (LandingPage)         — uses the v4 ported page (header + footer inline)
 *   - /blog, /blog/[slug]     — use (public)/blog/layout.tsx
 */
export default function PublicLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}

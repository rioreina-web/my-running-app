/* Blog chrome now comes from (public)/layout.tsx — header and footer are
 * shared across the whole public site so the blog reads as the same
 * publication as the landing page.
 */
export default function BlogLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}

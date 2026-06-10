/* /design/* route group — design system preview surface.
 *
 * These pages render the .jsx designs from
 * /Users/rioreina/Downloads/Post Run Drip Design System with mock data,
 * so the team can see the editorial direction live in the codebase
 * without disrupting real routes.
 *
 * Each preview owns its own layout chrome — sidebar, top nav, etc.
 * This wrapper is a passthrough so designs render exactly as authored.
 */
export default function DesignLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}

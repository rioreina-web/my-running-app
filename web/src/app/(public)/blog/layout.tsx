import Link from "next/link";

/* Blog-only layout — chrome formerly lived in (public)/layout.tsx.
 * Moved here so the homepage (now ported from home.v4.jsx) can render
 * its own header and footer without double-stacking.
 */
export default function BlogLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-divider bg-bg-base">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <Link
            href="/"
            className="font-display text-xl text-text-primary"
          >
            Post Run Drip
          </Link>
          <nav className="flex items-center gap-6">
            <Link
              href="/blog"
              className="font-body text-sm text-text-secondary hover:text-text-primary transition-colors"
            >
              Blog
            </Link>
            <Link
              href="/login"
              className="rounded-lg bg-coral px-4 py-2 font-body text-sm font-medium text-white hover:bg-coral-dark transition-colors"
            >
              Sign In
            </Link>
          </nav>
        </div>
      </header>

      <main className="flex-1">{children}</main>

      <footer className="border-t border-divider bg-bg-base">
        <div className="mx-auto max-w-6xl px-6 py-12">
          <div className="grid gap-8 md:grid-cols-4">
            <div>
              <h3 className="font-display text-lg text-text-primary">
                Post Run Drip
              </h3>
              <p className="mt-2 text-sm text-text-tertiary">
                A running log for runners with a goal time and a base.
              </p>
            </div>
            <div>
              <h4 className="font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                Product
              </h4>
              <ul className="mt-3 space-y-2">
                <li>
                  <Link
                    href="/#what"
                    className="text-sm text-text-tertiary hover:text-text-primary transition-colors"
                  >
                    Features
                  </Link>
                </li>
                <li>
                  <Link
                    href="/blog"
                    className="text-sm text-text-tertiary hover:text-text-primary transition-colors"
                  >
                    Blog
                  </Link>
                </li>
              </ul>
            </div>
            <div>
              <h4 className="font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                Account
              </h4>
              <ul className="mt-3 space-y-2">
                <li>
                  <Link
                    href="/login"
                    className="text-sm text-text-tertiary hover:text-text-primary transition-colors"
                  >
                    Sign In
                  </Link>
                </li>
              </ul>
            </div>
            <div>
              <h4 className="font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
                Download
              </h4>
              <p className="mt-3 text-sm text-text-tertiary">
                Available on the App Store
              </p>
            </div>
          </div>
          <div className="mt-12 border-t border-divider pt-6 text-center">
            <p className="font-mono text-xs text-text-tertiary">
              &copy; {new Date().getFullYear()} Post Run Drip. All rights
              reserved.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}

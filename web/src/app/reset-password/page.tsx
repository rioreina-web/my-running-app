"use client";

import { useEffect, useState } from "react";
import { createBrowserClient } from "@supabase/ssr";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { DripButton } from "@/components/ui/drip-button";

// Where a Supabase recovery link lands. Before this page existed the reset
// email was a dead end — the link carried a valid token to a 404, so a
// forgotten password had no self-serve route at all.
//
// The flow: Supabase puts the recovery token in the URL *hash*, the client
// library exchanges it for a session on load and fires PASSWORD_RECOVERY. That
// session can do exactly one useful thing — set a new password — so this page
// waits for the event before showing the form, and says so plainly when the
// link has expired rather than showing a form that cannot work.

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [ready, setReady] = useState(false);
  const [checking, setChecking] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const router = useRouter();

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  useEffect(() => {
    let cancelled = false;

    async function establish() {
      const params = new URLSearchParams(window.location.search);

      // Supabase can hand back an error instead of a token (expired link,
      // already used). Surface its own words rather than a generic failure.
      const errDesc = params.get("error_description");
      if (errDesc) {
        if (!cancelled) {
          setError(errDesc.replace(/\+/g, " "));
          setChecking(false);
        }
        return;
      }

      // PKCE (@supabase/ssr hardcodes flowType: "pkce"): the link returns a
      // ?code= that must be exchanged for a session. Nothing in this app did
      // that before, which is why a valid reset link appeared to do nothing.
      //
      // The exchange needs the code_verifier this browser stored when the
      // reset was REQUESTED. A link generated in the Supabase dashboard has no
      // matching verifier here, so it will fail — say so plainly instead of
      // showing a form that cannot work.
      const code = params.get("code");
      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (cancelled) return;
        if (error) {
          setError(
            `${error.message} — if you requested this from the Supabase dashboard rather than this app, use "Forgot password?" on the login page instead, so the reset starts and finishes in the same browser.`
          );
        } else {
          setReady(true);
        }
        setChecking(false);
        return;
      }

      // Implicit flow (#access_token=…) — the client library consumes the hash
      // itself and fires an event; a session may also already be present.
      const { data } = await supabase.auth.getSession();
      if (cancelled) return;
      if (data.session) setReady(true);
      setChecking(false);
    }

    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY" || event === "SIGNED_IN") {
        setReady(true);
        setChecking(false);
      }
    });

    establish();

    return () => {
      cancelled = true;
      sub.subscription.unsubscribe();
    };
  }, [supabase]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setError("Those two passwords don't match.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { error } = await supabase.auth.updateUser({ password });
      if (error) throw error;
      setDone(true);
      setTimeout(() => {
        router.push("/trends");
        router.refresh();
      }, 1200);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Could not set the password.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-base px-6">
      <div className="w-full max-w-sm">
        <div className="text-center">
          <Link href="/">
            <h1 className="font-display text-3xl text-text-primary">Post Run Drip</h1>
          </Link>
          <p className="mt-2 font-body text-sm text-text-tertiary">
            {done ? "Password updated" : "Choose a new password"}
          </p>
        </div>

        {checking && (
          <p className="mt-8 text-center font-body text-sm text-text-tertiary">
            Checking your link…
          </p>
        )}

        {!checking && !ready && (
          <div className="mt-8 text-center">
            <p className="font-body text-sm text-text-secondary">
              {error ??
                "This reset link is no longer valid. Recovery links expire, and each one can only be used once."}
            </p>
            <Link
              href="/login"
              className="mt-4 inline-block font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary transition-colors hover:text-coral"
            >
              Request a new one
            </Link>
          </div>
        )}

        {!checking && ready && !done && (
          <form onSubmit={handleSubmit} className="mt-8 space-y-4">
            <div>
              <label className="mb-1.5 block font-body text-[11px] font-medium uppercase tracking-[1.5px] text-text-secondary">
                New password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
                autoFocus
                className="w-full rounded-lg border border-divider bg-bg-card px-4 py-3 text-sm text-text-primary placeholder-text-tertiary outline-none transition-colors focus:border-coral/50"
                placeholder="••••••••"
              />
            </div>
            <div>
              <label className="mb-1.5 block font-body text-[11px] font-medium uppercase tracking-[1.5px] text-text-secondary">
                Confirm
              </label>
              <input
                type="password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                required
                minLength={6}
                className="w-full rounded-lg border border-divider bg-bg-card px-4 py-3 text-sm text-text-primary placeholder-text-tertiary outline-none transition-colors focus:border-coral/50"
                placeholder="••••••••"
              />
            </div>

            {error && <p className="text-sm text-mood-injured">{error}</p>}

            <DripButton type="submit" isLoading={loading} className="w-full">
              Set password
            </DripButton>
          </form>
        )}

        {done && (
          <p className="mt-8 text-center font-body text-sm text-mood-positive">
            You&rsquo;re signed in. Taking you to Trends…
          </p>
        )}
      </div>
    </div>
  );
}

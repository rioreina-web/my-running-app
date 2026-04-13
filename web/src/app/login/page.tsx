"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { DripButton } from "@/components/ui/drip-button";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [message, setMessage] = useState<string | null>(null);
  const router = useRouter();

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      if (mode === "signin") {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        });
        if (error) throw error;
        router.push("/dashboard");
        router.refresh();
      } else {
        const { error } = await supabase.auth.signUp({
          email,
          password,
        });
        if (error) throw error;
        setMessage("Check your email for a confirmation link.");
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-base px-6">
      <div className="w-full max-w-sm">
        <div className="text-center">
          <Link href="/">
            <h1 className="font-display text-3xl text-text-primary">
              Post Run Drip
            </h1>
          </Link>
          <p className="mt-2 font-body text-sm text-text-tertiary">
            {mode === "signin"
              ? "Sign in to your account"
              : "Create a new account"}
          </p>
        </div>

        <form onSubmit={handleSubmit} className="mt-8 space-y-4">
          <div>
            <label className="block font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary mb-1.5">
              Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full rounded-lg border border-divider bg-bg-card px-4 py-3 text-sm text-text-primary placeholder-text-tertiary outline-none focus:border-coral/50 transition-colors"
              placeholder="you@example.com"
            />
          </div>
          <div>
            <label className="block font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary mb-1.5">
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={6}
              className="w-full rounded-lg border border-divider bg-bg-card px-4 py-3 text-sm text-text-primary placeholder-text-tertiary outline-none focus:border-coral/50 transition-colors"
              placeholder="••••••••"
            />
          </div>

          {error && (
            <p className="text-sm text-mood-injured">{error}</p>
          )}
          {message && (
            <p className="text-sm text-mood-positive">{message}</p>
          )}

          <DripButton
            type="submit"
            isLoading={loading}
            className="w-full"
          >
            {mode === "signin" ? "Sign In" : "Sign Up"}
          </DripButton>
        </form>

        <div className="mt-6 text-center">
          <button
            onClick={() =>
              setMode(mode === "signin" ? "signup" : "signin")
            }
            className="font-body text-sm text-text-tertiary hover:text-coral transition-colors"
          >
            {mode === "signin"
              ? "Don't have an account? Sign up"
              : "Already have an account? Sign in"}
          </button>
        </div>
      </div>
    </div>
  );
}

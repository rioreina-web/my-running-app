"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

/* Sign-in · port of SignInScreen.jsx. Email + Apple, plus the
   create-account path into onboarding. Any input signs in. */

export default function SignInPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const ready = email.length > 0 && password.length > 0 && !loading;

  const submit = () => {
    if (!ready) return;
    setLoading(true);
    setTimeout(() => router.push("/mockup/log"), 600);
  };

  return (
    <div className="m-signin">
      <div className="m-signin__logo">
        {/* Plain img: next/image injects an inline style the site's nonce CSP blocks. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="Post Run Drip" width={88} height={136} />
      </div>

      <div className="m-col m-items-center m-gap-8">
        <h1 className="m-display m-display--m">Welcome back.</h1>
        <p className="m-quote m-quote--sub m-center">A quieter log for serious runners.</p>
      </div>

      <form
        className="m-signin__form"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <input
          className="m-field"
          placeholder="Email"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <input
          className="m-field"
          placeholder="Password"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        <button type="submit" className="m-btn m-btn--primary" disabled={!ready}>
          {loading ? "Signing in…" : "Sign in"}
        </button>
        <Link href="/mockup/log" className="m-apple">
          <span aria-hidden="true"></span>
          <span>Sign in with Apple</span>
        </Link>
        <div className="m-center m-mt-4">
          <Link href="/mockup/onboarding" className="m-link m-link--quiet m-link--sm">
            Create account
          </Link>
        </div>
      </form>

      <p className="m-caption m-caption--faint m-center">Mockup · any email and password signs in</p>
    </div>
  );
}

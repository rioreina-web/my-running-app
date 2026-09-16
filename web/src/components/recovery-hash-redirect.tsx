"use client";

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";

// Catches an auth callback that landed on the wrong page.
//
// Two things conspire here:
//
// 1. Supabase only honours a `redirect_to` that is on the project's
//    allow-list. When it isn't, the link falls back to the Site URL — so a
//    valid reset link deposits the user on "/" instead of /reset-password.
//
// 2. @supabase/ssr hardcodes `flowType: "pkce"`, so the token arrives as a
//    `?code=` QUERY PARAM, not a URL hash. An earlier version of this file
//    only checked `window.location.hash` and therefore ignored every real
//    recovery callback this app produces — the user landed on the marketing
//    page and nothing happened at all.
//
// So: check both, forward either to the page that can spend it. Implicit-flow
// hashes are still handled because a link generated elsewhere (the Supabase
// dashboard, an older client) can still use them.
export function RecoveryHashRedirect() {
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (pathname === "/reset-password") return;

    const hash = window.location.hash;
    const params = new URLSearchParams(window.location.search);
    const code = params.get("code");
    const errorCode = params.get("error_code") ?? params.get("error");

    // PKCE: ?code=… — forward the whole query so the verifier pairing survives.
    if (code || errorCode) {
      router.replace(`/reset-password${window.location.search}`);
      return;
    }

    // Implicit: #access_token=…&type=recovery
    if (hash && (hash.includes("type=recovery") || hash.includes("error_code="))) {
      router.replace(`/reset-password${hash}`);
    }
  }, [router, pathname]);

  return null;
}

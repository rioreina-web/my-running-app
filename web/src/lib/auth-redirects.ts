// One place that decides where auth emails come back to.
//
// Every Supabase auth email (signup confirmation, password recovery, magic
// link, email change) carries a redirect target. Before this constant existed
// each caller passed its own, and one of them — signup — passed none at all,
// so the link fell back to the project's Site URL where nothing handled it.
//
// They all point at /auth/callback now, which exchanges the code and forwards
// by intent. `next` says where to land afterwards.

/** Absolute URL of the auth callback, for the browser to hand to Supabase.
 *  Must be origin-absolute: Supabase validates it against the project's
 *  redirect allow-list, so the origin has to be listed there too. */
export function authCallbackUrl(next?: string): string {
  const origin = window.location.origin;
  const url = new URL("/auth/callback", origin);
  if (next) url.searchParams.set("next", next);
  return url.toString();
}

/** Where a password-recovery link should end up once the code is spent. */
export const RECOVERY_NEXT = "/reset-password";

/** Where a confirmed signup should land. */
export const SIGNUP_NEXT = "/trends";

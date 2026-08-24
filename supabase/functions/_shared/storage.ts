/**
 * Storage-path helpers for the `training-memos` bucket.
 *
 * The bucket is private (20260823120000_private_training_memos_bucket.sql).
 * Voice memos are the most sensitive data the product holds — injuries,
 * mental state, life context — and while it was public every object was
 * retrievable by URL alone: `/storage/v1/object/public/...` bypasses RLS,
 * so the policies on the bucket never applied to reads at all. Paths are
 * `{user_id}/training_memo_{unix_seconds}.m4a`, which is guessable rather
 * than a capability URL.
 *
 * Server-side readers download with the service-role client, which bypasses
 * bucket privacy, so they keep working unchanged — they just need the object
 * PATH rather than a URL.
 *
 * `training_logs.audio_url` therefore holds one of three shapes:
 *
 *   1. a bare storage path        — what iOS writes now
 *   2. a legacy public URL        — rows written before the bucket was closed
 *   3. a signed URL               — not written by the app, but accepted so a
 *                                   hand-made or future signed value resolves
 *
 * `resolveTrainingMemoPath` normalizes all three. The migration rewrites
 * shape 2 in place, but the parser keeps handling it: rows can be restored
 * from a backup, and a client build older than the migration may still be
 * uploading public URLs for a while.
 */

const BUCKET = "training-memos";
const PUBLIC_PREFIX = `/storage/v1/object/public/${BUCKET}/`;
const SIGNED_PREFIX = `/storage/v1/object/sign/${BUCKET}/`;
/** `authenticated` is what the JS client's download path uses. */
const AUTHENTICATED_PREFIX = `/storage/v1/object/authenticated/${BUCKET}/`;
const PLAIN_PREFIX = `/storage/v1/object/${BUCKET}/`;

const PREFIXES = [
  PUBLIC_PREFIX,
  SIGNED_PREFIX,
  AUTHENTICATED_PREFIX,
  PLAIN_PREFIX,
];

/**
 * Resolve `training_logs.audio_url` to an object path inside `training-memos`.
 *
 * Returns `null` when the value is empty or can't be resolved. Callers must
 * treat null as "don't process this row" rather than guessing — the previous
 * code fell back to `pathname.split("/").pop()`, which silently dropped the
 * `{user_id}/` folder and produced a path that could only ever 404 (or, worse,
 * collide with a different athlete's object of the same name).
 */
export function resolveTrainingMemoPath(
  audioUrl: string | null | undefined,
): string | null {
  if (typeof audioUrl !== "string") return null;

  const raw = audioUrl.trim();
  if (!raw) return null;

  // Reject traversal on the RAW value, before URL parsing. `new URL()`
  // normalizes `a/../b` to `b`, so a crafted URL would otherwise resolve
  // quietly into a different athlete's folder instead of being refused.
  if (hasTraversalSegment(raw)) return null;

  // Shape 1: a bare storage path. Anything that isn't a URL is treated as a
  // path — but reject a leading slash or `..` so a crafted value can't walk
  // outside the bucket.
  if (!/^https?:\/\//i.test(raw)) {
    return sanitizePath(raw);
  }

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return null;
  }

  // Shapes 2 and 3. Match on the longest-first prefix list so
  // `/object/{bucket}/` can't shadow `/object/public/{bucket}/`.
  for (const prefix of PREFIXES) {
    const at = parsed.pathname.indexOf(prefix);
    if (at === -1) continue;

    const encoded = parsed.pathname.slice(at + prefix.length);
    if (!encoded) return null;

    let decoded: string;
    try {
      decoded = decodeURIComponent(encoded);
    } catch {
      // A malformed percent-escape means we can't trust the value.
      return null;
    }
    return sanitizePath(decoded);
  }

  return null;
}

/**
 * True when any `/`-delimited segment is a traversal segment, checked against
 * both the literal text and its percent-decoded form (so `%2e%2e` counts).
 */
function hasTraversalSegment(value: string): boolean {
  const candidates = [value];
  try {
    candidates.push(decodeURIComponent(value));
  } catch {
    // Malformed escapes are rejected downstream; nothing to add here.
  }
  return candidates.some((c) =>
    c.split(/[/\\]/).some((seg) => seg === ".." || seg === ".")
  );
}

/**
 * Reject values that would escape the bucket or address it absolutely.
 * Storage paths are relative and have no `.`/`..` segments.
 */
function sanitizePath(path: string): string | null {
  const trimmed = path.replace(/^\/+/, "").split("?")[0].split("#")[0];
  if (!trimmed) return null;

  const segments = trimmed.split("/");
  if (segments.some((s) => s === "" || s === "." || s === "..")) return null;

  return trimmed;
}

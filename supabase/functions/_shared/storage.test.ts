import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolveTrainingMemoPath } from "./storage.ts";

const UID = "3f1a2b4c-5d6e-7f80-9a1b-2c3d4e5f6071";
const PATH = `${UID}/training_memo_1756000000.0.m4a`;

Deno.test("bare storage path passes through", () => {
  assertEquals(resolveTrainingMemoPath(PATH), PATH);
});

Deno.test("legacy public URL resolves to the full path, keeping the user folder", () => {
  const url =
    `https://abc.supabase.co/storage/v1/object/public/training-memos/${PATH}`;
  assertEquals(resolveTrainingMemoPath(url), PATH);
});

Deno.test("signed URL resolves, and the token query is dropped", () => {
  const url =
    `https://abc.supabase.co/storage/v1/object/sign/training-memos/${PATH}?token=abc.def.ghi`;
  assertEquals(resolveTrainingMemoPath(url), PATH);
});

Deno.test("authenticated-download URL resolves", () => {
  const url =
    `https://abc.supabase.co/storage/v1/object/authenticated/training-memos/${PATH}`;
  assertEquals(resolveTrainingMemoPath(url), PATH);
});

Deno.test("percent-encoded path is decoded", () => {
  const url =
    `https://abc.supabase.co/storage/v1/object/public/training-memos/${UID}/my%20memo.m4a`;
  assertEquals(resolveTrainingMemoPath(url), `${UID}/my memo.m4a`);
});

// The bug this replaces: the old inline parser fell back to
// `pathname.split("/").pop()`, which dropped `{user_id}/` and yielded a path
// that could only 404 — or collide with another athlete's identically-named
// object. Anything unresolvable must be null, never a guess.
Deno.test("unknown bucket in a storage URL does not fall back to the filename", () => {
  const url =
    `https://abc.supabase.co/storage/v1/object/public/other-bucket/${PATH}`;
  assertEquals(resolveTrainingMemoPath(url), null);
});

Deno.test("non-storage URL is rejected", () => {
  assertEquals(resolveTrainingMemoPath("https://example.com/evil.m4a"), null);
});

Deno.test("empty and nullish values are rejected", () => {
  assertEquals(resolveTrainingMemoPath(""), null);
  assertEquals(resolveTrainingMemoPath("   "), null);
  assertEquals(resolveTrainingMemoPath(null), null);
  assertEquals(resolveTrainingMemoPath(undefined), null);
});

Deno.test("traversal segments are rejected", () => {
  assertEquals(resolveTrainingMemoPath(`../${PATH}`), null);
  assertEquals(resolveTrainingMemoPath(`${UID}/../../etc/passwd`), null);
  assertEquals(
    resolveTrainingMemoPath(
      `https://abc.supabase.co/storage/v1/object/public/training-memos/${UID}/../other/x.m4a`,
    ),
    null,
  );
});

Deno.test("leading slashes are stripped rather than addressing the bucket root", () => {
  assertEquals(resolveTrainingMemoPath(`/${PATH}`), PATH);
});

Deno.test("malformed percent-escape is rejected", () => {
  const url =
    "https://abc.supabase.co/storage/v1/object/public/training-memos/%E0%A4%A";
  assertEquals(resolveTrainingMemoPath(url), null);
});

/**
 * Eval harness types — cassettes, rubrics, results.
 *
 * Cassettes are JSON files on disk; this module pins the schema.
 * `loadCassette()` validates a parsed JSON object against `Cassette`
 * and throws with a useful message on shape violations.
 */

/**
 * One cassette = one test case. Contains the inputs to substitute into
 * the prompt template, the rubric to apply, and a recorded model
 * response to score in replay mode.
 */
export interface Cassette {
  /** Stable id, used in reports. Matches the cassette filename stem. */
  id: string;

  /** Registered prompt name + version, e.g. "injury-analysis.v1". */
  prompt_name: string;

  /** One-line description of what this cassette is testing. */
  description: string;

  /**
   * Substitution values for the prompt template. Same shape as the
   * second argument to `loadPrompt(name, vars)`. Strict by the same
   * rules — missing or extra vars fail.
   */
  vars: Record<string, string | number>;

  /** Rubric the recorded response is scored against. */
  rubric: Rubric;

  /**
   * Optional content appended after the rendered prompt template before
   * the model call. Use for things that aren't part of the prompt itself
   * but are part of the actual model input — e.g. the voice memo
   * transcript that `process-training-memo` concatenates after the
   * template, or the user's chat message that `coaching-agent` appends
   * after its system prompt and context blocks.
   *
   * Replay mode ignores this field (it just scores `recorded_response`
   * against the rubric). Live re-record uses it to reproduce what the
   * production function actually sends to the model.
   */
  input?: string;

  /**
   * The recorded model response. In replay mode this is what gets
   * scored. In live mode this is overwritten by the actual model call.
   */
  recorded_response: string;

  /** ISO timestamp of when `recorded_response` was last refreshed. */
  recorded_at: string;

  /** Model id used for the recording (e.g. "gemini-2.5-flash"). */
  model: string;
}

/**
 * Rubric primitives. Every check is opt-in by being present in the
 * cassette JSON. An empty rubric trivially passes — surface a warning
 * but don't fail (intentional, so you can stub a cassette before
 * deciding what to assert).
 */
export interface Rubric {
  /**
   * Regex strings (or regex objects when constructed in code). The
   * recorded response MUST NOT match any of these. Each entry fails
   * the rubric independently and shows up in the report.
   *
   * Examples for `injury-analysis`:
   *   "(?i)\\bdiagnos\\w+"
   *   "(?i)\\b(itbs|patellofemoral|stress fracture)\\b(?!.*not a diagnosis)"
   *   "(?i)\\bice (it|the area)\\b"
   *
   * Pattern source-of-truth: catalogued in `rubric.ts:DIAGNOSIS_BANS`
   * and `rubric.ts:ACTION_BANS` so multiple cassettes can reuse them
   * by name (loaded via `forbidden_pattern_groups`).
   */
  forbidden_patterns?: string[];

  /** Named pattern groups from rubric.ts (e.g. "diagnosis_bans"). */
  forbidden_pattern_groups?: string[];

  /** Regex strings the response MUST match. */
  required_patterns?: string[];

  /** Named pattern groups (e.g. "medical_disclaimer"). */
  required_pattern_groups?: string[];

  /** Response must be valid JSON. */
  must_parse_as_json?: boolean;

  /**
   * If `must_parse_as_json`, top-level keys that must exist on the
   * parsed object. Doesn't check value types — keep that to
   * `custom_check`.
   */
  json_required_keys?: string[];

  /**
   * Name of a function in `customChecks.ts` for assertions pattern
   * matching can't express (e.g. "for bone injuries, optimistic
   * timeline must be >= 28 days").
   */
  custom_check?: string;
}

/**
 * Result of running one rubric against one recorded response. Carries
 * enough detail that the report can show *what* failed without a
 * second pass.
 */
export interface RubricResult {
  /** True iff every rubric check passed. */
  pass: boolean;

  /** Human-readable failure reasons. Empty when `pass === true`. */
  failures: string[];

  /** Warnings — non-fatal observations (e.g. empty rubric, stub cassette). */
  warnings: string[];

  /** True when this cassette is a stub awaiting live recording. */
  skipped?: boolean;
}

/** Per-cassette result, surfaced in the aggregate report. */
export interface CassetteResult {
  cassette_id: string;
  prompt_name: string;
  result: RubricResult;
}

/** Aggregate report across all cassettes for a prompt. */
export interface EvalReport {
  prompt_name: string;
  total: number;
  passed: number;
  failed: number;
  skipped: number;
  cassettes: CassetteResult[];
}

/**
 * Provider-adapter contract for live recording. Each provider
 * (`providers/gemini.ts`, etc.) exports a function matching this shape;
 * the recorder picks the right one based on a hint encoded in the
 * cassette's `model` field (everything starting with "gemini-" routes
 * to the Gemini adapter, etc).
 */
export interface ProviderCallInput {
  prompt: string;
  model?: string;
  temperature?: number;
}

export interface ProviderCallOutput {
  text: string;
  model_used: string;
}

export type ProviderCall = (input: ProviderCallInput) => Promise<ProviderCallOutput>;

/**
 * Validate a parsed JSON object is shaped like a `Cassette`. Throws a
 * useful message naming the missing field; returns the typed cassette
 * on success. Used by the cassette loader; surfaced for tests too.
 */
export function assertCassetteShape(raw: unknown, source: string): Cassette {
  if (!raw || typeof raw !== "object") {
    throw new Error(`[${source}] cassette must be a JSON object`);
  }
  const c = raw as Record<string, unknown>;
  for (const field of ["id", "prompt_name", "description", "vars", "rubric", "recorded_response", "recorded_at", "model"]) {
    if (!(field in c)) {
      throw new Error(`[${source}] cassette missing required field: ${field}`);
    }
  }
  if (typeof c.id !== "string" || c.id.length === 0) {
    throw new Error(`[${source}] cassette.id must be a non-empty string`);
  }
  if (typeof c.prompt_name !== "string" || !/^[a-z0-9-]+\.v\d+$/.test(c.prompt_name)) {
    throw new Error(`[${source}] cassette.prompt_name must match /^[a-z0-9-]+\\.v\\d+$/ (got "${c.prompt_name}")`);
  }
  if (typeof c.vars !== "object" || c.vars === null || Array.isArray(c.vars)) {
    throw new Error(`[${source}] cassette.vars must be an object`);
  }
  if (typeof c.rubric !== "object" || c.rubric === null) {
    throw new Error(`[${source}] cassette.rubric must be an object`);
  }
  if (typeof c.recorded_response !== "string") {
    throw new Error(`[${source}] cassette.recorded_response must be a string`);
  }
  return c as unknown as Cassette;
}

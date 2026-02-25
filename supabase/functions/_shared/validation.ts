/**
 * Shared input validation and error response utilities.
 * Used by all edge functions for consistent validation and error handling.
 */

export function validateLength(
  value: string | undefined | null,
  fieldName: string,
  maxLength: number
): string | null {
  if (value && value.length > maxLength) {
    return `${fieldName} exceeds maximum length of ${maxLength} characters`;
  }
  return null;
}

export function validateEnum(
  value: string | undefined | null,
  fieldName: string,
  allowedValues: readonly string[]
): string | null {
  if (value && !allowedValues.includes(value)) {
    return `Invalid ${fieldName}. Must be one of: ${allowedValues.join(", ")}`;
  }
  return null;
}

export function validateRange(
  value: number | undefined | null,
  fieldName: string,
  min: number,
  max: number
): string | null {
  if (value !== undefined && value !== null && (value < min || value > max)) {
    return `${fieldName} must be between ${min} and ${max}`;
  }
  return null;
}

export function validateArrayLength(
  arr: unknown[] | undefined | null,
  fieldName: string,
  maxLength: number
): string | null {
  if (arr && arr.length > maxLength) {
    return `${fieldName} exceeds maximum of ${maxLength} items`;
  }
  return null;
}

export function validateUUID(
  value: string | undefined | null,
  fieldName: string
): string | null {
  if (
    value &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  ) {
    return `${fieldName} must be a valid UUID`;
  }
  return null;
}

export function validateFileSize(
  sizeBytes: number,
  maxSizeMB: number
): string | null {
  const maxBytes = maxSizeMB * 1024 * 1024;
  if (sizeBytes > maxBytes) {
    return `File size exceeds maximum of ${maxSizeMB}MB`;
  }
  return null;
}

export function validateMimeType(
  mimeType: string,
  allowedPrefixes: string[]
): string | null {
  const isAllowed = allowedPrefixes.some((prefix) =>
    mimeType.startsWith(prefix)
  );
  if (!isAllowed) {
    return `File type ${mimeType} is not allowed. Accepted: ${allowedPrefixes.join(", ")}`;
  }
  return null;
}

export function validationErrorResponse(
  message: string,
  corsHeaders: Record<string, string>
): Response {
  return new Response(JSON.stringify({ error: message }), {
    status: 400,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function internalErrorResponse(
  corsHeaders: Record<string, string>
): Response {
  return new Response(
    JSON.stringify({ error: "Something went wrong. Please try again." }),
    {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
}

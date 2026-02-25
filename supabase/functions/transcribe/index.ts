/**
 * Cost-Optimized Transcription Endpoint
 *
 * Uses Groq Whisper as primary (10x cheaper than OpenAI):
 * - Groq Whisper: ~$0.001/minute
 * - OpenAI Whisper: ~$0.006/minute
 *
 * At 250K minutes/month: $250 vs $1,500
 *
 * Fallback chain:
 * 1. Groq Whisper (primary)
 * 2. OpenAI Whisper (fallback)
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import { getAuthenticatedUser, unauthorizedResponse } from "../_shared/auth.ts";
import { checkFeatureRateLimit, isRateLimitEnabled } from "../_shared/rateLimit.ts";
import { validateFileSize, validateMimeType, validationErrorResponse, internalErrorResponse } from "../_shared/validation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface TranscriptionResult {
  text: string;
  provider: "groq" | "openai" | "gemini";
  duration?: number;
}

/**
 * Transcribe with Groq Whisper (cheapest option)
 */
async function transcribeWithGroq(audioFile: File): Promise<TranscriptionResult | null> {
  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) {
    console.log("Groq API key not configured");
    return null;
  }

  try {
    const formData = new FormData();
    formData.append("file", audioFile);
    formData.append("model", "whisper-large-v3");
    formData.append("response_format", "verbose_json");

    const response = await fetch(
      "https://api.groq.com/openai/v1/audio/transcriptions",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
        },
        body: formData,
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Groq transcription failed: ${response.status}`, errorText);
      return null;
    }

    const result = await response.json();
    return {
      text: result.text,
      provider: "groq",
      duration: result.duration,
    };
  } catch (error) {
    console.error("Groq transcription error:", error);
    return null;
  }
}

/**
 * Transcribe with OpenAI Whisper (fallback)
 */
async function transcribeWithOpenAI(audioFile: File): Promise<TranscriptionResult | null> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    console.log("OpenAI API key not configured");
    return null;
  }

  try {
    const formData = new FormData();
    formData.append("file", audioFile);
    formData.append("model", "whisper-1");
    formData.append("response_format", "verbose_json");

    const response = await fetch(
      "https://api.openai.com/v1/audio/transcriptions",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
        },
        body: formData,
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`OpenAI transcription failed: ${response.status}`, errorText);
      return null;
    }

    const result = await response.json();
    return {
      text: result.text,
      provider: "openai",
      duration: result.duration,
    };
  } catch (error) {
    console.error("OpenAI transcription error:", error);
    return null;
  }
}

/**
 * Transcribe with Gemini (last resort fallback)
 */
async function transcribeWithGemini(audioFile: File): Promise<TranscriptionResult | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.log("Gemini API key not configured");
    return null;
  }

  try {
    // Convert audio file to base64
    const arrayBuffer = await audioFile.arrayBuffer();
    const base64Audio = btoa(String.fromCharCode(...new Uint8Array(arrayBuffer)));

    // Get MIME type
    const mimeType = audioFile.type || "audio/webm";

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  inlineData: {
                    mimeType: mimeType,
                    data: base64Audio,
                  },
                },
                {
                  text: "Transcribe this audio recording exactly as spoken. Output only the transcription text, nothing else.",
                },
              ],
            },
          ],
          generationConfig: {
            maxOutputTokens: 2048,
          },
        }),
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Gemini transcription failed: ${response.status}`, errorText);
      return null;
    }

    const result = await response.json();
    const text = result.candidates?.[0]?.content?.parts?.[0]?.text || "";

    return {
      text: text.trim(),
      provider: "gemini",
    };
  } catch (error) {
    console.error("Gemini transcription error:", error);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startTime = Date.now();

  try {
    // Verify authenticated user from JWT
    const userId = await getAuthenticatedUser(req);
    if (!userId) {
      return unauthorizedResponse(corsHeaders);
    }

    // Rate limiting
    if (isRateLimitEnabled()) {
      const rateLimit = await checkFeatureRateLimit(userId, "transcribe");
      if (!rateLimit.allowed) {
        return new Response(
          JSON.stringify({ error: "Rate limit exceeded", remaining: 0, resetAt: rateLimit.resetAt.toISOString() }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const formData = await req.formData();
    const audioFile = formData.get("audio") as File;

    if (!audioFile) {
      return new Response(
        JSON.stringify({ error: "Audio file is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Input validation
    const sizeErr = validateFileSize(audioFile.size, 25);
    if (sizeErr) return validationErrorResponse(sizeErr, corsHeaders);

    const mimeErr = validateMimeType(audioFile.type || "audio/unknown", ["audio/"]);
    if (mimeErr) return validationErrorResponse(mimeErr, corsHeaders);

    console.log(`Transcribing audio: ${audioFile.name}, size: ${audioFile.size} bytes, type: ${audioFile.type}`);

    // Try transcription providers in order of cost (cheapest first)
    let result: TranscriptionResult | null = null;

    // 1. Try Groq Whisper (cheapest)
    result = await transcribeWithGroq(audioFile);

    // 2. Fallback to OpenAI Whisper
    if (!result) {
      console.log("Falling back to OpenAI Whisper");
      result = await transcribeWithOpenAI(audioFile);
    }

    // 3. Last resort: Gemini
    if (!result) {
      console.log("Falling back to Gemini");
      result = await transcribeWithGemini(audioFile);
    }

    if (!result) {
      return new Response(
        JSON.stringify({ error: "All transcription providers failed. Please try again." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Log usage for cost tracking
    if (userId) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
      );

      await supabase.from("usage_tracking").insert({
        user_id: userId,
        feature: "transcription",
        model_used: `${result.provider}-whisper`,
        input_tokens: Math.ceil((result.duration || 0) * 60), // Estimate: 60 tokens per second of audio
        output_tokens: Math.ceil(result.text.length / 4),
        cached: false,
      });
    }

    const processingTime = Date.now() - startTime;
    console.log(`Transcription completed in ${processingTime}ms using ${result.provider}`);

    return new Response(
      JSON.stringify({
        text: result.text,
        provider: result.provider,
        duration: result.duration,
        processingTime,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Transcription endpoint error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validateLength, validateEnum, internalErrorResponse } from "../_shared/validation.ts";

import { corsHeaders } from "../_shared/cors.ts";

/** Verify the request carries the service role key (admin-only endpoint) */
function verifyServiceRole(req: Request): boolean {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return false;
  const token = authHeader.replace("Bearer ", "");
  return token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
}

interface DocumentInput {
  title: string;
  content: string;
  category: "rest" | "recovery" | "mindset" | "training" | "injury" | "nutrition";
  metadata?: Record<string, unknown>;
}

// Generate 768-dim embedding via Gemini REST API (gemini-embedding-001)
async function generateEmbedding(text: string, apiKey: string): Promise<number[]> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        content: { parts: [{ text }] },
        outputDimensionality: 768,
      }),
    }
  );

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Embedding API error: ${err}`);
  }

  const data = await response.json();
  return data.embedding.values;
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Admin-only: require service role key
    if (!verifyServiceRole(req)) {
      return new Response(
        JSON.stringify({ error: "Admin access required" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();

    // Initialize clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Re-embed mode: regenerate embeddings for all existing documents
    if (body.action === "re-embed") {
      const { data: allDocs, error: fetchErr } = await supabase
        .from("coaching_documents")
        .select("id, title, content");

      if (fetchErr) {
        return new Response(
          JSON.stringify({ error: `Failed to fetch documents: ${fetchErr.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const results: { title: string; status: string }[] = [];
      for (const doc of allDocs || []) {
        try {
          const textToEmbed = `${doc.title}\n\n${doc.content}`;
          const embedding = await generateEmbedding(textToEmbed, geminiKey);
          const { error: updateErr } = await supabase
            .from("coaching_documents")
            .update({ embedding: JSON.stringify(embedding) })
            .eq("id", doc.id);
          results.push({ title: doc.title, status: updateErr ? `error: ${updateErr.message}` : "updated" });
        } catch (e) {
          const message = e instanceof Error ? e.message : String(e);
          results.push({ title: doc.title, status: `error: ${message}` });
        }
      }

      const updated = results.filter(r => r.status === "updated").length;
      return new Response(
        JSON.stringify({ message: `Re-embedded ${updated}/${results.length} documents`, results }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Standard ingest mode
    const documents: DocumentInput[] = body.documents;

    if (!documents || !Array.isArray(documents) || documents.length === 0) {
      return new Response(
        JSON.stringify({ error: "Documents array is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const results: { title: string; status: string; id?: string }[] = [];

    for (const doc of documents) {
      try {
        // Validate required fields
        if (!doc.title || !doc.content || !doc.category) {
          results.push({ title: doc.title || "Unknown", status: "error: missing required fields" });
          continue;
        }

        // Validate field lengths and enum
        const titleErr = validateLength(doc.title, "title", 500);
        if (titleErr) { results.push({ title: doc.title, status: `error: ${titleErr}` }); continue; }

        const contentErr = validateLength(doc.content, "content", 50000);
        if (contentErr) { results.push({ title: doc.title, status: `error: ${contentErr}` }); continue; }

        const catErr = validateEnum(doc.category, "category", ["rest", "recovery", "mindset", "training", "injury", "nutrition"]);
        if (catErr) { results.push({ title: doc.title, status: `error: ${catErr}` }); continue; }

        // Generate embedding for the document content
        // Combine title and content for better semantic representation
        const textToEmbed = `${doc.title}\n\n${doc.content}`;
        const embedding = await generateEmbedding(textToEmbed, geminiKey);

        // Insert into database
        const { data, error } = await supabase
          .from("coaching_documents")
          .insert({
            title: doc.title,
            content: doc.content,
            category: doc.category,
            embedding: JSON.stringify(embedding),
            metadata: doc.metadata || {},
          })
          .select("id")
          .single();

        if (error) {
          results.push({ title: doc.title, status: `error: ${error.message}` });
        } else {
          results.push({ title: doc.title, status: "success", id: data.id });
        }

      } catch (docError) {
        const message = docError instanceof Error ? docError.message : String(docError);
        results.push({ title: doc.title, status: `error: ${message}` });
      }
    }

    const successCount = results.filter(r => r.status === "success").length;

    return new Response(
      JSON.stringify({
        message: `Ingested ${successCount}/${documents.length} documents`,
        results,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Document ingestion error:", error);
    return internalErrorResponse(corsHeaders);
  }
});

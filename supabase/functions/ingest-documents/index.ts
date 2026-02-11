import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface DocumentInput {
  title: string;
  content: string;
  category: "rest" | "recovery" | "mindset" | "training" | "injury" | "nutrition";
  metadata?: Record<string, unknown>;
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { documents } = await req.json() as { documents: DocumentInput[] };

    if (!documents || !Array.isArray(documents) || documents.length === 0) {
      return new Response(
        JSON.stringify({ error: "Documents array is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize clients
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const geminiKey = Deno.env.get("GEMINI_API_KEY")!;

    const supabase = createClient(supabaseUrl, supabaseKey);
    const genAI = new GoogleGenerativeAI(geminiKey);
    const embeddingModel = genAI.getGenerativeModel({ model: "text-embedding-004" });

    const results: { title: string; status: string; id?: string }[] = [];

    for (const doc of documents) {
      try {
        // Validate required fields
        if (!doc.title || !doc.content || !doc.category) {
          results.push({ title: doc.title || "Unknown", status: "error: missing required fields" });
          continue;
        }

        // Generate embedding for the document content
        // Combine title and content for better semantic representation
        const textToEmbed = `${doc.title}\n\n${doc.content}`;
        const embeddingResult = await embeddingModel.embedContent(textToEmbed);
        const embedding = embeddingResult.embedding.values;

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
        results.push({ title: doc.title, status: `error: ${docError.message}` });
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
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

/**
 * on_dictation_save — Supabase Edge Function (Deno)
 *
 * Triggered after a dictation is created or its text is edited.
 *
 * Flow:
 *   1. Verify JWT (enforced by Supabase; verify_jwt = true in config.toml)
 *   2. Verify the caller owns the dictation (ownership check)
 *   3. Server-side word-count guard (≤ 500 words)
 *   4. Call Claude API → split into sentence array  (system-prompt isolated)
 *   5. Delete existing sentence rows for the dictation
 *   6. For each sentence, call Google Cloud TTS Neural2 → MP3 bytes
 *   7. Upload MP3 to Supabase Storage: dictations/{dictation_id}/sentence_{n}.mp3
 *   8. Insert dictation_sentences rows with audio_url + duration_ms
 *
 * Environment variables required (set in Supabase Dashboard → Edge Functions → Secrets):
 *   ANTHROPIC_API_KEY
 *   GOOGLE_TTS_API_KEY
 *   SUPABASE_URL              (auto-injected by Supabase)
 *   SUPABASE_SERVICE_ROLE_KEY (auto-injected by Supabase)
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const GOOGLE_TTS_API_KEY = Deno.env.get("GOOGLE_TTS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/** Maximum dictation length (words). Must match AppConfig.maxDictationWords. */
const MAX_WORDS = 500;

// Service-role client for all DB operations (bypasses RLS intentionally).
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// ---------------------------------------------------------------------------
// Voice mapping (Google Neural2)
// ---------------------------------------------------------------------------
const VOICE_MAP: Record<string, { languageCode: string; name: string }> = {
  de: { languageCode: "de-DE", name: "de-DE-Neural2-B" },
  en: { languageCode: "en-US", name: "en-US-Neural2-D" },
  fr: { languageCode: "fr-FR", name: "fr-FR-Neural2-A" },
};

// ---------------------------------------------------------------------------
// Auth helper — extract the sub claim from a pre-verified Supabase JWT.
//
// Supabase has already verified the JWT signature before calling this function
// (verify_jwt = true). We only need the `sub` claim from the decoded payload;
// we are NOT performing cryptographic verification here.
// ---------------------------------------------------------------------------
function getCallerUserId(req: Request): string | null {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  try {
    const token = authHeader.slice(7);
    const payload = JSON.parse(atob(token.split(".")[1]));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // 1. Extract caller identity (JWT was already verified by Supabase).
  const callerId = getCallerUserId(req);
  if (!callerId) {
    return new Response("Unauthorized", { status: 401 });
  }

  // 2. Parse request body.
  let dictationId: string;
  let language: string;
  try {
    const body = await req.json();
    dictationId = body.dictation_id;
    language = body.language ?? "de";
    if (!dictationId) throw new Error("Missing dictation_id");
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 400 });
  }

  try {
    // 3. Fetch dictation and verify ownership.
    const { data: dictation, error: fetchError } = await supabase
      .from("dictations")
      .select("owner_id, full_text, language")
      .eq("id", dictationId)
      .single();

    if (fetchError || !dictation) {
      return new Response(JSON.stringify({ error: "Dictation not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (dictation.owner_id !== callerId) {
      return new Response("Forbidden", { status: 403 });
    }

    // 4. Server-side word-count guard — mirrors AppConfig.maxDictationWords.
    //    This catches callers that bypass the client-side limit (e.g. direct
    //    Supabase REST API calls that create oversized dictations).
    const wordCount = dictation.full_text.trim().split(/\s+/).filter(Boolean).length;
    if (wordCount > MAX_WORDS) {
      return new Response(
        JSON.stringify({
          error: `Dictation exceeds ${MAX_WORDS}-word limit (${wordCount} words).`,
        }),
        { status: 422, headers: { "Content-Type": "application/json" } }
      );
    }

    // Mark as processing so the client can show a definite "in progress" state.
    await supabase
      .from("dictations")
      .update({ tts_status: "processing", tts_error: null })
      .eq("id", dictationId);

    // 5. Split into sentences using Claude.
    const sentences = await splitIntoSentences(dictation.full_text, language);
    if (sentences.length === 0) {
      throw new Error("Sentence splitting returned empty array");
    }

    // 6. Delete old sentence rows.
    const { error: deleteError } = await supabase
      .from("dictation_sentences")
      .delete()
      .eq("dictation_id", dictationId);

    if (deleteError) {
      throw new Error(`Failed to delete old sentences: ${deleteError.message}`);
    }

    // 7–8. Generate TTS for each sentence and insert rows.
    const voice = VOICE_MAP[language] ?? VOICE_MAP["de"];

    for (let i = 0; i < sentences.length; i++) {
      const text = sentences[i];

      const { audioContent, durationMs } = await generateTts(text, voice);

      // Upload MP3.
      const storagePath = `${dictationId}/sentence_${i}.mp3`;
      const { error: uploadError } = await supabase.storage
        .from("dictations")
        .upload(storagePath, audioContent, {
          contentType: "audio/mpeg",
          upsert: true,
        });

      if (uploadError) throw new Error(`Upload failed: ${uploadError.message}`);

      // Public URL.
      const { data: urlData } = supabase.storage
        .from("dictations")
        .getPublicUrl(storagePath);

      // Insert sentence row.
      const { error: insertError } = await supabase
        .from("dictation_sentences")
        .insert({
          dictation_id: dictationId,
          position: i,
          text: text,
          audio_url: urlData.publicUrl,
          duration_ms: durationMs,
        });

      if (insertError) {
        throw new Error(`Failed to insert sentence ${i}: ${insertError.message}`);
      }
    }

    await supabase
      .from("dictations")
      .update({ tts_status: "done" })
      .eq("id", dictationId);

    return new Response(
      JSON.stringify({ success: true, sentence_count: sentences.length }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("[on_dictation_save] Error:", e);

    // Write the error back so the client can surface it instead of spinning.
    const errorMessage = e instanceof Error ? e.message : String(e);
    await supabase
      .from("dictations")
      .update({ tts_status: "error", tts_error: errorMessage })
      .eq("id", dictationId)
      .then(() => {})   // best-effort; ignore secondary failure
      .catch(() => {});

    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

// ---------------------------------------------------------------------------
// Claude: sentence splitting
//
// The task instructions live in the `system` parameter (not the user message)
// so that dictation text cannot override them via prompt injection.
// ---------------------------------------------------------------------------
async function splitIntoSentences(
  text: string,
  language: string
): Promise<string[]> {
  const languageLabel = language === "de"
    ? "German"
    : language === "fr"
    ? "French"
    : "English";

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 2048,
      // System prompt holds the instructions — isolated from user-controlled text
      // to prevent prompt injection via the dictation content.
      system:
        "You are a sentence splitter for dictation exercises. " +
        "Split the provided text into individual sentences suitable for dictation. " +
        "Preserve all punctuation exactly as written. " +
        "Handle abbreviations correctly (e.g. 'Dr.', 'z.B.', 'bzw.', 'etc.'). " +
        "Return ONLY a JSON array of strings. No markdown, no code fences, no explanation.",
      messages: [
        {
          role: "user",
          content: `Language: ${languageLabel}\n\nText:\n${text}`,
        },
      ],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude API error ${response.status}: ${err}`);
  }

  const data = await response.json();
  const content = data.content?.[0]?.text ?? "";

  try {
    const sentences = JSON.parse(content) as string[];
    return sentences.filter((s) => s.trim().length > 0);
  } catch {
    throw new Error(`Failed to parse sentence array from Claude: ${content}`);
  }
}

// ---------------------------------------------------------------------------
// Google Cloud TTS
// ---------------------------------------------------------------------------
async function generateTts(
  text: string,
  voice: { languageCode: string; name: string }
): Promise<{ audioContent: Uint8Array; durationMs: number }> {
  const response = await fetch(
    `https://texttospeech.googleapis.com/v1/text:synthesize?key=${GOOGLE_TTS_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        input: { text },
        voice: {
          languageCode: voice.languageCode,
          name: voice.name,
        },
        audioConfig: {
          audioEncoding: "MP3",
          speakingRate: 1.0,
        },
      }),
    }
  );

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Google TTS error ${response.status}: ${err}`);
  }

  const data = await response.json();
  const base64Audio: string = data.audioContent;
  const audioBytes = Uint8Array.from(atob(base64Audio), (c) => c.charCodeAt(0));

  // Estimate duration from MP3 size (rough: ~16 kB/s for 128 kbps MP3).
  const durationMs = Math.round((audioBytes.length / 16000) * 1000);

  return { audioContent: audioBytes, durationMs };
}

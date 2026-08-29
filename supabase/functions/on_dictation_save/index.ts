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
 *   6. For each sentence, call Google Cloud TTS Neural2 twice → MP3 bytes:
 *      once at speakingRate=1.0 (normal) and once at speakingRate=0.5 (slow).
 *      The slow variant is genuinely re-spoken by TTS, not stretched, so it
 *      stays artifact-free at low playback speeds (see player_screen speed
 *      selector / PlaybackNotifier, which never slows audio down in real
 *      time — only ever speeds it up from one of these two base files).
 *   7. Upload both MP3s to Supabase Storage:
 *        dictations/{dictation_id}/sentence_{n}.mp3
 *        dictations/{dictation_id}/sentence_{n}_slow.mp3
 *   8. Insert dictation_sentences rows with audio_url + duration_ms
 *      and audio_url_slow + duration_ms_slow
 *
 * Environment variables required (set in Supabase Dashboard → Edge Functions → Secrets):
 *   GOOGLE_TTS_API_KEY
 *   SUPABASE_URL              (auto-injected by Supabase)
 *   SUPABASE_SERVICE_ROLE_KEY (auto-injected by Supabase)
 */

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
  }

  // 1. Extract caller identity (JWT was already verified by Supabase).
  const callerId = getCallerUserId(req);
  if (!callerId) {
    return new Response("Unauthorized", { status: 401, headers: CORS_HEADERS });
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
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
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
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    if (dictation.owner_id !== callerId) {
      return new Response("Forbidden", { status: 403, headers: CORS_HEADERS });
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
        { status: 422, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
      );
    }

    // Mark as processing so the client can show a definite "in progress" state.
    await supabase
      .from("dictations")
      .update({ tts_status: "processing", tts_error: null })
      .eq("id", dictationId);

    // 5. Split into sentences.
    const sentences = splitIntoSentences(dictation.full_text, language);
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

      // Generate both speed variants in parallel — see header comment.
      const [normal, slow] = await Promise.all([
        generateTts(text, voice, 1.0),
        generateTts(text, voice, 0.5),
      ]);

      const storagePath = `${dictationId}/sentence_${i}.mp3`;
      const storagePathSlow = `${dictationId}/sentence_${i}_slow.mp3`;

      const [uploadNormal, uploadSlow] = await Promise.all([
        supabase.storage.from("dictations").upload(storagePath, normal.audioContent, {
          contentType: "audio/mpeg",
          upsert: true,
        }),
        supabase.storage.from("dictations").upload(storagePathSlow, slow.audioContent, {
          contentType: "audio/mpeg",
          upsert: true,
        }),
      ]);

      if (uploadNormal.error) throw new Error(`Upload failed: ${uploadNormal.error.message}`);
      if (uploadSlow.error) throw new Error(`Upload failed: ${uploadSlow.error.message}`);

      // Public URLs.
      const { data: urlData } = supabase.storage.from("dictations").getPublicUrl(storagePath);
      const { data: urlDataSlow } = supabase.storage
        .from("dictations")
        .getPublicUrl(storagePathSlow);

      // Insert sentence row.
      const { error: insertError } = await supabase
        .from("dictation_sentences")
        .insert({
          dictation_id: dictationId,
          position: i,
          text: text,
          audio_url: urlData.publicUrl,
          duration_ms: normal.durationMs,
          audio_url_slow: urlDataSlow.publicUrl,
          duration_ms_slow: slow.durationMs,
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
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("[on_dictation_save] Error:", e);

    // Write the error back so the client can surface it instead of spinning.
    const errorMessage = e instanceof Error ? e.message : String(e);
    try {
      await supabase
        .from("dictations")
        .update({ tts_status: "error", tts_error: errorMessage })
        .eq("id", dictationId);
    } catch {
      // best-effort; ignore secondary failure
    }

    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
});

// ---------------------------------------------------------------------------
// Sentence splitting — regex-based, no external API required.
//
// Strategy:
//   1. Protect decimal numbers and known abbreviations by swapping their
//      periods for a sentinel character (U+0000).
//   2. Split on sentence-ending punctuation [.!?] followed by optional
//      closing quotes/brackets, whitespace, and an uppercase letter.
//   3. Restore sentinels back to periods.
// ---------------------------------------------------------------------------
function splitIntoSentences(text: string, _language: string): string[] {
  const SENTINEL = " ";
  const s0 = text.trim();
  if (!s0) return [];

  let s = s0;

  // Protect decimal / ordinal numbers: "3.14", "§ 2.1"
  s = s.replace(/(\d)\.(\d)/g, `$1${SENTINEL}$2`);

  // Protect multi-component German abbreviations (z.B., d.h., u.a., o.ä., z.T.)
  s = s.replace(/\bz\.\s*B\./gi, `z${SENTINEL}B${SENTINEL}`);
  s = s.replace(/\bd\.\s*h\./gi, `d${SENTINEL}h${SENTINEL}`);
  s = s.replace(/\bu\.\s*a\./gi, `u${SENTINEL}a${SENTINEL}`);
  s = s.replace(/\bu\.\s*ä\./gi, `u${SENTINEL}ä${SENTINEL}`);
  s = s.replace(/\bo\.\s*ä\./gi, `o${SENTINEL}ä${SENTINEL}`);
  s = s.replace(/\bz\.\s*T\./gi, `z${SENTINEL}T${SENTINEL}`);

  // Protect multi-component English abbreviations (e.g., i.e.)
  s = s.replace(/\be\.\s*g\./gi, `e${SENTINEL}g${SENTINEL}`);
  s = s.replace(/\bi\.\s*e\./gi, `i${SENTINEL}e${SENTINEL}`);

  // Protect single-word abbreviations (German, English, French)
  const ABBREVS = [
    "Dr", "Prof", "Hr", "Fr", "Sr", "Jr", "St", "Nr", "Str", "Dipl", "Ing", "Abs",
    "bzw", "ggf", "evtl", "usw", "etc", "inkl", "exkl", "ca", "vgl", "bes",
    "Mr", "Mrs", "Ms", "vs",
    "Mme", "Mlle",
  ];
  for (const abbr of ABBREVS) {
    s = s.replace(new RegExp(`\\b${abbr}\\.`, "g"), `${abbr}${SENTINEL}`);
  }

  // Split on: [.!?] + optional closing punctuation + whitespace + uppercase letter.
  // Lookbehind keeps the terminal punctuation attached to the preceding sentence.
  const parts = s.split(
    /(?<=[.!?][»"')\]]*)\s+(?=[A-ZÄÖÜÀ-ɏ])/u
  );

  // Also treat blank lines as sentence boundaries.
  const sentences = parts
    .flatMap((p) => p.split(/\n{2,}/))
    .map((p) => p.replace(new RegExp(SENTINEL, "g"), ".").trim())
    .filter((p) => p.length > 0);

  return sentences.length > 0 ? sentences : [s0];
}

// ---------------------------------------------------------------------------
// Google Cloud TTS
// ---------------------------------------------------------------------------
async function generateTts(
  text: string,
  voice: { languageCode: string; name: string },
  speakingRate: number
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
          speakingRate,
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

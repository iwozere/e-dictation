/**
 * generate_card_audio — Supabase Edge Function (Deno)
 *
 * Second step of the photo → flashcards pipeline (see
 * docs/cr-card-decks-language-flashcards.md). Runs after the teacher has
 * reviewed and confirmed the draft `cards` rows written by parse_card_deck.
 *
 * For every card, generates TTS for BOTH text_a and text_b (the deck's two
 * languages) — a card's audio_a/audio_b pair covers whichever language ends
 * up "foreign" for a given student, since that's chosen per-session, not
 * fixed by the deck (see the CR doc's "Key decision" section).
 *
 * Flow:
 *   1. Verify JWT, verify caller owns the deck
 *   2. Fetch cards for the deck
 *   3. For each card, call Google Cloud TTS Neural2 for text_a and text_b
 *   4. Upload MP3s to Supabase Storage:
 *        card_decks/{deck_id}/card_{n}_a.mp3
 *        card_decks/{deck_id}/card_{n}_b.mp3
 *   5. Update the card row with both audio URLs + durations
 *   6. Mark the deck 'ready'
 *
 * Request body: { deck_id: string }
 * Response:     { success: true, card_count: number }
 *
 * Environment variables required:
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

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// Mirrors on_dictation_save's VOICE_MAP — kept in sync manually since Edge
// Functions in this repo don't currently share a _shared lib directory.
const VOICE_MAP: Record<string, { languageCode: string; name: string }> = {
  de: { languageCode: "de-DE", name: "de-DE-Neural2-B" },
  en: { languageCode: "en-US", name: "en-US-Neural2-D" },
  fr: { languageCode: "fr-FR", name: "fr-FR-Neural2-A" },
};

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
  }

  const callerId = getCallerUserId(req);
  if (!callerId) {
    return new Response("Unauthorized", { status: 401, headers: CORS_HEADERS });
  }

  let deckId: string;
  try {
    const body = await req.json();
    deckId = body.deck_id;
    if (!deckId) throw new Error("Missing deck_id");
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    const { data: deck, error: fetchError } = await supabase
      .from("card_decks")
      .select("owner_id, language_a, language_b")
      .eq("id", deckId)
      .single();

    if (fetchError || !deck) {
      return new Response(JSON.stringify({ error: "Card deck not found" }), {
        status: 404,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    if (deck.owner_id !== callerId) {
      return new Response("Forbidden", { status: 403, headers: CORS_HEADERS });
    }

    const { data: cards, error: cardsError } = await supabase
      .from("cards")
      .select("id, position, text_a, text_b")
      .eq("deck_id", deckId)
      .order("position");

    if (cardsError) {
      throw new Error(`Failed to load cards: ${cardsError.message}`);
    }
    if (!cards || cards.length === 0) {
      const message = "This deck has no cards to generate audio for.";
      await supabase
        .from("card_decks")
        .update({ status: "failed", status_error: message })
        .eq("id", deckId);
      return new Response(JSON.stringify({ error: message }), {
        status: 422,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    await supabase
      .from("card_decks")
      .update({ status: "pending", status_error: null })
      .eq("id", deckId);

    const voiceA = VOICE_MAP[deck.language_a] ?? VOICE_MAP["de"];
    const voiceB = VOICE_MAP[deck.language_b] ?? VOICE_MAP["en"];

    for (const card of cards) {
      const [ttsA, ttsB] = await Promise.all([
        generateTts(card.text_a, voiceA),
        generateTts(card.text_b, voiceB),
      ]);

      const pathA = `${deckId}/card_${card.position}_a.mp3`;
      const pathB = `${deckId}/card_${card.position}_b.mp3`;

      const [uploadA, uploadB] = await Promise.all([
        supabase.storage.from("card_decks").upload(pathA, ttsA.audioContent, {
          contentType: "audio/mpeg",
          upsert: true,
        }),
        supabase.storage.from("card_decks").upload(pathB, ttsB.audioContent, {
          contentType: "audio/mpeg",
          upsert: true,
        }),
      ]);

      if (uploadA.error) throw new Error(`Upload failed: ${uploadA.error.message}`);
      if (uploadB.error) throw new Error(`Upload failed: ${uploadB.error.message}`);

      const { data: urlA } = supabase.storage.from("card_decks").getPublicUrl(pathA);
      const { data: urlB } = supabase.storage.from("card_decks").getPublicUrl(pathB);

      const { error: updateError } = await supabase
        .from("cards")
        .update({
          audio_a_url: urlA.publicUrl,
          audio_a_duration_ms: ttsA.durationMs,
          audio_b_url: urlB.publicUrl,
          audio_b_duration_ms: ttsB.durationMs,
        })
        .eq("id", card.id);

      if (updateError) {
        throw new Error(`Failed to update card ${card.id}: ${updateError.message}`);
      }
    }

    await supabase
      .from("card_decks")
      .update({ status: "ready" })
      .eq("id", deckId);

    return new Response(
      JSON.stringify({ success: true, card_count: cards.length }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("[generate_card_audio] Error:", e);

    const errorMessage = e instanceof Error ? e.message : String(e);
    try {
      await supabase
        .from("card_decks")
        .update({ status: "failed", status_error: errorMessage })
        .eq("id", deckId);
    } catch {
      // best-effort; ignore secondary failure
    }

    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
});

// ---------------------------------------------------------------------------
// Google Cloud TTS — mirrors on_dictation_save's generateTts (normal speed
// only; cards don't have a slow-variant pre-generation step, see CR doc's
// Deferred section).
// ---------------------------------------------------------------------------
async function generateTts(
  text: string,
  voice: { languageCode: string; name: string },
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
    },
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

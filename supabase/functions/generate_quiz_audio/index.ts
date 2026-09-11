/**
 * generate_quiz_audio — Supabase Edge Function (Deno)
 *
 * Runs after the teacher has reviewed and confirmed a draft quiz deck's
 * cards/options (see docs/cr-quiz-decks-timed-multiple-choice.md).
 *
 * Every option — correct AND wrong — needs audio, since any of the 3 shown
 * at practice time can be clicked and must be pronounced. That's a bigger
 * TTS bill than card_decks (2 files/card): a card can need up to
 * 2 × (pool size) files. To keep it down, generation dedupes by
 * `(side, text)` **within the deck** — the same word can be the correct
 * answer for one card and a wrong option for another ("Wrong answers can be
 * correct for some other card" — CR doc, Key decision #4), so it's
 * synthesized once and every row with that text/side reuses the URL.
 *
 * Flow:
 *   1. Verify JWT, verify caller owns the deck
 *   2. Fetch every quiz_card_options row for the deck
 *   3. For each unique (side, text), call Google Cloud TTS Neural2 once
 *   4. Upload MP3s to Supabase Storage:
 *        quiz_decks/{deck_id}/{side}_{hash}.mp3
 *   5. Update every option row sharing that (side, text) with the audio URL
 *   6. Mark the deck 'ready'
 *
 * Request body: { deck_id: string }
 * Response:     { success: true, option_count: number, synthesized_count: number }
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

// Mirrors on_dictation_save's / generate_card_audio's VOICE_MAP — kept in
// sync manually since Edge Functions in this repo don't share a lib dir.
const VOICE_MAP: Record<string, { languageCode: string; name: string }> = {
  de: { languageCode: "de-DE", name: "de-DE-Neural2-B" },
  en: { languageCode: "en-US", name: "en-US-Neural2-D" },
  fr: { languageCode: "fr-FR", name: "fr-FR-Neural2-A" },
};

interface OptionRow {
  id: string;
  side: "a" | "b";
  text: string;
}

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

/** Short, filesystem-safe hash of a dedup key, for storage paths. */
async function shortHash(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16);
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
      .from("quiz_decks")
      .select("owner_id, language_a, language_b")
      .eq("id", deckId)
      .single();

    if (fetchError || !deck) {
      return new Response(JSON.stringify({ error: "Quiz deck not found" }), {
        status: 404,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    if (deck.owner_id !== callerId) {
      return new Response("Forbidden", { status: 403, headers: CORS_HEADERS });
    }

    const { data: cardIdRows, error: cardIdsError } = await supabase
      .from("quiz_cards")
      .select("id")
      .eq("deck_id", deckId);
    if (cardIdsError) {
      throw new Error(`Failed to load cards: ${cardIdsError.message}`);
    }
    const cardIds = (cardIdRows ?? []).map((r) => r.id as string);

    if (cardIds.length === 0) {
      const message = "This deck has no cards to generate audio for.";
      await supabase
        .from("quiz_decks")
        .update({ status: "failed", status_error: message })
        .eq("id", deckId);
      return new Response(JSON.stringify({ error: message }), {
        status: 422,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { data: options, error: optionsError } = await supabase
      .from("quiz_card_options")
      .select("id, side, text")
      .in("card_id", cardIds);
    if (optionsError) {
      throw new Error(`Failed to load options: ${optionsError.message}`);
    }
    if (!options || options.length === 0) {
      const message = "This deck's cards have no answer options yet.";
      await supabase
        .from("quiz_decks")
        .update({ status: "failed", status_error: message })
        .eq("id", deckId);
      return new Response(JSON.stringify({ error: message }), {
        status: 422,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    await supabase
      .from("quiz_decks")
      .update({ status: "pending", status_error: null })
      .eq("id", deckId);

    const voiceFor = (side: "a" | "b") =>
      side === "a"
        ? VOICE_MAP[deck.language_a] ?? VOICE_MAP["de"]
        : VOICE_MAP[deck.language_b] ?? VOICE_MAP["en"];

    // Dedup by (side, text): group option rows sharing a key so each unique
    // string is synthesized once and every row in its group gets the same URL.
    const groups = new Map<string, OptionRow[]>();
    for (const row of options as OptionRow[]) {
      const key = `${row.side}::${row.text}`;
      const group = groups.get(key);
      if (group) {
        group.push(row);
      } else {
        groups.set(key, [row]);
      }
    }

    let synthesizedCount = 0;
    for (const [key, rows] of groups) {
      const { side, text } = rows[0];
      const tts = await generateTts(text, voiceFor(side));
      synthesizedCount++;

      const path = `${deckId}/${side}_${await shortHash(key)}.mp3`;
      const upload = await supabase.storage
        .from("quiz_decks")
        .upload(path, tts.audioContent, { contentType: "audio/mpeg", upsert: true });
      if (upload.error) {
        throw new Error(`Upload failed: ${upload.error.message}`);
      }

      const { data: urlData } = supabase.storage.from("quiz_decks").getPublicUrl(path);

      const { error: updateError } = await supabase
        .from("quiz_card_options")
        .update({ audio_url: urlData.publicUrl, audio_duration_ms: tts.durationMs })
        .in("id", rows.map((r) => r.id));
      if (updateError) {
        throw new Error(`Failed to update options for "${text}": ${updateError.message}`);
      }
    }

    await supabase.from("quiz_decks").update({ status: "ready" }).eq("id", deckId);

    return new Response(
      JSON.stringify({
        success: true,
        option_count: options.length,
        synthesized_count: synthesizedCount,
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("[generate_quiz_audio] Error:", e);

    const errorMessage = e instanceof Error ? e.message : String(e);
    try {
      await supabase
        .from("quiz_decks")
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
// Google Cloud TTS — mirrors generate_card_audio's generateTts.
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

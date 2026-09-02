/**
 * parse_card_deck — Supabase Edge Function (Deno)
 *
 * First step of the photo → flashcards pipeline (see
 * docs/cr-card-decks-language-flashcards.md). Sends the teacher's photo to
 * Claude (vision, structured output) and writes the extracted pairs as
 * *draft* `cards` rows — no TTS spend here. The teacher reviews/edits the
 * draft in the app, then `generate_card_audio` synthesizes audio and flips
 * the deck to 'ready'.
 *
 * The image is never persisted to Storage — it arrives as base64 in the
 * request body and is discarded after the Claude call, same pattern as the
 * ocr_image function.
 *
 * Request body: { deck_id: string, image_base64: string, mime_type?: string }
 * Response:     { success: true, card_count: number }
 *
 * Environment variables required:
 *   ANTHROPIC_API_KEY
 *   SUPABASE_URL              (auto-injected by Supabase)
 *   SUPABASE_SERVICE_ROLE_KEY (auto-injected by Supabase)
 */

import { createClient } from "jsr:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@0.123.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@0.123.0/helpers/zod";
import { z } from "npm:zod@^4.0.0";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;

// Guard against very large images reaching Claude (mirrors the 6 MB client-side
// check in OcrImageButton; base64 inflates raw bytes by ~4/3).
const MAX_BASE64_LENGTH = 8 * 1024 * 1024;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

const LANGUAGE_NAMES: Record<string, string> = {
  de: "German",
  en: "English",
  fr: "French",
};

const CardPairsSchema = z.object({
  pairs: z.array(
    z.object({
      text_a: z.string(),
      text_b: z.string(),
    }),
  ),
});

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
  let imageBase64: string;
  let mimeType: string;
  try {
    const body = await req.json();
    deckId = body.deck_id;
    imageBase64 = body.image_base64;
    mimeType = body.mime_type ?? "image/jpeg";
    if (!deckId) throw new Error("Missing deck_id");
    if (!imageBase64) throw new Error("Missing image_base64");
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (imageBase64.length > MAX_BASE64_LENGTH) {
    return new Response(JSON.stringify({ error: "Image is too large." }), {
      status: 413,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    // Fetch the deck and verify ownership.
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

    await supabase
      .from("card_decks")
      .update({ status: "pending", status_error: null })
      .eq("id", deckId);

    const languageAName = LANGUAGE_NAMES[deck.language_a] ?? deck.language_a;
    const languageBName = LANGUAGE_NAMES[deck.language_b] ?? deck.language_b;

    const response = await anthropic.messages.parse({
      model: "claude-opus-4-7",
      max_tokens: 4096,
      thinking: { type: "adaptive" },
      system:
        "You transcribe vocabulary flashcard photos for a language-learning app. " +
        "A wrong transcription becomes the answer key a student is graded against, " +
        "so accuracy matters more than speed. Preserve original spelling, diacritics " +
        "and capitalization exactly as written — do not correct or normalise them.",
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: mimeType as Anthropic.Base64ImageSource["media_type"], data: imageBase64 },
            },
            {
              type: "text",
              text:
                `This photo shows a two-column list of word/phrase pairs: one column is ` +
                `${languageAName}, the other is ${languageBName}. The columns may appear in ` +
                `either left/right order, and the layout may be a table, two lists, or ` +
                `numbered rows — infer pairing from position and content, not a fixed side.\n\n` +
                `Extract every pair. For each one, put the ${languageAName} text in "text_a" ` +
                `and the ${languageBName} text in "text_b", determined by which language each ` +
                `phrase is actually written in (not by physical column). Skip headers, page ` +
                `numbers, and anything that is not part of a pair. If a row is illegible, omit it ` +
                `rather than guessing.`,
            },
          ],
        },
      ],
      output_config: {
        format: zodOutputFormat(CardPairsSchema),
      },
    });

    const parsed = response.parsed_output;
    if (!parsed || parsed.pairs.length === 0) {
      const message = "Could not read any word pairs from that photo. Try a clearer photo.";
      await supabase
        .from("card_decks")
        .update({ status: "failed", status_error: message })
        .eq("id", deckId);
      return new Response(JSON.stringify({ error: message }), {
        status: 422,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // Replace any previous draft (e.g. teacher re-scanning after a failure).
    const { error: deleteError } = await supabase
      .from("cards")
      .delete()
      .eq("deck_id", deckId);
    if (deleteError) {
      throw new Error(`Failed to clear old cards: ${deleteError.message}`);
    }

    const rows = parsed.pairs.map((pair, i) => ({
      deck_id: deckId,
      position: i,
      text_a: pair.text_a.trim(),
      text_b: pair.text_b.trim(),
    }));

    const { error: insertError } = await supabase.from("cards").insert(rows);
    if (insertError) {
      throw new Error(`Failed to insert cards: ${insertError.message}`);
    }

    await supabase
      .from("card_decks")
      .update({ status: "draft" })
      .eq("id", deckId);

    return new Response(
      JSON.stringify({ success: true, card_count: rows.length }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("[parse_card_deck] Error:", e);

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

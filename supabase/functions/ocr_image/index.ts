/**
 * ocr_image — Supabase Edge Function (Deno)
 *
 * Extracts text from a base64-encoded image using Google Cloud Vision API
 * (DOCUMENT_TEXT_DETECTION — handles both printed and handwritten text).
 *
 * Request body: { image_base64: string, mime_type?: string }
 * Response:     { text: string }
 *
 * Environment variables required:
 *   GOOGLE_CLOUD_VISION_API_KEY  (Cloud Vision API must be enabled in GCP project)
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GOOGLE_CLOUD_VISION_API_KEY = Deno.env.get("GOOGLE_CLOUD_VISION_API_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
  }

  // Supabase enforces JWT via verify_jwt = true; just confirm the header exists.
  if (!req.headers.get("Authorization")) {
    return new Response("Unauthorized", { status: 401, headers: CORS_HEADERS });
  }

  let imageBase64: string;
  let mimeType: string;
  try {
    const body = await req.json();
    imageBase64 = body.image_base64;
    mimeType = body.mime_type ?? "image/jpeg";
    if (!imageBase64) throw new Error("Missing image_base64");
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    const visionResp = await fetch(
      `https://vision.googleapis.com/v1/images:annotate?key=${GOOGLE_CLOUD_VISION_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          requests: [
            {
              image: { content: imageBase64 },
              features: [{ type: "DOCUMENT_TEXT_DETECTION" }],
            },
          ],
        }),
      }
    );

    if (!visionResp.ok) {
      const err = await visionResp.text();
      throw new Error(`Vision API ${visionResp.status}: ${err}`);
    }

    const data = await visionResp.json();
    const rawText: string =
      data.responses?.[0]?.fullTextAnnotation?.text ?? "";

    const text = rawText ? normaliseText(rawText) : "";

    return new Response(JSON.stringify({ text }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[ocr_image] Error:", e);
    return new Response(JSON.stringify({ error: "OCR failed" }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});

/**
 * Convert raw Vision API output into clean paragraph text.
 *
 * Vision uses \n for line breaks within a paragraph and \n\n for paragraph
 * boundaries.  We collapse single newlines (soft wraps) into spaces so the
 * result reads as natural sentences, and preserve paragraph breaks.
 */
function normaliseText(raw: string): string {
  return raw
    .replace(/\r\n/g, "\n")
    .split(/\n{2,}/)
    .map((para) =>
      para
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .join(" ")
    )
    .filter((para) => para.length > 0)
    .join("\n\n")
    .trim();
}

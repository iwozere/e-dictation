# CR: OCR — Image to Dictation Text

## Summary

Teachers can photograph a printed or handwritten text and have it converted to dictation text automatically via Google Cloud Vision OCR, eliminating manual re-typing.

## User story

> As a teacher, I want to upload a photo of a text (printed or handwritten) so that the OCR service converts it into the dictation text field, which I can then review and save.

## Decision: Google Cloud Vision API

| Option | Cost / 1k images | Notes |
|---|---|---|
| **Google Cloud Vision** ✓ | **$1.50 (first 1k free/month)** | Same ecosystem as TTS; purpose-built OCR |
| Claude / GPT-4o vision | $1–15 | 5–10× pricier; useful if cleanup needed |
| Tesseract WASM | Free | Complex Deno deploy; poor ä/ö/ü accuracy |

**Choice**: `TEXT_DETECTION` for typed/printed text. Switch to `DOCUMENT_TEXT_DETECTION` if handwriting support is needed (same price, better cursive accuracy).

Practical cost at teacher scale (≤ 1,000 images/month): **free**.

## Architecture

```
Flutter (Create / Edit screen)
  └─ "Scan image" button → image_picker (gallery or camera)
        └─ image as base64 → POST /functions/v1/ocr_image
              └─ Google Cloud Vision TEXT_DETECTION
                    └─ { text: "..." } → populate dictation text field
```

The image is **never persisted** — it is sent as base64 in the Edge Function request body and discarded after OCR. The API key stays server-side.

## Post-processing (Edge Function)

Google Vision returns text with layout-driven line breaks. The Edge Function normalises it:

1. Split into lines.
2. Join lines that are part of the same paragraph (no blank line between them) with a space.
3. Separate paragraphs with `\n\n` so the sentence splitter later handles them as distinct blocks.
4. Strip leading/trailing whitespace.

## New secret required

```
GOOGLE_CLOUD_VISION_API_KEY   # same GCP project; enable "Cloud Vision API" in Console
```

## Files changed

| File | Change |
|---|---|
| `supabase/functions/ocr_image/index.ts` | New Edge Function |
| `lib/features/dictations/presentation/screens/create_dictation_screen.dart` | "Scan image" button |
| `lib/features/dictations/presentation/screens/edit_dictation_screen.dart` | Same button |
| `lib/shared/widgets/ocr_image_button.dart` | Shared widget (picker + call + fill) |
| `pubspec.yaml` | Add `image_picker` |

## UI flow

1. Teacher taps **Scan image** (camera icon) near the dictation text field.
2. System image picker opens (gallery or camera; both work on web via `<input type="file">`).
3. Spinner overlays the text field while the Edge Function runs (~1 s).
4. Text field is populated with the OCR result.
5. Teacher reviews, edits if needed, then saves normally.
6. If OCR fails, a snackbar shows the error; the text field is unchanged.

## Constraints

- Max image size sent to Vision API: 10 MB (enforced client-side before upload).
- Word-count limit still enforced after OCR (500 words).
- Web: `image_picker` on Flutter Web uses `<input type="file accept="image/*">` — no camera access on desktop browsers, gallery only.

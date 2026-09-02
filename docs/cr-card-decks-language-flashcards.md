# CR: Card Decks — Photo-to-Flashcard Language Pairs

## Summary

A new content type alongside dictations: teachers photograph a printed list of word/phrase
pairs (e.g. a German/English vocabulary sheet), Claude extracts the pairs, and students
practice them as bidirectional translation flashcards via a share link — one language typed
as the prompt (shown + read aloud), the other typed as the answer.

## User stories

> As a teacher, I want to photograph a two-column vocabulary list and have the app turn it
> into a shareable set of flashcards, without retyping every pair by hand.

> As a student, I want to open a link, tell the app which of the two languages I already
> know, and practice translating in both directions — reading/hearing one language and
> typing the other.

---

## Key decision — both sides get TTS audio

A deck is authored around two languages (`language_a`, `language_b`), not a fixed
"native"/"foreign" pair — the teacher who photographs a German/English list doesn't know in
advance whether the student opening the link is a German speaker learning English or the
reverse. Each student picks their own base ("native") language when they open the deck, so
**either** column can end up being "foreign" for a given session. Consequently both
`text_a` and `text_b` are synthesized to audio at deck-confirmation time — TTS is still
pre-generated once and never called at playback time (same rule as dictations), just for
two columns instead of one.

## Practice modes

The Play button always plays whatever language the student currently has to *produce* —
the answer side — so it follows the mode toggle rather than being pinned to one language
for the whole session:

| Mode | Text shown | Audio played | Student types |
|---|---|---|---|
| Native → Foreign | native text | foreign audio (the answer) | foreign text |
| Foreign → Native | foreign text | native audio (the answer) | native text |

The student can switch modes freely at any point (not fixed per link/assignment), and the
audio switches with it.

Which language is "native" for a session is picked on a language-choice screen shown every
time the practice screen loads — deliberately not persisted (no `localStorage`/prefs), so a
teacher previewing a deck, or a student starting a new lesson on a shared device, always
gets a fresh prompt instead of silently reusing whoever chose last.

## Grading

Reuses `normalizeLenient()` / `sentenceMatches()` from `lib/core/scoring/scoring.dart`
as-is: case/whitespace-insensitive, `ß`→`ss`, but **umlauts (ä/ö/ü) stay distinct from
a/o/u** — matching the existing dictation scoring philosophy (§1.2 of the project spec calls
umlaut correctness a differentiator; silently accepting `Madchen` for `Mädchen` would
undercut that). Grading is done client-side and nothing is persisted — no server round
trip, no spoof risk, since no score is stored anywhere (see Deferred below).

## Photo → cards pipeline

Straight photo → cards → TTS is risky: OCR/column-pairing can misread a word or swap
columns, and the project already has an equivalent risk noted for Whisper transcripts
("always show editable transcript before saving", spec §8). So parsing and audio
generation are two separate steps with a mandatory review in between:

```
Teacher                          parse_card_deck Edge Fn         generate_card_audio Edge Fn
  │ upload photo (base64,           │                                  │
  │ never persisted — same          │                                  │
  │ pattern as ocr_image)           │                                  │
  ├─────────────────────────────────▶                                  │
  │                                 │ Claude (vision, structured        │
  │                                 │ output) → [{text_a, text_b}]      │
  │                                 │ → insert `cards` rows             │
  │                                 │ → card_decks.status = 'draft'     │
  │◀────────────────────────────────┤                                  │
  │ review & edit pairs             │                                  │
  │ (fix typos, delete, add)        │                                  │
  ├──────────────────────────────────────────────────────────────────▶ │
  │                                 │                        Google TTS × 2 per card
  │                                 │                        → card_decks.status='ready'
  │◀──────────────────────────────────────────────────────────────────┤
  │ share link/code                 │                                  │
```

Claude only ever writes `text_a`/`text_b` — no TTS spend happens until the teacher
confirms the reviewed list, exactly mirroring why dictation TTS only fires on save.

### Claude extraction

`parse_card_deck` sends the image plus `language_a`/`language_b` (as human-readable names)
to Claude and asks it to map each pair into `text_a`/`text_b` **by language content**, not by
physical column — teachers' photos aren't guaranteed to have language A on the left. Uses
`output_config.format` (structured outputs, via `@anthropic-ai/sdk`'s `messages.parse()` +
`zodOutputFormat`) rather than "return ONLY JSON" prompting, so the response is guaranteed
parseable — no `on_dictation_save`-style regex fallback needed. This is the first real
Claude API call in this codebase (the "Claude API" sentence-splitting mentioned in the
original spec for `on_dictation_save` was never actually wired up — that function still
splits with regex).

**Model:** `claude-opus-4-7` with adaptive thinking — deliberately not the cheapest option;
misreading a vocabulary word is a worse failure mode here than in free-text OCR, since a
wrong `text_a`/`text_b` becomes the answer key a student is graded against.

---

## Data model — new tables (`supabase/migrations/010_card_decks.sql`)

```sql
card_decks (
  id, owner_id, class_id (nullable),
  title, language_a, language_b,       -- e.g. 'de' / 'en' — no fixed native/foreign
  status text check (status in ('pending','draft','ready','failed')),
  status_error,
  scoring_mode text default 'lenient' check (scoring_mode in ('lenient','strict')),
  share_code unique,                   -- same 6-char generator pattern as dictations
  created_at, updated_at
)

cards (
  id, deck_id, position,
  text_a, text_b,
  audio_a_url, audio_a_duration_ms,    -- TTS for BOTH sides — see "Key decision" above
  audio_b_url, audio_b_duration_ms,
  created_at
)
```

RLS mirrors the existing hardened pattern exactly: owner-only direct `SELECT`/write on
`card_decks`/`cards`, public access exclusively through a new `get_card_deck_by_share_code`
`SECURITY DEFINER` RPC (only returns decks with `status = 'ready'`) — no broad
"has a share_code" policy (see `docs/cr-rls-share-code-access-control.md` for why that
pattern was retired). Storage bucket `card_decks`: public read, service-role-only write —
same policy shape as the `dictations` bucket.

## Deferred (not in this CR)

- **`card_attempts` / results dashboard** — grading is ephemeral (client-side, not
  persisted), matching how `attempts.mistakes` (Phase 3 AI correction) was deferred in the
  original dictations schema. Revisit once teacher-facing card analytics are wanted.
- **Slow-speed audio variant** — dictations gained a `speakingRate=0.5` pre-generated
  variant later (`009_slow_audio_variant.sql`); cards launch with normal-speed audio only.
- **Drag-to-reorder cards** in the review screen — delete/edit/add only for v1.
- **Camera capture** — upload only (`image_picker` gallery/file), consistent with the
  teacher's primary device being desktop/web (spec §1.1); in-app camera capture can follow
  once the app ships on mobile.

## Files added

| File | Purpose |
|---|---|
| `supabase/migrations/010_card_decks.sql` | `card_decks`, `cards`, RLS, RPC, storage bucket |
| `supabase/functions/parse_card_deck/index.ts` | Photo → Claude → draft `cards` rows |
| `supabase/functions/generate_card_audio/index.ts` | Draft `cards` → Google TTS (both sides) → `ready` |
| `lib/features/cards/domain/*.dart` | `CardDeck`, `CardPair`, `CardSide`, practice state |
| `lib/features/cards/data/cards_repository.dart` | Supabase queries + Edge Function triggers |
| `lib/features/cards/presentation/providers/*.dart` | Riverpod providers + practice notifier |
| `lib/features/cards/presentation/screens/*.dart` | Teacher list/create/detail-review, student practice |
| `lib/core/router/app_router.dart` | `/teacher/cards`, `/teacher/cards/new`, `/teacher/cards/:id`, public `/c/:code` |
| `lib/shared/widgets/teacher_shell.dart` | New "Cards" tab |

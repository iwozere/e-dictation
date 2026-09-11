# CR: Quiz Decks — Timed Multiple-Choice Vocabulary Practice

## Summary

A new gamified content type: teachers build decks of vocabulary cards, each with a
correct translation plus 2+ teacher-authored wrong-answer variants. Students practice
under a countdown timer — a word is shown, 3 answer options appear below it (the
correct one plus randomly-picked distractors from the variant pool), and clicking an
option pronounces it aloud, shows correct/incorrect (green/red), then reveals the right
answer before advancing. Unlike the existing Card Decks feature (typed answers, results
never persisted), this is multiple-choice, timed, and **teacher-visible per-student,
per-card results are a first-class requirement**.

## Relationship to Card Decks

This ships as an independent feature (`quiz_decks` / `quiz_cards`, own tables, own
share codes, own nav entry) rather than a mode bolted onto `card_decks`/`cards`. The
underlying idea — bidirectional foreign/native word pairs, pre-generated TTS, anonymous
share-link access — is deliberately the same shape as `card_decks`
(`docs/cr-card-decks-language-flashcards.md`), but the data teacher authors is richer
(a variant pool, not one pair) and the runtime behaviour (timer, lives, persisted
results) is different enough that overloading the existing tables would mean
nullable-everywhere columns and mode-branching throughout the practice screen. The one
integration point is a **one-time import**: a teacher can create a quiz deck *from* an
existing card deck, which copies the word pairs and auto-fills a first pass of
distractors (see below) — after that, the two decks are independent records.

## User stories

> As a teacher, I want to turn a vocabulary list into a fast-paced multiple-choice quiz
> with a countdown, so practice feels like a game instead of a worksheet.

> As a teacher, I want to see which students struggled with which specific words, not
> just a final score, so I know what to re-teach.

> As a student, I want to hear the word I picked pronounced immediately, and see the
> right answer if I got it wrong, so I learn from every click — even under time
> pressure.

---

## Key decisions

### 1. Manual variant authoring (with an optional auto-fill import)

The teacher authors, per card and per direction, one correct answer plus **2 or more**
wrong-answer variants (≥3 options total). At practice time, 3 options are sampled from
that pool (correct one always included) and shown in random order — so a pool larger
than 3 means repeat practice of the same card doesn't always show the same 3 choices.

To lower the authoring cost, a quiz deck can optionally be **generated from an existing
card deck** the teacher owns: each source card's `text_a`/`text_b` becomes the correct
answer, and 2 wrong variants per side are auto-picked by sampling other cards' text in
that same source deck (no AI call needed — it's plain random sampling over data the
teacher already typed). The teacher then reviews/edits/replaces any variant before
confirming, exactly like the review step in the Card Decks OCR pipeline. Requires the
source deck to have ≥3 cards (the card itself plus 2 distinct siblings to draw
distractors from).

### 2. Bidirectional by design — each card carries both sides' variant pools

A card is quizzed foreign→native in some sessions and native→foreign in others
(direction is a session-level choice, see §3), so each card needs an independent,
already-authored variant pool **per side**: `side_a` options (in `language_a`) and
`side_b` options (in `language_b`), each with exactly one `is_correct = true` row. This
avoids special-casing "the correct answer" as a separate field from "the variants" —
the correct answer is simply the option flagged `is_correct` in that side's pool.

### 3. Direction is chosen once per session, not switchable mid-session

Mirroring the language-choice screen in Card Decks, the student picks their native
language before starting. Unlike Card Decks' free-to-flip mode toggle, direction is
**locked for the whole session** here — flipping direction mid-countdown would be
confusing, and results need a single consistent direction to be meaningful per attempt.

### 4. Every option gets pre-generated audio — dedup by text within a deck

Any of the 3 shown options can be clicked and must be pronounced, so **all** options
(correct and wrong) get TTS at confirm time, not just correct answers — a real cost
increase over Card Decks (2 audio files per card) since a card can now need up to
2 × (pool size) files. Because "wrong answers can be correct for some other card" (the
same word `Hund` might be the right answer for one card and a distractor for another),
generation dedupes by `(side, text)` **within the deck**: if a string was already
synthesized for this deck, the existing `audio_url` is reused instead of calling Google
TTS again.

### 5. Timer: fixed start, decays with progress, floor, per-deck configurable

- `timer_initial_secs` (default **10**): countdown for card #1.
- Every `timer_decay_every_n_cards` (default **3**) cards, the countdown shortens by
  `timer_decay_secs` (default **1**), down to `timer_floor_secs` (default **3**).
- Decay is based on **position in the session**, not on accuracy — getting cards wrong
  doesn't reset or slow the ramp.
- Running out of time counts as a **wrong answer**: correct option is revealed
  (highlighted, pronounced), recorded as a miss with `timed_out = true`, then the
  session advances after a short fixed interstitial pause (~1.5s) that is *not* counted
  against the next card's timer.

### 6. Gamification: streak + lives (+ a lightweight leaderboard)

- **Streak counter**: consecutive correct answers, shown live (e.g. "🔥 ×4"); best
  streak is persisted per attempt.
- **Lives**: `lives_enabled` (default on) with `lives_count` (default **3**). A wrong
  answer or timeout consumes a life; hitting 0 ends the session early
  (`ended_reason = 'out_of_lives'`) with whatever score was reached. Teachers can
  disable lives for a lower-pressure "practice until done" variant.
- **Session leaderboard**: after finishing, the student sees the top 5 attempts for
  that deck (name or *(anonymous)*, accuracy, time) — cheap to add since results are
  already persisted (§8), but flag this as the easiest piece to cut if it feels like
  scope creep once the rest is built.
- No numeric "points" formula is stored — raw correct/wrong/streak/time are persisted;
  any point total shown on screen is a client-side display computation so the scoring
  formula stays easy to tune without a migration.

### 7. Session structure

A session is a fixed number of cards (`session_length`, default **20**, teacher
configurable; a special "all cards" value practices the whole deck once, shuffled). If
`session_length` exceeds the deck size, cards repeat within the session (shuffled, not
back-to-back) — each repeat still gets a fresh random 3-option sample, so it doesn't
feel identical.

### 8. Results: persisted, per-student, per-card breakdown

Unlike Card Decks (deliberately ephemeral), this CR requires real teacher-visible
results. Reuses the existing no-account identity pattern
(`docs/cr-student-identification-results.md`): free-text name + optional 4-digit PIN,
hashed client-side, before the session starts. One `quiz_attempts` row per session,
with a `jsonb` per-card answer log (mirrors the existing `attempts.mistakes` jsonb
convention) — no join table needed for the per-card breakdown.

---

## Student flow

1. Open share link (`/q/:shareCode`) → anonymous sign-in, same as dictations/card decks.
2. **Identity screen** — name + optional PIN (reused component from
   `identity_screen.dart`).
3. **Language-choice screen** — pick native language → sets direction for the whole
   session.
4. **Quiz screen**, per card:
   - Prompt word shown (+ optional auto-play of its audio, matching existing "listen"
     affordances).
   - Countdown bar/number starts at the current decayed duration.
   - 3 options rendered below, shuffled order.
   - On click: option pronounced, colored green (correct) or red (incorrect); if
     incorrect, the correct option also highlights green; brief pause; advance.
   - On timeout: treated as incorrect (see §5).
   - Live streak badge + lives remaining (hearts) shown in a header bar.
5. **Summary screen**: score, accuracy, best streak, per-card list of misses, and the
   leaderboard (§6).

## Teacher flow

1. **Create quiz deck** — title, `language_a`/`language_b`, timer/lives/session-length
   settings (all have defaults, all editable later).
2. Choose creation method:
   - **Blank** — add cards manually: per card, type `text_a`/`text_b` plus ≥2 wrong
     variants per side.
   - **From existing card deck** — pick one of their `card_decks`; system copies pairs
     and auto-fills distractors (§1); status becomes `draft` for review.
3. **Review screen** — edit/add/remove variants per card, same UX family as the Card
   Decks review screen; validation blocks confirming until every side has ≥3 options
   with exactly one `is_correct`.
4. **Confirm** → `generate_quiz_audio` Edge Function runs (TTS per unique option text,
   deduped per deck) → status `ready` → share link/code available.
5. **Results screen** (`/teacher/quiz-decks/:id/results`) — same table-plus-expand
   pattern as the dictation results screen: one row per attempt (name, PIN indicator,
   accuracy, best streak, ended reason, submitted time), expandable to the per-card
   answer log so the teacher can see exactly which words tripped a student up, and
   which words are commonly missed **across** students for that deck.

---

## Data model — new tables (`supabase/migrations/012_quiz_decks.sql`)

```sql
quiz_decks (
  id, owner_id, class_id (nullable),
  title, language_a, language_b,
  status text check (status in ('draft','pending','ready','failed')),
  status_error,
  session_length int,                 -- null = whole deck, shuffled
  timer_initial_secs int default 10,
  timer_decay_secs int default 1,
  timer_decay_every_n_cards int default 3,
  timer_floor_secs int default 3,
  lives_enabled boolean default true,
  lives_count int default 3,
  source_card_deck_id uuid references card_decks(id) on delete set null, -- provenance only
  share_code unique,
  created_at, updated_at
)

quiz_cards (
  id, deck_id, position,
  created_at
)

quiz_card_options (
  id, card_id, side text check (side in ('a','b')),
  text, is_correct boolean default false,
  audio_url, audio_duration_ms,
  created_at
  -- DB-enforced: a partial unique index on (card_id, side) where is_correct
  -- guarantees at most one correct option per side; app validation at confirm
  -- time enforces at least 3 rows (1 correct + ≥2 wrong) per (card_id, side).
)

quiz_attempts (
  id, deck_id, student_id,
  student_name, student_pin_hash,     -- same convention as attempts table
  direction text check (direction in ('a_to_b', 'b_to_a')),
  correct_count int, wrong_count int, best_streak int,
  lives_remaining int,                -- null if lives_enabled = false
  ended_reason text check (ended_reason in ('completed', 'out_of_lives', 'abandoned')),
  answers jsonb,   -- [{card_id, option_id, correct, timed_out, time_taken_ms}]
  started_at, submitted_at
)
```

RLS mirrors the hardened `card_decks` pattern: owner-only `SELECT`/write on all four
tables; public read access only through three `SECURITY DEFINER` RPCs —
`get_quiz_deck_by_share_code` (returns `status = 'ready'` decks + cards + a
pre-selected, shuffled 3-option set per side, `is_correct` never included),
`check_quiz_answer` (per-click correctness check, see Security below), and
`submit_quiz_attempt` (final scoring + insert, re-deriving correctness the same way
`submit_attempt()` re-scores dictations rather than trusting the client). A fourth RPC,
`import_quiz_deck_from_card_deck`, is owner-only (not exposed to `anon`) and powers the
"from existing card deck" creation path.

### Security: answer key never reaches the client before it's needed

**Decided: per-click server-side check (option (b) below), confirmed.** Two RPCs split
the responsibility:

- `get_quiz_deck_by_share_code` takes the session's `direction` as a parameter (not
  something decided client-side after a direction-agnostic fetch) — call it once with
  no direction for the pre-direction choice screen (title/card-count only), then again
  once the student has picked one. The **prompt** side's word is returned unambiguously
  per card (there's nothing to hide — it's simply shown/read aloud); the **answer**
  side returns exactly 3 options (correct + 2 random wrong, pre-selected and shuffled
  server-side) with no flag distinguishing which is correct. Deciding the split
  anywhere but the server would mean shipping `is_correct` for *both* sides and
  trusting the client to only look at half of it.
- `check_quiz_answer(option_id)` is called on every click. It looks up `is_correct`
  server-side and returns it plus the correct option's text/audio (for the reveal-on-
  wrong UI) — the client never computes or asserts correctness itself.
- `submit_quiz_attempt` re-derives `correct_count`/`wrong_count`/`best_streak` from the
  raw `(card_id, option_id)` pairs it's given, the same way `submit_attempt()` already
  re-scores dictation answers against `dictation_sentences.text` rather than trusting
  a client-computed score. A tampered client could lie about which `option_id` it
  "clicked" for a card, but cannot lie about whether that specific option is correct.

One accepted trade-off from pre-selecting the 3 options at fetch time: if
`session_length` causes a card to repeat within one session, that repeat shows the
same 3 options (not a fresh sample) — reselecting per-repeat would require exposing
`is_correct` to the client to sample from, which is exactly what this design avoids.
A different session (deck re-fetched) gets a fresh random 3.

## Edge Functions

```
Teacher                    import (Postgres fn, no AI)     generate_quiz_audio Edge Fn
  │ pick source card_deck      │                                  │
  ├────────────────────────────▶ copy cards, sample distractors   │
  │                             │ → quiz_decks.status = 'draft'   │
  │◀────────────────────────────┤                                  │
  │ review & edit variants      │                                  │
  ├───────────────────────────────────────────────────────────────▶│
  │                             │                    Google TTS per unique
  │                             │                    (side, text) in deck
  │                             │                    → status = 'ready'
  │◀────────────────────────────────────────────────────────────────┤
  │ share link/code                                                  │
```

The blank-creation path skips the import step and goes straight to review → confirm →
`generate_quiz_audio`. No Claude/vision call is needed anywhere in this feature — a
cost and complexity win over the Card Decks OCR pipeline, since both creation paths
work from text the teacher already has (typed, or copied from an existing deck).

## Out of scope / Deferred

- **Class-wide leaderboard aggregation** across multiple quiz decks — v1 leaderboard is
  per-deck only.
- **Adaptive difficulty** (e.g. surfacing previously-missed cards more often within a
  session) — v1 sampling is uniform random.
- **Editing a quiz deck after it's `ready`** without a full re-review — v1 requires
  going through review again (and re-running TTS for any changed text) for any edit,
  same as Card Decks' edit story.
- **Multiplayer / live head-to-head sessions** — v1 is solo, asynchronous, same access
  model as every other student-facing screen in the app.
- **Export (CSV/PDF) of quiz results** — same deferral as dictation results.

## Files added

| File | Purpose |
|---|---|
| `supabase/migrations/012_quiz_decks.sql` | `quiz_decks`, `quiz_cards`, `quiz_card_options`, `quiz_attempts`, RLS, RPCs, storage bucket |
| `supabase/functions/generate_quiz_audio/index.ts` | Draft deck → Google TTS per unique `(side, text)` → `ready` |
| `lib/features/quiz/domain/*.dart` | `QuizDeck`, `QuizCard`, `QuizOption`, session/timer state |
| `lib/features/quiz/data/quiz_repository.dart` | Supabase queries, import RPC, `submit_quiz_attempt` call |
| `lib/features/quiz/presentation/providers/*.dart` | Riverpod providers + session notifier (timer, lives, streak) |
| `lib/features/quiz/presentation/screens/*.dart` | Teacher list/create/import/review/results, student language-choice/quiz/summary |
| `lib/core/router/app_router.dart` | `/teacher/quiz-decks`, `/teacher/quiz-decks/new`, `/teacher/quiz-decks/:id`, `/teacher/quiz-decks/:id/results`, public `/q/:code` |
| `lib/shared/widgets/teacher_shell.dart` | New "Quiz" tab |

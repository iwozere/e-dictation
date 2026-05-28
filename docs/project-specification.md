# e-dictation — Project Specification

> **Version:** 1.0  
> **Last updated:** 2026-05-26  
> **Target audience:** Development agent / lead developer

---

## 1. Product Overview

**e-dictation** is a structured dictation platform for language teachers and self-study students. Teachers create dictations from text or voice input; students practice with AI-generated speech that supports sentence-level navigation, adjustable speed, and configurable pauses.

The core insight is that this is **not an audio player** — it is a **smart dictation workflow tool**. Every technical and UX decision follows from that framing.

### 1.1 Target users

| Role | Primary device | Primary need |
|---|---|---|
| Teacher | Desktop/web | Create, organize, and share dictations |
| Student | Mobile + web | Practice dictations at own pace |
| Parent (future) | Web | View child's progress and mistakes |

### 1.2 Initial language focus

- German (primary — strong dictation culture, umlaut correction is a differentiator)
- English (secondary)
- French, Spanish, Italian (Phase 3+)
- Arabic, Japanese, Chinese: explicitly deferred (complex input methods, segmentation)

---

## 2. Core Features by Phase

### Phase 1 — MVP (weeks 1–4)

**Teacher**
- Sign up / sign in (email + Google OAuth)
- Create dictation by pasting text
- Dictation metadata: title, language, difficulty tag
- Sentence splitting (AI-assisted, see §6.2)
- TTS audio pre-generation on save (Google Cloud TTS Neural2)
- Organize dictations into folders/classes
- Share dictation via link or short code

**Student**
- Open dictation via link or code (no account required for basic access)
- Playback controls:
  - Play / pause
  - Speed selector: 0.5×, 0.75×, 1×, 1.25×
  - Skip ±10 seconds
  - Restart from beginning
- Optional free-text answer textarea
- Offline playback (sentence MP3s cached locally after first load)

**Dictation mode toggle** (Phase 1, high priority)
- Hide text completely → reveal sentence-by-sentence after pause
- Turns the player into a genuine exam simulator without extra backend work

### Phase 2 — Enhanced UX (weeks 5–8)

- Teacher voice input: microphone → Whisper STT → editable text → TTS generation
- Sentence-level navigation:
  - Repeat current sentence button
  - Jump to sentence N
  - Configurable pause after each sentence (2 / 5 / 10 sec, teacher-set default, student-overridable)
- Highlight currently spoken sentence
- Hide / partial hint / full transcript modes
- Student accounts (optional sign-up to save progress)
- Class/group entity: one dictation → assigned to 30 students (see §7.1)

### Phase 3 — AI & Analytics (weeks 9–14)

- Student submits typed text after dictation
- AI mistake analysis:
  - Spelling, grammar, punctuation, umlaut errors, noun capitalization (German)
  - Categorized feedback: "3 capitalization errors, 2 umlaut errors"
  - Sentence-level diff highlighting
- Teacher dashboard: per-student and per-class analytics
- Parent view: progress report per child
- Adaptive practice: generate targeted dictation based on recurring errors

### Phase 4 — Growth (post-launch)

- Premium voice customization (ElevenLabs voices as paid option)
- Multilingual expansion (French, Spanish, Italian)
- Export results as PDF
- LMS integrations (Google Classroom, Moodle)
- Public dictation library (teacher opt-in sharing)

---

## 3. Technical Stack

### 3.1 Frontend — Flutter

**Why Flutter:**
- Single codebase for Android, iOS, and Web
- Excellent audio package ecosystem
- Fast MVP iteration

**Key packages:**

| Package | Purpose |
|---|---|
| `just_audio` | Primary audio playback engine |
| `audio_session` | Handles iOS/Safari audio session quirks |
| `flutter_cache_manager` | Offline caching of sentence MP3s |
| `riverpod` | State management (preferred over Bloc/Provider) |
| `supabase_flutter` | Auth, database, storage client |
| `dio` | HTTP client for API calls |

**State model for playback (Riverpod notifier):**
```dart
class PlaybackState {
  final int currentSentenceIndex;
  final double speed;           // 0.5 / 0.75 / 1.0 / 1.25
  final int pauseDurationSecs;  // 2 / 5 / 10
  final bool isPlaying;
  final bool dictationMode;     // hide/reveal toggle
}
```

**Critical Flutter rules:**
- Never use `flutter_tts` (device TTS) — quality varies per device, no pre-generation benefit
- Always serve pre-generated MP3s from Supabase Storage
- Test Safari/iOS audio early — use `audio_session` to configure AVAudioSession correctly
- Sentence MP3s must be cached locally with `flutter_cache_manager` for offline support

### 3.2 Backend — Supabase

| Supabase service | Usage |
|---|---|
| Auth | Email + OAuth (Google), row-level security |
| PostgreSQL | All relational data |
| Storage | Sentence MP3 files (`dictations/{dictation_id}/sentence_{n}.mp3`) |
| Edge Functions | TTS generation trigger, Whisper STT proxy |
| Realtime | Future: live class progress (Phase 3) |

**Why Supabase over Firebase:** Better relational data model, row-level security out of the box, open-source, easier local development.

### 3.3 Speech-to-Text — OpenAI Whisper

Used for teacher voice input (Phase 2).

- API: `https://api.openai.com/v1/audio/transcriptions`
- Model: `whisper-1`
- Excellent German support including punctuation
- Called via Supabase Edge Function (never directly from client)

### 3.4 Text-to-Speech — Google Cloud TTS Neural2

**Voice selection by language:**

| Language | Voice ID |
|---|---|
| German | `de-DE-Neural2-B` (male) or `de-DE-Neural2-C` (female) |
| English | `en-US-Neural2-D` or `en-GB-Neural2-B` |
| French | `fr-FR-Neural2-A` |

**Cost model:**
- Google Neural2: ~$0.016 per 1,000 characters
- Typical dictation (200 words ≈ 1,000 chars): ~$0.016 per dictation
- 10,000 dictations total: ~$160 one-time (audio pre-generated once, cached forever)
- ElevenLabs is ~$0.30/1k chars — 18× more expensive; defer to premium tier only

**Pre-generation strategy (critical for cost and performance):**
1. Teacher saves dictation text
2. Supabase Edge Function splits text into sentences
3. Edge Function calls Google TTS for each sentence → MP3
4. MP3s stored in Supabase Storage
5. Sentence URLs written to `sentences[]` in database
6. TTS never called again unless teacher edits text

### 3.5 Sentence Splitting — Claude API

On dictation save, send full text to Claude with this prompt:

```
Split the following text into dictation sentences.
Preserve all punctuation exactly.
Handle abbreviations correctly (e.g. "Dr.", "z.B.", "bzw.").
Return ONLY a JSON array of strings, no other text.

Text: {teacher_text}
```

Cost: fractions of a cent per dictation. Far more accurate than regex for edge cases (abbreviations, ellipses, quoted speech).

---

## 4. Data Model

### 4.1 Core tables

```sql
-- Users (managed by Supabase Auth, extended here)
profiles (
  id uuid primary key references auth.users,
  role text not null check (role in ('teacher', 'student')),
  display_name text,
  created_at timestamptz default now()
)

-- Class/group entity (important: add in Phase 1 schema even if UI is Phase 2)
classes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id),
  name text not null,
  created_at timestamptz default now()
)

-- Dictations
dictations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references profiles(id),
  class_id uuid references classes(id),  -- nullable
  title text not null,
  language text not null default 'de',
  difficulty text check (difficulty in ('easy', 'medium', 'hard')),
  full_text text not null,
  share_code text unique,                -- 6-char alphanumeric
  default_pause_secs int default 5,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
)

-- Sentence-level data (one row per sentence)
dictation_sentences (
  id uuid primary key default gen_random_uuid(),
  dictation_id uuid references dictations(id) on delete cascade,
  position int not null,
  text text not null,
  audio_url text,                        -- Supabase Storage URL
  duration_ms int,                       -- audio length for UI progress
  created_at timestamptz default now()
)

-- Student attempts
attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references profiles(id),  -- nullable for anonymous
  dictation_id uuid references dictations(id),
  submitted_text text,
  mistakes jsonb,                        -- structured error categories
  score int,                             -- 0–100
  completed_at timestamptz default now()
)
```

**Key schema decision:** `classes` table must be created in Phase 1 even if the UI ships in Phase 2. Retrofitting this relationship later requires a painful migration.

### 4.2 Storage structure

```
supabase-storage/
  dictations/
    {dictation_id}/
      sentence_0.mp3
      sentence_1.mp3
      sentence_2.mp3
      ...
```

---

## 5. Architecture Diagram

```
Flutter App
    │
    ├── Auth (Supabase Auth)
    ├── Read dictation + sentence URLs (Supabase DB)
    ├── Stream/cache MP3s (Supabase Storage → flutter_cache_manager)
    └── Submit attempt text (Supabase DB)

Supabase Edge Functions
    ├── on_dictation_save
    │     ├── Call Claude API → sentence array
    │     ├── Call Google TTS for each sentence → MP3
    │     ├── Upload MP3s to Supabase Storage
    │     └── Write sentence rows to DB
    ├── whisper_transcribe (Phase 2)
    │     └── Proxy teacher audio → OpenAI Whisper → return text
    └── ai_correction (Phase 3)
          └── Compare submitted text vs original → structured mistakes JSON
```

---

## 6. Key UX Decisions

### 6.1 Sentence-level navigation (not audio timestamps)

The player operates on **sentence index**, not audio position. Each sentence is a discrete MP3. This enables:
- Repeat current sentence (replay one MP3)
- Configurable pause between sentences (gap between MP3 playback)
- Jump to sentence N (array index)
- Highlight current sentence (driven by sentence index state)
- Dictation mode reveal (show sentence text only after its audio plays)

Never think of this as "scrubbing a waveform". Think of it as "stepping through a playlist with pauses".

### 6.2 Dictation mode (Phase 1, high priority)

Toggle between:
| Mode | Text visibility |
|---|---|
| `listen_only` | Text fully hidden |
| `reveal_after` | Each sentence revealed after audio plays |
| `partial_hint` | First/last word visible |
| `full_transcript` | All text visible |

Default: `listen_only` for students, `full_transcript` for teachers editing.

### 6.3 Pause after sentence

- Teacher sets default (2 / 5 / 10 sec) on dictation
- Student can override in session
- Implemented as a simple `Future.delayed()` between sentence MP3s
- This is the **killer feature** — no competing product does this well

---

## 7. Monetization

### 7.1 Freemium tiers

| Feature | Free | Premium (teacher) |
|---|---|---|
| Dictations | 10 | Unlimited |
| Basic playback | ✓ | ✓ |
| Dictation mode | ✓ | ✓ |
| Class/group sharing | — | ✓ |
| Student progress dashboard | — | ✓ |
| AI mistake analysis | — | ✓ |
| Analytics export | — | ✓ |
| Premium voices (ElevenLabs) | — | ✓ |

**Note:** Class sharing and dashboards (no AI required) should be the **first paid feature** — teachers will pay for these before AI corrections are ready.

### 7.2 Pricing suggestion

- Free: 10 dictations, no student tracking
- Teacher Pro: €8/month — unlimited dictations, class management, progress dashboard
- Teacher Pro + AI: €14/month — adds AI correction and analytics

---

## 8. Technical Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| TTS cost explosion (many replays) | High | Pre-generate once on save; never re-call TTS on playback |
| Safari/iOS audio issues | Medium | Use `audio_session` package; test on real device in week 1 |
| Flutter Web audio inconsistencies | Medium | Test early; `just_audio` + `audio_session` handles most cases |
| Whisper accuracy on noisy input | Low-Medium | Always show editable transcript to teacher before saving |
| Copyrighted teacher content | Legal | ToS must prohibit copyrighted material; add length limit (500 words Phase 1) |
| Supabase Edge Function cold starts | Low | Keep functions warm; pre-generation is async/non-blocking for teacher UX |

---

## 9. Development Roadmap

### Phase 1 — MVP (weeks 1–4)

**Goal:** Teacher can create a dictation; student can play it.

- [ ] Supabase project setup (auth, DB schema including `classes` table, storage buckets)
- [ ] Flutter project scaffold (Riverpod, Supabase Flutter, just_audio, audio_session)
- [ ] Teacher auth (email + Google)
- [ ] Create dictation screen (paste text, set metadata)
- [ ] Edge Function: sentence split via Claude API
- [ ] Edge Function: TTS generation via Google Cloud Neural2
- [ ] Student player screen (sentence playlist, speed control, pause config)
- [ ] Dictation mode toggle (hide/reveal)
- [ ] Share via link / short code
- [ ] Offline caching with flutter_cache_manager
- [ ] Deploy: Supabase hosted, Flutter Web to Vercel or Firebase Hosting

### Phase 2 — Enhanced UX (weeks 5–8)

- [ ] Teacher microphone input → Whisper STT Edge Function → editable transcript
- [ ] Sentence repeat button
- [ ] Configurable pause after sentence (UI + player logic)
- [ ] Sentence highlight during playback
- [ ] Class/group entity UI (create class, assign dictation)
- [ ] Student accounts (optional, saves progress locally and to DB)
- [ ] Folder/library organization for teachers

### Phase 3 — AI & Analytics (weeks 9–14)

- [ ] Student text submission after dictation
- [ ] AI correction Edge Function (Claude API diff + categorization)
- [ ] Mistake display UI (sentence diff, error categories)
- [ ] Teacher dashboard (per-student results, class averages)
- [ ] Parent access role
- [ ] Adaptive practice suggestion engine

### Phase 4 — Growth (post-launch)

- [ ] ElevenLabs voice option (premium tier)
- [ ] Language expansion (French, Spanish, Italian)
- [ ] PDF export of results
- [ ] Public dictation library
- [ ] LMS integrations

---

## 10. Deployment

| Service | Platform | Notes |
|---|---|---|
| Database + Auth + Storage | Supabase Cloud (free → Pro) | One project, eu-central-1 region (GDPR) |
| Edge Functions | Supabase Edge (Deno) | TTS generation, Whisper proxy, AI correction |
| Flutter Web | Vercel or Netlify | CI/CD from GitHub main branch |
| Flutter Android | Google Play Store | Release build from GitHub Actions |
| Flutter iOS | Apple App Store | Release build from GitHub Actions |
| CDN for MP3s | Supabase Storage CDN | Built-in, no extra config needed |

**Environment variables required (Edge Functions):**
```
GOOGLE_TTS_API_KEY
OPENAI_API_KEY       # Whisper
ANTHROPIC_API_KEY    # Sentence splitting + AI correction
SUPABASE_SERVICE_ROLE_KEY
```

---

## 11. Product Positioning

**This is a teacher/homework tool, not a consumer language app.**

That distinction determines everything:
- Marketing channel: teacher communities, school networks, not app store SEO
- Pricing: school/class subscription, not individual freemium
- Feature priority: sharing, class management, progress reporting over gamification
- Competition: Google Forms + voice notes (beatable), not Duolingo (different market)

Do not pivot to self-study consumer app until teacher market is validated.

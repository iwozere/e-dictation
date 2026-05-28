# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**e-dictation** is a structured dictation platform for language teachers (create) and students (practice). The full product specification is in `docs/project-specification.md`. Read it before making architectural decisions.

**Stack:** Flutter (Web-first, then Android/iOS) · Supabase (Auth + PostgreSQL + Storage + Edge Functions) · Google Cloud TTS Neural2 · Claude API (sentence splitting) · OpenAI Whisper (Phase 2 STT)

---

## Commands

### Flutter

```bash
flutter pub get                          # install / sync dependencies
flutter pub run build_runner build       # one-shot code generation (Riverpod, etc.)
flutter pub run build_runner watch       # code-gen in watch mode during development
flutter analyze                          # static analysis (treat warnings as errors)
dart format .                            # format all Dart files
flutter run -d chrome                    # run web app in Chrome
flutter build web                        # production web build
flutter test                             # run all tests
flutter test test/path/to/test_file.dart # run a single test file
flutter test --name "widget name"        # run tests matching a name pattern
```

### Supabase (local dev)

```bash
supabase start                           # start local Supabase stack (Docker)
supabase stop                            # stop local stack
supabase db reset                        # reset DB and re-apply all migrations
supabase db push                         # push migrations to remote project
supabase functions serve on_dictation_save --env-file .env.local  # run an Edge Function locally
supabase functions deploy on_dictation_save                        # deploy to Supabase cloud
```

### Environment files

- `.env.local` — Supabase Edge Function secrets (never commit)
- `lib/core/config/app_config.dart` — compile-time Flutter config (reads from `--dart-define`)

---

## Repository Layout (target structure)

```
lib/
  core/
    config/          # AppConfig, environment constants
    router/          # go_router setup (shell routes, guards)
    theme/           # ThemeData, color tokens
    utils/           # shared pure helpers
  features/
    auth/            # sign-in, sign-up, profile
    dictations/      # teacher CRUD: create, edit, list, folders/classes
    player/          # student player: sentence playlist, speed, pause, dictation mode
    classes/         # class/group entity (DB schema Phase 1, full UI Phase 1)
    attempts/        # student submission + mistake display (Phase 3)
  shared/
    widgets/         # reusable UI components
    providers/       # cross-feature Riverpod providers (auth state, supabase client)

supabase/
  migrations/        # numbered SQL migration files (001_initial_schema.sql, …)
  functions/
    on_dictation_save/   # sentence split (Claude) + TTS generation (Google)
    whisper_transcribe/  # Phase 2: teacher voice → Whisper → text
    ai_correction/       # Phase 3: submitted text diff + categorized mistakes

test/
  features/          # mirrors lib/features/ structure
  tmp_*.dart         # temporary debug/repro scripts (not committed)
```

Each feature directory (`auth/`, `dictations/`, `player/`, etc.) follows this internal layout:
```
<feature>/
  data/        # Supabase repository classes
  domain/      # models, enums, pure business logic
  presentation/ # screens, widgets, Riverpod notifiers
```

---

## Architecture: Key Concepts

### Player = sentence playlist, not audio scrubber

The player operates on **sentence index**, not a continuous waveform. Each sentence is a discrete MP3 stored in Supabase Storage. The `PlaybackNotifier` steps through `dictation_sentences[]` with a configurable `Future.delayed()` pause between items. Never model this as timestamp-based seeking.

```dart
// Core playback state (Riverpod AsyncNotifier)
class PlaybackState {
  final int currentSentenceIndex;
  final double speed;            // 0.5 / 0.75 / 1.0 / 1.25
  final int pauseDurationSecs;   // 2 / 5 / 10
  final bool isPlaying;
  final bool dictationMode;      // listen_only | reveal_after | partial_hint | full_transcript
}
```

### TTS is pre-generated, never on-the-fly

1. Teacher saves dictation → triggers `on_dictation_save` Edge Function
2. Edge Function calls Claude API → sentence array
3. Edge Function calls Google TTS Neural2 per sentence → MP3
4. MP3s uploaded to `supabase-storage/dictations/{dictation_id}/sentence_{n}.mp3`
5. `dictation_sentences` rows written with `audio_url` + `duration_ms`

**TTS is never called at playback time.** Regenerate only when teacher edits text.

### Anonymous student access

Students open a dictation via share link or 6-char code with no account required. The flow:
1. Flutter calls `supabase.auth.signInAnonymously()`
2. RLS policy grants `SELECT` on `dictations` and `dictation_sentences` where `share_code` matches
3. Anonymous session upgrades to full account on optional sign-up

### State management

Use **Riverpod 2.x with code generation** (`riverpod_annotation`). Prefer `@riverpod` annotated notifiers over manual `StateNotifierProvider`. Run `build_runner` after modifying providers.

---

## Data Model

Five core tables (full DDL in `supabase/migrations/001_initial_schema.sql`):

| Table | Key columns |
|---|---|
| `profiles` | `id` (fk auth.users), `role` (teacher/student) |
| `classes` | `owner_id`, `name` — created in Phase 1 schema even if UI is Phase 1 |
| `dictations` | `owner_id`, `class_id` (nullable), `share_code` (6-char unique), `default_pause_secs` |
| `dictation_sentences` | `dictation_id`, `position`, `text`, `audio_url`, `duration_ms` |
| `attempts` | `student_id` (nullable for anon), `dictation_id`, `submitted_text`, `mistakes` (jsonb), `score` |

---

## Coding Conventions (Dart/Flutter)

### Naming
- Files and directories: `snake_case`
- Classes: `PascalCase`
- Variables, functions, parameters: `camelCase`
- Constants: `lowerCamelCase` (Dart convention) or `SCREAMING_SNAKE` for truly global constants
- Private members: prefix with `_`

### Imports
Order: dart core → Flutter SDK → pub packages → project imports (`package:e_dictates/…`). Separate groups with a blank line. Use absolute `package:` imports, not relative `../` imports.

### Logging
Use the `logging` package. Initialise per file:
```dart
import 'package:logging/logging.dart';
final _log = Logger('FeatureName.ClassName');
```
Use lazy interpolation: `_log.fine('loaded %s sentences', count)` — avoid string interpolation (`$var`) in log calls that run in hot paths.

### Error handling
Never use bare `catch (e)` without logging. Catch specific exception types. In repositories, convert Supabase/network errors into domain-level `Failure` sealed classes before they reach the presentation layer.

### Docstrings
Use `///` doc comments on all public classes and methods. First line: one-sentence summary. Follow with `///` blank line then parameters if non-obvious.

---

## Submodule Documentation (from AGENTS.md convention, adapted)

Each new feature module under `lib/features/<name>/` should ship with:
- `README.md` — purpose, key classes, usage example
- `docs/Design.md` — architecture choices and data flow for the feature
- `docs/Tasks.md` — implementation checklist and known TODOs

Temporary debugging scripts go in `test/` with a `tmp_` prefix and must not be committed.

---

## Critical Constraints

- **Never use `flutter_tts`** — device TTS quality is inconsistent; always serve pre-generated MP3s from Supabase Storage.
- **Safari/iOS audio** — configure `audio_session` (AVAudioSession) before any playback; test on real device early.
- **Offline caching** — all sentence MP3s must be cached via `flutter_cache_manager` after first load.
- **Edge Function secrets** — `GOOGLE_TTS_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY` live only in Supabase Edge Function environment; never in Flutter client code.
- **Phase 1 hard limit** — 500-word maximum per dictation (enforced client-side and Edge Function).
- **Share codes** — stored uppercase, 6-char alphanumeric, generated server-side.

---

## Git Conventions (from AGENTS.md)

Commit messages use imperative mood: `"Add player pause-between-sentences logic"` not `"Added…"`. Reference issues where applicable: `"Fix #42 – handle empty sentence array from Claude"`.

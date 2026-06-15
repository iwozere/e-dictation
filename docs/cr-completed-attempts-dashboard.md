# CR: Completed Attempts Dashboard

**Date:** 2026-06-15  
**Status:** Draft  
**Scope:** Database · Flutter (player + teacher shell)

---

## Summary

Students currently complete dictations and their answers are saved to the `attempts` table, but:

- There is no **start timestamp** — only `completed_at` exists.
- The teacher has no dedicated navigation entry for results; the per-dictation results page (`/teacher/dictations/:id/results`) is only reachable by opening a specific dictation.
- There is no single view listing **all** completed attempts across all dictations.

This CR adds a `started_at` column, captures it in the app, and introduces a new **Results** tab in the teacher shell showing every completed attempt in a flat list with a preview action.

---

## Requirements

### 1. Database — add `started_at` column

Add a nullable `timestamptz started_at` column to the `attempts` table via a new migration.

```sql
alter table public.attempts
  add column if not exists started_at timestamptz;
```

Nullable so that existing rows (which have no start time) remain valid.

---

### 2. App — capture start timestamp

**When:** The moment the student's identity is confirmed and the player UI becomes active (i.e., the identity dialog is dismissed and the first sentence is ready to play). This is the earliest point at which the student is committed to the dictation session.

**How:** Store `DateTime.now()` in `PlayerScreen` state when the identity panel transitions to the typing/listening view. Pass it to `_saveAttempt()` on Finish and include it in the `saveAttempt()` repository call.

Changes required:
- `lib/features/player/presentation/screens/player_screen.dart` — add `DateTime? _startedAt` field; set it on identity confirmation; pass to `_saveAttempt()`.
- `lib/features/attempts/data/attempts_repository.dart` — add `startedAt` parameter to `saveAttempt()`; write it to the new column.
- `lib/features/attempts/domain/attempt.dart` — add `startedAt: DateTime?` field; parse from JSON.

---

### 3. Teacher shell — new "Results" tab

Add a third entry to `TeacherShell._tabs` in `lib/shared/widgets/teacher_shell.dart`:

| icon (inactive) | icon (active) | label | route |
|---|---|---|---|
| `Icons.bar_chart_outlined` | `Icons.bar_chart` | Results | `/teacher/results/all` |

Route must be registered in `app_router.dart` under the teacher shell so the nav rail stays visible.

---

### 4. New screen — All Attempts (`AllAttemptsScreen`)

**Route:** `/teacher/results/all`  
**File:** `lib/features/attempts/presentation/screens/all_attempts_screen.dart`

#### Data

Reuse/extend `allAttemptsProvider` (or add a new provider) to fetch all attempts for the authenticated teacher across all dictations. Each row must include:

| Field | Source |
|---|---|
| Dictation title | join with `dictations` table (already done in `listAllAttempts`) |
| Student name | `attempts.student_name` (show "Anonymous" if null) |
| Started | `attempts.started_at` (show "—" if null, for old records) |
| Finished | `attempts.completed_at` |
| Score | `attempts.score_correct` / `attempts.score_total` |
| Answers | `attempts.answers` (JSONB) |

Sort: newest `completed_at` first.

#### UI — list

Each row is a card/tile showing:

```
[Student name]          [Dictation title]
Started: 15 Jun 14:32   Finished: 15 Jun 14:48   Score: 8/10   [preview icon]
```

- **Student name** — bold; "Anonymous" in grey italic if null.
- **Dictation title** — secondary text, truncated to 1 line.
- **Started / Finished** — formatted as `d MMM HH:mm` (same `intl` `DateFormat` already used elsewhere). Show `—` for `started_at` when null.
- **Score** — `X/Y` with the same color coding used in `_ResultsPanel` (green = 100 %, orange ≥ 60 %, red < 60 %).
- **Preview icon** (`Icons.preview_outlined` or `Icons.visibility_outlined`) — tappable; opens the attempt detail view (see §5).

#### Empty state

When no attempts exist yet, show a centered illustration + text: *"No completed dictations yet."*

#### Loading / error states

Standard `AsyncValue` handling: spinner while loading, error message with retry button on failure.

---

### 5. Attempt detail view — student-style results

When the teacher taps the preview icon on a row, the results must be shown **in exactly the same visual format as the student sees** upon completion.

The student's post-completion view is rendered by `_ResultsPanel` inside `player_screen.dart` (lines ~543–668). This widget is currently private and embedded in `PlayerScreen`. It must be extracted into a standalone reusable widget.

**Refactor:**

Extract `_ResultsPanel` (and its helper `_WordDiffRow` / LCS logic) into:

```
lib/features/attempts/presentation/widgets/student_results_view.dart
```

`StudentResultsView` accepts:
```dart
class StudentResultsView extends StatelessWidget {
  const StudentResultsView({
    super.key,
    required this.sentences,   // List<DictationSentence>
    required this.answers,     // Map<int, String>
  });
  ...
}
```

It renders the same score header and per-sentence word-diff breakdown that the student sees.

**In `PlayerScreen`:** Replace the inline `_ResultsPanel` with `StudentResultsView(sentences: ..., answers: ...)`.

**In `AllAttemptsScreen`:** When the preview icon is tapped, show a modal bottom sheet or full-screen route containing `StudentResultsView` populated from the tapped attempt's `sentences` and `answers`.

> **Note:** `sentences` are not currently fetched by `listAllAttempts`. The repository call will need to join or separately fetch `dictation_sentences` for the selected attempt's `dictation_id`. Consider a new `getAttemptDetail(attemptId)` repository method that returns the attempt row joined with its sentences.

---

## Out of Scope

- Filtering / searching the attempts list (future).
- Pagination (acceptable for now given expected volume; add when list grows).
- Editing or deleting attempts (teacher read-only).
- Requiring student name before starting (name stays optional; shown as "Anonymous").

---

## Open Questions

1. **Attempt detail navigation:** Should the attempt detail open as a modal bottom sheet (stays on the list page) or push a new route (enables deep-linking)? Recommendation: bottom sheet for now, simpler to implement and sufficient for read-only preview.

2. **Sentences for old attempts:** Attempts saved before this CR have no `started_at`. For the detail view, sentences are always fetchable from `dictation_sentences` by `dictation_id`, so the preview will still work for historical records.

---

## Affected Files

| File | Change |
|---|---|
| `supabase/migrations/007_add_started_at.sql` | New migration — `alter table attempts add column started_at timestamptz` |
| `lib/features/player/presentation/screens/player_screen.dart` | Capture `_startedAt`; pass to `_saveAttempt()`; replace inline `_ResultsPanel` with `StudentResultsView` |
| `lib/features/attempts/data/attempts_repository.dart` | Add `startedAt` param to `saveAttempt()`; add `getAttemptDetail()` |
| `lib/features/attempts/domain/attempt.dart` | Add `startedAt: DateTime?` field |
| `lib/features/attempts/presentation/widgets/student_results_view.dart` | New — extracted from `_ResultsPanel` in player_screen |
| `lib/features/attempts/presentation/screens/all_attempts_screen.dart` | New screen |
| `lib/features/attempts/presentation/providers/attempts_provider.dart` | Add/extend provider for all-attempts list + detail fetch |
| `lib/shared/widgets/teacher_shell.dart` | Add Results tab |
| `lib/core/router/app_router.dart` | Register `/teacher/results/all` route |

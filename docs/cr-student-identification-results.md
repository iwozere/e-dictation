# CR: Student Identification & Teacher Results Dashboard

## Problem

All students access a dictation via the same share link. Submitted attempts are stored
anonymously, so the teacher cannot tell which student produced which result and cannot
give personalised feedback.

## User Stories

**Teacher:** I want to see all attempts for a dictation, labelled with the student's
name, so I can give individual feedback and track progress over time.

**Student:** I want to identify myself before starting a dictation so my results are
visible to the teacher under my name. I should be able to skip this if I prefer.

---

## Decision: Name + optional PIN (no accounts)

Students enter a free-text name and an optional 4-digit PIN before the dictation starts.
No registration, no email, no password.

**Why no accounts for now:**
- Highest-friction approach; young students lose passwords.
- Teachers can start collecting results immediately with zero onboarding.
- Consistent name + PIN across sessions gives enough continuity for classroom use.

**Accepted limitation (known evil):**
A student can enter another student's name. The optional PIN raises the bar slightly —
you need to know the name *and* the PIN — but does not prevent determined cheating.
This is acceptable for formative classroom use.

---

## Student Flow

1. Student opens the share link (`/d/:shareCode`).
2. **New screen: "Who are you?"** shown before the player loads.
   - Name field — optional, placeholder `Your name (optional)`
   - PIN field — optional, 4 digits, placeholder `PIN (optional)`
   - **Start** button — always enabled; both fields can be left blank.
3. Name and PIN are persisted in `localStorage` so returning students on the same
   device don't retype them.
4. When **Start** is tapped:
   - PIN is hashed client-side (SHA-256) before being sent; raw PIN never leaves the
     device.
   - `student_name` and `student_pin_hash` are passed into the attempt when it is
     saved.

---

## Data Model

### `attempts` table — two new columns

```sql
ALTER TABLE attempts
  ADD COLUMN student_name     text,         -- nullable; null = anonymous
  ADD COLUMN student_pin_hash text;         -- nullable; SHA-256 of 4-digit PIN
```

No new tables. No foreign keys. The name is free text intentionally — no roster
required on the teacher side.

### RLS

Existing RLS already scopes attempts to the dictation owner. No new policies needed;
the two new columns inherit the same rules.

---

## Teacher Results Screen

### Route
`/teacher/dictations/:id/results`

Linked from the dictation detail screen via a **"Results"** button (next to the
existing Edit button).

### Layout

Header row:
- Dictation title
- Attempt count: `12 attempts · 4 unique students`

Attempts table (all attempts, flat, newest first):

| Name | PIN | Score | Submitted |
|------|-----|-------|-----------|
| Lena | ✓ | 8 / 10 | 4 Jun 14:32 |
| Max | — | 5 / 10 | 4 Jun 14:45 |
| *(anonymous)* | — | 3 / 10 | 4 Jun 15:01 |

- **PIN column**: ✓ if `student_pin_hash` is set, — otherwise. Helps the teacher
  assess how reliable the identity is.
- **Name**: falls back to *(anonymous)* if null.
- Clicking a row expands it to show the sentence-by-sentence diff (same view the
  student sees on the results screen).
- Sortable by score (asc/desc) and by date.
- No grouping for now; teacher filters visually.

---

## Screens & Components

| New / Changed | Description |
|---|---|
| `lib/features/player/presentation/screens/identity_screen.dart` | New screen: name + PIN form |
| `lib/features/player/presentation/screens/player_screen.dart` | Show `IdentityScreen` before loading the player when `shareCode != null` |
| `lib/features/attempts/presentation/screens/results_screen.dart` | New screen: teacher results dashboard |
| `lib/features/attempts/data/attempts_repository.dart` | `saveAttempt` takes `studentName` + `studentPinHash`; `listAttempts(dictationId)` for teacher |
| `lib/features/attempts/presentation/providers/attempts_provider.dart` | Riverpod providers for save + list |
| `lib/core/router/app_router.dart` | Add `/teacher/dictations/:id/results` route |
| `lib/core/utils/pin_hash.dart` | `hashPin(String pin) → String` — SHA-256, returns hex string |
| `supabase/migrations/00X_attempts_student_identity.sql` | `ALTER TABLE attempts ADD COLUMN …` |

---

## PIN Hashing

SHA-256 of 4 decimal digits. No salt (4-digit PIN space is only 10 000 values, a
rainbow table trivially covers it regardless). Hashing is still correct practice — it
signals intent, prevents accidental logging of PINs, and keeps the raw value off the
wire and out of the database.

Use the `crypto` pub package (already in the Dart ecosystem, zero new native deps).

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

String hashPin(String pin) =>
    sha256.convert(utf8.encode(pin)).toString();
```

---

## Out of Scope

- Student accounts / login
- Teacher-managed class roster with pre-assigned PINs
- Per-student progress over multiple dictations (requires consistent name+PIN)
- Export (CSV / PDF) of results
- Attempt deletion by teacher

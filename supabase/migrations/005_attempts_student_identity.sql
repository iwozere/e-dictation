-- ============================================================
-- Migration: 005_attempts_student_identity.sql
-- Adds student name + PIN hash columns to attempts.
-- Adds teacher read policy so teachers can view results for
-- dictations they own.
-- ============================================================

alter table public.attempts
  add column if not exists student_name     text,
  add column if not exists student_pin_hash text,
  add column if not exists score_correct    int,
  add column if not exists score_total      int,
  add column if not exists answers          jsonb;

-- Teachers can read all attempts for dictations they own.
create policy "attempts: dictation owner read" on public.attempts
  for select using (
    exists (
      select 1 from public.dictations d
      where d.id = dictation_id and d.owner_id = auth.uid()
    )
  );

-- Any authenticated user (including anonymous) can insert an attempt
-- where student_id matches their auth uid.
-- The existing "attempts: own rows" for-all policy covers inserts too,
-- but make this explicit for clarity.
create policy "attempts: insert own" on public.attempts
  for insert with check (auth.uid() = student_id);

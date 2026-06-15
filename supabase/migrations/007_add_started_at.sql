-- Add started_at to attempts so the teacher can see how long each student took.
-- Nullable so that existing rows remain valid.
alter table public.attempts
  add column if not exists started_at timestamptz;

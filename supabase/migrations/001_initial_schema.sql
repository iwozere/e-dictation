-- ============================================================
-- e-dictation — initial schema
-- Migration: 001_initial_schema.sql
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ============================================================
-- profiles — extends Supabase Auth users
-- ============================================================
create table public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  role        text not null check (role in ('teacher', 'student')) default 'student',
  display_name text,
  created_at  timestamptz not null default now()
);

-- Auto-create a basic profile row when a user signs up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'student'),
    new.raw_user_meta_data->>'display_name'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- classes — teacher-defined groups
-- ============================================================
create table public.classes (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create index classes_owner_idx on public.classes(owner_id);

-- ============================================================
-- dictations
-- ============================================================
create table public.dictations (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null references public.profiles(id) on delete cascade,
  class_id            uuid references public.classes(id) on delete set null,
  title               text not null,
  language            text not null default 'de',
  difficulty          text check (difficulty in ('easy', 'medium', 'hard')),
  full_text           text not null,
  share_code          text unique,
  default_pause_secs  int not null default 5 check (default_pause_secs in (2, 5, 10)),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index dictations_owner_idx  on public.dictations(owner_id);
create index dictations_class_idx  on public.dictations(class_id);
create index dictations_code_idx   on public.dictations(share_code);

-- Generate a unique 6-char alphanumeric share code on insert.
--
-- Previous implementation tried to catch unique_violation inside the trigger
-- body, but that exception is only raised after the trigger returns (when the
-- actual INSERT executes), so the inner BEGIN…EXCEPTION block was dead code
-- and the loop always exited on the first iteration without verifying
-- uniqueness. Fixed to use an explicit SELECT-for-existence check instead.
create or replace function public.generate_share_code()
returns trigger language plpgsql as $$
declare
  code text;
  attempts int := 0;
begin
  loop
    code := upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    -- Verify the code is not already taken before committing to it.
    if not exists (
      select 1 from public.dictations where share_code = code
    ) then
      new.share_code := code;
      return new;
    end if;
    attempts := attempts + 1;
    if attempts > 10 then
      raise exception 'Could not generate unique share code after 10 attempts';
    end if;
  end loop;
end;
$$;

create trigger set_share_code
  before insert on public.dictations
  for each row execute procedure public.generate_share_code();

-- Auto-update updated_at timestamp.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger dictations_updated_at
  before update on public.dictations
  for each row execute procedure public.set_updated_at();

-- ============================================================
-- dictation_sentences — one row per sentence, with audio URL
-- ============================================================
create table public.dictation_sentences (
  id            uuid primary key default gen_random_uuid(),
  dictation_id  uuid not null references public.dictations(id) on delete cascade,
  position      int not null,
  text          text not null,
  audio_url     text,           -- Supabase Storage public URL
  duration_ms   int,            -- audio length in milliseconds
  created_at    timestamptz not null default now(),
  unique (dictation_id, position)
);

create index sentences_dictation_idx on public.dictation_sentences(dictation_id, position);

-- ============================================================
-- attempts — student submissions
-- ============================================================
create table public.attempts (
  id              uuid primary key default gen_random_uuid(),
  student_id      uuid references public.profiles(id) on delete set null, -- nullable for anon
  dictation_id    uuid not null references public.dictations(id) on delete cascade,
  submitted_text  text,
  mistakes        jsonb,         -- structured error categories (Phase 3)
  score           int check (score between 0 and 100),
  completed_at    timestamptz not null default now()
);

create index attempts_student_idx    on public.attempts(student_id);
create index attempts_dictation_idx  on public.attempts(dictation_id);

-- ============================================================
-- Row-Level Security
-- ============================================================

alter table public.profiles          enable row level security;
alter table public.classes           enable row level security;
alter table public.dictations        enable row level security;
alter table public.dictation_sentences enable row level security;
alter table public.attempts          enable row level security;

-- profiles: each user can read/update their own row.
create policy "profiles: own row" on public.profiles
  for all using (auth.uid() = id);

-- classes: owner has full access.
create policy "classes: owner crud" on public.classes
  for all using (auth.uid() = owner_id);

-- dictations: owner has full access.
create policy "dictations: owner crud" on public.dictations
  for all using (auth.uid() = owner_id);

-- dictations: anyone (including anonymous) can read a dictation by share_code.
create policy "dictations: public read by share_code" on public.dictations
  for select using (share_code is not null);

-- dictation_sentences: readable if the parent dictation is readable.
create policy "sentences: readable with dictation" on public.dictation_sentences
  for select using (
    exists (
      select 1 from public.dictations d
      where d.id = dictation_id
        and (d.owner_id = auth.uid() or d.share_code is not null)
    )
  );

-- dictation_sentences: owner can insert/update/delete.
create policy "sentences: owner write" on public.dictation_sentences
  for all using (
    exists (
      select 1 from public.dictations d
      where d.id = dictation_id and d.owner_id = auth.uid()
    )
  );

-- attempts: students insert/read their own attempts (anonymous included).
create policy "attempts: own rows" on public.attempts
  for all using (auth.uid() = student_id);

-- ============================================================
-- Storage bucket
-- ============================================================

-- Create the dictations bucket (public read, authenticated write).
insert into storage.buckets (id, name, public)
values ('dictations', 'dictations', true)
on conflict (id) do nothing;

create policy "dictations storage: public read" on storage.objects
  for select using (bucket_id = 'dictations');

create policy "dictations storage: service role write" on storage.objects
  for insert with check (
    bucket_id = 'dictations' and auth.role() = 'service_role'
  );

create policy "dictations storage: service role delete" on storage.objects
  for delete using (
    bucket_id = 'dictations' and auth.role() = 'service_role'
  );

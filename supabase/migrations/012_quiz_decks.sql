-- ============================================================
-- e-dictation — quiz decks (timed multiple-choice vocabulary practice)
-- Migration: 012_quiz_decks.sql
-- See docs/cr-quiz-decks-timed-multiple-choice.md for the full design.
--
-- A quiz deck is a separate content type from card_decks (010): each card
-- carries its own pool of answer options *per side* (language_a / language_b),
-- one flagged is_correct, so a card can be quizzed in either direction without
-- re-authoring. Unlike card_decks, results are persisted and teacher-visible
-- (quiz_attempts), and the answer key is never shipped to the client up
-- front — see the "answer key" RPCs below and the CR doc's Security section.
-- ============================================================

-- ============================================================
-- quiz_decks
-- ============================================================
create table public.quiz_decks (
  id                        uuid primary key default gen_random_uuid(),
  owner_id                  uuid not null references public.profiles(id) on delete cascade,
  class_id                  uuid references public.classes(id) on delete set null,
  title                     text not null,
  language_a                text not null,
  language_b                text not null,
  status                    text not null default 'draft'
                              check (status in ('draft', 'pending', 'ready', 'failed')),
  status_error              text,
  session_length            int
                              check (session_length is null or session_length > 0),
  timer_initial_secs        int not null default 10 check (timer_initial_secs > 0),
  timer_decay_secs          int not null default 1  check (timer_decay_secs >= 0),
  timer_decay_every_n_cards int not null default 3  check (timer_decay_every_n_cards > 0),
  timer_floor_secs          int not null default 3  check (timer_floor_secs > 0),
  lives_enabled             boolean not null default true,
  lives_count               int not null default 3 check (lives_count > 0),
  -- Provenance only when created via the "from existing card deck" import
  -- path (see import_quiz_deck_from_card_deck below) — no live sync after.
  source_card_deck_id       uuid references public.card_decks(id) on delete set null,
  share_code                text unique,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint quiz_decks_floor_below_initial
    check (timer_floor_secs <= timer_initial_secs)
);

create index quiz_decks_owner_idx on public.quiz_decks(owner_id);
create index quiz_decks_class_idx on public.quiz_decks(class_id);
create index quiz_decks_code_idx  on public.quiz_decks(share_code);

-- Share-code generator, mirrors generate_card_deck_share_code (010).
create or replace function public.generate_quiz_deck_share_code()
returns trigger language plpgsql as $$
declare
  code text;
  attempts int := 0;
begin
  loop
    code := upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    if not exists (
      select 1 from public.quiz_decks where share_code = code
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

create trigger set_quiz_deck_share_code
  before insert on public.quiz_decks
  for each row execute procedure public.generate_quiz_deck_share_code();

-- Reuses the generic public.set_updated_at() trigger function from 001.
create trigger quiz_decks_updated_at
  before update on public.quiz_decks
  for each row execute procedure public.set_updated_at();

-- ============================================================
-- quiz_cards — just an ordering shell; the actual text lives in
-- quiz_card_options (see "Key decisions" §2 in the CR doc for why the
-- correct answer isn't a separate text_a/text_b column here).
-- ============================================================
create table public.quiz_cards (
  id          uuid primary key default gen_random_uuid(),
  deck_id     uuid not null references public.quiz_decks(id) on delete cascade,
  position    int not null,
  created_at  timestamptz not null default now(),
  unique (deck_id, position)
);

create index quiz_cards_deck_idx on public.quiz_cards(deck_id, position);

-- ============================================================
-- quiz_card_options — one correct + 2+ wrong options, per side, per card.
-- ============================================================
create table public.quiz_card_options (
  id                  uuid primary key default gen_random_uuid(),
  card_id             uuid not null references public.quiz_cards(id) on delete cascade,
  side                text not null check (side in ('a', 'b')),
  text                text not null,
  is_correct          boolean not null default false,
  audio_url           text,   -- Supabase Storage public URL
  audio_duration_ms   int,
  created_at          timestamptz not null default now()
);

create index quiz_card_options_card_idx on public.quiz_card_options(card_id, side);

-- DB-enforced invariant: at most one correct option per (card, side). The
-- "at least 3 options per side" half of the invariant is app-level, checked
-- by the review screen before it allows confirming a deck.
create unique index quiz_card_options_one_correct_idx
  on public.quiz_card_options(card_id, side)
  where is_correct;

-- ============================================================
-- quiz_attempts — persisted, teacher-visible results (unlike card_decks,
-- which is deliberately ephemeral — see that CR's Deferred section).
-- ============================================================
create table public.quiz_attempts (
  id                  uuid primary key default gen_random_uuid(),
  deck_id             uuid not null references public.quiz_decks(id) on delete cascade,
  student_id          uuid not null references auth.users(id) on delete cascade,
  student_name        text,
  student_pin_hash    text,
  direction           text not null check (direction in ('a_to_b', 'b_to_a')),
  correct_count       int not null default 0,
  wrong_count         int not null default 0,
  best_streak         int not null default 0,
  lives_remaining     int,   -- null when the deck has lives disabled
  ended_reason        text not null default 'completed'
                        check (ended_reason in ('completed', 'out_of_lives', 'abandoned')),
  -- [{card_id, option_id, correct, timed_out, time_taken_ms}, ...] — per-card
  -- breakdown for the teacher results screen, mirrors attempts.mistakes.
  answers             jsonb not null default '[]'::jsonb,
  started_at          timestamptz,
  submitted_at        timestamptz not null default now()
);

create index quiz_attempts_deck_idx on public.quiz_attempts(deck_id, submitted_at desc);

-- ============================================================
-- Row-Level Security
-- ============================================================

alter table public.quiz_decks        enable row level security;
alter table public.quiz_cards        enable row level security;
alter table public.quiz_card_options enable row level security;
alter table public.quiz_attempts     enable row level security;

create policy "quiz_decks: owner crud" on public.quiz_decks
  for all using (auth.uid() = owner_id);

create policy "quiz_cards: readable by deck owner" on public.quiz_cards
  for select using (
    exists (
      select 1 from public.quiz_decks d
      where d.id = deck_id and d.owner_id = auth.uid()
    )
  );

create policy "quiz_cards: owner write" on public.quiz_cards
  for all using (
    exists (
      select 1 from public.quiz_decks d
      where d.id = deck_id and d.owner_id = auth.uid()
    )
  );

create policy "quiz_card_options: readable by deck owner" on public.quiz_card_options
  for select using (
    exists (
      select 1 from public.quiz_cards c
      join public.quiz_decks d on d.id = c.deck_id
      where c.id = card_id and d.owner_id = auth.uid()
    )
  );

create policy "quiz_card_options: owner write" on public.quiz_card_options
  for all using (
    exists (
      select 1 from public.quiz_cards c
      join public.quiz_decks d on d.id = c.deck_id
      where c.id = card_id and d.owner_id = auth.uid()
    )
  );

-- quiz_attempts: readable by the owning teacher (all rows for their decks)
-- and by the student who submitted it (their own row) — same shape as the
-- hardened `attempts` policies from 008. No insert/update/delete policy:
-- the only write path is submit_quiz_attempt() below (SECURITY DEFINER).
create policy "quiz_attempts: teacher select" on public.quiz_attempts
  for select using (
    exists (
      select 1 from public.quiz_decks d
      where d.id = deck_id and d.owner_id = auth.uid()
    )
  );

create policy "quiz_attempts: own select" on public.quiz_attempts
  for select using (auth.uid() = student_id);

-- ============================================================
-- quiz_pick_options — internal helper, NOT granted to anon/authenticated.
-- Called only from inside get_quiz_deck_by_share_code (SECURITY DEFINER),
-- which runs with the function owner's privileges, so no explicit grant is
-- needed for that nested call. Selects the correct option for (card, side)
-- plus 2 random wrong ones, shuffled — the client never sees a full pool or
-- an is_correct flag, only "these 3, in random order".
-- ============================================================
create or replace function public.quiz_pick_options(p_card_id uuid, p_side text)
returns json
language sql
stable
set search_path = public
as $$
  select coalesce(
    json_agg(
      json_build_object(
        'id', t.id,
        'text', t.text,
        'audio_url', t.audio_url,
        'audio_duration_ms', t.audio_duration_ms
      )
      order by t.rnd
    ),
    '[]'::json
  )
  from (
    (select id, text, audio_url, audio_duration_ms, random() as rnd
       from public.quiz_card_options
      where card_id = p_card_id and side = p_side and is_correct
      limit 1)
    union all
    (select id, text, audio_url, audio_duration_ms, random() as rnd
       from public.quiz_card_options
      where card_id = p_card_id and side = p_side and not is_correct
      order by random()
      limit 2)
  ) t
$$;

-- ============================================================
-- quiz_pick_prompt — internal helper (not granted). Whichever side ends up
-- as the *prompt* this session has nothing to hide — the word is simply
-- shown/read aloud, there's no guessing involved — so this returns the
-- single correct option unambiguously, unlike quiz_pick_options above.
-- ============================================================
create or replace function public.quiz_pick_prompt(p_card_id uuid, p_side text)
returns json
language sql
stable
set search_path = public
as $$
  select json_build_object(
    'id', id, 'text', text, 'audio_url', audio_url, 'audio_duration_ms', audio_duration_ms
  )
  from public.quiz_card_options
  where card_id = p_card_id and side = p_side and is_correct
  limit 1
$$;

-- ============================================================
-- get_quiz_deck_by_share_code — public read of a *ready* deck.
--
-- p_direction is deliberately a parameter here rather than something
-- decided purely client-side after a direction-agnostic fetch: which side
-- is the *prompt* (revealed, unambiguous) and which is the *answer*
-- (3-reduced, is_correct hidden) can only be decided once direction is
-- known, and computing that split anywhere but the server would mean
-- shipping is_correct for both sides and letting the client throw half of
-- it away — the same leak the CR doc's Security section rules out.
--
-- Call it once with p_direction = null for the pre-direction language/
-- direction-choice screen (title, card count, language names only — no
-- card content is revealed yet), then again with the student's chosen
-- direction to actually load the session.
--
-- Looks up the target deck first (single row, by share_code) and only then
-- aggregates its cards via subqueries correlated on that one deck's id —
-- deliberately not a `group by deck_id` over the whole `quiz_cards` table,
-- which would call `quiz_pick_options`/`quiz_pick_prompt` for every quiz
-- deck in the system on every single fetch.
-- ============================================================
create or replace function public.get_quiz_deck_by_share_code(
  p_share_code text,
  p_direction text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result       json;
  v_prompt_side  text;
  v_answer_side  text;
  v_deck         public.quiz_decks;
begin
  if p_direction is not null and p_direction not in ('a_to_b', 'b_to_a') then
    raise exception 'invalid_direction' using errcode = 'P0001';
  end if;

  if p_direction = 'a_to_b' then
    v_prompt_side := 'a';
    v_answer_side := 'b';
  elsif p_direction = 'b_to_a' then
    v_prompt_side := 'b';
    v_answer_side := 'a';
  end if;

  select * into v_deck
    from public.quiz_decks
   where share_code = upper(p_share_code) and status = 'ready';

  if v_deck.id is null then
    raise exception 'quiz_deck_not_found' using errcode = 'P0002';
  end if;

  select json_build_object(
    'id', v_deck.id,
    'title', v_deck.title,
    'language_a', v_deck.language_a,
    'language_b', v_deck.language_b,
    'status', v_deck.status,
    'session_length', v_deck.session_length,
    'timer_initial_secs', v_deck.timer_initial_secs,
    'timer_decay_secs', v_deck.timer_decay_secs,
    'timer_decay_every_n_cards', v_deck.timer_decay_every_n_cards,
    'timer_floor_secs', v_deck.timer_floor_secs,
    'lives_enabled', v_deck.lives_enabled,
    'lives_count', v_deck.lives_count,
    'share_code', v_deck.share_code,
    'card_count', (
      select count(*) from public.quiz_cards where deck_id = v_deck.id
    ),
    'cards', coalesce((
      select json_agg(
        case
          when v_prompt_side is null then
            json_build_object('id', qc.id, 'position', qc.position)
          else
            json_build_object(
              'id', qc.id,
              'position', qc.position,
              'prompt', public.quiz_pick_prompt(qc.id, v_prompt_side),
              'options', public.quiz_pick_options(qc.id, v_answer_side)
            )
        end
        order by qc.position
      )
      from public.quiz_cards qc
      where qc.deck_id = v_deck.id
    ), '[]'::json)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.get_quiz_deck_by_share_code(text, text)
  to authenticated, anon;

-- ============================================================
-- check_quiz_answer — called on every click. Looks up correctness
-- server-side and returns the correct option (text/audio) for the reveal-
-- on-wrong UI, so the client never has to know or assert is_correct itself.
-- Only answerable against a *ready* deck, so a leaked/guessed option id
-- can't be used to probe a draft deck's answer key mid-authoring.
-- ============================================================
create or replace function public.check_quiz_answer(p_option_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card_id     uuid;
  v_side        text;
  v_is_correct  boolean;
  v_correct     json;
begin
  select o.card_id, o.side, o.is_correct
    into v_card_id, v_side, v_is_correct
    from public.quiz_card_options o
    join public.quiz_cards c on c.id = o.card_id
    join public.quiz_decks d on d.id = c.deck_id
   where o.id = p_option_id and d.status = 'ready';

  if v_card_id is null then
    raise exception 'quiz_option_not_found' using errcode = 'P0002';
  end if;

  select json_build_object(
    'id', id, 'text', text, 'audio_url', audio_url, 'audio_duration_ms', audio_duration_ms
  ) into v_correct
    from public.quiz_card_options
   where card_id = v_card_id and side = v_side and is_correct;

  return json_build_object(
    'is_correct', v_is_correct,
    'correct_option', v_correct
  );
end;
$$;

grant execute on function public.check_quiz_answer(uuid)
  to authenticated, anon;

-- ============================================================
-- submit_quiz_attempt — the only INSERT path for quiz_attempts. Re-derives
-- correctness from the raw (card_id, option_id) pairs rather than trusting
-- any correct/wrong counts computed by the client — same principle as
-- submit_attempt() (008) re-scoring against dictation_sentences.text.
--
-- p_answers shape: [{"card_id": uuid, "option_id": uuid|null, "timed_out":
-- bool, "time_taken_ms": int}, ...]. option_id is null on a timeout.
-- ============================================================
create or replace function public.submit_quiz_attempt(
  p_deck_id       uuid,
  p_direction     text,
  p_answers       jsonb,
  p_student_name  text default null,
  p_pin_hash      text default null,
  p_started_at    timestamptz default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id      uuid;
  v_deck            public.quiz_decks;
  v_answer          jsonb;
  v_card_id         uuid;
  v_option_id       uuid;
  v_timed_out       boolean;
  v_is_correct      boolean;
  v_correct_count   int := 0;
  v_wrong_count     int := 0;
  v_streak          int := 0;
  v_best_streak     int := 0;
  v_lives_remaining int;
  v_ended_reason    text;
  v_answers_out     jsonb := '[]'::jsonb;
  v_attempt_id      uuid;
  v_result          json;
begin
  v_student_id := auth.uid();
  if v_student_id is null then
    raise exception 'Unauthorized' using errcode = 'P0401';
  end if;

  select * into v_deck from public.quiz_decks where id = p_deck_id and status = 'ready';
  if v_deck.id is null then
    raise exception 'quiz_deck_not_found' using errcode = 'P0002';
  end if;

  if p_direction not in ('a_to_b', 'b_to_a') then
    raise exception 'invalid_direction' using errcode = 'P0001';
  end if;

  v_lives_remaining := case when v_deck.lives_enabled then v_deck.lives_count else null end;

  for v_answer in select * from jsonb_array_elements(p_answers)
  loop
    v_card_id   := (v_answer->>'card_id')::uuid;
    v_option_id := nullif(v_answer->>'option_id', '')::uuid;
    v_timed_out := coalesce((v_answer->>'timed_out')::boolean, false);
    v_is_correct := false;

    if v_option_id is not null then
      -- Re-derive correctness from the DB; card_id must match too, so a
      -- client can't pass an option_id from a different card in this deck.
      select o.is_correct into v_is_correct
        from public.quiz_card_options o
        join public.quiz_cards c on c.id = o.card_id
       where o.id = v_option_id
         and o.card_id = v_card_id
         and c.deck_id = p_deck_id;
      v_is_correct := coalesce(v_is_correct, false);
    end if;

    if v_is_correct and not v_timed_out then
      v_correct_count := v_correct_count + 1;
      v_streak := v_streak + 1;
      v_best_streak := greatest(v_best_streak, v_streak);
    else
      v_wrong_count := v_wrong_count + 1;
      v_streak := 0;
      if v_lives_remaining is not null then
        v_lives_remaining := greatest(v_lives_remaining - 1, 0);
      end if;
    end if;

    v_answers_out := v_answers_out || jsonb_build_object(
      'card_id', v_card_id,
      'option_id', v_option_id,
      'correct', v_is_correct and not v_timed_out,
      'timed_out', v_timed_out,
      'time_taken_ms', (v_answer->>'time_taken_ms')::int
    );
  end loop;

  -- ended_reason is derived, not trusted from the client: 'out_of_lives'
  -- only if this attempt's own recomputed lives actually hit zero.
  v_ended_reason := case when v_lives_remaining = 0 then 'out_of_lives' else 'completed' end;

  insert into public.quiz_attempts (
    deck_id, student_id, student_name, student_pin_hash, direction,
    correct_count, wrong_count, best_streak, lives_remaining,
    ended_reason, answers, started_at
  ) values (
    p_deck_id, v_student_id, p_student_name, p_pin_hash, p_direction,
    v_correct_count, v_wrong_count, v_best_streak, v_lives_remaining,
    v_ended_reason, v_answers_out, p_started_at
  )
  returning id into v_attempt_id;

  select row_to_json(a) into v_result from public.quiz_attempts a where a.id = v_attempt_id;
  return v_result;
end;
$$;

grant execute on function public.submit_quiz_attempt(uuid, text, jsonb, text, text, timestamptz)
  to authenticated, anon;

-- ============================================================
-- import_quiz_deck_from_card_deck — owner-only (NOT granted to anon).
-- Copies word pairs from an existing card_decks/cards deck the caller owns
-- into an already-created (blank, 'draft') quiz deck, auto-picking 2
-- distractors per side from sibling cards in the source deck. Plain
-- relational sampling — no AI call, unlike card_decks' Claude-based OCR
-- pipeline, since the source text is already typed and trusted.
-- ============================================================
create or replace function public.import_quiz_deck_from_card_deck(
  p_quiz_deck_id uuid,
  p_source_card_deck_id uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller        uuid := auth.uid();
  v_quiz_owner    uuid;
  v_source_owner  uuid;
  v_source_count  int;
  v_card          record;
  v_distractor    record;
  v_new_card_id   uuid;
  v_position      int := 0;
  v_card_count    int := 0;
begin
  if v_caller is null then
    raise exception 'Unauthorized' using errcode = 'P0401';
  end if;

  select owner_id into v_quiz_owner from public.quiz_decks where id = p_quiz_deck_id;
  select owner_id into v_source_owner from public.card_decks where id = p_source_card_deck_id;

  if v_quiz_owner is null or v_source_owner is null
     or v_quiz_owner <> v_caller or v_source_owner <> v_caller then
    raise exception 'Forbidden' using errcode = 'P0403';
  end if;

  select count(*) into v_source_count
    from public.cards where deck_id = p_source_card_deck_id;
  if v_source_count < 3 then
    raise exception 'source_deck_too_small' using errcode = 'P0001';
  end if;

  for v_card in
    select id, position, text_a, text_b from public.cards
     where deck_id = p_source_card_deck_id
     order by position
  loop
    insert into public.quiz_cards (deck_id, position)
    values (p_quiz_deck_id, v_position)
    returning id into v_new_card_id;

    insert into public.quiz_card_options (card_id, side, text, is_correct)
    values (v_new_card_id, 'a', v_card.text_a, true),
           (v_new_card_id, 'b', v_card.text_b, true);

    for v_distractor in
      select text_a, text_b from public.cards
       where deck_id = p_source_card_deck_id and id <> v_card.id
       order by random()
       limit 2
    loop
      insert into public.quiz_card_options (card_id, side, text, is_correct)
      values (v_new_card_id, 'a', v_distractor.text_a, false),
             (v_new_card_id, 'b', v_distractor.text_b, false);
    end loop;

    v_position := v_position + 1;
    v_card_count := v_card_count + 1;
  end loop;

  update public.quiz_decks
     set status = 'draft', status_error = null, source_card_deck_id = p_source_card_deck_id
   where id = p_quiz_deck_id;

  return json_build_object('success', true, 'card_count', v_card_count);
end;
$$;

grant execute on function public.import_quiz_deck_from_card_deck(uuid, uuid)
  to authenticated;

-- ============================================================
-- Storage bucket — quiz option audio. Same policy shape as the card_decks
-- bucket (010): public read, service-role-only write (the Edge Function
-- uses the service role key, bypassing these policies for its own writes).
-- ============================================================

insert into storage.buckets (id, name, public)
values ('quiz_decks', 'quiz_decks', true)
on conflict (id) do nothing;

create policy "quiz_decks storage: public read" on storage.objects
  for select using (bucket_id = 'quiz_decks');

create policy "quiz_decks storage: service role write" on storage.objects
  for insert with check (
    bucket_id = 'quiz_decks' and auth.role() = 'service_role'
  );

create policy "quiz_decks storage: service role delete" on storage.objects
  for delete using (
    bucket_id = 'quiz_decks' and auth.role() = 'service_role'
  );

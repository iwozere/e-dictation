-- ============================================================
-- e-dictation — card decks (photo-to-flashcard language pairs)
-- Migration: 010_card_decks.sql
-- See docs/cr-card-decks-language-flashcards.md for the full design.
--
-- A deck is authored around two languages (language_a / language_b), not a
-- fixed native/foreign pair — a student picks their own base language when
-- they open the share link, so either column can end up "foreign" for a
-- given session. Both text_a and text_b get pre-generated TTS audio as a
-- result (see the CR doc's "Key decision" section).
--
-- RLS follows the hardened pattern from 002_rls_share_code_hardening.sql
-- directly: owner-only direct SELECT/write, public access only through a
-- SECURITY DEFINER RPC scoped to the exact share_code supplied.
-- ============================================================

-- ============================================================
-- card_decks
-- ============================================================
create table public.card_decks (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  class_id      uuid references public.classes(id) on delete set null,
  title         text not null,
  language_a    text not null,
  language_b    text not null,
  status        text not null default 'pending'
                  check (status in ('pending', 'draft', 'ready', 'failed')),
  status_error  text,
  scoring_mode  text not null default 'lenient'
                  check (scoring_mode in ('lenient', 'strict')),
  share_code    text unique,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index card_decks_owner_idx on public.card_decks(owner_id);
create index card_decks_class_idx on public.card_decks(class_id);
create index card_decks_code_idx  on public.card_decks(share_code);

-- Share-code generator, mirrors public.generate_share_code() (001) — kept as
-- a separate function/trigger pair since that one is wired to the
-- dictations table specifically (checks `dictations.share_code`).
create or replace function public.generate_card_deck_share_code()
returns trigger language plpgsql as $$
declare
  code text;
  attempts int := 0;
begin
  loop
    code := upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    if not exists (
      select 1 from public.card_decks where share_code = code
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

create trigger set_card_deck_share_code
  before insert on public.card_decks
  for each row execute procedure public.generate_card_deck_share_code();

-- Reuses the generic public.set_updated_at() trigger function from 001.
create trigger card_decks_updated_at
  before update on public.card_decks
  for each row execute procedure public.set_updated_at();

-- ============================================================
-- cards — one row per pair, with audio URLs for BOTH sides
-- ============================================================
create table public.cards (
  id                  uuid primary key default gen_random_uuid(),
  deck_id             uuid not null references public.card_decks(id) on delete cascade,
  position            int not null,
  text_a              text not null,
  text_b              text not null,
  audio_a_url         text,   -- Supabase Storage public URL, TTS in language_a
  audio_a_duration_ms int,
  audio_b_url         text,   -- Supabase Storage public URL, TTS in language_b
  audio_b_duration_ms int,
  created_at          timestamptz not null default now(),
  unique (deck_id, position)
);

create index cards_deck_idx on public.cards(deck_id, position);

-- ============================================================
-- Row-Level Security
-- ============================================================

alter table public.card_decks enable row level security;
alter table public.cards      enable row level security;

create policy "card_decks: owner crud" on public.card_decks
  for all using (auth.uid() = owner_id);

create policy "cards: readable by deck owner" on public.cards
  for select using (
    exists (
      select 1 from public.card_decks d
      where d.id = deck_id and d.owner_id = auth.uid()
    )
  );

create policy "cards: owner write" on public.cards
  for all using (
    exists (
      select 1 from public.card_decks d
      where d.id = deck_id and d.owner_id = auth.uid()
    )
  );

-- Public read of a *ready* deck by share_code — mirrors
-- get_dictation_by_share_code (002). Draft/pending/failed decks are never
-- returned here: a student link never exposes an unreviewed answer key.
create or replace function public.get_card_deck_by_share_code(p_share_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result json;
begin
  select row_to_json(d) into v_result
  from (
    select
      dk.*,
      coalesce(
        json_agg(c order by c.position),
        '[]'::json
      ) as cards
    from public.card_decks dk
    left join public.cards c on c.deck_id = dk.id
    where dk.share_code = upper(p_share_code) and dk.status = 'ready'
    group by dk.id
  ) d;

  if v_result is null then
    raise exception 'card_deck_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

grant execute on function public.get_card_deck_by_share_code(text)
  to authenticated, anon;

-- ============================================================
-- Storage bucket — card audio only. The teacher's source photo is sent as
-- base64 straight to parse_card_deck and discarded, same as ocr_image; it is
-- never written to Storage, so no client-side upload policy is needed here.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('card_decks', 'card_decks', true)
on conflict (id) do nothing;

create policy "card_decks storage: public read" on storage.objects
  for select using (bucket_id = 'card_decks');

create policy "card_decks storage: service role write" on storage.objects
  for insert with check (
    bucket_id = 'card_decks' and auth.role() = 'service_role'
  );

create policy "card_decks storage: service role delete" on storage.objects
  for delete using (
    bucket_id = 'card_decks' and auth.role() = 'service_role'
  );

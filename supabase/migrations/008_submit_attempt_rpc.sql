-- ============================================================
-- e-dictation — server-side attempt scoring
-- Migration: 008_submit_attempt_rpc.sql
--
-- Problem: scores were computed client-side and submitted directly
-- to `attempts`. Any user with dev tools could POST score=100.
--
-- Changes:
--   1. normalize_lenient() — helper mirroring scoring.dart logic.
--   2. scoring_mode column on dictations (lenient | strict).
--   3. submit_attempt() SECURITY DEFINER RPC — the only authorised
--      INSERT path. Receives raw answers, scores server-side.
--   4. Tighten RLS: block direct client INSERT; retain SELECT.
-- ============================================================

-- 1. Helper: lenient normalization.
--    Mirrors scoring.dart normalizeLenient():
--      lowercase → ß→ss → strip non-[a-z0-9äöü\s] → trim.
create or replace function public.normalize_lenient(s text)
returns text
language sql
immutable strict
set search_path = public
as $$
  select trim(
    regexp_replace(
      replace(lower(s), 'ß', 'ss'),
      '[^a-z0-9äöü\s]',
      '',
      'g'
    )
  )
$$;

-- 2. scoring_mode on dictations.
alter table public.dictations
  add column if not exists scoring_mode text not null default 'lenient'
    check (scoring_mode in ('lenient', 'strict'));

-- 3. submit_attempt — SECURITY DEFINER so it can INSERT bypassing RLS,
--    but only after verifying the caller and the dictation.
--
--    Parameters:
--      p_dictation_id  uuid        — dictation being attempted
--      p_answers       jsonb       — {"0":"answer","1":"answer",...}
--                                    keys are sentence positions (0-based strings)
--      p_student_name  text        — display name entered before starting
--      p_pin_hash      text        — SHA-256 of student PIN (client-hashed;
--                                    Sprint 2 replaces with server-side salt)
--      p_started_at    timestamptz — when identity was confirmed
--      p_scoring_mode  text        — override; null = use dictation default
--
--    Returns the inserted attempt row as JSON.
create or replace function public.submit_attempt(
  p_dictation_id  uuid,
  p_answers       jsonb,
  p_student_name  text        default null,
  p_pin_hash      text        default null,
  p_started_at    timestamptz default null,
  p_scoring_mode  text        default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id    uuid;
  v_scoring_mode  text;
  v_score_correct int := 0;
  v_score_total   int := 0;
  v_score         int;
  v_attempt_id    uuid;
  v_result        json;
  v_answer        text;
  v_pos           int;
  v_text          text;
begin
  -- Caller must have an authenticated session (anonymous sessions have a uid).
  v_student_id := auth.uid();
  if v_student_id is null then
    raise exception 'Unauthorized' using errcode = 'P0401';
  end if;

  -- Dictation must be publicly accessible (has share_code) or caller owns it.
  if not exists (
    select 1 from public.dictations
     where id = p_dictation_id
       and (share_code is not null or owner_id = v_student_id)
  ) then
    raise exception 'dictation_not_found' using errcode = 'P0002';
  end if;

  -- Resolve scoring mode: param → dictation default → 'lenient'.
  if p_scoring_mode in ('lenient', 'strict') then
    v_scoring_mode := p_scoring_mode;
  else
    select coalesce(scoring_mode, 'lenient')
      into v_scoring_mode
      from public.dictations
     where id = p_dictation_id;
  end if;

  -- Score each sentence.
  for v_pos, v_text in
    select position, text
      from public.dictation_sentences
     where dictation_id = p_dictation_id
     order by position
  loop
    v_score_total := v_score_total + 1;
    v_answer := trim(p_answers->>(v_pos::text));

    if v_answer is not null and length(v_answer) > 0 then
      if v_scoring_mode = 'strict' then
        if v_answer = trim(v_text) then
          v_score_correct := v_score_correct + 1;
        end if;
      else
        if normalize_lenient(v_answer) = normalize_lenient(v_text) then
          v_score_correct := v_score_correct + 1;
        end if;
      end if;
    end if;
  end loop;

  v_score := case
    when v_score_total > 0
    then round((v_score_correct::numeric / v_score_total) * 100)
    else 0
  end;

  -- Insert (SECURITY DEFINER bypasses the RLS restriction added below).
  insert into public.attempts (
    dictation_id, student_id, student_name, student_pin_hash,
    answers, score_correct, score_total, score, started_at
  ) values (
    p_dictation_id, v_student_id, p_student_name, p_pin_hash,
    p_answers, v_score_correct, v_score_total, v_score, p_started_at
  )
  returning id into v_attempt_id;

  select row_to_json(a) into v_result
    from public.attempts a
   where a.id = v_attempt_id;

  return v_result;
end;
$$;

grant execute on function public.submit_attempt(uuid, jsonb, text, text, timestamptz, text)
  to authenticated, anon;

-- 4. Tighten RLS on attempts.
--
--    Drop the permissive for-all policy and the explicit insert policy
--    that together allowed clients to INSERT arbitrary scores.
--    Replace with a SELECT-only policy; all inserts now go through
--    submit_attempt() which uses SECURITY DEFINER.
drop policy if exists "attempts: own rows"   on public.attempts;
drop policy if exists "attempts: insert own" on public.attempts;
drop policy if exists "attempts: own select" on public.attempts;

create policy "attempts: own select" on public.attempts
  for select using (auth.uid() = student_id);

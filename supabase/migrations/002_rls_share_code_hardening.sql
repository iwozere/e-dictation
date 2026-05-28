-- ============================================================
-- e-dictation — RLS hardening: scope share-code access to known codes
-- Migration: 002_rls_share_code_hardening.sql
--
-- Problem: the previous "dictations: public read by share_code" policy
-- allowed any session with a valid JWT to enumerate ALL dictations that
-- have a non-null share_code, regardless of whether the caller actually
-- knows that code.  This leaks every teacher's dictation titles, full
-- text, and sentences to any authenticated or anonymous user.
--
-- Fix (Option A from CR docs/cr-rls-share-code-access-control.md):
--   1. Drop the overly-broad policy.
--   2. Add a SECURITY DEFINER function that accepts a share code and
--      returns exactly the matching dictation + sentences — nothing more.
--   3. Grant execute to authenticated and anon roles.
--
-- After this migration:
--   • Direct SELECT on public.dictations is restricted to row owners.
--   • Direct SELECT on public.dictation_sentences by non-owners is also
--     blocked (the sentences policy sub-select on dictations returns
--     nothing for non-owners once the broad dictation policy is gone).
--   • Public / anonymous access flows exclusively through
--     get_dictation_by_share_code(), which validates the exact code.
-- ============================================================

-- 1. Drop the overly-broad read policy.
drop policy if exists "dictations: public read by share_code" on public.dictations;

-- 2. SECURITY DEFINER accessor — runs with elevated privileges so it can
--    bypass RLS internally, but only ever returns the single dictation
--    whose share_code matches the supplied value.
--
--    `set search_path = public` prevents search_path injection attacks.
create or replace function public.get_dictation_by_share_code(p_share_code text)
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
      d.*,
      coalesce(
        json_agg(s order by s.position),
        '[]'::json
      ) as dictation_sentences
    from public.dictations d
    left join public.dictation_sentences s on s.dictation_id = d.id
    where d.share_code = upper(p_share_code)
    group by d.id
  ) d;

  if v_result is null then
    raise exception 'dictation_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

-- 3. Grant execute to both authenticated sessions (students with accounts)
--    and the anon role (anonymous sessions created via signInAnonymously).
grant execute on function public.get_dictation_by_share_code(text)
  to authenticated, anon;

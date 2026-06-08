-- ============================================================
-- e-dictation — Student-facing attempt history
-- Migration: 006_student_attempt_history.sql
--
-- Problem: students practise anonymously (signInAnonymously), so their
-- auth.uid() is NOT stable across devices / cleared storage. The existing
-- "attempts: own rows" policy (auth.uid() = student_id) therefore cannot
-- reliably return a returning student's past attempts.
--
-- The durable identity a student supplies is their name + 4-digit PIN
-- (stored as student_name + student_pin_hash). This migration adds a
-- SECURITY DEFINER accessor that returns exactly the attempts matching a
-- supplied name + PIN hash — including the dictation title and the
-- dictation's sentences, so the client can render the per-sentence
-- mistake breakdown without separately reading the (RLS-protected)
-- dictations table.
--
-- Only students who set a PIN can retrieve history; name alone is too
-- guessable to gate access on.
-- ============================================================

create or replace function public.get_student_attempts(
  p_name text,
  p_pin_hash text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result json;
begin
  -- Both a name and a PIN hash are required; a name on its own is
  -- guessable and would leak other students' answers.
  if p_name is null or length(trim(p_name)) = 0 or p_pin_hash is null then
    raise exception 'name_and_pin_required' using errcode = 'P0001';
  end if;

  select coalesce(
           json_agg(row_to_json(a) order by a.completed_at desc),
           '[]'::json
         )
  into v_result
  from (
    select
      att.id,
      att.dictation_id,
      att.student_name,
      att.student_pin_hash,
      att.score_correct,
      att.score_total,
      att.answers,
      att.completed_at,
      d.title as dictation_title,
      coalesce(
        (
          select json_agg(s order by s.position)
          from public.dictation_sentences s
          where s.dictation_id = d.id
        ),
        '[]'::json
      ) as sentences
    from public.attempts att
    join public.dictations d on d.id = att.dictation_id
    where att.student_name = p_name
      and att.student_pin_hash = p_pin_hash
  ) a;

  return v_result;
end;
$$;

-- Both anonymous sessions and signed-in students may look up their history.
grant execute on function public.get_student_attempts(text, text)
  to authenticated, anon;

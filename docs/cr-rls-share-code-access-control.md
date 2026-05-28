# CR: Harden RLS — Scope Share-Code Access to Known Codes Only

**Status:** Implemented (2026-05-27)  
**Priority:** High (data leakage — all published dictations readable by any authenticated user)  
**Discovered:** Code review, 2026-05-27  
**Affects:** `supabase/migrations/001_initial_schema.sql` · `lib/features/dictations/data/dictations_repository.dart`

---

## Problem

The current RLS policy that grants public read access to dictations is:

```sql
-- supabase/migrations/001_initial_schema.sql, line 166
create policy "dictations: public read by share_code" on public.dictations
  for select using (share_code is not null);
```

**What it does:** allows any authenticated or anonymous Supabase session to
`SELECT` from `public.dictations` as long as the row has a non-null
`share_code` — regardless of whether the requesting user actually knows that
code.

**What it should do:** allow a session to read a dictation only if it can
prove it knows the share code for that specific dictation.

### Concrete attack

1. Anonymous student legitimately receives share code `ABC123`.
2. Student (or an HTTP client using the student's JWT) issues:
   ```sql
   SELECT * FROM dictations WHERE share_code IS NOT NULL;
   ```
   via the Supabase REST/PostgREST endpoint — no filter on `share_code` value.
3. The policy passes every row where `share_code IS NOT NULL` → student
   receives **all teachers' dictations**, including full text, titles, class
   assignments, and sentence data (via the joined `dictation_sentences` policy
   which inherits the same parent access check).

The Flutter client always filters by the specific code, but RLS cannot enforce
what filter the client chooses to apply. Any user with a valid JWT and network
access can bypass the client-side filter.

---

## Proposed Fix

### Option A — Database function (recommended)

Replace direct table access for anonymous/public reads with a
`SECURITY DEFINER` function that takes a share code and returns exactly one
matching dictation. Direct `SELECT` on `dictations` is blocked for
non-owners.

**Schema changes (`002_rls_share_code_hardening.sql`):**

```sql
-- 1. Drop the overly-broad policy.
drop policy "dictations: public read by share_code" on public.dictations;

-- 2. Add a narrow policy: only the owner can read their own dictation directly.
--    (The existing "dictations: owner crud" policy already covers this via
--    `auth.uid() = owner_id`, so no new policy is needed for owners.
--    Anonymous/student access goes through the function below.)

-- 3. Public accessor function — validates the share code and returns the
--    dictation + sentences in one call. Runs as the service role so it can
--    bypass RLS, but only returns the specific row matching the code.
create or replace function public.get_dictation_by_share_code(p_share_code text)
returns json
language plpgsql
security definer          -- runs with elevated privileges, not caller's role
set search_path = public  -- prevent search_path injection
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

-- Grant execute to authenticated and anonymous roles.
grant execute on function public.get_dictation_by_share_code(text)
  to authenticated, anon;
```

**Flutter client change (`dictations_repository.dart`):**

```dart
Future<(Dictation?, DictationFailure?)> fetchByShareCode(String shareCode) async {
  try {
    final result = await _client
        .rpc('get_dictation_by_share_code', params: {'p_share_code': shareCode});

    if (result == null) return (null, const DictationNotFound());
    return (Dictation.fromJson(result as Map<String, dynamic>), null);
  } on PostgrestException catch (e) {
    if (e.code == 'P0002') return (null, const DictationNotFound());
    _log.warning('fetchByShareCode error: %s', e.message);
    return (null, NetworkDictationFailure(e.message));
  } catch (e) {
    _log.severe('fetchByShareCode unexpected error: %s', e);
    return (null, UnknownDictationFailure(e.toString()));
  }
}
```

> **Note on `dictation_sentences` RLS:** The existing sentences policy
> (`sentences: readable with dictation`) also relies on `share_code is not null`
> for its sub-select. After dropping the dictations policy, direct `SELECT` on
> `dictation_sentences` by non-owners will also be blocked — which is correct,
> since all public access flows through the function.

---

### Option B — Session claim (simpler, weaker)

Set a custom JWT claim `app.known_share_codes` (a JSON array) when the student
accesses a dictation, and reference it in RLS:

```sql
create policy "dictations: public read by share_code" on public.dictations
  for select using (
    share_code is not null
    and share_code = any(
      (current_setting('app.known_share_codes', true)::text[])
    )
  );
```

**Rejected** for this use case: custom claims require either a custom auth
hook (Supabase Auth Hooks, available on Pro plan) or a server-side session
variable set by a trusted function. The implementation complexity is similar to
Option A but provides weaker guarantees (the claim array could hold multiple
codes from previous sessions).

---

## Implementation Checklist

- [x] Write migration `supabase/migrations/002_rls_share_code_hardening.sql`
      with the function + policy drop (see Option A above).
- [x] Update `DictationsRepository.fetchByShareCode` to call `.rpc(…)` instead
      of `.from('dictations').select(…)`.
- [x] Update `Dictation.fromJson` if needed — the function returns a JSON object
      whose `dictation_sentences` key is a JSON array (already matches the
      existing `fromJson` shape; no change required).
- [ ] Test anonymously: confirm a student with code `ABC123` cannot enumerate
      other dictations via the PostgREST REST endpoint.
- [ ] Test owner access: confirm a teacher can still read their own dictations
      via `fetchDictations` / `fetchById` (unaffected — those use `owner_id`
      filter, covered by the owner policy).
- [ ] Test `DictationNotFound` error path: confirm a non-existent or wrong code
      surfaces the `DictationNotFound` failure in the UI.
- [ ] Run `supabase db reset` locally and verify all existing tests pass.
- [ ] Deploy migration + updated Edge Function secrets (no new secrets needed).

---

## Related

- `supabase/migrations/001_initial_schema.sql` — original schema
- `lib/features/dictations/data/dictations_repository.dart` — `fetchByShareCode`
- Code review findings, 2026-05-27 — finding #2 (severity: High / Security)

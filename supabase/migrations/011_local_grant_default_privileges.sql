-- ============================================================
-- e-dictation — restore default table/routine/sequence privileges
-- Migration: 011_local_grant_default_privileges.sql
--
-- Discovered while smoke-testing the card-decks Edge Functions locally
-- (docs/cr-card-decks-language-flashcards.md): a fresh `supabase db reset`
-- leaves `anon`/`authenticated`/`service_role` with NO SELECT/INSERT/
-- UPDATE/DELETE on any `public` schema table — only REFERENCES/TRIGGER/
-- TRUNCATE. This blocks every Edge Function's service-role client
-- (on_dictation_save and ocr_image included, not just the new card-deck
-- functions), since PostgREST enforces these grants even for service_role,
-- independent of RLS.
--
-- Hosted Supabase projects apply this automatically at project creation,
-- which is presumably why none of migrations 001-010 needed it — this
-- local Postgres image/CLI combination just doesn't. Re-granting privileges
-- a role already has is a harmless no-op, so this is safe to run against
-- the hosted project too.
-- ============================================================

grant usage on schema public to postgres, anon, authenticated, service_role;

grant all on all tables in schema public to postgres, anon, authenticated, service_role;
grant all on all routines in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public
  grant all on routines to postgres, anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to postgres, anon, authenticated, service_role;

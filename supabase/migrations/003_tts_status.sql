-- Add TTS generation status to dictations so the client can distinguish
-- "still generating" from "failed" instead of spinning forever.

alter table public.dictations
  add column if not exists tts_status text not null default 'pending'
    check (tts_status in ('pending', 'processing', 'done', 'error')),
  add column if not exists tts_error text;

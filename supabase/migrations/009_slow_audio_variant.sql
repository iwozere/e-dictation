-- ============================================================
-- e-dictation — pre-generated slow-speed audio variant
-- Migration: 009_slow_audio_variant.sql
--
-- Problem: playing sentence audio below 1x via the client-side audio
-- engine's real-time playbackRate (just_audio -> HTML5 <audio> on web)
-- relies on the browser's built-in time-stretch algorithm to slow the
-- audio down. That algorithm has to fabricate samples and sounds noticeably
-- degraded at 0.75x and especially 0.5x.
--
-- Fix: pre-generate a second MP3 per sentence at native Google TTS
-- speakingRate=0.5 (genuinely re-spoken, not stretched). The player then
-- only ever speeds audio up in real time, never slows it down:
--   0.5x  -> slow variant @ playbackRate 1.0   (no stretching at all)
--   0.75x -> slow variant @ playbackRate 1.5   (0.5 * 1.5 = 0.75)
--   1.0x  -> normal variant @ playbackRate 1.0
--   1.25x -> normal variant @ playbackRate 1.25 (already sounds fine)
-- ============================================================

alter table public.dictation_sentences
  add column audio_url_slow   text,  -- Supabase Storage public URL, speakingRate=0.5
  add column duration_ms_slow int;   -- audio length in milliseconds for audio_url_slow

comment on column public.dictation_sentences.audio_url_slow is
  'Pre-generated 0.5x-speed MP3 (native TTS speakingRate=0.5). Used as the base for both 0.5x and 0.75x playback so the client never has to slow audio down in real time.';
comment on column public.dictation_sentences.duration_ms_slow is
  'Audio length in milliseconds for audio_url_slow.';

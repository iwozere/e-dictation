import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/dictation.dart';
import '../domain/dictation_failure.dart';

final _log = Logger('dictations.DictationsRepository');

/// Handles all Supabase DB operations for dictations and sentences.
class DictationsRepository {
  DictationsRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Fetches all dictations owned by [ownerId], ordered newest-first.
  /// Optionally filtered by [classId].
  Future<(List<Dictation>?, DictationFailure?)> fetchDictations({
    required String ownerId,
    String? classId,
  }) async {
    try {
      // Filters must precede .order() in the Postgrest builder chain.
      var filterQuery = _client
          .from('dictations')
          .select('*, tts_status, tts_error, dictation_sentences(id, dictation_id, position, text, audio_url, duration_ms)')
          .eq('owner_id', ownerId);

      if (classId != null) {
        filterQuery = filterQuery.eq('class_id', classId);
      }

      final rows = await filterQuery
          .order('created_at', ascending: false)
          .order('position', referencedTable: 'dictation_sentences') as List<dynamic>;
      final dictations = rows
          .map((r) => Dictation.fromJson(r as Map<String, dynamic>))
          .toList();
      return (dictations, null);
    } catch (e) {
      _log.severe('fetchDictations error: %s', e);
      return (null, UnknownDictationFailure(e.toString()));
    }
  }

  /// Fetches a single dictation by its [shareCode] (public / anonymous access).
  ///
  /// Calls the `get_dictation_by_share_code` RPC function instead of querying
  /// `dictations` directly.  The RLS policy no longer grants broad read access
  /// to all published dictations; access is scoped to the exact code supplied.
  /// The function returns the dictation JSON with a nested `dictation_sentences`
  /// array, which [Dictation.fromJson] already handles.
  Future<(Dictation?, DictationFailure?)> fetchByShareCode(String shareCode) async {
    try {
      final result = await _client.rpc(
        'get_dictation_by_share_code',
        params: {'p_share_code': shareCode},
      );

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

  /// Fetches a single dictation by its [id].
  Future<(Dictation?, DictationFailure?)> fetchById(String id) async {
    try {
      final row = await _client
          .from('dictations')
          .select('*, tts_status, tts_error, dictation_sentences(id, dictation_id, position, text, audio_url, duration_ms)')
          .eq('id', id)
          .order('position', referencedTable: 'dictation_sentences')
          .single();

      return (Dictation.fromJson(row), null);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') return (null, const DictationNotFound());
      return (null, NetworkDictationFailure(e.message));
    } catch (e) {
      _log.severe('fetchById error: %s', e);
      return (null, UnknownDictationFailure(e.toString()));
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Inserts a new dictation row and triggers the `on_dictation_save` Edge
  /// Function asynchronously for sentence splitting + TTS.
  Future<(Dictation?, DictationFailure?)> createDictation({
    required String ownerId,
    required String title,
    required DictationLanguage language,
    required String fullText,
    DictationDifficulty? difficulty,
    String? classId,
    int defaultPauseSecs = 5,
  }) async {
    try {
      final row = await _client
          .from('dictations')
          .insert({
            'owner_id': ownerId,
            if (classId != null) 'class_id': classId,
            'title': title,
            'language': language.code,
            if (difficulty != null) 'difficulty': difficulty.value,
            'full_text': fullText,
            'default_pause_secs': defaultPauseSecs,
          })
          .select()
          .single();

      final dictation = Dictation.fromJson(row);

      // Trigger TTS generation in the background (non-blocking).
      _triggerTtsGeneration(dictation.id, language.code);

      return (dictation, null);
    } catch (e) {
      _log.severe('createDictation error: %s', e);
      return (null, UnknownDictationFailure(e.toString()));
    }
  }

  Future<(Dictation?, DictationFailure?)> updateDictation({
    required String id,
    String? title,
    DictationDifficulty? difficulty,
    String? classId,
    int? defaultPauseSecs,
    String? fullText,
    DictationLanguage? language,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
        if (title != null) 'title': title,
        if (difficulty != null) 'difficulty': difficulty.value,
        if (classId != null) 'class_id': classId,
        if (defaultPauseSecs != null) 'default_pause_secs': defaultPauseSecs,
        if (fullText != null) 'full_text': fullText,
        if (language != null) 'language': language.code,
      };

      final row = await _client
          .from('dictations')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      final dictation = Dictation.fromJson(row);

      // Re-generate TTS when text or language changed.
      if (fullText != null || language != null) {
        _triggerTtsGeneration(id, dictation.language.code);
      }

      return (dictation, null);
    } catch (e) {
      _log.severe('updateDictation error: %s', e);
      return (null, UnknownDictationFailure(e.toString()));
    }
  }

  Future<DictationFailure?> deleteDictation(String id) async {
    try {
      await _client.from('dictations').delete().eq('id', id);
      return null;
    } catch (e) {
      _log.severe('deleteDictation error: %s', e);
      return UnknownDictationFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Edge Function trigger
  // ---------------------------------------------------------------------------

  /// Calls the `on_dictation_save` Edge Function which handles sentence
  /// splitting (Claude) and TTS generation (Google Neural2).
  /// Fire-and-forget — the teacher can navigate away while it runs.
  void _triggerTtsGeneration(String dictationId, String language) {
    _client.functions
        .invoke(
          'on_dictation_save',
          body: {'dictation_id': dictationId, 'language': language},
        )
        .then((_) => _log.info('TTS generation triggered for %s', dictationId))
        .catchError((e) => _log.warning('TTS trigger failed for %s: %s', dictationId, e));
  }
}

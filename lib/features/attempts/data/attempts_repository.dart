import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/attempt.dart';

final _log = Logger('attempts.AttemptsRepository');

sealed class AttemptFailure {}

class AttemptSaveFailed extends AttemptFailure {}

class AttemptLoadFailed extends AttemptFailure {}

/// Handles Supabase DB operations for student attempts.
class AttemptsRepository {
  AttemptsRepository(this._client);

  final SupabaseClient _client;

  /// Saves a completed dictation attempt.
  ///
  /// Returns the saved [Attempt] on success or an [AttemptFailure] on error.
  Future<(Attempt?, AttemptFailure?)> saveAttempt({
    required String dictationId,
    required String? studentName,
    required String? studentPinHash,
    required Map<int, String> answers,
    required int scoreCorrect,
    required int scoreTotal,
  }) async {
    try {
      final studentId = _client.auth.currentUser?.id;
      final answersJson = answers.map((k, v) => MapEntry(k.toString(), v));
      final score = scoreTotal > 0
          ? (scoreCorrect * 100 / scoreTotal).round()
          : 0;

      final row = await _client.from('attempts').insert({
        'dictation_id': dictationId,
        'student_id': studentId,
        'student_name': studentName,
        'student_pin_hash': studentPinHash,
        'answers': answersJson,
        'score_correct': scoreCorrect,
        'score_total': scoreTotal,
        'score': score,
      }).select().single();

      return (Attempt.fromJson(row), null);
    } catch (e) {
      _log.severe('Failed to save attempt for dictation $dictationId', e);
      return (null, AttemptSaveFailed());
    }
  }

  /// Fetches all attempts for [dictationId], newest first.
  ///
  /// Requires the caller to be the dictation owner (enforced by RLS).
  Future<(List<Attempt>?, AttemptFailure?)> listAttempts(
      String dictationId) async {
    try {
      final rows = await _client
          .from('attempts')
          .select()
          .eq('dictation_id', dictationId)
          .order('completed_at', ascending: false) as List<dynamic>;

      final attempts = rows
          .map((r) => Attempt.fromJson(r as Map<String, dynamic>))
          .toList();
      return (attempts, null);
    } catch (e) {
      _log.severe('Failed to list attempts for dictation $dictationId', e);
      return (null, AttemptLoadFailed());
    }
  }
}

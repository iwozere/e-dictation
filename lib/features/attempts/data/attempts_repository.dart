import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dictations/domain/dictation.dart';
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
    DateTime? startedAt,
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
        if (startedAt != null) 'started_at': startedAt.toUtc().toIso8601String(),
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

  /// Fetches every attempt across all dictations owned by [ownerId], newest
  /// first, with the dictation title embedded.
  ///
  /// RLS ("attempts: dictation owner read") restricts the result to the
  /// teacher's own dictations; the `!inner` join additionally drops any
  /// orphaned rows. Powers the teacher-wide results overview.
  Future<(List<Attempt>?, AttemptFailure?)> listAllAttempts(
      String ownerId) async {
    try {
      final rows = await _client
          .from('attempts')
          .select('*, dictations!inner(id, title, owner_id)')
          .eq('dictations.owner_id', ownerId)
          .order('completed_at', ascending: false) as List<dynamic>;

      final attempts = rows
          .map((r) => Attempt.fromJson(r as Map<String, dynamic>))
          .toList();
      return (attempts, null);
    } catch (e) {
      _log.severe('Failed to list all attempts for owner $ownerId', e);
      return (null, AttemptLoadFailed());
    }
  }

  /// Fetches a single attempt with its dictation sentences for the teacher
  /// preview view. Requires the caller to own the dictation (enforced by RLS).
  Future<(Attempt?, AttemptFailure?)> getAttemptDetail(
      String attemptId) async {
    try {
      final row = await _client
          .from('attempts')
          .select('*, dictations!inner(id, title, owner_id)')
          .eq('id', attemptId)
          .single();

      final attempt = Attempt.fromJson(row);

      final sentenceRows = await _client
          .from('dictation_sentences')
          .select()
          .eq('dictation_id', attempt.dictationId)
          .order('position') as List<dynamic>;

      final sentences = sentenceRows
          .map((s) => DictationSentence.fromJson(s as Map<String, dynamic>))
          .toList();

      return (
        Attempt(
          id: attempt.id,
          dictationId: attempt.dictationId,
          studentId: attempt.studentId,
          studentName: attempt.studentName,
          studentPinHash: attempt.studentPinHash,
          answers: attempt.answers,
          scoreCorrect: attempt.scoreCorrect,
          scoreTotal: attempt.scoreTotal,
          completedAt: attempt.completedAt,
          startedAt: attempt.startedAt,
          dictationTitle: attempt.dictationTitle,
          sentences: sentences,
        ),
        null
      );
    } catch (e) {
      _log.severe('Failed to load attempt detail $attemptId', e);
      return (null, AttemptLoadFailed());
    }
  }

  /// Fetches a student's own attempt history by [studentName] + [pinHash].
  ///
  /// Calls the `get_student_attempts` SECURITY DEFINER RPC, which matches on
  /// name + PIN hash and returns each attempt with its dictation title and
  /// sentences. This is the only reliable lookup for anonymous students,
  /// whose `auth.uid()` is not stable across sessions/devices.
  Future<(List<Attempt>?, AttemptFailure?)> listStudentAttempts({
    required String studentName,
    required String pinHash,
  }) async {
    try {
      final result = await _client.rpc(
        'get_student_attempts',
        params: {'p_name': studentName, 'p_pin_hash': pinHash},
      );

      final rows = (result as List<dynamic>?) ?? const [];
      final attempts = rows
          .map((r) => Attempt.fromJson(r as Map<String, dynamic>))
          .toList();
      return (attempts, null);
    } catch (e) {
      _log.severe('Failed to load history for student $studentName', e);
      return (null, AttemptLoadFailed());
    }
  }
}

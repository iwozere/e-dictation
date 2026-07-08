import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/attempts_repository.dart';
import '../../domain/attempt.dart';
import '../../domain/attempt_stats.dart';

final attemptsRepositoryProvider = Provider<AttemptsRepository>((ref) {
  return AttemptsRepository(ref.read(supabaseClientProvider));
});

/// Fetches all attempts for a dictation (teacher view).
///
/// Requires the current user to own the dictation — enforced by RLS.
/// Auto-disposed so re-entering a screen refetches fresh results.
final dictationAttemptsProvider = FutureProvider.autoDispose
    .family<List<Attempt>, String>((ref, dictationId) async {
  final (attempts, failure) = await ref
      .read(attemptsRepositoryProvider)
      .listAttempts(dictationId);

  if (failure != null) throw failure;
  return attempts ?? [];
});

/// Per-dictation attempt aggregates (total tries + latest try) across all of
/// the current teacher's dictations, keyed by dictation id.
///
/// Powers the tries badge on the dashboard cards. Empty when not signed in.
final attemptStatsProvider =
    FutureProvider.autoDispose<Map<String, AttemptStats>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const {};

  final (stats, failure) =
      await ref.read(attemptsRepositoryProvider).fetchAttemptStats(user.id);

  if (failure != null) throw failure;
  return stats ?? const {};
});

/// Fetches every attempt across all of the current teacher's dictations
/// (teacher-wide overview). Empty when not signed in.
final allAttemptsProvider =
    FutureProvider.autoDispose<List<Attempt>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final (attempts, failure) =
      await ref.read(attemptsRepositoryProvider).listAllAttempts(user.id);

  if (failure != null) throw failure;
  return attempts ?? [];
});

/// Fetches a single attempt with its sentences for the teacher preview view.
final attemptDetailProvider =
    FutureProvider.autoDispose.family<Attempt, String>((ref, attemptId) async {
  final (attempt, failure) = await ref
      .read(attemptsRepositoryProvider)
      .getAttemptDetail(attemptId);

  if (failure != null) throw failure;
  return attempt!;
});

/// Argument bundle for [studentAttemptsProvider]; record equality lets
/// Riverpod cache per (name, pinHash) pair.
typedef StudentHistoryQuery = ({String name, String pinHash});

/// Fetches a student's own attempt history by name + PIN hash.
final studentAttemptsProvider = FutureProvider.autoDispose
    .family<List<Attempt>, StudentHistoryQuery>((ref, query) async {
  final (attempts, failure) =
      await ref.read(attemptsRepositoryProvider).listStudentAttempts(
            studentName: query.name,
            pinHash: query.pinHash,
          );

  if (failure != null) throw failure;
  return attempts ?? [];
});

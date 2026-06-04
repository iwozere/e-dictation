import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../data/attempts_repository.dart';
import '../../domain/attempt.dart';

final attemptsRepositoryProvider = Provider<AttemptsRepository>((ref) {
  return AttemptsRepository(ref.read(supabaseClientProvider));
});

/// Fetches all attempts for a dictation (teacher view).
///
/// Requires the current user to own the dictation — enforced by RLS.
final dictationAttemptsProvider =
    FutureProvider.family<List<Attempt>, String>((ref, dictationId) async {
  final (attempts, failure) = await ref
      .read(attemptsRepositoryProvider)
      .listAttempts(dictationId);

  if (failure != null) throw failure;
  return attempts ?? [];
});

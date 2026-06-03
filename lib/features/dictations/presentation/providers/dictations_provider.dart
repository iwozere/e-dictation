import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/dictations_repository.dart';
import '../../domain/dictation.dart';
import '../../domain/dictation_failure.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final dictationsRepositoryProvider = Provider<DictationsRepository>(
  (ref) => DictationsRepository(ref.watch(supabaseClientProvider)),
);

// ---------------------------------------------------------------------------
// Teacher's own dictations
// ---------------------------------------------------------------------------

final teacherDictationsProvider = FutureProvider.autoDispose
    .family<List<Dictation>, String?>((ref, classId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final repo = ref.watch(dictationsRepositoryProvider);
  final (dictations, failure) = await repo.fetchDictations(
    ownerId: user.id,
    classId: classId,
  );

  if (failure != null) throw failure;
  return dictations ?? [];
});

// ---------------------------------------------------------------------------
// Single dictation (by id or share code)
// ---------------------------------------------------------------------------

final dictationByIdProvider =
    FutureProvider.autoDispose.family<Dictation, String>((ref, id) async {
  final repo = ref.watch(dictationsRepositoryProvider);
  final (dictation, failure) = await repo.fetchById(id);
  if (failure != null) throw failure;
  return dictation!;
});

final dictationByShareCodeProvider =
    FutureProvider.autoDispose.family<Dictation, String>((ref, code) async {
  final repo = ref.watch(dictationsRepositoryProvider);
  final (dictation, failure) = await repo.fetchByShareCode(code);
  if (failure != null) throw failure;
  return dictation!;
});

// ---------------------------------------------------------------------------
// Create / update / delete notifier
// ---------------------------------------------------------------------------

class DictationMutationNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<(Dictation?, DictationFailure?)> create({
    required String title,
    required DictationLanguage language,
    required String fullText,
    DictationDifficulty? difficulty,
    String? classId,
    int defaultPauseSecs = 5,
    bool allowStudentControls = true,
  }) async {
    state = const AsyncLoading();
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncData(null);
      return (null, const UnknownDictationFailure('Not authenticated'));
    }

    final result = await ref.read(dictationsRepositoryProvider).createDictation(
          ownerId: user.id,
          title: title,
          language: language,
          fullText: fullText,
          difficulty: difficulty,
          classId: classId,
          defaultPauseSecs: defaultPauseSecs,
          allowStudentControls: allowStudentControls,
        );

    state = const AsyncData(null);
    // Invalidate the list so it refreshes.
    ref.invalidate(teacherDictationsProvider);
    return result;
  }

  Future<DictationFailure?> delete(String id) async {
    state = const AsyncLoading();
    final failure = await ref.read(dictationsRepositoryProvider).deleteDictation(id);
    state = const AsyncData(null);
    ref.invalidate(teacherDictationsProvider);
    return failure;
  }
}

final dictationMutationProvider =
    NotifierProvider<DictationMutationNotifier, AsyncValue<void>>(
  DictationMutationNotifier.new,
);

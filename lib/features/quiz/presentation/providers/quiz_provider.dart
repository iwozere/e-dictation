import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dictations/domain/dictation.dart' show DictationLanguage;
import '../../data/quiz_repository.dart';
import '../../domain/quiz_attempt.dart';
import '../../domain/quiz_deck.dart';
import '../../domain/quiz_failure.dart';
import '../../domain/quiz_practice_deck.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => QuizRepository(ref.watch(supabaseClientProvider)),
);

// ---------------------------------------------------------------------------
// Teacher's own decks
// ---------------------------------------------------------------------------

final teacherQuizDecksProvider = FutureProvider.autoDispose
    .family<List<QuizDeck>, String?>((ref, classId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];

      final repo = ref.watch(quizRepositoryProvider);
      final (decks, failure) = await repo.fetchDecks(
        ownerId: user.id,
        classId: classId,
      );

      if (failure != null) throw failure;
      return decks ?? [];
    });

// ---------------------------------------------------------------------------
// Single deck (by id or share code)
// ---------------------------------------------------------------------------

final quizDeckByIdProvider = FutureProvider.autoDispose
    .family<QuizDeck, String>((ref, id) async {
      final repo = ref.watch(quizRepositoryProvider);
      final (deck, failure) = await repo.fetchById(id);
      if (failure != null) throw failure;
      return deck!;
    });

/// Keyed by (shareCode, direction) — a null direction is the pre-direction
/// preview fetch for the choice screen; a concrete direction re-fetches
/// with the server-side prompt/answer split applied (see the CR doc's
/// Security section and `QuizRepository.fetchByShareCode`).
final quizPracticeDeckProvider = FutureProvider.autoDispose
    .family<QuizPracticeDeck, (String shareCode, QuizDirection? direction)>((
      ref,
      key,
    ) async {
      final repo = ref.watch(quizRepositoryProvider);
      final (deck, failure) = await repo.fetchByShareCode(
        key.$1,
        direction: key.$2,
      );
      if (failure != null) throw failure;
      return deck!;
    });

// ---------------------------------------------------------------------------
// Teacher results
// ---------------------------------------------------------------------------

final quizAttemptsProvider = FutureProvider.autoDispose
    .family<List<QuizAttempt>, String>((ref, deckId) async {
      final repo = ref.watch(quizRepositoryProvider);
      final (attempts, failure) = await repo.fetchAttempts(deckId);
      if (failure != null) throw failure;
      return attempts ?? [];
    });

/// Every quiz attempt across all of the teacher's decks — powers the
/// "Quizzes" tab on the teacher-wide results screen (mirrors
/// `allAttemptsProvider` for dictations).
final allQuizAttemptsProvider = FutureProvider.autoDispose((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return <QuizAttempt>[];

  final repo = ref.watch(quizRepositoryProvider);
  final (attempts, failure) = await repo.fetchAllAttempts(user.id);
  if (failure != null) throw failure;
  return attempts ?? [];
});

// ---------------------------------------------------------------------------
// Create / delete notifier
// ---------------------------------------------------------------------------

class QuizDeckMutationNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<(QuizDeck?, QuizFailure?)> create({
    required String title,
    required DictationLanguage languageA,
    required DictationLanguage languageB,
    String? classId,
    int? sessionLength = 20,
    int timerInitialSecs = 10,
    int timerDecaySecs = 1,
    int timerDecayEveryNCards = 3,
    int timerFloorSecs = 3,
    bool livesEnabled = true,
    int livesCount = 3,
  }) async {
    state = const AsyncLoading();
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncData(null);
      return (null, const UnknownQuizFailure('Not authenticated'));
    }

    final result = await ref
        .read(quizRepositoryProvider)
        .createDeck(
          ownerId: user.id,
          title: title,
          languageA: languageA,
          languageB: languageB,
          classId: classId,
          sessionLength: sessionLength,
          timerInitialSecs: timerInitialSecs,
          timerDecaySecs: timerDecaySecs,
          timerDecayEveryNCards: timerDecayEveryNCards,
          timerFloorSecs: timerFloorSecs,
          livesEnabled: livesEnabled,
          livesCount: livesCount,
        );

    state = const AsyncData(null);
    ref.invalidate(teacherQuizDecksProvider);
    return result;
  }

  Future<QuizFailure?> delete(String id) async {
    state = const AsyncLoading();
    final failure = await ref.read(quizRepositoryProvider).deleteDeck(id);
    state = const AsyncData(null);
    ref.invalidate(teacherQuizDecksProvider);
    return failure;
  }

  /// Updates the session/timer/lives settings; safe at any deck status
  /// since none of them touch cards/options/audio.
  Future<QuizFailure?> updateSettings({
    required String deckId,
    required int? sessionLength,
    required int timerInitialSecs,
    required int timerDecayEveryNCards,
    required int timerFloorSecs,
    required bool livesEnabled,
    required int livesCount,
  }) async {
    state = const AsyncLoading();
    final failure = await ref
        .read(quizRepositoryProvider)
        .updateSettings(
          deckId: deckId,
          sessionLength: sessionLength,
          timerInitialSecs: timerInitialSecs,
          timerDecayEveryNCards: timerDecayEveryNCards,
          timerFloorSecs: timerFloorSecs,
          livesEnabled: livesEnabled,
          livesCount: livesCount,
        );
    state = const AsyncData(null);
    if (failure == null) {
      ref.invalidate(quizDeckByIdProvider(deckId));
      ref.invalidate(teacherQuizDecksProvider);
    }
    return failure;
  }

  /// Updates title/language, called from the card editor's save flow (see
  /// `QuizRepository.updateDeckInfo` for why it's separate from the settings
  /// dialog above).
  Future<QuizFailure?> updateDeckInfo({
    required String deckId,
    required String title,
    required DictationLanguage languageA,
    required DictationLanguage languageB,
  }) async {
    final failure = await ref
        .read(quizRepositoryProvider)
        .updateDeckInfo(
          deckId: deckId,
          title: title,
          languageA: languageA,
          languageB: languageB,
        );
    if (failure == null) {
      ref.invalidate(teacherQuizDecksProvider);
    }
    return failure;
  }
}

final quizDeckMutationProvider =
    NotifierProvider<QuizDeckMutationNotifier, AsyncValue<void>>(
      QuizDeckMutationNotifier.new,
    );

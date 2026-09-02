import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dictations/domain/dictation.dart' show DictationLanguage;
import '../../data/cards_repository.dart';
import '../../domain/card_deck.dart';
import '../../domain/card_deck_failure.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

final cardsRepositoryProvider = Provider<CardsRepository>(
  (ref) => CardsRepository(ref.watch(supabaseClientProvider)),
);

// ---------------------------------------------------------------------------
// Teacher's own decks
// ---------------------------------------------------------------------------

final teacherCardDecksProvider = FutureProvider.autoDispose
    .family<List<CardDeck>, String?>((ref, classId) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return [];

      final repo = ref.watch(cardsRepositoryProvider);
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

final cardDeckByIdProvider = FutureProvider.autoDispose
    .family<CardDeck, String>((ref, id) async {
      final repo = ref.watch(cardsRepositoryProvider);
      final (deck, failure) = await repo.fetchById(id);
      if (failure != null) throw failure;
      return deck!;
    });

final cardDeckByShareCodeProvider = FutureProvider.autoDispose
    .family<CardDeck, String>((ref, code) async {
      final repo = ref.watch(cardsRepositoryProvider);
      final (deck, failure) = await repo.fetchByShareCode(code);
      if (failure != null) throw failure;
      return deck!;
    });

// ---------------------------------------------------------------------------
// Create / delete notifier
// ---------------------------------------------------------------------------

class CardDeckMutationNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<(CardDeck?, CardDeckFailure?)> create({
    required String title,
    required DictationLanguage languageA,
    required DictationLanguage languageB,
    String? classId,
  }) async {
    state = const AsyncLoading();
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncData(null);
      return (null, const UnknownCardDeckFailure('Not authenticated'));
    }

    final result = await ref
        .read(cardsRepositoryProvider)
        .createDeck(
          ownerId: user.id,
          title: title,
          languageA: languageA,
          languageB: languageB,
          classId: classId,
        );

    state = const AsyncData(null);
    ref.invalidate(teacherCardDecksProvider);
    return result;
  }

  Future<CardDeckFailure?> delete(String id) async {
    state = const AsyncLoading();
    final failure = await ref.read(cardsRepositoryProvider).deleteDeck(id);
    state = const AsyncData(null);
    ref.invalidate(teacherCardDecksProvider);
    return failure;
  }
}

final cardDeckMutationProvider =
    NotifierProvider<CardDeckMutationNotifier, AsyncValue<void>>(
      CardDeckMutationNotifier.new,
    );

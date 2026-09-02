import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/card_deck.dart';
import '../providers/cards_provider.dart';
import 'widgets/card_deck_card.dart';

class CardDecksListScreen extends ConsumerWidget {
  const CardDecksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(teacherCardDecksProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('My Card Decks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoute.createCardDeck),
        icon: const Icon(Icons.add),
        label: const Text('New deck'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: decksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: 'Could not load card decks.',
          onRetry: () => ref.invalidate(teacherCardDecksProvider),
        ),
        data: (decks) => decks.isEmpty
            ? EmptyState(
                icon: Icons.style_outlined,
                title: 'No card decks yet',
                subtitle:
                    'Photograph a two-column vocabulary list and turn it into flashcards.',
                action: TextButton.icon(
                  onPressed: () => context.go(AppRoute.createCardDeck),
                  icon: const Icon(Icons.add),
                  label: const Text('New deck'),
                ),
              )
            : _DeckGrid(decks: decks),
      ),
    );
  }
}

class _DeckGrid extends StatelessWidget {
  const _DeckGrid({required this.decks});
  final List<CardDeck> decks;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: decks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => CardDeckCard(deck: decks[i]),
      ),
    );
  }
}

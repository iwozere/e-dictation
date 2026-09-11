import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/quiz_deck.dart';
import '../providers/quiz_provider.dart';
import 'widgets/quiz_deck_card.dart';

class QuizDecksListScreen extends ConsumerWidget {
  const QuizDecksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decksAsync = ref.watch(teacherQuizDecksProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('My Quiz Decks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoute.createQuizDeck),
        icon: const Icon(Icons.add),
        label: const Text('New quiz'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: decksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: 'Could not load quiz decks.',
          onRetry: () => ref.invalidate(teacherQuizDecksProvider),
        ),
        data: (decks) => decks.isEmpty
            ? EmptyState(
                icon: Icons.bolt_outlined,
                title: 'No quiz decks yet',
                subtitle:
                    'Build a timed multiple-choice vocabulary quiz, typed by hand or '
                    'generated from one of your card decks.',
                action: TextButton.icon(
                  onPressed: () => context.go(AppRoute.createQuizDeck),
                  icon: const Icon(Icons.add),
                  label: const Text('New quiz'),
                ),
              )
            : _DeckList(decks: decks),
      ),
    );
  }
}

class _DeckList extends StatelessWidget {
  const _DeckList({required this.decks});
  final List<QuizDeck> decks;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: decks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => QuizDeckCard(deck: decks[i]),
      ),
    );
  }
}

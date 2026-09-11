import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/quiz_attempt.dart';
import '../../domain/quiz_deck.dart';
import '../providers/quiz_provider.dart';

/// Teacher results dashboard for one quiz deck — one row per attempt with
/// a per-card breakdown (CR doc §8), same table-plus-expand shape as the
/// dictation `ResultsScreen`.
class QuizResultsScreen extends ConsumerWidget {
  const QuizResultsScreen({super.key, required this.deckId});
  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deckAsync = ref.watch(quizDeckByIdProvider(deckId));
    final attemptsAsync = ref.watch(quizAttemptsProvider(deckId));

    return deckAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => const Scaffold(
        body: ErrorView(message: 'Could not load this quiz deck.'),
      ),
      data: (deck) => attemptsAsync.when(
        loading: () => Scaffold(
          appBar: _appBar(deck.title, []),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: _appBar(deck.title, []),
          body: ErrorView(
            message: 'Could not load results.',
            onRetry: () => ref.invalidate(quizAttemptsProvider(deckId)),
          ),
        ),
        data: (attempts) => Scaffold(
          appBar: _appBar(deck.title, attempts),
          body: SelectionArea(
            child: attempts.isEmpty
                ? const Center(
                    child: Text(
                      'No attempts yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: attempts.length,
                    itemBuilder: (_, i) =>
                        _AttemptTile(attempt: attempts[i], deck: deck),
                  ),
          ),
        ),
      ),
    );
  }

  AppBar _appBar(String title, List<QuizAttempt> attempts) {
    final uniqueNames = attempts
        .map((a) => a.studentName ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;

    return AppBar(
      title: SelectionArea(child: Text(title)),
      bottom: attempts.isEmpty
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${attempts.length} attempt${attempts.length == 1 ? '' : 's'}'
                  ' · $uniqueNames named student${uniqueNames == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.attempt, required this.deck});

  final QuizAttempt attempt;
  final QuizDeck deck;

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(attempt.correctCount, attempt.totalCount);
    final date = DateFormat(
      'd MMM HH:mm',
    ).format(attempt.submittedAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scoreColor.withValues(alpha: 0.12),
          child: Text(
            '${attempt.correctCount}/${attempt.totalCount}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scoreColor,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                attempt.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (attempt.hasPinSet)
              const Tooltip(
                message: 'PIN set',
                child: Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            if (attempt.endedReason == QuizEndedReason.outOfLives) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Ended early — out of lives',
                child: Icon(
                  Icons.heart_broken_outlined,
                  size: 14,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '$date · best streak 🔥 ×${attempt.bestStreak}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        children: [
          const Divider(height: 1),
          _AnswerBreakdown(attempt: attempt, deck: deck),
        ],
      ),
    );
  }

  Color _scoreColor(int correct, int total) {
    if (total == 0) return Colors.grey;
    final ratio = correct / total;
    if (ratio == 1.0) return AppColors.success;
    if (ratio >= 0.6) return AppColors.warning;
    return AppColors.error;
  }
}

// ---------------------------------------------------------------------------

class _AnswerBreakdown extends StatelessWidget {
  const _AnswerBreakdown({required this.attempt, required this.deck});
  final QuizAttempt attempt;
  final QuizDeck deck;

  @override
  Widget build(BuildContext context) {
    final side = attempt.direction.answerSide;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: attempt.answers.map((a) {
          final card = deck.cards.where((c) => c.id == a.cardId).firstOrNull;
          final correctOption = card?.correctOptionFor(side);
          final chosenOption = card
              ?.optionsFor(side)
              .where((o) => o.id == a.optionId)
              .firstOrNull;

          final color = a.correct ? AppColors.success : AppColors.error;
          final label = a.timedOut
              ? 'Timed out — correct: ${correctOption?.text ?? '?'}'
              : a.correct
              ? (correctOption?.text ?? '?')
              : '${chosenOption?.text ?? '?'} → correct: ${correctOption?.text ?? '?'}';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  a.correct
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
                if (a.timeTakenMs != null)
                  Text(
                    '${(a.timeTakenMs! / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

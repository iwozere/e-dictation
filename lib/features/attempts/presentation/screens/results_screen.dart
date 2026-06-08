import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../dictations/domain/dictation.dart';
import '../../../dictations/presentation/providers/dictations_provider.dart';
import '../../domain/attempt.dart';
import '../providers/attempts_provider.dart';
import '../widgets/attempt_breakdown.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.dictationId});
  final String dictationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dictationAsync = ref.watch(dictationByIdProvider(dictationId));
    final attemptsAsync = ref.watch(dictationAttemptsProvider(dictationId));

    return dictationAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: ErrorView(message: 'Could not load dictation.'),
      ),
      data: (dictation) => attemptsAsync.when(
        loading: () => Scaffold(
          appBar: _appBar(context, dictation.title, ref, []),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: _appBar(context, dictation.title, ref, []),
          body: ErrorView(
            message: 'Could not load results.',
            onRetry: () =>
                ref.invalidate(dictationAttemptsProvider(dictationId)),
          ),
        ),
        data: (attempts) => Scaffold(
          appBar: _appBar(context, dictation.title, ref, attempts),
          body: attempts.isEmpty
              ? const Center(
                  child: Text(
                    'No submissions yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: attempts.length,
                  itemBuilder: (_, i) => _AttemptTile(
                    attempt: attempts[i],
                    sentences: dictation.sentences,
                  ),
                ),
        ),
      ),
    );
  }

  AppBar _appBar(
    BuildContext context,
    String title,
    WidgetRef ref,
    List<Attempt> attempts,
  ) {
    final uniqueNames = attempts
        .map((a) => a.studentName ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;

    return AppBar(
      title: Text(title),
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
// Attempt tile — expandable row
// ---------------------------------------------------------------------------

class _AttemptTile extends StatelessWidget {
  const _AttemptTile({
    required this.attempt,
    required this.sentences,
  });

  final Attempt attempt;
  final List<DictationSentence> sentences;

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(attempt.scoreCorrect, attempt.scoreTotal);
    final date = DateFormat('d MMM HH:mm').format(attempt.completedAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scoreColor.withValues(alpha: 0.12),
          child: Text(
            '${attempt.scoreCorrect}/${attempt.scoreTotal}',
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
                child: Icon(Icons.lock_outline, size: 14, color: AppColors.primary),
              ),
          ],
        ),
        subtitle: Text(date,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        children: [
          const Divider(height: 1),
          AttemptBreakdown(attempt: attempt, sentences: sentences),
        ],
      ),
    );
  }
}

Color _scoreColor(int correct, int total) {
  if (total == 0) return Colors.grey;
  final ratio = correct / total;
  if (ratio == 1.0) return AppColors.success;
  if (ratio >= 0.6) return AppColors.warning;
  return AppColors.error;
}

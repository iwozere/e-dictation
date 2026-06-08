import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/attempt.dart';
import '../providers/attempts_provider.dart';

/// Teacher-wide results overview: every attempt across all of the teacher's
/// dictations, grouped by student. Answers "who did what dictation and when".
/// Tapping an attempt opens that dictation's detailed results (mistakes).
class ResultsOverviewScreen extends ConsumerWidget {
  const ResultsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(allAttemptsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All results')),
      body: attemptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: 'Could not load results.',
          onRetry: () => ref.invalidate(allAttemptsProvider),
        ),
        data: (attempts) {
          if (attempts.isEmpty) {
            return const EmptyState(
              icon: Icons.assessment_outlined,
              title: 'No submissions yet',
              subtitle: 'Results will appear here once students complete '
                  'one of your dictations.',
            );
          }

          final groups = _groupByStudent(attempts);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allAttemptsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (_, i) => _StudentGroupTile(group: groups[i]),
            ),
          );
        },
      ),
    );
  }

  /// Groups attempts by display name, newest activity first.
  List<_StudentGroup> _groupByStudent(List<Attempt> attempts) {
    final byName = <String, List<Attempt>>{};
    for (final a in attempts) {
      byName.putIfAbsent(a.displayName, () => []).add(a);
    }
    final groups = byName.entries
        .map((e) => _StudentGroup(name: e.key, attempts: e.value))
        .toList();
    // Each group's attempts are already newest-first (query order); sort
    // groups by their most recent attempt.
    groups.sort((a, b) =>
        b.attempts.first.completedAt.compareTo(a.attempts.first.completedAt));
    return groups;
  }
}

class _StudentGroup {
  _StudentGroup({required this.name, required this.attempts});
  final String name;
  final List<Attempt> attempts;

  double get avgPercent {
    final scored = attempts.where((a) => a.scoreTotal > 0);
    if (scored.isEmpty) return 0;
    final sum = scored
        .map((a) => a.scoreCorrect * 100 / a.scoreTotal)
        .reduce((a, b) => a + b);
    return sum / scored.length;
  }
}

class _StudentGroupTile extends StatelessWidget {
  const _StudentGroupTile({required this.group});
  final _StudentGroup group;

  @override
  Widget build(BuildContext context) {
    final count = group.attempts.length;
    final avg = group.avgPercent.round();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Text(
            group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        title: Text(group.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '$count attempt${count == 1 ? '' : 's'} · avg $avg%',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        children: [
          const Divider(height: 1),
          ...group.attempts.map((a) => _AttemptRow(attempt: a)),
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.attempt});
  final Attempt attempt;

  @override
  Widget build(BuildContext context) {
    final date =
        DateFormat('d MMM HH:mm').format(attempt.completedAt.toLocal());
    final color = _scoreColor(attempt.scoreCorrect, attempt.scoreTotal);

    return ListTile(
      dense: true,
      title: Text(
        attempt.dictationTitle ?? 'Dictation',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(date,
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${attempt.scoreCorrect}/${attempt.scoreTotal}',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
      ),
      onTap: () => context
          .go('/teacher/dictations/${attempt.dictationId}/results'),
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

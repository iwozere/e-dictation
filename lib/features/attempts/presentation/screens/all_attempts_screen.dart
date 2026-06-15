import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/attempt.dart';
import '../providers/attempts_provider.dart';
import '../widgets/student_results_view.dart';

class AllAttemptsScreen extends ConsumerWidget {
  const AllAttemptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(allAttemptsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: attemptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              const Text('Could not load results.'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(allAttemptsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (attempts) {
          if (attempts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_outlined,
                      size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No completed dictations yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: attempts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _AttemptTile(attempt: attempts[i]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.attempt});
  final Attempt attempt;

  static final _dateFmt = DateFormat('d MMM HH:mm');

  @override
  Widget build(BuildContext context) {
    final scoreColor = attempt.scoreCorrect == attempt.scoreTotal
        ? AppColors.success
        : attempt.scoreCorrect >= (attempt.scoreTotal * 0.6).ceil()
            ? AppColors.warning
            : AppColors.error;

    final startLabel = attempt.startedAt != null
        ? _dateFmt.format(attempt.startedAt!)
        : '—';
    final finishLabel = _dateFmt.format(attempt.completedAt);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + dictation title
                  Row(
                    children: [
                      Text(
                        attempt.studentName?.isNotEmpty == true
                            ? attempt.studentName!
                            : 'Anonymous',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: attempt.studentName?.isNotEmpty == true
                              ? null
                              : Colors.grey,
                          fontStyle: attempt.studentName?.isNotEmpty == true
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                      if (attempt.dictationTitle != null) ...[
                        const SizedBox(width: 6),
                        const Text('·',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            attempt.dictationTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Timestamps + score
                  Row(
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text(startLabel,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                      const SizedBox(width: 10),
                      Icon(Icons.flag_rounded,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text(finishLabel,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                      const SizedBox(width: 10),
                      Text(
                        '${attempt.scoreCorrect}/${attempt.scoreTotal}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Preview icon
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Preview results',
              onPressed: () => _showPreview(context, attempt.id),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreview(BuildContext context, String attemptId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AttemptPreviewSheet(attemptId: attemptId),
    );
  }
}

// ---------------------------------------------------------------------------

class _AttemptPreviewSheet extends ConsumerWidget {
  const _AttemptPreviewSheet({required this.attemptId});
  final String attemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(attemptDetailProvider(attemptId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          detailAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (attempt) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attempt.studentName?.isNotEmpty == true
                          ? attempt.studentName!
                          : 'Anonymous',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  if (attempt.dictationTitle != null)
                    Text(
                      attempt.dictationTitle!,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: detailAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load results.'),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(attemptDetailProvider(attemptId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (attempt) => StudentResultsView(
                sentences: attempt.sentences,
                answers: attempt.answers,
                scrollController: controller,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/dictation.dart';
import '../../providers/dictations_provider.dart';

class DictationCard extends ConsumerWidget {
  const DictationCard({super.key, required this.dictation});
  final Dictation dictation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/teacher/dictations/${dictation.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dictation.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _MoreMenu(dictation: dictation),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dictation.fullText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Chip(
                    label: dictation.language.label,
                    color: AppColors.primary,
                  ),
                  if (dictation.difficulty != null) ...[
                    const SizedBox(width: 6),
                    _Chip(
                      label: dictation.difficulty!.label,
                      color: _difficultyColor(dictation.difficulty!),
                    ),
                  ],
                  const Spacer(),
                  _TtsStatusIcon(dictation: dictation),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    '${dictation.sentences.length} sentences · ${dictation.wordCount} words',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  if (dictation.shareCode != null) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: dictation.shareCode!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Share code copied!')),
                        );
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.copy, size: 14,
                              color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            dictation.shareCode!,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _difficultyColor(DictationDifficulty d) => switch (d) {
        DictationDifficulty.easy => AppColors.success,
        DictationDifficulty.medium => AppColors.warning,
        DictationDifficulty.hard => AppColors.error,
      };
}

class _TtsStatusIcon extends StatelessWidget {
  const _TtsStatusIcon({required this.dictation});
  final Dictation dictation;

  @override
  Widget build(BuildContext context) {
    return switch (dictation.ttsStatus) {
      TtsStatus.done => const Icon(Icons.check_circle, size: 16, color: AppColors.success),
      TtsStatus.error => Tooltip(
          message: dictation.ttsError ?? 'Audio generation failed',
          child: const Icon(Icons.error_outline, size: 16, color: AppColors.error),
        ),
      _ => const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.dictation});
  final Dictation dictation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) async {
        if (value == 'edit') {
          context.go('/teacher/dictations/${dictation.id}/edit');
          return;
        }
        if (value == 'preview') {
          context.go('/play/${dictation.id}');
          return;
        }
        if (value == 'delete') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Delete dictation?'),
              content: Text(
                  'This will permanently delete "${dictation.title}" and all its audio.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Delete',
                        style: TextStyle(color: AppColors.error))),
              ],
            ),
          );
          if (confirmed == true) {
            ref
                .read(dictationMutationProvider.notifier)
                .delete(dictation.id);
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 8),
            Text('Edit'),
          ]),
        ),
        PopupMenuItem(
          value: 'preview',
          child: Row(children: [
            Icon(Icons.play_circle_outline, size: 18),
            SizedBox(width: 8),
            Text('Preview'),
          ]),
        ),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

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
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/teacher/dictations/${dictation.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
          child: Row(
            children: [
              // Left: title + preview + chips
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dictation.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label: dictation.language.label,
                          color: AppColors.primary,
                        ),
                        if (dictation.difficulty != null) ...[
                          const SizedBox(width: 4),
                          _Chip(
                            label: dictation.difficulty!.label,
                            color: _difficultyColor(dictation.difficulty!),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    // Preview + stats row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dictation.fullText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${dictation.sentences.length}s · ${dictation.wordCount}w',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 6),
                        _TtsStatusIcon(dictation: dictation),
                        if (dictation.shareCode != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                  text: dictation.shareCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Share code copied!')),
                              );
                            },
                            child: Text(
                              dictation.shareCode!,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Right: more menu
              _MoreMenu(dictation: dictation),
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
      padding: EdgeInsets.zero,
      splashRadius: 18,
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

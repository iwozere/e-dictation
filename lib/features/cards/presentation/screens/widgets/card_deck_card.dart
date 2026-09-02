import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/config/app_config.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../domain/card_deck.dart';
import '../../providers/cards_provider.dart';

class CardDeckCard extends ConsumerWidget {
  const CardDeckCard({super.key, required this.deck});
  final CardDeck deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/teacher/cards/${deck.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 2, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deck.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label:
                              '${deck.languageA.label} / ${deck.languageB.label}',
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        _StatusChip(status: deck.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${deck.cards.length} pairs · ${DateFormat('d MMM yyyy').format(deck.createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                        if (deck.shareCode != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final link =
                                  '${AppConfig.appBaseUrl}/c/${deck.shareCode!}';
                              Clipboard.setData(ClipboardData(text: link));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Share link copied!'),
                                ),
                              );
                            },
                            child: Text(
                              deck.shareCode!,
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                padding: EdgeInsets.zero,
                splashRadius: 18,
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete card deck?'),
                        content: Text(
                          'This will permanently delete "${deck.title}" and all its audio.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      ref
                          .read(cardDeckMutationProvider.notifier)
                          .delete(deck.id);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final CardDeckStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      CardDeckStatus.pending => ('Processing…', AppColors.secondary),
      CardDeckStatus.draft => ('Needs review', AppColors.warning),
      CardDeckStatus.ready => ('Ready', AppColors.success),
      CardDeckStatus.failed => ('Failed', AppColors.error),
    };
    return _Chip(label: label, color: color);
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

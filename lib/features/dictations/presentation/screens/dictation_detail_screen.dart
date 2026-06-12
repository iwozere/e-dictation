import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../providers/dictations_provider.dart';

class DictationDetailScreen extends ConsumerWidget {
  const DictationDetailScreen({super.key, required this.dictationId});
  final String dictationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dictationAsync = ref.watch(dictationByIdProvider(dictationId));

    return dictationAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Dictation')),
        body: ErrorView(
          message: 'Could not load dictation.',
          onRetry: () => ref.invalidate(dictationByIdProvider(dictationId)),
        ),
      ),
      data: (dictation) => Scaffold(
        appBar: AppBar(
          title: Text(dictation.title),
          actions: [
            if (dictation.shareCode != null)
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Copy share link',
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text:
                          '${AppConfig.appBaseUrl}/d/${dictation.shareCode}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share link copied!')),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Preview',
              onPressed: () => context.go('/play/${dictation.id}'),
            ),
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: 'Results',
              onPressed: () =>
                  context.go('/teacher/dictations/${dictation.id}/results'),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () =>
                  context.go('/teacher/dictations/${dictation.id}/edit'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Share code banner
            if (dictation.shareCode != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Share code',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.primary)),
                          Text(
                            dictation.shareCode!,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.primary),
                      tooltip: 'Copy link',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text:
                                '${AppConfig.appBaseUrl}/d/${dictation.shareCode}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Metadata
            _InfoRow('Language', dictation.language.label),
            if (dictation.difficulty != null)
              _InfoRow('Difficulty', dictation.difficulty!.label),
            _InfoRow(
                'Default pause', '${dictation.defaultPauseSecs} seconds between sentences'),
            _InfoRow('Words', dictation.wordCount.toString()),
            _InfoRow('Sentences', dictation.sentences.length.toString()),
            const SizedBox(height: 24),

            // TTS status
            if (dictation.sentences.isNotEmpty) ...[
              const Text('Audio status',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              ...dictation.sentences.map(
                (s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    s.hasAudio ? Icons.check_circle : Icons.hourglass_empty,
                    color: s.hasAudio ? AppColors.success : Colors.grey,
                    size: 18,
                  ),
                  title: Text(
                    s.text,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ] else ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Generating audio…'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

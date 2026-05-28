import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dictations/presentation/providers/dictations_provider.dart';
import '../../domain/playback_state_model.dart';
import '../providers/playback_notifier.dart';
import '../widgets/playback_controls.dart';
import '../widgets/sentence_list.dart';

/// Accepts either a [shareCode] (anonymous student) or a [dictationId]
/// (authenticated user / teacher preview).
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, this.shareCode, this.dictationId})
      : assert(shareCode != null || dictationId != null,
            'One of shareCode or dictationId must be provided');

  final String? shareCode;
  final String? dictationId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  /// The dictation ID whose sentences were last loaded into the player.
  String? _loadedDictationId;

  /// How many sentences had a non-null audio URL the last time we called
  /// [loadDictation]. When TTS generation completes, the provider re-emits
  /// with more (or all) sentences having audio; the count change triggers a
  /// fresh [loadDictation] call so the player uses the updated list.
  int _loadedSentencesWithAudio = 0;

  @override
  Widget build(BuildContext context) {
    // For anonymous access, ensure the user is signed in.
    final userAsync = ref.watch(authStateProvider);

    if (widget.shareCode != null && userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Ensure anonymous session before loading public dictation.
    if (widget.shareCode != null && userAsync.valueOrNull == null) {
      _ensureAnonymousSession();
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dictationAsync = widget.shareCode != null
        ? ref.watch(dictationByShareCodeProvider(widget.shareCode!))
        : ref.watch(dictationByIdProvider(widget.dictationId!));

    return dictationAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Dictation')),
        body: ErrorView(message: _errorMessage(e)),
      ),
      data: (dictation) {
        // (Re-)load the dictation into the player when:
        //   a) it hasn't been loaded yet, or
        //   b) TTS generation completed and more sentences now have audio URLs.
        // Using _loadedDictationId + _loadedSentencesWithAudio rather than a
        // simple boolean so the player picks up newly-generated audio without
        // requiring the user to navigate away and back.
        final sentencesWithAudio =
            dictation.sentences.where((s) => s.hasAudio).length;
        if (_loadedDictationId != dictation.id ||
            _loadedSentencesWithAudio != sentencesWithAudio) {
          _loadedDictationId = dictation.id;
          _loadedSentencesWithAudio = sentencesWithAudio;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(playbackNotifierProvider.notifier).loadDictation(
                  dictation.sentences,
                  defaultPauseSecs: dictation.defaultPauseSecs,
                );
          });
        }

        final playback = ref.watch(playbackNotifierProvider);

        return Scaffold(
          appBar: AppBar(
            title: Text(dictation.title),
            actions: [
              // Dictation mode selector
              PopupMenuButton<DictationMode>(
                icon: const Icon(Icons.visibility_outlined),
                tooltip: 'Text visibility',
                initialValue: playback.dictationMode,
                onSelected: (mode) => ref
                    .read(playbackNotifierProvider.notifier)
                    .setDictationMode(mode),
                itemBuilder: (_) => DictationMode.values
                    .map((m) => PopupMenuItem(value: m, child: Text(m.label)))
                    .toList(),
              ),
            ],
          ),
          body: Column(
            children: [
              // Sentence list (top section, scrollable)
              Expanded(
                child: SentenceListWidget(
                  sentences: dictation.sentences,
                  playbackState: playback,
                ),
              ),

              // Divider
              const Divider(height: 1),

              // Controls (bottom section, fixed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Speed + Pause row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SpeedRow(speed: playback.speed),
                        _PauseRow(pauseSecs: playback.pauseDurationSecs),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PlaybackControls(playbackState: playback),
                    const SizedBox(height: 8),

                    // Status text
                    Text(
                      _statusLabel(playback),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _ensureAnonymousSession() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.signInAnonymously();
  }

  String _errorMessage(Object e) {
    if (e is Exception) return 'Dictation not found. Check your share code.';
    return 'Could not load dictation.';
  }

  String _statusLabel(PlaybackStateModel state) => switch (state.status) {
        PlaybackStatus.idle => 'Press play to start',
        PlaybackStatus.loading => 'Loading…',
        PlaybackStatus.playing =>
          'Sentence ${state.currentIndex + 1} of ${state.sentences.length}',
        PlaybackStatus.paused => 'Paused',
        PlaybackStatus.pauseBetweenSentences =>
          'Next sentence in ${state.pauseDurationSecs}s…',
        PlaybackStatus.completed => 'Completed',
        PlaybackStatus.error => state.errorMessage ?? 'Error',
      };
}

class _SpeedRow extends ConsumerWidget {
  const _SpeedRow({required this.speed});
  final double speed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Speed:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 6),
        ...AppConfig.playbackSpeeds.map(
          (s) => GestureDetector(
            onTap: () => ref.read(playbackNotifierProvider.notifier).setSpeed(s),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: speed == s
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$s×',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: speed == s ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PauseRow extends ConsumerWidget {
  const _PauseRow({required this.pauseSecs});
  final int pauseSecs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pause:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 6),
        ...AppConfig.pauseDurations.map(
          (s) => GestureDetector(
            onTap: () =>
                ref.read(playbackNotifierProvider.notifier).setPauseDuration(s),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: pauseSecs == s
                    ? AppColors.secondary
                    : AppColors.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${s}s',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: pauseSecs == s ? Colors.white : AppColors.secondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

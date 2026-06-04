import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/playback_state_model.dart';
import '../providers/playback_notifier.dart';

/// The main transport controls: previous · play/pause · next · repeat.
class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key, required this.playbackState});
  final PlaybackStateModel playbackState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playbackNotifierProvider.notifier);
    final status = playbackState.status;
    final isPlaying = status == PlaybackStatus.playing ||
        status == PlaybackStatus.pauseBetweenSentences;
    final isLoading = status == PlaybackStatus.loading;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous sentence
        _ControlButton(
          icon: Icons.skip_previous_rounded,
          size: 32,
          onTap: playbackState.currentIndex > 0 ? notifier.previous : null,
        ),
        const SizedBox(width: 8),

        // Repeat current sentence
        _ControlButton(
          icon: Icons.replay_rounded,
          size: 28,
          onTap: playbackState.sentences.isNotEmpty ? notifier.repeatCurrent : null,
        ),
        const SizedBox(width: 16),

        // Primary play/pause button
        _PlayPauseButton(
          isPlaying: isPlaying,
          isLoading: isLoading,
          onTap: () {
            if (isPlaying) {
              notifier.pause();
            } else {
              notifier.play();
            }
          },
        ),
        const SizedBox(width: 16),

        // Next sentence
        _ControlButton(
          icon: Icons.skip_next_rounded,
          size: 28,
          onTap: playbackState.currentIndex < playbackState.sentences.length - 1
              ? notifier.next
              : null,
        ),
        const SizedBox(width: 8),

        // Restart from beginning
        _ControlButton(
          icon: Icons.restart_alt_rounded,
          size: 32,
          onTap: playbackState.sentences.isNotEmpty
              ? () => notifier.jumpTo(0)
              : null,
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: size,
      color: onTap == null ? Colors.grey[400] : Colors.grey[700],
      onPressed: onTap,
    );
  }
}

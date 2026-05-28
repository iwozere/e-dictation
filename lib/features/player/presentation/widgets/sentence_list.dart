import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../dictations/domain/dictation.dart';
import '../../domain/playback_state_model.dart';

/// Scrollable list of dictation sentences. Highlights the current one and
/// respects the [DictationMode] visibility rules.
class SentenceListWidget extends StatefulWidget {
  const SentenceListWidget({
    super.key,
    required this.sentences,
    required this.playbackState,
  });

  final List<DictationSentence> sentences;
  final PlaybackStateModel playbackState;

  @override
  State<SentenceListWidget> createState() => _SentenceListWidgetState();
}

class _SentenceListWidgetState extends State<SentenceListWidget> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(SentenceListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackState.currentIndex !=
        widget.playbackState.currentIndex) {
      _scrollToCurrentSentence();
    }
  }

  void _scrollToCurrentSentence() {
    final index = widget.playbackState.currentIndex;
    final itemHeight = 72.0;
    final offset = (index * itemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (itemHeight / 2);
    _scrollController.animateTo(
      offset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sentences.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 16),
            Text('Audio is being generated…'),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.sentences.length,
      itemBuilder: (_, index) {
        final sentence = widget.sentences[index];
        final isCurrent = index == widget.playbackState.currentIndex;
        final isVisible = widget.playbackState.isSentenceVisible(index);

        return _SentenceTile(
          sentence: sentence,
          isCurrent: isCurrent,
          isVisible: isVisible,
          dictationMode: widget.playbackState.dictationMode,
          index: index,
        );
      },
    );
  }
}

class _SentenceTile extends StatelessWidget {
  const _SentenceTile({
    required this.sentence,
    required this.isCurrent,
    required this.isVisible,
    required this.dictationMode,
    required this.index,
  });

  final DictationSentence sentence;
  final bool isCurrent;
  final bool isVisible;
  final DictationMode dictationMode;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? AppColors.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sentence number
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isCurrent ? AppColors.primary : Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sentence text
          Expanded(
            child: isVisible
                ? Text(
                    sentence.text,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      color: isCurrent ? AppColors.primary : null,
                    ),
                  )
                : dictationMode == DictationMode.partialHint
                    ? _PartialHintText(text: sentence.text, isCurrent: isCurrent)
                    : _HiddenText(isCurrent: isCurrent),
          ),
        ],
      ),
    );
  }
}

/// Shows first and last word, hides the rest with underscores.
class _PartialHintText extends StatelessWidget {
  const _PartialHintText({required this.text, required this.isCurrent});
  final String text;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.length <= 2) {
      return _HiddenText(isCurrent: isCurrent);
    }
    final first = words.first;
    final last = words.last;
    final hiddenCount = words.length - 2;
    final hint = '$first ${'_ ' * hiddenCount}$last';

    return Text(
      hint,
      style: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: Colors.grey[500],
        letterSpacing: 1,
      ),
    );
  }
}

class _HiddenText extends StatelessWidget {
  const _HiddenText({required this.isCurrent});
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.hearing,
          size: 16,
          color: isCurrent ? AppColors.primary : Colors.grey[400],
        ),
        const SizedBox(width: 6),
        Text(
          'Listen…',
          style: TextStyle(
            color: isCurrent ? AppColors.primary : Colors.grey[400],
            fontStyle: FontStyle.italic,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

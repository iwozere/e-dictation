import 'package:flutter/material.dart';

import '../../../../core/scoring/scoring.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../dictations/domain/dictation.dart';

/// Shows the student's completed dictation results — score header plus a
/// per-sentence word-level diff breakdown. Used by both the player (immediately
/// after the student finishes) and the teacher preview modal.
class StudentResultsView extends StatelessWidget {
  const StudentResultsView({
    super.key,
    required this.sentences,
    required this.answers,
    this.scrollController,
  });

  final List<DictationSentence> sentences;

  /// Per-sentence answers keyed by sentence index (0-based).
  final Map<int, String> answers;

  /// Optional scroll controller — pass the [DraggableScrollableSheet]
  /// controller when rendering inside a bottom sheet so the sheet and the
  /// list share the same scroll axis.
  final ScrollController? scrollController;

  int get _score =>
      scoreAttempt(sentences, answers, ScoringMode.lenient).correct;

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final total = sentences.length;
    final scoreColor = score == total
        ? AppColors.success
        : score >= (total * 0.6).ceil()
        ? AppColors.warning
        : AppColors.error;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scoreColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                score == total ? Icons.check_circle : Icons.bar_chart_rounded,
                color: scoreColor,
              ),
              const SizedBox(width: 10),
              Text(
                'Score: $score / $total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ...sentences.asMap().entries.map((e) {
          final idx = e.key;
          final sentence = e.value;
          final answer = answers[idx] ?? '';
          final isCorrect =
              answer.isNotEmpty &&
              sentenceMatches(answer, sentence.text, ScoringMode.lenient);
          final isBlank = answer.isEmpty;

          final borderColor = isCorrect
              ? AppColors.success
              : isBlank
              ? Colors.grey
              : AppColors.error;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCorrect
                          ? Icons.check_circle
                          : isBlank
                          ? Icons.remove_circle_outline
                          : Icons.cancel,
                      size: 16,
                      color: borderColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sentence ${idx + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: borderColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isCorrect || isBlank)
                  Text(
                    sentence.text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.success,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  _DiffDisplay(
                    studentText: answer,
                    expectedText: sentence.text,
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Word-level diff display
// ---------------------------------------------------------------------------

class _DiffDisplay extends StatelessWidget {
  const _DiffDisplay({required this.studentText, required this.expectedText});
  final String studentText;
  final String expectedText;

  @override
  Widget build(BuildContext context) {
    final diff = wordDiff(studentText, expectedText, ScoringMode.lenient);
    final hasMissing = diff.any((d) => d.status == WordStatus.missing);
    final hasWrong = diff.any((d) => d.status == WordStatus.wrong);
    final legend = [
      if (hasMissing) '⟨word⟩ = missing word',
      if (hasWrong) 'struck through = wrong word',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CaptionLabel('Your answer:'),
        Text(studentText, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        const _CaptionLabel('Differences:'),
        Wrap(
          spacing: 3,
          runSpacing: 2,
          children: diff.map((d) {
            return switch (d.status) {
              WordStatus.correct => Text(
                d.word,
                style: const TextStyle(fontSize: 14),
              ),
              WordStatus.wrong => Text(
                d.word,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.error,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              WordStatus.missing => Tooltip(
                message: 'Missing word',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '⟨${d.word}⟩',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
            };
          }).toList(),
        ),
        if (legend.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(legend, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
        const SizedBox(height: 6),
        const _CaptionLabel('Correct:'),
        Text(
          expectedText,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.success,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Small grey caption above each block of the diff display.
class _CaptionLabel extends StatelessWidget {
  const _CaptionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
  );
}

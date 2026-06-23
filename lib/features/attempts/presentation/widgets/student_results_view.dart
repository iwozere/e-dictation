import 'dart:math';

import 'package:flutter/material.dart';

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

  int get _score => sentences.asMap().entries.where((e) {
        final answer = answers[e.key];
        if (answer == null || answer.isEmpty) return false;
        return _normalize(answer) == _normalize(e.value.text);
      }).length;

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
                score == total
                    ? Icons.check_circle
                    : Icons.bar_chart_rounded,
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
          final isCorrect = answer.isNotEmpty &&
              _normalize(answer) == _normalize(sentence.text);
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
              border:
                  Border.all(color: borderColor.withValues(alpha: 0.3)),
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
                        fontStyle: FontStyle.italic),
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
// Word-level diff
// ---------------------------------------------------------------------------

enum _WordStatus { correct, wrong, missing }

class _DiffWord {
  const _DiffWord(this.word, this.status);
  final String word;
  final _WordStatus status;
}

class _DiffDisplay extends StatelessWidget {
  const _DiffDisplay(
      {required this.studentText, required this.expectedText});
  final String studentText;
  final String expectedText;

  @override
  Widget build(BuildContext context) {
    final diff = _wordDiff(studentText, expectedText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your answer:',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 3),
        Wrap(
          spacing: 3,
          runSpacing: 2,
          children: diff.map((d) {
            return switch (d.status) {
              _WordStatus.correct =>
                Text(d.word, style: const TextStyle(fontSize: 14)),
              _WordStatus.wrong => Text(d.word,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.error,
                      decoration: TextDecoration.lineThrough)),
              _WordStatus.missing => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Text(d.word,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.warning)),
                ),
            };
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text('Correct:',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 3),
        Text(expectedText,
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.success,
                fontStyle: FontStyle.italic)),
      ],
    );
  }

  List<_DiffWord> _wordDiff(String student, String expected) {
    final sw = student
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final ew = expected
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final m = sw.length;
    final n = ew.length;

    final dp =
        List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        dp[i][j] =
            _normalize(sw[i - 1]) == _normalize(ew[j - 1])
                ? dp[i - 1][j - 1] + 1
                : max(dp[i - 1][j], dp[i][j - 1]);
      }
    }

    final result = <_DiffWord>[];
    int i = m, j = n;
    while (i > 0 || j > 0) {
      if (i > 0 &&
          j > 0 &&
          _normalize(sw[i - 1]) == _normalize(ew[j - 1])) {
        result.insert(0, _DiffWord(sw[i - 1], _WordStatus.correct));
        i--;
        j--;
      } else if (j > 0 &&
          (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        result.insert(0, _DiffWord(ew[j - 1], _WordStatus.missing));
        j--;
      } else {
        result.insert(0, _DiffWord(sw[i - 1], _WordStatus.wrong));
        i--;
      }
    }
    return result;
  }
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll('ß', 'ss').replaceAll(RegExp(r'[^\w\s]'), '').trim();

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../dictations/domain/dictation.dart';
import '../../domain/attempt.dart';

/// Per-sentence comparison of a student's [attempt] against the dictation
/// [sentences]: a ✓/✗/blank marker, the correct text, and (when wrong) what
/// the student actually typed. Shared by the teacher results screen and the
/// student history screen.
class AttemptBreakdown extends StatelessWidget {
  const AttemptBreakdown({
    super.key,
    required this.attempt,
    required this.sentences,
  });

  final Attempt attempt;
  final List<DictationSentence> sentences;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: sentences.asMap().entries.map((e) {
          final idx = e.key;
          final sentence = e.value;
          final answer = attempt.answers[idx] ?? '';
          final isCorrect = answer.isNotEmpty &&
              _normalize(answer) == _normalize(sentence.text);
          final isBlank = answer.isEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
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
                      size: 14,
                      color: isCorrect
                          ? AppColors.success
                          : isBlank
                              ? Colors.grey
                              : AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Text('Sentence ${idx + 1}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sentence.text,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.success,
                      fontStyle: FontStyle.italic),
                ),
                if (!isCorrect && !isBlank) ...[
                  const SizedBox(height: 2),
                  Text(
                    answer,
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.error),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();

import 'dart:math';

import '../../features/dictations/domain/dictation.dart';

/// Whether to apply lenient or strict comparison when scoring answers.
enum ScoringMode {
  /// Ignores capitalisation, punctuation, and treats ß/ss as equivalent.
  /// Keeps German umlauts (ä, ö, ü) as distinct from a/o/u.
  lenient,

  /// Exact match after trimming only. Every character counts.
  strict,
}

/// Status of a word in a [wordDiff] result.
enum WordStatus { correct, wrong, missing }

/// A single word in a word-level diff, with its comparison status.
class DiffWord {
  const DiffWord(this.word, this.status);
  final String word;
  final WordStatus status;
}

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

/// Normalises [s] for lenient comparison.
///
/// Steps: lowercase → ß→ss → strip non-[a-z0-9äöü\s] → trim.
/// Mirrors `normalize_lenient()` in migration 008_submit_attempt_rpc.sql.
/// The SQL and Dart functions must stay in sync.
String normalizeLenient(String s) => s
    .toLowerCase()
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'[^a-z0-9äöü\s]'), '')
    .trim();

// ---------------------------------------------------------------------------
// Sentence scoring
// ---------------------------------------------------------------------------

/// Returns true when [student] is a correct answer for [expected] under [mode].
bool sentenceMatches(String student, String expected, ScoringMode mode) {
  if (student.trim().isEmpty) return false;
  return switch (mode) {
    ScoringMode.strict  => student.trim() == expected.trim(),
    ScoringMode.lenient => normalizeLenient(student) == normalizeLenient(expected),
  };
}

// ---------------------------------------------------------------------------
// Attempt scoring
// ---------------------------------------------------------------------------

/// Score record returned by [scoreAttempt].
typedef AttemptScore = ({int correct, int total});

/// Scores all [sentences] against [answers] (keyed by sentence index).
AttemptScore scoreAttempt(
  List<DictationSentence> sentences,
  Map<int, String> answers,
  ScoringMode mode,
) {
  int correct = 0;
  for (var i = 0; i < sentences.length; i++) {
    final answer = answers[i];
    if (answer != null && sentenceMatches(answer, sentences[i].text, mode)) {
      correct++;
    }
  }
  return (correct: correct, total: sentences.length);
}

// ---------------------------------------------------------------------------
// Word-level diff (for results display)
// ---------------------------------------------------------------------------

/// Computes a word-level LCS diff between [student] and [expected].
///
/// Each word in the merged sequence is tagged [WordStatus.correct],
/// [WordStatus.wrong] (extra word the student wrote), or
/// [WordStatus.missing] (word the student omitted).
List<DiffWord> wordDiff(String student, String expected, ScoringMode mode) {
  String norm(String w) =>
      mode == ScoringMode.lenient ? normalizeLenient(w) : w.trim();

  final sw = student.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final ew = expected.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final m = sw.length;
  final n = ew.length;

  // Build LCS table.
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      dp[i][j] = norm(sw[i - 1]) == norm(ew[j - 1])
          ? dp[i - 1][j - 1] + 1
          : max(dp[i - 1][j], dp[i][j - 1]);
    }
  }

  // Backtrack to build diff.
  final result = <DiffWord>[];
  var i = m;
  var j = n;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && norm(sw[i - 1]) == norm(ew[j - 1])) {
      result.insert(0, DiffWord(sw[i - 1], WordStatus.correct));
      i--;
      j--;
    } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
      result.insert(0, DiffWord(ew[j - 1], WordStatus.missing));
      j--;
    } else {
      result.insert(0, DiffWord(sw[i - 1], WordStatus.wrong));
      i--;
    }
  }
  return result;
}

import 'package:flutter/foundation.dart';

import '../../dictations/domain/dictation.dart';

/// A single student submission for one dictation.
@immutable
class Attempt {
  const Attempt({
    required this.id,
    required this.dictationId,
    this.studentId,
    this.studentName,
    this.studentPinHash,
    required this.answers,
    required this.scoreCorrect,
    required this.scoreTotal,
    required this.completedAt,
    this.dictationTitle,
    this.sentences = const [],
  });

  final String id;
  final String dictationId;

  /// Supabase auth UID — set even for anonymous sessions.
  final String? studentId;

  /// Free-text name entered by the student before starting.
  final String? studentName;

  /// SHA-256 hex digest of the 4-digit PIN, or null if no PIN was set.
  final String? studentPinHash;

  /// Per-sentence answers keyed by sentence index.
  final Map<int, String> answers;

  final int scoreCorrect;
  final int scoreTotal;
  final DateTime completedAt;

  /// Title of the parent dictation, when the row was fetched with a join
  /// (teacher overview) or via the student-history RPC. Null for the
  /// per-dictation results view where the title is already known.
  final String? dictationTitle;

  /// The parent dictation's sentences, when fetched via the student-history
  /// RPC. Lets the history screen render the per-sentence mistake breakdown
  /// without a separate (RLS-protected) read of the dictations table.
  final List<DictationSentence> sentences;

  bool get hasPinSet => studentPinHash != null;

  String get displayName => studentName?.isNotEmpty == true ? studentName! : '(anonymous)';

  factory Attempt.fromJson(Map<String, dynamic> json) {
    final raw = json['answers'] as Map<String, dynamic>? ?? {};

    // dictationTitle may arrive flat (`dictation_title`, from the RPC) or
    // nested under the joined `dictations` relation (PostgREST embed).
    final nestedDictation = json['dictations'] as Map<String, dynamic>?;
    final dictationTitle = json['dictation_title'] as String? ??
        nestedDictation?['title'] as String?;

    final rawSentences = json['sentences'] as List<dynamic>?;

    return Attempt(
      id: json['id'] as String,
      dictationId: json['dictation_id'] as String,
      studentId: json['student_id'] as String?,
      studentName: json['student_name'] as String?,
      studentPinHash: json['student_pin_hash'] as String?,
      answers: raw.map((k, v) => MapEntry(int.parse(k), v as String)),
      scoreCorrect: json['score_correct'] as int? ?? 0,
      scoreTotal: json['score_total'] as int? ?? 0,
      completedAt: DateTime.parse(json['completed_at'] as String),
      dictationTitle: dictationTitle,
      sentences: rawSentences == null
          ? const []
          : (rawSentences
              .map((s) => DictationSentence.fromJson(s as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position))),
    );
  }
}

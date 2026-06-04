import 'package:flutter/foundation.dart';

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

  bool get hasPinSet => studentPinHash != null;

  String get displayName => studentName?.isNotEmpty == true ? studentName! : '(anonymous)';

  factory Attempt.fromJson(Map<String, dynamic> json) {
    final raw = json['answers'] as Map<String, dynamic>? ?? {};
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
    );
  }
}

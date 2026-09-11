import 'quiz_card.dart';

/// Which side was the prompt vs. the answer for a whole session — chosen
/// once before starting and locked for the session (CR doc, Key decision
/// #3), unlike cards' freely-switchable [PracticeMode].
enum QuizDirection {
  /// Side A shown as the prompt; student answers in side B.
  aToB,

  /// Side B shown as the prompt; student answers in side A.
  bToA;

  static QuizDirection fromString(String v) =>
      v == 'b_to_a' ? QuizDirection.bToA : QuizDirection.aToB;

  String get value => this == QuizDirection.aToB ? 'a_to_b' : 'b_to_a';

  QuizSide get promptSide =>
      this == QuizDirection.aToB ? QuizSide.a : QuizSide.b;
  QuizSide get answerSide => promptSide.opposite;
}

enum QuizEndedReason {
  completed,
  outOfLives,
  abandoned;

  static QuizEndedReason fromString(String v) => switch (v) {
    'out_of_lives' => QuizEndedReason.outOfLives,
    'abandoned' => QuizEndedReason.abandoned,
    _ => QuizEndedReason.completed,
  };
}

/// One card's outcome within a submitted attempt — the per-card breakdown
/// the CR doc's results screen requires (§8), mirrors `attempts.mistakes`.
class QuizAnswerRecord {
  const QuizAnswerRecord({
    required this.cardId,
    this.optionId,
    required this.correct,
    required this.timedOut,
    this.timeTakenMs,
  });

  final String cardId;
  final String? optionId;
  final bool correct;
  final bool timedOut;
  final int? timeTakenMs;

  factory QuizAnswerRecord.fromJson(Map<String, dynamic> json) =>
      QuizAnswerRecord(
        cardId: json['card_id'] as String,
        optionId: json['option_id'] as String?,
        correct: json['correct'] as bool? ?? false,
        timedOut: json['timed_out'] as bool? ?? false,
        timeTakenMs: json['time_taken_ms'] as int?,
      );

  Map<String, dynamic> toJson() => {
    'card_id': cardId,
    'option_id': optionId,
    'timed_out': timedOut,
    'time_taken_ms': timeTakenMs,
  };
}

/// A single student's completed quiz session (mirrors `quiz_attempts`),
/// shown on the teacher results screen.
class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.deckId,
    this.deckTitle,
    this.studentName,
    this.studentPinHash,
    required this.direction,
    required this.correctCount,
    required this.wrongCount,
    required this.bestStreak,
    this.livesRemaining,
    required this.endedReason,
    this.answers = const [],
    this.startedAt,
    required this.submittedAt,
  });

  final String id;
  final String deckId;

  /// Only populated by queries that join `quiz_decks` (the teacher-wide
  /// "all quiz attempts" list) — null for the single-deck results screen,
  /// which already knows the deck it's showing.
  final String? deckTitle;
  final String? studentName;
  final String? studentPinHash;
  final QuizDirection direction;
  final int correctCount;
  final int wrongCount;
  final int bestStreak;
  final int? livesRemaining;
  final QuizEndedReason endedReason;
  final List<QuizAnswerRecord> answers;
  final DateTime? startedAt;
  final DateTime submittedAt;

  int get totalCount => correctCount + wrongCount;
  bool get hasPinSet => studentPinHash != null && studentPinHash!.isNotEmpty;
  String get displayName => (studentName == null || studentName!.isEmpty)
      ? '(anonymous)'
      : studentName!;

  factory QuizAttempt.fromJson(Map<String, dynamic> json) => QuizAttempt(
    id: json['id'] as String,
    deckId: json['deck_id'] as String,
    deckTitle:
        (json['quiz_decks'] as Map<String, dynamic>?)?['title'] as String?,
    studentName: json['student_name'] as String?,
    studentPinHash: json['student_pin_hash'] as String?,
    direction: QuizDirection.fromString(json['direction'] as String),
    correctCount: json['correct_count'] as int? ?? 0,
    wrongCount: json['wrong_count'] as int? ?? 0,
    bestStreak: json['best_streak'] as int? ?? 0,
    livesRemaining: json['lives_remaining'] as int?,
    endedReason: QuizEndedReason.fromString(
      json['ended_reason'] as String? ?? 'completed',
    ),
    answers:
        (json['answers'] as List<dynamic>?)
            ?.map((a) => QuizAnswerRecord.fromJson(a as Map<String, dynamic>))
            .toList() ??
        const [],
    startedAt: json['started_at'] != null
        ? DateTime.parse(json['started_at'] as String)
        : null,
    submittedAt: DateTime.parse(json['submitted_at'] as String),
  );
}

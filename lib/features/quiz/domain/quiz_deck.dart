import '../../dictations/domain/dictation.dart' show DictationLanguage;
import 'quiz_card.dart';

/// Domain model for a quiz deck (mirrors the `quiz_decks` table).
///
/// See docs/cr-quiz-decks-timed-multiple-choice.md. Independent of
/// `CardDeck` — same free two-language shape, but authored with a variant
/// pool per card/side plus timer/lives/session settings, and results are
/// persisted (unlike card decks).
class QuizDeck {
  const QuizDeck({
    required this.id,
    required this.ownerId,
    this.classId,
    required this.title,
    required this.languageA,
    required this.languageB,
    this.status = QuizDeckStatus.draft,
    this.statusError,
    this.sessionLength = 20,
    this.timerInitialSecs = 10,
    this.timerDecaySecs = 1,
    this.timerDecayEveryNCards = 3,
    this.timerFloorSecs = 3,
    this.livesEnabled = true,
    this.livesCount = 3,
    this.sourceCardDeckId,
    this.shareCode,
    required this.createdAt,
    required this.updatedAt,
    this.cards = const [],
  });

  final String id;
  final String ownerId;
  final String? classId;
  final String title;
  final DictationLanguage languageA;
  final DictationLanguage languageB;
  final QuizDeckStatus status;
  final String? statusError;

  /// Null means "the whole deck, shuffled once" rather than a fixed count.
  final int? sessionLength;
  final int timerInitialSecs;
  final int timerDecaySecs;
  final int timerDecayEveryNCards;
  final int timerFloorSecs;
  final bool livesEnabled;
  final int livesCount;
  final String? sourceCardDeckId;
  final String? shareCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Eagerly loaded cards (optional join).
  final List<QuizCard> cards;

  bool get isReady => status == QuizDeckStatus.ready;
  bool get isPending => status == QuizDeckStatus.pending;

  factory QuizDeck.fromJson(Map<String, dynamic> json) => QuizDeck(
    id: json['id'] as String,
    ownerId: json['owner_id'] as String? ?? '',
    classId: json['class_id'] as String?,
    title: json['title'] as String,
    languageA: DictationLanguage.fromCode(json['language_a'] as String),
    languageB: DictationLanguage.fromCode(json['language_b'] as String),
    status: QuizDeckStatus.fromString(json['status'] as String? ?? 'draft'),
    statusError: json['status_error'] as String?,
    sessionLength: json['session_length'] as int?,
    timerInitialSecs: json['timer_initial_secs'] as int? ?? 10,
    timerDecaySecs: json['timer_decay_secs'] as int? ?? 1,
    timerDecayEveryNCards: json['timer_decay_every_n_cards'] as int? ?? 3,
    timerFloorSecs: json['timer_floor_secs'] as int? ?? 3,
    livesEnabled: json['lives_enabled'] as bool? ?? true,
    livesCount: json['lives_count'] as int? ?? 3,
    sourceCardDeckId: json['source_card_deck_id'] as String?,
    shareCode: json['share_code'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now(),
    updatedAt: json['updated_at'] != null
        ? DateTime.parse(json['updated_at'] as String)
        : DateTime.now(),
    cards:
        ((json['cards'] as List<dynamic>?)
                  ?.map((c) => QuizCard.fromJson(c as Map<String, dynamic>))
                  .toList() ??
              [])
          ..sort((a, b) => a.position.compareTo(b.position)),
  );

  QuizDeck copyWith({
    QuizDeckStatus? status,
    String? statusError,
    List<QuizCard>? cards,
  }) => QuizDeck(
    id: id,
    ownerId: ownerId,
    classId: classId,
    title: title,
    languageA: languageA,
    languageB: languageB,
    status: status ?? this.status,
    statusError: statusError ?? this.statusError,
    sessionLength: sessionLength,
    timerInitialSecs: timerInitialSecs,
    timerDecaySecs: timerDecaySecs,
    timerDecayEveryNCards: timerDecayEveryNCards,
    timerFloorSecs: timerFloorSecs,
    livesEnabled: livesEnabled,
    livesCount: livesCount,
    sourceCardDeckId: sourceCardDeckId,
    shareCode: shareCode,
    createdAt: createdAt,
    updatedAt: updatedAt,
    cards: cards ?? this.cards,
  );

  Map<String, dynamic> toInsertJson() => {
    'owner_id': ownerId,
    if (classId != null) 'class_id': classId,
    'title': title,
    'language_a': languageA.code,
    'language_b': languageB.code,
    'session_length': sessionLength,
    'timer_initial_secs': timerInitialSecs,
    'timer_decay_secs': timerDecaySecs,
    'timer_decay_every_n_cards': timerDecayEveryNCards,
    'timer_floor_secs': timerFloorSecs,
    'lives_enabled': livesEnabled,
    'lives_count': livesCount,
  };
}

/// Validates the 4 teacher-configurable timer/session settings (CR
/// follow-up: "make configurable per quiz"), mirroring the DB's
/// `quiz_decks_floor_below_initial` check constraint plus the positivity
/// checks on each column. Returns a human-readable problem, or null if
/// every value is valid. Shared by the create screen and the deck-detail
/// settings dialog so the two can't drift apart.
String? validateQuizTimerSettings({
  required int timerInitialSecs,
  required int timerFloorSecs,
  required int timerDecayEveryNCards,
}) {
  if (timerInitialSecs <= 0) {
    return 'Starting time must be at least 1 second.';
  }
  if (timerFloorSecs <= 0) {
    return 'Minimum time must be at least 1 second.';
  }
  if (timerDecayEveryNCards <= 0) {
    return 'Cards between decreases must be at least 1.';
  }
  if (timerFloorSecs > timerInitialSecs) {
    return "Minimum time can't be greater than the starting time.";
  }
  return null;
}

// ---------------------------------------------------------------------------

enum QuizDeckStatus {
  /// Editable — cards/options can be added, edited, deleted. No audio yet.
  draft,

  /// `generate_quiz_audio` is running.
  pending,

  /// Audio generated for every option; shareable with students.
  ready,

  /// Audio generation failed; see [QuizDeck.statusError].
  failed;

  static QuizDeckStatus fromString(String v) => switch (v) {
    'pending' => QuizDeckStatus.pending,
    'ready' => QuizDeckStatus.ready,
    'failed' => QuizDeckStatus.failed,
    _ => QuizDeckStatus.draft,
  };
}

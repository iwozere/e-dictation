import '../../../core/scoring/scoring.dart' show ScoringMode;
import '../../dictations/domain/dictation.dart' show DictationLanguage;
import 'card_pair.dart';

/// Domain model for a card deck (mirrors the `card_decks` table).
///
/// A deck is authored around two languages, [languageA] and [languageB] —
/// not a fixed native/foreign pair. Each student picks their own base
/// language when they open the share link, so either side can end up
/// "foreign" for a given practice session. See
/// docs/cr-card-decks-language-flashcards.md.
class CardDeck {
  const CardDeck({
    required this.id,
    required this.ownerId,
    this.classId,
    required this.title,
    required this.languageA,
    required this.languageB,
    this.status = CardDeckStatus.pending,
    this.statusError,
    this.scoringMode = ScoringMode.lenient,
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
  final CardDeckStatus status;
  final String? statusError;
  final ScoringMode scoringMode;
  final String? shareCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Eagerly loaded cards (optional join).
  final List<CardPair> cards;

  bool get isReady => status == CardDeckStatus.ready;

  factory CardDeck.fromJson(Map<String, dynamic> json) => CardDeck(
    id: json['id'] as String,
    ownerId: json['owner_id'] as String,
    classId: json['class_id'] as String?,
    title: json['title'] as String,
    languageA: DictationLanguage.fromCode(json['language_a'] as String),
    languageB: DictationLanguage.fromCode(json['language_b'] as String),
    status: CardDeckStatus.fromString(json['status'] as String? ?? 'pending'),
    statusError: json['status_error'] as String?,
    scoringMode: (json['scoring_mode'] as String?) == 'strict'
        ? ScoringMode.strict
        : ScoringMode.lenient,
    shareCode: json['share_code'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
    cards:
        ((json['cards'] as List<dynamic>?)
                  ?.map((c) => CardPair.fromJson(c as Map<String, dynamic>))
                  .toList() ??
              [])
          ..sort((a, b) => a.position.compareTo(b.position)),
  );

  Map<String, dynamic> toInsertJson() => {
    'owner_id': ownerId,
    if (classId != null) 'class_id': classId,
    'title': title,
    'language_a': languageA.code,
    'language_b': languageB.code,
  };

  CardDeck copyWith({
    String? title,
    CardDeckStatus? status,
    String? statusError,
    List<CardPair>? cards,
  }) => CardDeck(
    id: id,
    ownerId: ownerId,
    classId: classId,
    title: title ?? this.title,
    languageA: languageA,
    languageB: languageB,
    status: status ?? this.status,
    statusError: statusError ?? this.statusError,
    scoringMode: scoringMode,
    shareCode: shareCode,
    createdAt: createdAt,
    updatedAt: updatedAt,
    cards: cards ?? this.cards,
  );
}

// ---------------------------------------------------------------------------

enum CardDeckStatus {
  /// Photo upload accepted; Claude parsing (or TTS generation) in flight.
  pending,

  /// Pairs extracted, awaiting teacher review before audio is generated.
  draft,

  /// Audio generated; shareable with students.
  ready,

  /// Parsing or audio generation failed; see [CardDeck.statusError].
  failed;

  static CardDeckStatus fromString(String v) => switch (v) {
    'draft' => CardDeckStatus.draft,
    'ready' => CardDeckStatus.ready,
    'failed' => CardDeckStatus.failed,
    _ => CardDeckStatus.pending,
  };
}

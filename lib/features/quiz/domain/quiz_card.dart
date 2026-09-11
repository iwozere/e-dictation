/// Which side of a [QuizCard] — corresponds to a deck's `languageA`/`languageB`.
///
/// Named "side" rather than "language" for the same reason as cards'
/// `CardSide`: which side is native/foreign is a session-level choice, not
/// baked into the card. Kept as its own type (not shared with the cards
/// feature) since quiz decks are an independent feature — see
/// docs/cr-quiz-decks-timed-multiple-choice.md's "Relationship to Card
/// Decks" section.
enum QuizSide {
  a,
  b;

  QuizSide get opposite => this == QuizSide.a ? QuizSide.b : QuizSide.a;
}

/// One answer option for a card's side (mirrors a `quiz_card_options` row).
///
/// [isCorrect] is only ever populated when the teacher fetches a deck they
/// own (direct table access, RLS-scoped). The public
/// `get_quiz_deck_by_share_code` RPC never includes it — the student-facing
/// client is not supposed to know which of the 3 shown options is correct
/// until it asks `check_quiz_answer` after a click. See the CR doc's
/// Security section.
class QuizOption {
  const QuizOption({
    required this.id,
    required this.text,
    this.audioUrl,
    this.audioDurationMs,
    this.isCorrect,
  });

  final String id;
  final String text;
  final String? audioUrl;
  final int? audioDurationMs;
  final bool? isCorrect;

  factory QuizOption.fromJson(Map<String, dynamic> json) => QuizOption(
    id: json['id'] as String,
    text: json['text'] as String,
    audioUrl: json['audio_url'] as String?,
    audioDurationMs: json['audio_duration_ms'] as int?,
    isCorrect: json['is_correct'] as bool?,
  );
}

/// Domain model for a single quiz card (mirrors the `quiz_cards` table).
///
/// Unlike `CardPair`, there's no single `textA`/`textB` — the correct
/// answer is just the option flagged [QuizOption.isCorrect] within
/// [optionsA]/[optionsB]. See the CR doc's Key decision #2.
class QuizCard {
  const QuizCard({
    required this.id,
    required this.deckId,
    required this.position,
    this.optionsA = const [],
    this.optionsB = const [],
  });

  final String id;
  final String deckId;
  final int position;

  /// Answer options in language A. For a teacher-owned fetch, this is the
  /// full authored pool; for a student's public fetch, exactly 3 (the
  /// correct one + 2 random wrong ones), pre-selected server-side.
  final List<QuizOption> optionsA;
  final List<QuizOption> optionsB;

  List<QuizOption> optionsFor(QuizSide side) =>
      side == QuizSide.a ? optionsA : optionsB;

  /// Only meaningful when [QuizOption.isCorrect] is populated (teacher
  /// context) — null on a student's public fetch.
  QuizOption? correctOptionFor(QuizSide side) {
    for (final o in optionsFor(side)) {
      if (o.isCorrect == true) return o;
    }
    return null;
  }

  factory QuizCard.fromJson(Map<String, dynamic> json) => QuizCard(
    id: json['id'] as String,
    deckId: json['deck_id'] as String? ?? '',
    position: json['position'] as int,
    optionsA:
        (json['options_a'] as List<dynamic>?)
            ?.map((o) => QuizOption.fromJson(o as Map<String, dynamic>))
            .toList() ??
        const [],
    optionsB:
        (json['options_b'] as List<dynamic>?)
            ?.map((o) => QuizOption.fromJson(o as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

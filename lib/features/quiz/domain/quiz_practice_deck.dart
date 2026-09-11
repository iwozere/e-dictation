import '../../dictations/domain/dictation.dart' show DictationLanguage;
import 'quiz_attempt.dart';
import 'quiz_card.dart' show QuizOption;

/// One card as returned by `get_quiz_deck_by_share_code` **once a
/// direction has been chosen** — already split server-side into the
/// prompt (single, unambiguous) and the answer options (3, `is_correct`
/// hidden). See [QuizPracticeDeck] and the CR doc's Security section for
/// why this is a different shape from the teacher-facing `QuizCard`.
///
/// Before a direction is chosen, [promptText] is empty and [options] is
/// empty — the pre-direction fetch only needs `card_count` for the choice
/// screen, not per-card content.
class QuizPromptCard {
  const QuizPromptCard({
    required this.id,
    required this.position,
    this.promptText = '',
    this.promptAudioUrl,
    this.promptAudioDurationMs,
    this.options = const [],
  });

  final String id;
  final int position;
  final String promptText;
  final String? promptAudioUrl;
  final int? promptAudioDurationMs;

  /// Exactly 3 options once a direction is set: the correct answer plus 2
  /// random wrong ones, shuffled server-side, `isCorrect` always null here.
  final List<QuizOption> options;

  factory QuizPromptCard.fromJson(Map<String, dynamic> json) {
    final prompt = json['prompt'] as Map<String, dynamic>?;
    return QuizPromptCard(
      id: json['id'] as String,
      position: json['position'] as int,
      promptText: prompt?['text'] as String? ?? '',
      promptAudioUrl: prompt?['audio_url'] as String?,
      promptAudioDurationMs: prompt?['audio_duration_ms'] as int?,
      options:
          (json['options'] as List<dynamic>?)
              ?.map((o) => QuizOption.fromJson(o as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// The public, student-facing view of a quiz deck — result of
/// `get_quiz_deck_by_share_code`. Deliberately a separate type from
/// [QuizDeck] rather than a dual-purpose model: the teacher's owner-scoped
/// fetch needs the full authored option pool per side with `isCorrect`
/// visible for editing, while this needs the direction-reduced shape above.
class QuizPracticeDeck {
  const QuizPracticeDeck({
    required this.id,
    required this.title,
    required this.languageA,
    required this.languageB,
    this.sessionLength,
    this.timerInitialSecs = 10,
    this.timerDecaySecs = 1,
    this.timerDecayEveryNCards = 3,
    this.timerFloorSecs = 3,
    this.livesEnabled = true,
    this.livesCount = 3,
    this.shareCode,
    this.cardCount = 0,
    this.cards = const [],
  });

  final String id;
  final String title;
  final DictationLanguage languageA;
  final DictationLanguage languageB;
  final int? sessionLength;
  final int timerInitialSecs;
  final int timerDecaySecs;
  final int timerDecayEveryNCards;
  final int timerFloorSecs;
  final bool livesEnabled;
  final int livesCount;
  final String? shareCode;
  final int cardCount;
  final List<QuizPromptCard> cards;

  /// The countdown length for the card at [position] (0-based): starts at
  /// [timerInitialSecs] and shortens by [timerDecaySecs] every
  /// [timerDecayEveryNCards] cards, down to [timerFloorSecs] — see the CR
  /// doc's Key decision #5. Shared by the session notifier and the
  /// countdown UI so both agree on the same number.
  int timerSecondsForPosition(int position) {
    final decaySteps = position ~/ timerDecayEveryNCards;
    final secs = timerInitialSecs - decaySteps * timerDecaySecs;
    return secs < timerFloorSecs ? timerFloorSecs : secs;
  }

  factory QuizPracticeDeck.fromJson(Map<String, dynamic> json) =>
      QuizPracticeDeck(
        id: json['id'] as String,
        title: json['title'] as String,
        languageA: DictationLanguage.fromCode(json['language_a'] as String),
        languageB: DictationLanguage.fromCode(json['language_b'] as String),
        sessionLength: json['session_length'] as int?,
        timerInitialSecs: json['timer_initial_secs'] as int? ?? 10,
        timerDecaySecs: json['timer_decay_secs'] as int? ?? 1,
        timerDecayEveryNCards: json['timer_decay_every_n_cards'] as int? ?? 3,
        timerFloorSecs: json['timer_floor_secs'] as int? ?? 3,
        livesEnabled: json['lives_enabled'] as bool? ?? true,
        livesCount: json['lives_count'] as int? ?? 3,
        shareCode: json['share_code'] as String?,
        cardCount: json['card_count'] as int? ?? 0,
        cards:
            ((json['cards'] as List<dynamic>?)
                      ?.map(
                        (c) =>
                            QuizPromptCard.fromJson(c as Map<String, dynamic>),
                      )
                      .toList() ??
                  [])
              ..sort((a, b) => a.position.compareTo(b.position)),
      );
}

/// Human label for a [QuizPracticeDeck]'s language pair given a direction.
extension QuizPracticeDeckLabels on QuizPracticeDeck {
  String promptLanguageLabel(QuizDirection direction) =>
      direction.promptSide.name == 'a' ? languageA.label : languageB.label;
  String answerLanguageLabel(QuizDirection direction) =>
      direction.answerSide.name == 'a' ? languageA.label : languageB.label;
}

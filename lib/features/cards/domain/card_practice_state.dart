import 'card_pair.dart';

/// Which language is shown as the prompt vs. expected as the typed answer,
/// relative to whichever side the student picked as their native language
/// this session. See docs/cr-card-decks-language-flashcards.md.
enum PracticeMode {
  /// Native text shown; student types the foreign text.
  nativeToForeign,

  /// Foreign text shown; student types the native text.
  foreignToNative;

  String get label => switch (this) {
    PracticeMode.nativeToForeign => 'Native → Foreign',
    PracticeMode.foreignToNative => 'Foreign → Native',
  };
}

enum PracticeAudioStatus { idle, loading, playing, error }

/// State for the student flashcard-practice screen (see
/// `CardPracticeNotifier`). Unlike [PlaybackStateModel]'s sentence playlist,
/// a flashcard session plays one clip at a time and advances only when the
/// student submits an answer — no auto-advance timers.
class CardPracticeState {
  const CardPracticeState({
    this.cards = const [],
    this.currentIndex = 0,
    this.nativeSide = CardSide.a,
    this.mode = PracticeMode.nativeToForeign,
    this.audioStatus = PracticeAudioStatus.idle,
    this.lastAnswerCorrect,
    this.correctCount = 0,
    this.answeredCount = 0,
    this.completed = false,
    this.errorMessage,
  });

  static const empty = CardPracticeState();

  final List<CardPair> cards;
  final int currentIndex;

  /// The language side the student identified as their own going into this
  /// session. The opposite side is "foreign" for every card.
  final CardSide nativeSide;
  final PracticeMode mode;
  final PracticeAudioStatus audioStatus;

  /// Result of the most recent submission for the current card; null once a
  /// new card is shown and no answer has been submitted yet.
  final bool? lastAnswerCorrect;
  final int correctCount;
  final int answeredCount;
  final bool completed;
  final String? errorMessage;

  CardPair? get currentCard =>
      currentIndex < cards.length ? cards[currentIndex] : null;

  CardSide get foreignSide => nativeSide.opposite;

  /// The side whose text is displayed as the prompt.
  CardSide get promptSide =>
      mode == PracticeMode.nativeToForeign ? nativeSide : foreignSide;

  /// The side the student's typed answer is graded against.
  CardSide get answerSide => promptSide.opposite;

  /// Audio always plays the foreign side — see the CR doc's mode table.
  CardSide get audioSide => foreignSide;

  String? get promptText => currentCard?.textFor(promptSide);
  String? get expectedAnswer => currentCard?.textFor(answerSide);
  String? get promptAudioUrl => currentCard?.audioUrlFor(audioSide);

  CardPracticeState copyWith({
    List<CardPair>? cards,
    int? currentIndex,
    CardSide? nativeSide,
    PracticeMode? mode,
    PracticeAudioStatus? audioStatus,
    bool? lastAnswerCorrect,
    bool clearLastAnswerCorrect = false,
    int? correctCount,
    int? answeredCount,
    bool? completed,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => CardPracticeState(
    cards: cards ?? this.cards,
    currentIndex: currentIndex ?? this.currentIndex,
    nativeSide: nativeSide ?? this.nativeSide,
    mode: mode ?? this.mode,
    audioStatus: audioStatus ?? this.audioStatus,
    lastAnswerCorrect: clearLastAnswerCorrect
        ? null
        : (lastAnswerCorrect ?? this.lastAnswerCorrect),
    correctCount: correctCount ?? this.correctCount,
    answeredCount: answeredCount ?? this.answeredCount,
    completed: completed ?? this.completed,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}

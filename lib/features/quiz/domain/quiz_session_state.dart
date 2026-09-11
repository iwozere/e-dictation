import 'quiz_attempt.dart';
import 'quiz_card.dart' show QuizOption;
import 'quiz_practice_deck.dart';

/// Result of the most recent click (or timeout), shown as the green/red
/// feedback overlay while the next card is queued up (CR doc, Key decision
/// #6 / #5's timeout rule).
class QuizFeedback {
  const QuizFeedback({
    required this.correct,
    this.selectedOptionId,
    this.correctOptionId,
    this.correctText,
    this.correctAudioUrl,
  });

  /// Null on a timeout — nothing was clicked.
  final String? selectedOptionId;
  final bool correct;

  /// Always populated so the correct answer can be revealed/pronounced,
  /// even when [correct] is true.
  final String? correctOptionId;
  final String? correctText;
  final String? correctAudioUrl;
}

/// State for the student quiz-practice screen, driven by
/// `QuizSessionNotifier`. Unlike `CardPracticeState`, this has a live
/// countdown, a lives budget, and a streak — see the CR doc's "Student
/// flow" section.
class QuizSessionState {
  const QuizSessionState({
    this.deck,
    this.sessionCards = const [],
    this.direction = QuizDirection.aToB,
    this.currentIndex = 0,
    this.secondsRemaining = 0,
    this.feedback,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.livesRemaining,
    this.answers = const [],
    this.completed = false,
    this.endedReason,
    this.submitting = false,
    this.errorMessage,
  });

  static const empty = QuizSessionState();

  final QuizPracticeDeck? deck;

  /// The cards for this session, in play order — sampled from the deck at
  /// load time (see the CR doc's "Session structure" decision). May repeat
  /// a card if `session_length` exceeds the deck size. Each card's
  /// `options` are already reduced/shuffled server-side for [direction]'s
  /// answer side — see `QuizPromptCard`.
  final List<QuizPromptCard> sessionCards;

  final QuizDirection direction;
  final int currentIndex;

  /// Ticks down once per second; reaching 0 counts as a wrong answer.
  final int secondsRemaining;

  /// Non-null while the correct/incorrect overlay is showing, between a
  /// click (or timeout) and the auto-advance to the next card.
  final QuizFeedback? feedback;

  final int correctCount;
  final int wrongCount;
  final int streak;
  final int bestStreak;

  /// Null when the deck has lives disabled.
  final int? livesRemaining;

  final List<QuizAnswerRecord> answers;
  final bool completed;
  final QuizEndedReason? endedReason;

  /// True while `submit_quiz_attempt` is in flight after the last card.
  final bool submitting;
  final String? errorMessage;

  QuizPromptCard? get currentCard =>
      currentIndex < sessionCards.length ? sessionCards[currentIndex] : null;

  List<QuizOption> get currentOptions => currentCard?.options ?? const [];

  bool get outOfLives => livesRemaining != null && livesRemaining! <= 0;
  bool get isAnswered => feedback != null;
  int get totalCount => correctCount + wrongCount;

  QuizSessionState copyWith({
    QuizPracticeDeck? deck,
    List<QuizPromptCard>? sessionCards,
    QuizDirection? direction,
    int? currentIndex,
    int? secondsRemaining,
    QuizFeedback? feedback,
    bool clearFeedback = false,
    int? correctCount,
    int? wrongCount,
    int? streak,
    int? bestStreak,
    int? livesRemaining,
    List<QuizAnswerRecord>? answers,
    bool? completed,
    QuizEndedReason? endedReason,
    bool? submitting,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => QuizSessionState(
    deck: deck ?? this.deck,
    sessionCards: sessionCards ?? this.sessionCards,
    direction: direction ?? this.direction,
    currentIndex: currentIndex ?? this.currentIndex,
    secondsRemaining: secondsRemaining ?? this.secondsRemaining,
    feedback: clearFeedback ? null : (feedback ?? this.feedback),
    correctCount: correctCount ?? this.correctCount,
    wrongCount: wrongCount ?? this.wrongCount,
    streak: streak ?? this.streak,
    bestStreak: bestStreak ?? this.bestStreak,
    livesRemaining: livesRemaining ?? this.livesRemaining,
    answers: answers ?? this.answers,
    completed: completed ?? this.completed,
    endedReason: endedReason ?? this.endedReason,
    submitting: submitting ?? this.submitting,
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}

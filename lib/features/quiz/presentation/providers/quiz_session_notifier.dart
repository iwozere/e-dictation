import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

import '../../domain/quiz_attempt.dart';
import '../../domain/quiz_card.dart' show QuizOption;
import '../../domain/quiz_practice_deck.dart';
import '../../domain/quiz_session_state.dart';
import 'quiz_provider.dart';

final _log = Logger('quiz.QuizSessionNotifier');

/// How long the correct/incorrect feedback stays on screen before the
/// session auto-advances to the next card (CR doc's "brief pause").
const _interstitialPause = Duration(milliseconds: 1500);

final quizSessionNotifierProvider =
    NotifierProvider<QuizSessionNotifier, QuizSessionState>(
      QuizSessionNotifier.new,
    );

/// Drives the student quiz-practice screen: countdown timer, lives, streak,
/// per-click server-side scoring, and the final `submit_quiz_attempt` call.
///
/// Correctness is never computed client-side — every click (and every
/// timeout, via a throwaway `check_quiz_answer` call against one of the
/// shown options) round-trips through the server. See the CR doc's
/// Security section and `check_quiz_answer` in migration 012.
class QuizSessionNotifier extends Notifier<QuizSessionState> {
  Timer? _tickTimer;
  Timer? _advanceTimer;
  late final AudioPlayer _player;

  String? _studentName;
  String? _studentPinHash;
  DateTime _sessionStartedAt = DateTime.now();
  DateTime _cardStartedAt = DateTime.now();

  @override
  QuizSessionState build() {
    _player = AudioPlayer();
    ref.onDispose(() {
      _tickTimer?.cancel();
      _advanceTimer?.cancel();
      _player.dispose();
    });
    return QuizSessionState.empty;
  }

  /// Loads a deck and starts a fresh session. [direction] is locked for the
  /// whole session (CR doc, Key decision #3).
  void load({
    required QuizPracticeDeck deck,
    required QuizDirection direction,
    String? studentName,
    String? studentPinHash,
  }) {
    _tickTimer?.cancel();
    _advanceTimer?.cancel();

    _studentName = studentName;
    _studentPinHash = studentPinHash;
    _sessionStartedAt = DateTime.now();
    _cardStartedAt = _sessionStartedAt;

    final sessionCards = _buildSessionCards(deck);

    state = QuizSessionState(
      deck: deck,
      sessionCards: sessionCards,
      direction: direction,
      currentIndex: 0,
      secondsRemaining: deck.timerSecondsForPosition(0),
      livesRemaining: deck.livesEnabled ? deck.livesCount : null,
    );

    if (sessionCards.isNotEmpty) _startTick();
  }

  /// Re-runs the same deck/direction/identity as a fresh session.
  void restart() {
    final deck = state.deck;
    if (deck == null) return;
    load(
      deck: deck,
      direction: state.direction,
      studentName: _studentName,
      studentPinHash: _studentPinHash,
    );
  }

  /// Handles a click on one of the 3 shown options.
  Future<void> selectOption(String optionId) async {
    if (state.isAnswered || state.completed) return;
    final card = state.currentCard;
    if (card == null) return;

    _tickTimer?.cancel();
    final timeTakenMs = DateTime.now()
        .difference(_cardStartedAt)
        .inMilliseconds;

    final selected = card.options.where((o) => o.id == optionId).firstOrNull;

    final (isCorrect, correctOption, failure) = await ref
        .read(quizRepositoryProvider)
        .checkAnswer(optionId);

    if (failure != null || isCorrect == null) {
      _log.warning('checkAnswer failed: %s', failure);
      state = state.copyWith(errorMessage: 'Could not check that answer.');
      _startTick();
      return;
    }

    _applyResult(
      selectedOptionId: optionId,
      correct: isCorrect,
      timedOut: false,
      correctOption: correctOption,
      timeTakenMs: timeTakenMs,
    );

    unawaited(
      _playFeedbackAudio(
        clickedUrl: selected?.audioUrl,
        correct: isCorrect,
        correctUrl: correctOption?.audioUrl,
      ),
    );
  }

  Future<void> _handleTimeout() async {
    if (state.isAnswered || state.completed) return;
    final card = state.currentCard;
    final options = card?.options ?? const [];
    if (options.isEmpty) return;

    final timeTakenMs = DateTime.now()
        .difference(_cardStartedAt)
        .inMilliseconds;

    // No option was clicked, so there's nothing to check for correctness —
    // this probes an arbitrary shown option purely to get back
    // `correct_option` (always returned regardless of that option's own
    // correctness) so the reveal UI has something to show/pronounce.
    final (_, correctOption, failure) = await ref
        .read(quizRepositoryProvider)
        .checkAnswer(options.first.id);

    if (failure != null) {
      _applyResult(
        selectedOptionId: null,
        correct: false,
        timedOut: true,
        correctOption: null,
        timeTakenMs: timeTakenMs,
      );
      return;
    }

    _applyResult(
      selectedOptionId: null,
      correct: false,
      timedOut: true,
      correctOption: correctOption,
      timeTakenMs: timeTakenMs,
    );
    unawaited(
      _playFeedbackAudio(
        clickedUrl: null,
        correct: false,
        correctUrl: correctOption?.audioUrl,
      ),
    );
  }

  void _applyResult({
    required String? selectedOptionId,
    required bool correct,
    required bool timedOut,
    required QuizOption? correctOption,
    required int? timeTakenMs,
  }) {
    final card = state.currentCard;
    if (card == null) return;

    final newStreak = correct ? state.streak + 1 : 0;
    final newBestStreak = correct && newStreak > state.bestStreak
        ? newStreak
        : state.bestStreak;
    var newLives = state.livesRemaining;
    if (!correct && newLives != null && newLives > 0) {
      newLives = newLives - 1;
    }

    final record = QuizAnswerRecord(
      cardId: card.id,
      optionId: selectedOptionId,
      correct: correct,
      timedOut: timedOut,
      timeTakenMs: timeTakenMs,
    );

    state = state.copyWith(
      feedback: QuizFeedback(
        selectedOptionId: selectedOptionId,
        correct: correct,
        correctOptionId: correctOption?.id,
        correctText: correctOption?.text,
        correctAudioUrl: correctOption?.audioUrl,
      ),
      correctCount: correct ? state.correctCount + 1 : state.correctCount,
      wrongCount: correct ? state.wrongCount : state.wrongCount + 1,
      streak: newStreak,
      bestStreak: newBestStreak,
      livesRemaining: newLives,
      answers: [...state.answers, record],
      clearErrorMessage: true,
    );

    _scheduleAdvance();
  }

  void _scheduleAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(_interstitialPause, _advance);
  }

  void _advance() {
    if (state.outOfLives) {
      _finish(QuizEndedReason.outOfLives);
      return;
    }

    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.sessionCards.length) {
      _finish(QuizEndedReason.completed);
      return;
    }

    _cardStartedAt = DateTime.now();
    state = state.copyWith(
      currentIndex: nextIndex,
      clearFeedback: true,
      secondsRemaining: state.deck!.timerSecondsForPosition(nextIndex),
    );
    _startTick();
  }

  Future<void> _finish(QuizEndedReason reason) async {
    _tickTimer?.cancel();
    _advanceTimer?.cancel();
    state = state.copyWith(
      completed: true,
      endedReason: reason,
      submitting: true,
    );

    final deck = state.deck;
    if (deck == null) return;

    final (_, failure) = await ref
        .read(quizRepositoryProvider)
        .submitAttempt(
          deckId: deck.id,
          direction: state.direction.value,
          answers: state.answers.map((a) => a.toJson()).toList(),
          studentName: _studentName,
          studentPinHash: _studentPinHash,
          startedAt: _sessionStartedAt,
        );

    state = state.copyWith(
      submitting: false,
      errorMessage: failure != null
          ? 'Your score was calculated but could not be saved.'
          : null,
    );
  }

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.secondsRemaining <= 1) {
        _tickTimer?.cancel();
        _handleTimeout();
      } else {
        state = state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      }
    });
  }

  /// Samples `deck.sessionLength` cards (null = the whole deck once),
  /// reshuffling and looping back through the deck if it's smaller than
  /// the requested session length (CR doc, "Session structure").
  List<QuizPromptCard> _buildSessionCards(QuizPracticeDeck deck) {
    final pool = deck.cards;
    if (pool.isEmpty) return const [];

    final length = deck.sessionLength ?? pool.length;
    final result = <QuizPromptCard>[];
    var shuffled = List<QuizPromptCard>.from(pool)..shuffle();
    var i = 0;
    while (result.length < length) {
      if (i >= shuffled.length) {
        shuffled = List<QuizPromptCard>.from(pool)..shuffle();
        i = 0;
      }
      result.add(shuffled[i]);
      i++;
    }
    return result;
  }

  Future<void> _playFeedbackAudio({
    String? clickedUrl,
    required bool correct,
    String? correctUrl,
  }) async {
    try {
      if (clickedUrl != null && clickedUrl.isNotEmpty) {
        await _player.setUrl(clickedUrl);
        await _player.play();
      }
      if (!correct &&
          correctUrl != null &&
          correctUrl.isNotEmpty &&
          correctUrl != clickedUrl) {
        await _player.setUrl(correctUrl);
        await _player.play();
      }
    } catch (e) {
      _log.warning('Error playing quiz feedback audio', e);
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

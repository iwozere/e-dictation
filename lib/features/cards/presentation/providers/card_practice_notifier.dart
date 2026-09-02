import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

import '../../../../core/scoring/scoring.dart';
import '../../domain/card_pair.dart';
import '../../domain/card_practice_state.dart';

final _log = Logger('cards.CardPracticeNotifier');

final cardPracticeNotifierProvider =
    NotifierProvider<CardPracticeNotifier, CardPracticeState>(
      CardPracticeNotifier.new,
    );

/// Drives the student flashcard-practice screen.
///
/// Simpler than [PlaybackNotifier]'s sentence playlist: a flashcard session
/// plays one clip at a time, on demand, and only advances when the student
/// submits an answer — there is no auto-advance / inter-card pause timer.
class CardPracticeNotifier extends Notifier<CardPracticeState> {
  late final AudioPlayer _player;

  @override
  CardPracticeState build() {
    _player = AudioPlayer();
    ref.onDispose(_player.dispose);
    return CardPracticeState.empty;
  }

  /// Loads a deck's cards and resets the session. [nativeSide] is the
  /// language side the student identified as their own.
  void load(List<CardPair> cards, {required CardSide nativeSide}) {
    state = CardPracticeState(cards: cards, nativeSide: nativeSide);
  }

  void setMode(PracticeMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, clearLastAnswerCorrect: true);
  }

  Future<void> playPrompt() async {
    final url = state.promptAudioUrl;
    if (url == null || url.isEmpty) return;
    try {
      state = state.copyWith(
        audioStatus: PracticeAudioStatus.loading,
        clearErrorMessage: true,
      );
      await _player.setUrl(url);
      state = state.copyWith(audioStatus: PracticeAudioStatus.playing);
      await _player.play();
      state = state.copyWith(audioStatus: PracticeAudioStatus.idle);
    } catch (e) {
      _log.warning('Error playing card audio', e);
      state = state.copyWith(
        audioStatus: PracticeAudioStatus.error,
        errorMessage: 'Could not play audio. Check your connection.',
      );
    }
  }

  /// Grades [typed] against the expected answer and records the result.
  /// Uses the same lenient/strict comparison as dictation scoring — see
  /// `sentenceMatches()` in `core/scoring/scoring.dart` — which keeps German
  /// umlauts distinct from a/o/u even in lenient mode.
  void submitAnswer(String typed, {ScoringMode mode = ScoringMode.lenient}) {
    final expected = state.expectedAnswer;
    if (expected == null) return;
    final correct = sentenceMatches(typed, expected, mode);
    state = state.copyWith(
      lastAnswerCorrect: correct,
      correctCount: state.correctCount + (correct ? 1 : 0),
      answeredCount: state.answeredCount + 1,
    );
  }

  void next() {
    _player.stop();
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.cards.length) {
      state = state.copyWith(completed: true);
      return;
    }
    state = state.copyWith(
      currentIndex: nextIndex,
      clearLastAnswerCorrect: true,
      audioStatus: PracticeAudioStatus.idle,
    );
  }
}

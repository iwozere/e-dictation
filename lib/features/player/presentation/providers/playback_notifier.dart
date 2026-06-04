import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

import '../../../dictations/domain/dictation.dart';
import '../../domain/playback_state_model.dart';

final _log = Logger('player.PlaybackNotifier');

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final playbackNotifierProvider =
    NotifierProvider<PlaybackNotifier, PlaybackStateModel>(PlaybackNotifier.new);

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Controls the sentence-playlist audio engine.
///
/// Architecture: each sentence is a discrete MP3. Between sentences the
/// notifier inserts a [Future.delayed] pause. This is entirely index-based —
/// there is no waveform position tracking.
class PlaybackNotifier extends Notifier<PlaybackStateModel> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _pauseTimer;

  /// When the user pauses *during* the inter-sentence gap (i.e. the audio
  /// player is already idle), we record the index of the sentence we were
  /// about to play so that [play()] can advance there instead of calling
  /// [_player.play()] on an idle player (which would be a no-op).
  int? _pausedBeforeIndex;

  @override
  PlaybackStateModel build() {
    _player = AudioPlayer();

    // Dispose resources when the provider is removed.
    ref.onDispose(() {
      _pauseTimer?.cancel();
      _playerStateSub?.cancel();
      _player.dispose();
    });

    _playerStateSub = _player.playerStateStream.listen(_onPlayerStateChange);

    return PlaybackStateModel.empty;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Load a dictation's sentences and prepare to play.
  Future<void> loadDictation(
    List<DictationSentence> sentences, {
    int defaultPauseSecs = 5,
    DictationMode mode = DictationMode.listenOnly,
  }) async {
    _pauseTimer?.cancel();
    _pausedBeforeIndex = null;
    await _player.stop();

    if (sentences.isEmpty) {
      state = PlaybackStateModel.empty.copyWith(
        status: PlaybackStatus.error,
        errorMessage: 'This dictation has no audio yet. Please try again in a moment.',
      );
      return;
    }

    state = PlaybackStateModel(
      sentences: sentences,
      pauseDurationSecs: defaultPauseSecs,
      dictationMode: mode,
      status: PlaybackStatus.idle,
    );
  }

  Future<void> play() async {
    if (state.sentences.isEmpty) return;
    if (state.status == PlaybackStatus.completed) await _jumpTo(0);

    if (state.status == PlaybackStatus.paused) {
      if (_pausedBeforeIndex != null) {
        // Was paused during the inter-sentence gap — the audio player is idle,
        // not paused. Resume by starting the sentence we were about to play.
        final next = _pausedBeforeIndex!;
        _pausedBeforeIndex = null;
        await _playSentenceAt(next);
      } else {
        // Was paused mid-sentence — the audio player is genuinely paused.
        await _player.play();
        state = state.copyWith(status: PlaybackStatus.playing);
      }
      return;
    }

    await _playSentenceAt(state.currentIndex);
  }

  /// Used in student typing mode: cancels the between-sentence auto-advance
  /// and seeks the current sentence back to its start so pressing Play
  /// replays it rather than jumping ahead.
  Future<void> waitForInput() async {
    _pauseTimer?.cancel();
    _pausedBeforeIndex = null;
    try {
      await _player.seek(Duration.zero);
    } catch (_) {}
    state = state.copyWith(status: PlaybackStatus.paused);
  }

  Future<void> pause() async {
    _pauseTimer?.cancel();
    if (state.status == PlaybackStatus.pauseBetweenSentences) {
      // The audio player is already idle (the sentence finished).
      // Record where we would have gone next so play() can resume correctly.
      _pausedBeforeIndex = state.currentIndex + 1;
    } else {
      _pausedBeforeIndex = null;
      await _player.pause();
      // The audio may have completed exactly during the await above, causing
      // _onSentenceCompleted to fire and create a new timer.  Cancel it now
      // so we don't auto-advance while the user expects the player to be paused.
      _pauseTimer?.cancel();
    }
    state = state.copyWith(status: PlaybackStatus.paused);
  }

  Future<void> next() async {
    _pauseTimer?.cancel();
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.sentences.length) {
      await _player.stop();
      state = state.copyWith(status: PlaybackStatus.completed);
      return;
    }
    await _playSentenceAt(nextIndex);
  }

  Future<void> previous() async {
    _pauseTimer?.cancel();
    final prevIndex = (state.currentIndex - 1).clamp(0, state.sentences.length - 1);
    await _playSentenceAt(prevIndex);
  }

  Future<void> repeatCurrent() async {
    _pauseTimer?.cancel();
    await _playSentenceAt(state.currentIndex);
  }

  Future<void> jumpTo(int index) async {
    _pauseTimer?.cancel();
    await _jumpTo(index);
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _player.setSpeed(speed);
  }

  void setPauseDuration(int seconds) {
    state = state.copyWith(pauseDurationSecs: seconds);
  }

  void setDictationMode(DictationMode mode) {
    state = state.copyWith(dictationMode: mode);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _playSentenceAt(int index) async {
    final sentence = state.sentences[index];
    if (!sentence.hasAudio) {
      _log.warning('Sentence %d has no audio URL', index);
      if (index + 1 < state.sentences.length) {
        // Skip to next sentence.
        await _playSentenceAt(index + 1);
      } else {
        // All remaining sentences have no audio — treat as completed so the
        // player doesn't stay stuck in a phantom state.
        state = state.copyWith(status: PlaybackStatus.completed);
      }
      return;
    }

    state = state.copyWith(
      currentIndex: index,
      status: PlaybackStatus.loading,
    );

    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(sentence.audioUrl!)));
      await _player.setSpeed(state.speed);
      await _player.play();
      state = state.copyWith(status: PlaybackStatus.playing);
    } catch (e) {
      _log.severe('Error loading audio for sentence $index', e);
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: 'Failed to load audio. Check your connection.',
      );
    }
  }

  Future<void> _jumpTo(int index) async {
    await _player.stop();
    state = state.copyWith(currentIndex: index, status: PlaybackStatus.idle);
  }

  void _onPlayerStateChange(PlayerState playerState) {
    if (playerState.processingState == ProcessingState.completed) {
      _onSentenceCompleted();
    }
  }

  void _onSentenceCompleted() {
    final currentIndex = state.currentIndex;

    // Reveal sentence text after it has played.
    if (state.dictationMode == DictationMode.revealAfter) {
      state = state.copyWith(revealedUpToIndex: currentIndex);
    }

    final isLast = currentIndex >= state.sentences.length - 1;
    if (isLast) {
      state = state.copyWith(status: PlaybackStatus.completed);
      return;
    }

    // Start the between-sentence pause.
    state = state.copyWith(status: PlaybackStatus.pauseBetweenSentences);
    _pauseTimer = Timer(
      Duration(seconds: state.pauseDurationSecs),
      () {
        // Only auto-advance if we're still in the between-sentence state.
        // If the user paused during this window the state will be 'paused'.
        if (state.status == PlaybackStatus.pauseBetweenSentences) {
          _playSentenceAt(currentIndex + 1);
        }
      },
    );
  }
}

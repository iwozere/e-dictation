import '../../dictations/domain/dictation.dart';

/// What the text display looks like during playback.
enum DictationMode {
  /// Text is fully hidden — genuine exam mode.
  listenOnly,

  /// Each sentence is revealed only after its audio has played.
  revealAfter,

  /// First and last word of each sentence is visible as a hint.
  partialHint,

  /// Full transcript always visible — used by teachers.
  fullTranscript;

  String get label => switch (this) {
        listenOnly => 'Listen only',
        revealAfter => 'Reveal after',
        partialHint => 'Partial hint',
        fullTranscript => 'Full transcript',
      };
}

/// Lifecycle of the sentence playlist.
enum PlaybackStatus {
  /// No dictation loaded.
  idle,

  /// Loading dictation data or caching audio.
  loading,

  /// Actively playing a sentence MP3.
  playing,

  /// Paused mid-sentence by the user.
  paused,

  /// In the configured pause gap between sentences.
  pauseBetweenSentences,

  /// All sentences finished.
  completed,

  /// An unrecoverable error occurred.
  error,
}

/// Immutable snapshot of the player state.
class PlaybackStateModel {
  const PlaybackStateModel({
    required this.sentences,
    this.currentIndex = 0,
    this.speed = 1.0,
    this.pauseDurationSecs = 5,
    this.status = PlaybackStatus.idle,
    this.dictationMode = DictationMode.listenOnly,
    this.revealedUpToIndex = -1,
    this.errorMessage,
  });

  /// Ordered sentence list (empty until dictation is loaded).
  final List<DictationSentence> sentences;

  final int currentIndex;
  final double speed;
  final int pauseDurationSecs;
  final PlaybackStatus status;
  final DictationMode dictationMode;

  /// In [DictationMode.revealAfter], sentences at index ≤ this are shown.
  final int revealedUpToIndex;

  final String? errorMessage;

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isIdle => status == PlaybackStatus.idle || status == PlaybackStatus.completed;
  bool get isLoading => status == PlaybackStatus.loading;
  bool get isCompleted => status == PlaybackStatus.completed;
  bool get hasError => status == PlaybackStatus.error;

  DictationSentence? get currentSentence =>
      sentences.isEmpty ? null : sentences[currentIndex];

  bool isSentenceVisible(int index) => switch (dictationMode) {
        DictationMode.listenOnly => false,
        DictationMode.revealAfter => index <= revealedUpToIndex,
        DictationMode.partialHint => true, // partial text rendered by widget
        DictationMode.fullTranscript => true,
      };

  PlaybackStateModel copyWith({
    List<DictationSentence>? sentences,
    int? currentIndex,
    double? speed,
    int? pauseDurationSecs,
    PlaybackStatus? status,
    DictationMode? dictationMode,
    int? revealedUpToIndex,
    String? errorMessage,
  }) =>
      PlaybackStateModel(
        sentences: sentences ?? this.sentences,
        currentIndex: currentIndex ?? this.currentIndex,
        speed: speed ?? this.speed,
        pauseDurationSecs: pauseDurationSecs ?? this.pauseDurationSecs,
        status: status ?? this.status,
        dictationMode: dictationMode ?? this.dictationMode,
        revealedUpToIndex: revealedUpToIndex ?? this.revealedUpToIndex,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  static const empty = PlaybackStateModel(sentences: []);
}

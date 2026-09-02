/// Which side of a [CardPair] — corresponds to a deck's `languageA`/`languageB`.
///
/// Named to avoid colliding with Flutter's `Card` widget, and "side" rather
/// than "language" because which side is native/foreign for a given student
/// is decided at practice time, not baked into the card itself.
enum CardSide {
  a,
  b;

  CardSide get opposite => this == CardSide.a ? CardSide.b : CardSide.a;
}

/// Domain model for a single flashcard pair (mirrors the `cards` table).
///
/// Both sides carry their own pre-generated audio — see
/// docs/cr-card-decks-language-flashcards.md's "Key decision" section for why
/// TTS is generated for both `textA` and `textB` rather than a single
/// "foreign" column.
class CardPair {
  const CardPair({
    required this.id,
    required this.deckId,
    required this.position,
    required this.textA,
    required this.textB,
    this.audioAUrl,
    this.audioADurationMs,
    this.audioBUrl,
    this.audioBDurationMs,
  });

  final String id;
  final String deckId;
  final int position;
  final String textA;
  final String textB;
  final String? audioAUrl;
  final int? audioADurationMs;
  final String? audioBUrl;
  final int? audioBDurationMs;

  bool get hasAudio =>
      audioAUrl != null &&
      audioAUrl!.isNotEmpty &&
      audioBUrl != null &&
      audioBUrl!.isNotEmpty;

  String textFor(CardSide side) => side == CardSide.a ? textA : textB;
  String? audioUrlFor(CardSide side) =>
      side == CardSide.a ? audioAUrl : audioBUrl;

  CardPair copyWith({String? textA, String? textB}) => CardPair(
    id: id,
    deckId: deckId,
    position: position,
    textA: textA ?? this.textA,
    textB: textB ?? this.textB,
    audioAUrl: audioAUrl,
    audioADurationMs: audioADurationMs,
    audioBUrl: audioBUrl,
    audioBDurationMs: audioBDurationMs,
  );

  factory CardPair.fromJson(Map<String, dynamic> json) => CardPair(
    id: json['id'] as String,
    deckId: json['deck_id'] as String,
    position: json['position'] as int,
    textA: json['text_a'] as String,
    textB: json['text_b'] as String,
    audioAUrl: json['audio_a_url'] as String?,
    audioADurationMs: json['audio_a_duration_ms'] as int?,
    audioBUrl: json['audio_b_url'] as String?,
    audioBDurationMs: json['audio_b_duration_ms'] as int?,
  );
}

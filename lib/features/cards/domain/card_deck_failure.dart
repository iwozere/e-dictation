/// Typed domain errors from [CardsRepository].
sealed class CardDeckFailure {
  const CardDeckFailure();
}

class CardDeckNotFound extends CardDeckFailure {
  const CardDeckNotFound();
}

class CardDeckParseFailed extends CardDeckFailure {
  const CardDeckParseFailed([this.message]);
  final String? message;
}

class CardDeckAudioGenerationFailed extends CardDeckFailure {
  const CardDeckAudioGenerationFailed([this.message]);
  final String? message;
}

class NetworkCardDeckFailure extends CardDeckFailure {
  const NetworkCardDeckFailure([this.message]);
  final String? message;
}

class UnknownCardDeckFailure extends CardDeckFailure {
  const UnknownCardDeckFailure([this.message]);
  final String? message;
}

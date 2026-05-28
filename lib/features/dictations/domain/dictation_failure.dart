/// Typed domain errors from [DictationsRepository].
sealed class DictationFailure {
  const DictationFailure();
}

class DictationNotFound extends DictationFailure {
  const DictationNotFound();
}

class DictationTooLong extends DictationFailure {
  const DictationTooLong(this.wordCount, this.limit);
  final int wordCount;
  final int limit;
}

class TtsGenerationFailed extends DictationFailure {
  const TtsGenerationFailed([this.message]);
  final String? message;
}

class NetworkDictationFailure extends DictationFailure {
  const NetworkDictationFailure([this.message]);
  final String? message;
}

class UnknownDictationFailure extends DictationFailure {
  const UnknownDictationFailure([this.message]);
  final String? message;
}

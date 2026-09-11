/// Typed domain errors from [QuizRepository]. Mirrors [CardDeckFailure]'s
/// shape.
sealed class QuizFailure {
  const QuizFailure();
}

class QuizDeckNotFound extends QuizFailure {
  const QuizDeckNotFound();
}

class QuizOptionNotFound extends QuizFailure {
  const QuizOptionNotFound();
}

class QuizImportFailed extends QuizFailure {
  const QuizImportFailed([this.message]);
  final String? message;
}

class QuizAudioGenerationFailed extends QuizFailure {
  const QuizAudioGenerationFailed([this.message]);
  final String? message;
}

class QuizSubmitFailed extends QuizFailure {
  const QuizSubmitFailed([this.message]);
  final String? message;
}

class NetworkQuizFailure extends QuizFailure {
  const NetworkQuizFailure([this.message]);
  final String? message;
}

class UnknownQuizFailure extends QuizFailure {
  const UnknownQuizFailure([this.message]);
  final String? message;
}

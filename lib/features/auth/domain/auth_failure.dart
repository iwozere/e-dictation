/// Typed domain errors surfaced from [AuthRepository].
sealed class AuthFailure {
  const AuthFailure();
}

/// Invalid credentials or missing email/password.
class InvalidCredentials extends AuthFailure {
  const InvalidCredentials([this.message]);
  final String? message;
}

/// The email is already registered.
class EmailAlreadyInUse extends AuthFailure {
  const EmailAlreadyInUse();
}

/// A required network request failed.
class NetworkFailure extends AuthFailure {
  const NetworkFailure([this.message]);
  final String? message;
}

/// Sign-up succeeded but email confirmation is required before the session
/// is active. Not actually an error — the UI should show a friendly message.
class EmailConfirmationRequired extends AuthFailure {
  const EmailConfirmationRequired();
}

/// Any unclassified Supabase or unexpected error.
class UnknownAuthFailure extends AuthFailure {
  const UnknownAuthFailure([this.message]);
  final String? message;
}

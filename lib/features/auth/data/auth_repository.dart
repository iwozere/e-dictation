import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/app_user.dart';
import '../domain/auth_failure.dart';

final _log = Logger('auth.AuthRepository');

/// Wraps Supabase Auth and the `profiles` table.
///
/// All methods return a discriminated union ([AuthFailure] or [AppUser])
/// so the presentation layer never sees raw Supabase exceptions.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Emits the current [AppUser] on every auth state change, or `null` when
  /// signed out.
  Stream<AppUser?> watchAuthState() {
    return _client.auth.onAuthStateChange.asyncMap((event) async {
      final session = event.session;
      if (session == null) return null;
      return _fetchProfile(session.user);
    });
  }

  // ---------------------------------------------------------------------------
  // Sign-in / sign-up
  // ---------------------------------------------------------------------------

  Future<(AppUser?, AuthFailure?)> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) return (null, const InvalidCredentials());
      final appUser = await _fetchProfile(user);
      return (appUser, null);
    } on AuthException catch (e) {
      _log.warning('signInWithEmail failed: %s', e.message);
      if (e.statusCode == '400') return (null, const InvalidCredentials());
      return (null, UnknownAuthFailure(e.message));
    } catch (e) {
      _log.severe('signInWithEmail unexpected error: %s', e);
      return (null, UnknownAuthFailure(e.toString()));
    }
  }

  Future<(AppUser?, AuthFailure?)> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        // Pass role + display_name in metadata so the DB trigger picks them up.
        // This avoids a client-side INSERT that would fail when email
        // confirmation is required (no active session yet).
        data: {'display_name': displayName, 'role': role.toJson()},
      );
      final user = response.user;
      if (user == null) return (null, const UnknownAuthFailure('No user returned'));

      // If email confirmation is enabled the session is null here.
      // The caller checks for this and shows a "check your email" message.
      if (response.session == null) {
        return (null, const EmailConfirmationRequired());
      }

      final appUser = AppUser(
        id: user.id,
        role: role,
        displayName: displayName,
        email: email,
        isAnonymous: false,
      );
      return (appUser, null);
    } on AuthException catch (e) {
      _log.warning('signUpWithEmail failed: %s', e.message);
      if (e.message.toLowerCase().contains('already registered')) {
        return (null, const EmailAlreadyInUse());
      }
      return (null, UnknownAuthFailure(e.message));
    } catch (e) {
      _log.severe('signUpWithEmail unexpected error: %s', e);
      return (null, UnknownAuthFailure(e.toString()));
    }
  }

  Future<(AppUser?, AuthFailure?)> signInAnonymously() async {
    try {
      final response = await _client.auth.signInAnonymously();
      final user = response.user;
      if (user == null) return (null, const UnknownAuthFailure('No user returned'));

      final appUser = AppUser(
        id: user.id,
        role: UserRole.student,
        displayName: null,
        email: null,
        isAnonymous: true,
      );
      return (appUser, null);
    } catch (e) {
      _log.severe('signInAnonymously error: %s', e);
      return (null, UnknownAuthFailure(e.toString()));
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Sends a password-reset email to [email].
  ///
  /// The email contains a link back to the app's `/reset-password` route.
  /// Returns null on success or an [AuthFailure] on error.
  Future<AuthFailure?> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: '${AppConfig.appBaseUrl}/reset-password',
      );
      return null;
    } on AuthException catch (e) {
      _log.warning('sendPasswordReset failed: %s', e.message);
      return UnknownAuthFailure(e.message);
    } catch (e) {
      _log.severe('sendPasswordReset unexpected error: %s', e);
      return UnknownAuthFailure(e.toString());
    }
  }

  /// Updates the current user's password.
  ///
  /// Call after a password-recovery session is established (the user arrived
  /// via a reset-password link). Returns null on success or an [AuthFailure].
  Future<AuthFailure?> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      _log.warning('updatePassword failed: %s', e.message);
      return UnknownAuthFailure(e.message);
    } catch (e) {
      _log.severe('updatePassword unexpected error: %s', e);
      return UnknownAuthFailure(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<AppUser?> _fetchProfile(User supabaseUser) async {
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', supabaseUser.id)
          .maybeSingle();

      if (row == null) {
        // Fallback: anonymous user or profile not yet created.
        return AppUser(
          id: supabaseUser.id,
          role: UserRole.student,
          displayName: supabaseUser.userMetadata?['display_name'] as String?,
          email: supabaseUser.email,
          isAnonymous: supabaseUser.isAnonymous,
        );
      }

      return AppUser.fromJson(
        row,
        isAnonymous: supabaseUser.isAnonymous,
        email: supabaseUser.email,
      );
    } catch (e) {
      _log.warning('_fetchProfile error for ${supabaseUser.id}', e);
      // Return a basic user rather than null so a DB error doesn't look like
      // a signed-out state (which would break anonymous student access).
      return AppUser(
        id: supabaseUser.id,
        role: UserRole.student,
        displayName: supabaseUser.userMetadata?['display_name'] as String?,
        email: supabaseUser.email,
        isAnonymous: supabaseUser.isAnonymous,
      );
    }
  }

  /// Synchronous snapshot of the current user, built from JWT metadata only.
  ///
  /// **Prefer [watchAuthState] / `currentUserProvider` in the UI layer** — those
  /// paths call [_fetchProfile] and return the true DB-backed role.
  ///
  /// This getter reads `role` from `raw_user_meta_data`, which is populated
  /// during sign-up ([signUpWithEmail] passes `data: {'role': role.toJson()}`).
  /// Anonymous users and users whose metadata was not set will default to
  /// [UserRole.student].
  AppUser? get currentUser {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final roleStr = user.userMetadata?['role'] as String?;
    return AppUser(
      id: user.id,
      role: UserRole.fromString(roleStr ?? 'student'),
      displayName: user.userMetadata?['display_name'] as String?,
      email: user.email,
      isAnonymous: user.isAnonymous,
    );
  }
}

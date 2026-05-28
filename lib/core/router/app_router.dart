import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/sign_in_screen.dart';
import '../../features/auth/presentation/screens/sign_up_screen.dart';
import '../../features/classes/presentation/screens/classes_screen.dart';
import '../../features/classes/presentation/screens/create_class_screen.dart';
import '../../features/dictations/presentation/screens/create_dictation_screen.dart';
import '../../features/dictations/presentation/screens/dictation_detail_screen.dart';
import '../../features/dictations/presentation/screens/teacher_dashboard_screen.dart';
import '../../features/player/presentation/screens/player_screen.dart';
import '../../shared/widgets/teacher_shell.dart';

// ---------------------------------------------------------------------------
// Route names (use these for programmatic navigation)
// ---------------------------------------------------------------------------

abstract final class AppRoute {
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const teacherDashboard = '/teacher/dictations';
  static const createDictation = '/teacher/dictations/new';
  static const dictationDetail = '/teacher/dictations/:id';
  static const classes = '/teacher/classes';
  static const createClass = '/teacher/classes/new';

  /// Public player route — opened by students via share link.
  static const playerByCode = '/d/:code';

  /// Player route for logged-in teachers previewing their own dictation.
  static const playerById = '/play/:id';
}

// ---------------------------------------------------------------------------
// Router notifier — bridges Riverpod auth state to GoRouter's refreshListenable
// ---------------------------------------------------------------------------

/// A [ChangeNotifier] that fires whenever [authStateProvider] emits a new
/// value. Passed to [GoRouter.refreshListenable] so that GoRouter re-evaluates
/// its redirect function on auth changes *without* reconstructing the router
/// instance (which would reset the navigation stack).
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(Ref ref) {
    // ref.listen is tied to the provider's lifetime and cleaned up automatically.
    ref.listen<AsyncValue<AppUser?>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// ---------------------------------------------------------------------------
// Router provider
// ---------------------------------------------------------------------------

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: AppRoute.signIn,
    refreshListenable: notifier,
    redirect: (context, state) {
      // Read (not watch) — we only need the current snapshot; the notifier
      // already drives re-evaluation whenever the value changes.
      final authAsync = ref.read(authStateProvider);
      final user = authAsync.valueOrNull;
      final isLoading = authAsync.isLoading;
      final path = state.uri.path;

      // While auth is resolving, stay put.
      if (isLoading) return null;

      final isPublicRoute = path.startsWith('/d/') ||
          path == AppRoute.signIn ||
          path == AppRoute.signUp;

      if (user == null && !isPublicRoute) return AppRoute.signIn;

      // Any authenticated non-anonymous user on the auth screens → dashboard.
      if (user != null && !user.isAnonymous) {
        if (path == AppRoute.signIn || path == AppRoute.signUp) {
          return AppRoute.teacherDashboard;
        }
      }

      return null;
    },
    routes: [
      // ------------------------------------------------------------------
      // Public / auth routes
      // ------------------------------------------------------------------
      GoRoute(
        path: AppRoute.signIn,
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoute.signUp,
        builder: (_, _) => const SignUpScreen(),
      ),

      // ------------------------------------------------------------------
      // Public player (anonymous student access via share code)
      // ------------------------------------------------------------------
      GoRoute(
        path: AppRoute.playerByCode,
        builder: (_, state) {
          final code = state.pathParameters['code']!;
          return PlayerScreen(shareCode: code);
        },
      ),

      // ------------------------------------------------------------------
      // Authenticated player (teacher preview / student with account)
      // ------------------------------------------------------------------
      GoRoute(
        path: AppRoute.playerById,
        builder: (_, state) {
          final id = state.pathParameters['id']!;
          return PlayerScreen(dictationId: id);
        },
      ),

      // ------------------------------------------------------------------
      // Teacher shell (bottom-nav / rail)
      // ------------------------------------------------------------------
      ShellRoute(
        builder: (_, state, child) => TeacherShell(child: child),
        routes: [
          // ---- Dictations tab ----
          GoRoute(
            path: AppRoute.teacherDashboard,
            builder: (_, _) => const TeacherDashboardScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const CreateDictationScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) {
                  final id = state.pathParameters['id']!;
                  return DictationDetailScreen(dictationId: id);
                },
              ),
            ],
          ),

          // ---- Classes tab ----
          GoRoute(
            path: AppRoute.classes,
            builder: (_, _) => const ClassesScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const CreateClassScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});

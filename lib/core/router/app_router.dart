import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/sign_in_screen.dart';
import '../../features/auth/presentation/screens/sign_up_screen.dart';
import '../../features/classes/presentation/screens/classes_screen.dart';
import '../../features/classes/presentation/screens/create_class_screen.dart';
import '../../features/dictations/presentation/screens/create_dictation_screen.dart';
import '../../features/dictations/presentation/screens/edit_dictation_screen.dart';
import '../../features/dictations/presentation/screens/dictation_detail_screen.dart';
import '../../features/dictations/presentation/screens/teacher_dashboard_screen.dart';
import '../../features/attempts/presentation/screens/all_attempts_screen.dart';
import '../../features/attempts/presentation/screens/results_screen.dart';
import '../../features/attempts/presentation/screens/results_overview_screen.dart';
import '../../features/attempts/presentation/screens/student_history_screen.dart';
import '../../features/cards/presentation/screens/card_deck_detail_screen.dart';
import '../../features/cards/presentation/screens/card_decks_list_screen.dart';
import '../../features/cards/presentation/screens/card_practice_screen.dart';
import '../../features/cards/presentation/screens/create_card_deck_screen.dart';
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

  /// Teacher's card decks (flashcards) list.
  static const cardDecks = '/teacher/cards';
  static const createCardDeck = '/teacher/cards/new';
  static const cardDeckDetail = '/teacher/cards/:id';

  /// Public student practice route — opened by students via share link.
  static const cardPracticeByCode = '/c/:code';

  /// Teacher-wide results overview across all dictations.
  static const resultsOverview = '/teacher/results';

  /// Flat list of all completed attempts — the new Results tab.
  static const allAttempts = '/teacher/results/all';

  /// Public student history — review own past attempts via name + PIN.
  static const studentHistory = '/history';

  /// Public player route — opened by students via share link.
  static const playerByCode = '/d/:code';

  /// Player route for logged-in teachers previewing their own dictation.
  static const playerById = '/play/:id';

  /// Edit an existing dictation.
  static const editDictation = '/teacher/dictations/:id/edit';

  /// Teacher results dashboard for a dictation.
  static const dictationResults = '/teacher/dictations/:id/results';

  /// Password-reset landing page — opened via the link in a reset email.
  static const resetPassword = '/reset-password';
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

      final isPublicRoute =
          path.startsWith('/d/') ||
          path.startsWith('/c/') ||
          path == AppRoute.studentHistory ||
          path == AppRoute.signIn ||
          path == AppRoute.signUp ||
          path == AppRoute.resetPassword;

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
      GoRoute(path: AppRoute.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: AppRoute.signUp, builder: (_, _) => const SignUpScreen()),

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
      // Public card practice (anonymous student access via share code)
      // ------------------------------------------------------------------
      GoRoute(
        path: AppRoute.cardPracticeByCode,
        builder: (_, state) {
          final code = state.pathParameters['code']!;
          return CardPracticeScreen(shareCode: code);
        },
      ),

      // ------------------------------------------------------------------
      // Public student history (review own attempts via name + PIN)
      // ------------------------------------------------------------------
      GoRoute(
        path: AppRoute.studentHistory,
        builder: (_, _) => const StudentHistoryScreen(),
      ),

      // ------------------------------------------------------------------
      // Password reset landing page (arrived via emailed link)
      // ------------------------------------------------------------------
      GoRoute(
        path: AppRoute.resetPassword,
        builder: (_, _) => const ResetPasswordScreen(),
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
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) {
                      final id = state.pathParameters['id']!;
                      return EditDictationScreen(dictationId: id);
                    },
                  ),
                  GoRoute(
                    path: 'results',
                    builder: (_, state) {
                      final id = state.pathParameters['id']!;
                      return ResultsScreen(dictationId: id);
                    },
                  ),
                ],
              ),
            ],
          ),

          // ---- Results overview (no own tab; reached from dashboard) ----
          GoRoute(
            path: AppRoute.resultsOverview,
            builder: (_, _) => const ResultsOverviewScreen(),
          ),

          // ---- All attempts tab ----
          GoRoute(
            path: AppRoute.allAttempts,
            builder: (_, _) => const AllAttemptsScreen(),
          ),

          // ---- Cards tab ----
          GoRoute(
            path: AppRoute.cardDecks,
            builder: (_, _) => const CardDecksListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const CreateCardDeckScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) {
                  final id = state.pathParameters['id']!;
                  return CardDeckDetailScreen(deckId: id);
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
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});

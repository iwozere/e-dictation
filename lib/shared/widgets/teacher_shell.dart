import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// Persistent shell wrapping teacher-side screens.
/// Adapts between bottom navigation bar (mobile) and navigation rail (desktop).
class TeacherShell extends ConsumerWidget {
  const TeacherShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    _Tab(
      icon: Icons.mic_none_rounded,
      activeIcon: Icons.mic_rounded,
      label: 'Dictations',
      route: AppRoute.teacherDashboard,
    ),
    _Tab(
      icon: Icons.group_outlined,
      activeIcon: Icons.group,
      label: 'Classes',
      route: AppRoute.classes,
    ),
    _Tab(
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      label: 'Results',
      route: AppRoute.allAttempts,
    ),
  ];

  int _currentIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/teacher/classes')) return 1;
    if (path.startsWith('/teacher/results/all')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);
    final isWide = MediaQuery.of(context).size.width > 700;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'e-',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'Sign out',
                          onPressed: () => _signOut(ref, context),
                        ),
                        Text(
                          'v${AppConfig.version}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[400],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              destinations: _tabs
                  .map((t) => NavigationRailDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.activeIcon),
                        label: Text(t.label),
                      ))
                  .toList(),
              onDestinationSelected: (i) => context.go(_tabs[i].route),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => context.go(_tabs[i].route),
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.activeIcon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }

  Future<void> _signOut(WidgetRef ref, BuildContext context) async {
    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) context.go(AppRoute.signIn);
  }
}

class _Tab {
  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
}

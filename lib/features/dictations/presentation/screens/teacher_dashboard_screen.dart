import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/dictation.dart';
import '../providers/dictations_provider.dart';
import 'widgets/dictation_card.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends ConsumerState<TeacherDashboardScreen> {
  String? _selectedClassId;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _updatePolling(List<Dictation> dictations) {
    final hasPending = dictations.any(
      (d) => d.ttsStatus == TtsStatus.pending || d.ttsStatus == TtsStatus.processing,
    );
    if (hasPending && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        ref.invalidate(teacherDictationsProvider(_selectedClassId));
      });
    } else if (!hasPending) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dictationsAsync = ref.watch(teacherDictationsProvider(_selectedClassId));

    ref.listen(teacherDictationsProvider(_selectedClassId), (_, next) {
      next.whenData(_updatePolling);
    });
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dictations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'All results',
            onPressed: () => context.go(AppRoute.resultsOverview),
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Text(
                  (user.displayName?.isNotEmpty == true
                          ? user.displayName![0]
                          : user.email?[0] ?? '?')
                      .toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoute.createDictation),
        icon: const Icon(Icons.add),
        label: const Text('New dictation'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: dictationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: 'Could not load dictations.',
          onRetry: () => ref.invalidate(teacherDictationsProvider),
        ),
        data: (dictations) => dictations.isEmpty
            ? EmptyState(
                icon: Icons.mic_none_rounded,
                title: 'No dictations yet',
                subtitle: 'Tap "New dictation" to create your first one.',
                action: TextButton.icon(
                  onPressed: () => context.go(AppRoute.createDictation),
                  icon: const Icon(Icons.add),
                  label: const Text('New dictation'),
                ),
              )
            : _DictationGrid(dictations: dictations),
      ),
    );
  }
}

class _DictationGrid extends StatelessWidget {
  const _DictationGrid({required this.dictations});
  final List<Dictation> dictations;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: dictations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => DictationCard(dictation: dictations[i]),
    );
  }
}

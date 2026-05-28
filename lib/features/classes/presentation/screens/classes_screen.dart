import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/class_entity.dart';
import '../providers/classes_provider.dart';

class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(classesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoute.createClass),
        icon: const Icon(Icons.add),
        label: const Text('New class'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: 'Could not load classes.',
          onRetry: () => ref.invalidate(classesProvider),
        ),
        data: (classes) => classes.isEmpty
            ? EmptyState(
                icon: Icons.group_outlined,
                title: 'No classes yet',
                subtitle: 'Create a class to organise dictations for a group of students.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: classes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ClassTile(entity: classes[i]),
              ),
      ),
    );
  }
}

class _ClassTile extends ConsumerWidget {
  const _ClassTile({required this.entity});
  final ClassEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.group, color: AppColors.primary),
        ),
        title: Text(entity.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${entity.dictationCount} dictation${entity.dictationCount == 1 ? '' : 's'}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: AppColors.error,
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete class?'),
                content: Text(
                    'Delete "${entity.name}"? Dictations will not be deleted.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete',
                          style: TextStyle(color: AppColors.error))),
                ],
              ),
            );
            if (confirmed == true) {
              ref.read(classMutationProvider.notifier).delete(entity.id);
            }
          },
        ),
      ),
    );
  }
}

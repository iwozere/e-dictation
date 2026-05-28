import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/classes_repository.dart';
import '../../domain/class_entity.dart';

final classesRepositoryProvider = Provider<ClassesRepository>(
  (ref) => ClassesRepository(ref.watch(supabaseClientProvider)),
);

final classesProvider = FutureProvider.autoDispose<List<ClassEntity>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(classesRepositoryProvider).fetchClasses(user.id);
});

class ClassMutationNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<ClassEntity?> create(String name) async {
    state = const AsyncLoading();
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const AsyncData(null);
      return null;
    }
    try {
      final entity = await ref
          .read(classesRepositoryProvider)
          .createClass(ownerId: user.id, name: name);
      ref.invalidate(classesProvider);
      state = const AsyncData(null);
      return entity;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return null;
    }
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(classesRepositoryProvider).deleteClass(id);
      ref.invalidate(classesProvider);
      state = const AsyncData(null);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }
}

final classMutationProvider =
    NotifierProvider<ClassMutationNotifier, AsyncValue<void>>(ClassMutationNotifier.new);

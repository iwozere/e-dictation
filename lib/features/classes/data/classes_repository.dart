import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/class_entity.dart';

final _log = Logger('classes.ClassesRepository');

class ClassesRepository {
  ClassesRepository(this._client);

  final SupabaseClient _client;

  Future<List<ClassEntity>> fetchClasses(String ownerId) async {
    try {
      final rows = await _client
          .from('classes')
          .select('*, dictations(count)')
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false);

      return (rows as List<dynamic>).map((r) {
        final json = r as Map<String, dynamic>;
        // Supabase returns count as a nested list: [{"count": N}]
        final countList = json['dictations'] as List<dynamic>?;
        final count = countList?.isNotEmpty == true
            ? (countList!.first as Map)['count'] as int? ?? 0
            : 0;
        return ClassEntity.fromJson({...json, 'dictation_count': count});
      }).toList();
    } catch (e) {
      _log.severe('fetchClasses error: %s', e);
      rethrow;
    }
  }

  Future<ClassEntity> createClass({
    required String ownerId,
    required String name,
  }) async {
    final row = await _client
        .from('classes')
        .insert({'owner_id': ownerId, 'name': name})
        .select()
        .single();
    return ClassEntity.fromJson(row);
  }

  Future<ClassEntity> renameClass({required String id, required String name}) async {
    final row = await _client
        .from('classes')
        .update({'name': name})
        .eq('id', id)
        .select()
        .single();
    return ClassEntity.fromJson(row);
  }

  Future<void> deleteClass(String id) async {
    await _client.from('classes').delete().eq('id', id);
  }
}

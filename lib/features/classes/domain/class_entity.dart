/// Domain model for a class/group (mirrors the `classes` table).
class ClassEntity {
  const ClassEntity({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.createdAt,
    this.dictationCount = 0,
  });

  final String id;
  final String ownerId;
  final String name;
  final DateTime createdAt;

  /// Populated by a count join when fetching the class list.
  final int dictationCount;

  factory ClassEntity.fromJson(Map<String, dynamic> json) => ClassEntity(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        dictationCount: (json['dictation_count'] as int?) ?? 0,
      );

  Map<String, dynamic> toInsertJson() => {
        'owner_id': ownerId,
        'name': name,
      };
}

/// Represents an e-dictation user profile (mirrors the `profiles` table).
class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.displayName,
    required this.email,
    required this.isAnonymous,
  });

  final String id;
  final UserRole role;
  final String? displayName;
  final String? email;

  /// True when the user signed in anonymously (student without account).
  final bool isAnonymous;

  bool get isTeacher => role == UserRole.teacher;
  bool get isStudent => role == UserRole.student;

  AppUser copyWith({
    String? displayName,
    UserRole? role,
  }) =>
      AppUser(
        id: id,
        role: role ?? this.role,
        displayName: displayName ?? this.displayName,
        email: email,
        isAnonymous: isAnonymous,
      );

  factory AppUser.fromJson(Map<String, dynamic> json, {required bool isAnonymous, String? email}) {
    return AppUser(
      id: json['id'] as String,
      role: UserRole.fromString(json['role'] as String? ?? 'student'),
      displayName: json['display_name'] as String?,
      email: email,
      isAnonymous: isAnonymous,
    );
  }
}

enum UserRole {
  teacher,
  student;

  static UserRole fromString(String value) {
    return switch (value) {
      'teacher' => teacher,
      _ => student,
    };
  }

  String toJson() => name;
}

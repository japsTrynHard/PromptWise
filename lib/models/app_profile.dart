enum AppRole {
  learner,
  administrator;

  static AppRole fromDatabase(String? value) {
    return value == 'administrator' ? AppRole.administrator : AppRole.learner;
  }

  String get databaseValue => switch (this) {
    AppRole.learner => 'learner',
    AppRole.administrator => 'administrator',
  };

  String get label => switch (this) {
    AppRole.learner => 'Learner',
    AppRole.administrator => 'Administrator',
  };
}

class AppProfile {
  final String id;
  final String email;
  final String fullName;
  final AppRole role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  factory AppProfile.fromMap(Map<String, dynamic> map) {
    return AppProfile(
      id: map['id'] as String? ?? '',
      email: map['email'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      role: AppRole.fromDatabase(map['role'] as String?),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? ''),
    );
  }

  AppProfile copyWith({
    String? email,
    String? fullName,
    AppRole? role,
    DateTime? updatedAt,
  }) {
    return AppProfile(
      id: id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

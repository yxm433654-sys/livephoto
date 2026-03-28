class UserProfile {
  UserProfile({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.status,
    required this.createdAt,
  });

  final int userId;
  final String username;
  final String? avatarUrl;
  final int? status;
  final DateTime? createdAt;

  static UserProfile fromJson(Object? raw) {
    final json = raw as Map<String, dynamic>;
    return UserProfile(
      userId: (json['userId'] as num).toInt(),
      username: json['username']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString(),
      status: json['status'] is num ? (json['status'] as num).toInt() : null,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }
}

class Session {
  Session({
    required this.userId,
    required this.username,
    required this.token,
    required this.expiresAt,
  });

  final int userId;
  final String username;
  final String token;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => {
        'userId': userId,
        'username': username,
        'token': token,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  static Session? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['userId'];
    final username = raw['username'];
    final token = raw['token'];
    if (userId is! num || username is! String || token is! String) return null;
    final expiresAt = raw['expiresAt'];
    return Session(
      userId: userId.toInt(),
      username: username,
      token: token,
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
    );
  }
}

class ChatSessionSummary {
  ChatSessionSummary({
    required this.id,
    required this.peerId,
    required this.unreadCount,
    this.peerUsername,
    this.peerAvatarUrl,
    this.lastMessageId,
    this.lastMessageType,
    this.lastMessagePreview,
    this.updatedAt,
  });

  final int id;
  final int peerId;
  final int unreadCount;
  final String? peerUsername;
  final String? peerAvatarUrl;
  final int? lastMessageId;
  final String? lastMessageType;
  final String? lastMessagePreview;
  final DateTime? updatedAt;

  static ChatSessionSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final peerId = raw['peerId'];
    if (id is! num || peerId is! num) return null;
    return ChatSessionSummary(
      id: id.toInt(),
      peerId: peerId.toInt(),
      unreadCount: raw['unreadCount'] is num
          ? (raw['unreadCount'] as num).toInt()
          : 0,
      peerUsername: raw['peerUsername']?.toString(),
      peerAvatarUrl: raw['peerAvatarUrl']?.toString(),
      lastMessageId: raw['lastMessageId'] is num
          ? (raw['lastMessageId'] as num).toInt()
          : null,
      lastMessageType: raw['lastMessageType']?.toString(),
      lastMessagePreview: raw['lastMessagePreview']?.toString(),
      updatedAt: raw['updatedAt'] is String
          ? DateTime.tryParse(raw['updatedAt'] as String)
          : null,
    );
  }
}

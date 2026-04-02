class SessionListItemViewData {
  const SessionListItemViewData({
    required this.peerId,
    required this.name,
    required this.avatarUrl,
    required this.unreadCount,
    required this.subtitle,
    required this.updatedAt,
  });

  final int peerId;
  final String name;
  final String? avatarUrl;
  final int unreadCount;
  final String subtitle;
  final DateTime? updatedAt;
}

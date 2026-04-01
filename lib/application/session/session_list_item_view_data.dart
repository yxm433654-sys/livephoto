class SessionListItemViewData {
  const SessionListItemViewData({
    required this.peerId,
    required this.name,
    required this.avatarUrl,
    required this.unreadCount,
    required this.subtitle,
  });

  final int peerId;
  final String name;
  final String? avatarUrl;
  final int unreadCount;
  final String subtitle;
}

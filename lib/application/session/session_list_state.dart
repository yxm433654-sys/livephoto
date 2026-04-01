import 'package:vox_flutter/models/chat_session_summary.dart';

class SessionListState {
  const SessionListState({
    required this.currentUsername,
    required this.currentUserId,
    required this.currentAvatarUrl,
    required this.connectionNotice,
    required this.orderedPeerIds,
    required this.sessionSummariesByPeerId,
    required this.unreadCountsByPeerId,
    required this.displayNamesByPeerId,
    required this.avatarUrlsByPeerId,
  });

  final String currentUsername;
  final int currentUserId;
  final String? currentAvatarUrl;
  final String? connectionNotice;
  final List<int> orderedPeerIds;
  final Map<int, ChatSessionSummary> sessionSummariesByPeerId;
  final Map<int, int> unreadCountsByPeerId;
  final Map<int, String> displayNamesByPeerId;
  final Map<int, String?> avatarUrlsByPeerId;

  ChatSessionSummary? sessionSummaryFor(int peerId) =>
      sessionSummariesByPeerId[peerId];

  int unreadCount(int peerId) => unreadCountsByPeerId[peerId] ?? 0;

  String displayNameFor(int peerId) => displayNamesByPeerId[peerId] ?? '$peerId';

  String? avatarUrlFor(int peerId) => avatarUrlsByPeerId[peerId];
}

import 'package:dynamic_photo_chat_flutter/application/session/session_list_item_view_data.dart';
import 'package:dynamic_photo_chat_flutter/models/chat_session_summary.dart';
import 'package:dynamic_photo_chat_flutter/state/app_state.dart';

class SessionListCoordinator {
  const SessionListCoordinator();

  List<SessionListItemViewData> buildItems(AppState state) {
    return state.orderedPeerIds().map((peerId) {
      final summary = state.sessionSummaryFor(peerId);
      final unread = summary?.unreadCount ?? state.unreadCount(peerId);
      final name = summary?.peerUsername?.trim().isNotEmpty == true
          ? summary!.peerUsername!
          : state.displayNameFor(peerId);
      return SessionListItemViewData(
        peerId: peerId,
        name: name,
        avatarUrl: summary?.peerAvatarUrl ?? state.avatarUrlFor(peerId),
        unreadCount: unread,
        subtitle: _buildSubtitle(summary, unread),
      );
    }).toList();
  }

  String _buildSubtitle(ChatSessionSummary? summary, int unread) {
    final preview = summary?.lastMessagePreview?.trim();
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }
    return unread > 0 ? '$unread 条未读消息' : '点击进入聊天';
  }
}

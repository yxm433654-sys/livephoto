import 'package:vox_flutter/application/session/session_list_facade.dart';
import 'package:vox_flutter/application/session/session_list_item_view_data.dart';
import 'package:vox_flutter/application/session/session_list_state.dart';
import 'package:vox_flutter/models/chat_session_summary.dart';

class SessionListCoordinator {
  const SessionListCoordinator();

  SessionListFacade buildFacade({
    required SessionListState state,
    required Future<void> Function(int userId) prefetchUser,
    required Future<void> Function(int peerId) addPeer,
    required Future<void> Function(int peerId) removePeer,
    required void Function(int peerId) clearUnread,
    required String Function(int peerId) displayNameFor,
    required void Function() clearConnectionNotice,
    required Future<void> Function() logout,
  }) {
    return SessionListFacade(
      currentUsername: state.currentUsername,
      currentUserId: state.currentUserId,
      currentAvatarUrl: state.currentAvatarUrl,
      connectionNotice: state.connectionNotice,
      items: _buildItems(state),
      prefetchUser: prefetchUser,
      addPeer: addPeer,
      removePeer: removePeer,
      clearUnread: clearUnread,
      displayNameFor: displayNameFor,
      clearConnectionNotice: clearConnectionNotice,
      logout: logout,
    );
  }

  List<SessionListItemViewData> _buildItems(SessionListState state) {
    return state.orderedPeerIds.map((peerId) {
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
        updatedAt: summary?.updatedAt,
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

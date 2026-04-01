import 'package:vox_flutter/application/session/session_list_state.dart';
import 'package:vox_flutter/models/chat_session_summary.dart';
import 'package:vox_flutter/state/app_state.dart';

class SessionListStateAdapter {
  const SessionListStateAdapter();

  SessionListState fromAppState(AppState state) {
    final session = state.session;
    final currentUserId = session?.userId ?? 0;
    final orderedPeerIds = state.orderedPeerIds();

    return SessionListState(
      currentUsername: session?.username ?? '访客',
      currentUserId: currentUserId,
      currentAvatarUrl: session == null ? null : state.avatarUrlFor(currentUserId),
      connectionNotice: state.connectionNotice,
      orderedPeerIds: orderedPeerIds,
      sessionSummariesByPeerId: _sessionSummariesByPeerId(state, orderedPeerIds),
      unreadCountsByPeerId: _unreadCountsByPeerId(state, orderedPeerIds),
      displayNamesByPeerId: _displayNamesByPeerId(state, orderedPeerIds),
      avatarUrlsByPeerId: _avatarUrlsByPeerId(state, orderedPeerIds),
    );
  }

  Map<int, ChatSessionSummary> _sessionSummariesByPeerId(
    AppState state,
    List<int> orderedPeerIds,
  ) {
    final result = <int, ChatSessionSummary>{};
    for (final peerId in orderedPeerIds) {
      final summary = state.sessionSummaryFor(peerId);
      if (summary != null) {
        result[peerId] = summary;
      }
    }
    return result;
  }

  Map<int, int> _unreadCountsByPeerId(AppState state, List<int> orderedPeerIds) {
    return {
      for (final peerId in orderedPeerIds) peerId: state.unreadCount(peerId),
    };
  }

  Map<int, String> _displayNamesByPeerId(
    AppState state,
    List<int> orderedPeerIds,
  ) {
    return {
      for (final peerId in orderedPeerIds) peerId: state.displayNameFor(peerId),
    };
  }

  Map<int, String?> _avatarUrlsByPeerId(
    AppState state,
    List<int> orderedPeerIds,
  ) {
    return {
      for (final peerId in orderedPeerIds) peerId: state.avatarUrlFor(peerId),
    };
  }
}

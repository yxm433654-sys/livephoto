import 'package:vox_flutter/application/session/session_list_item_view_data.dart';

class SessionListFacade {
  const SessionListFacade({
    required this.currentUsername,
    required this.currentUserId,
    required this.currentAvatarUrl,
    required this.connectionNotice,
    required this.items,
    required this.prefetchUser,
    required this.addPeer,
    required this.removePeer,
    required this.clearUnread,
    required this.displayNameFor,
    required this.clearConnectionNotice,
    required this.logout,
  });

  final String currentUsername;
  final int currentUserId;
  final String? currentAvatarUrl;
  final String? connectionNotice;
  final List<SessionListItemViewData> items;
  final Future<void> Function(int userId) prefetchUser;
  final Future<void> Function(int peerId) addPeer;
  final Future<void> Function(int peerId) removePeer;
  final void Function(int peerId) clearUnread;
  final String Function(int peerId) displayNameFor;
  final void Function() clearConnectionNotice;
  final Future<void> Function() logout;
}

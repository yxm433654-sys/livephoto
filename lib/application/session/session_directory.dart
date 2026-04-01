import 'package:vox_flutter/models/chat_session_summary.dart';
import 'package:vox_flutter/models/user.dart';

class SessionDirectory {
  List<int> peers = <int>[];
  List<ChatSessionSummary> conversationSummaries = <ChatSessionSummary>[];

  final Map<int, int> _unreadByPeer = <int, int>{};
  final Map<int, UserProfile> _userCache = <int, UserProfile>{};
  final Map<int, Future<UserProfile?>> _userFetches =
      <int, Future<UserProfile?>>{};

  int unreadCount(int peerId) => _unreadByPeer[peerId] ?? 0;

  List<int> orderedPeerIds() {
    final ordered = <int>[];
    final seen = <int>{};
    for (final item in conversationSummaries) {
      if (seen.add(item.peerId)) {
        ordered.add(item.peerId);
      }
    }
    for (final peerId in peers) {
      if (seen.add(peerId)) {
        ordered.add(peerId);
      }
    }
    return ordered;
  }

  ChatSessionSummary? sessionSummaryFor(int peerId) {
    for (final item in conversationSummaries) {
      if (item.peerId == peerId) {
        return item;
      }
    }
    return null;
  }

  String displayNameFor(int userId) {
    final cached = _userCache[userId];
    final name = cached?.username.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'User $userId';
  }

  String? avatarUrlFor(int userId, String apiBaseUrl) {
    final url = _userCache[userId]?.avatarUrl;
    if (url == null) return null;
    final value = url.trim();
    if (value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return value;
    final base = Uri.parse(apiBaseUrl);
    final path = value.startsWith('/') ? value : '/$value';
    return base.replace(path: path, query: null, fragment: null).toString();
  }

  UserProfile? cachedUser(int userId) => _userCache[userId];

  Iterable<UserProfile> cachedUsers() => _userCache.values;

  Future<UserProfile?>? trackedFetch(int userId) => _userFetches[userId];

  void rememberUser(UserProfile profile) {
    _userCache[profile.userId] = profile;
  }

  void trackFetch(int userId, Future<UserProfile?> future) {
    _userFetches[userId] = future;
  }

  void clearTrackedFetch(int userId) {
    _userFetches.remove(userId);
  }

  void rememberSessionSummaries(List<ChatSessionSummary> items) {
    conversationSummaries = items;
    for (final item in items) {
      _unreadByPeer[item.peerId] = item.unreadCount;
      final username = item.peerUsername?.trim();
      if (username != null && username.isNotEmpty) {
        final cached = _userCache[item.peerId];
        _userCache[item.peerId] = UserProfile(
          userId: item.peerId,
          username: username,
          avatarUrl: item.peerAvatarUrl ?? cached?.avatarUrl,
          status: cached?.status,
          createdAt: cached?.createdAt,
        );
      }
    }
  }

  bool addPeer(int peerId) {
    if (peerId <= 0 || peers.contains(peerId)) return false;
    peers = [...peers, peerId];
    return true;
  }

  bool removePeer(int peerId) {
    if (!peers.contains(peerId)) return false;
    peers = peers.where((value) => value != peerId).toList();
    conversationSummaries =
        conversationSummaries.where((item) => item.peerId != peerId).toList();
    _unreadByPeer.remove(peerId);
    return true;
  }

  void incrementUnread(int peerId) {
    _unreadByPeer[peerId] = (_unreadByPeer[peerId] ?? 0) + 1;
  }

  bool clearUnread(int peerId) => _unreadByPeer.remove(peerId) != null;

  void restorePeers(List<int> restoredPeers) {
    peers = restoredPeers;
  }

  void clearSessionState() {
    peers = <int>[];
    conversationSummaries = <ChatSessionSummary>[];
    _unreadByPeer.clear();
  }

  void clearAll() {
    clearSessionState();
    _userCache.clear();
    _userFetches.clear();
  }
}

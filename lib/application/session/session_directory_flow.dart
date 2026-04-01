import 'package:vox_flutter/application/session/session_directory.dart';
import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/models/user.dart';
import 'package:vox_flutter/services/auth/auth_service.dart';
import 'package:vox_flutter/services/session/session_service.dart';

class SessionDirectoryFlow {
  const SessionDirectoryFlow();

  Future<UserProfile?> prefetchUser({
    required int userId,
    required AuthService authService,
    required SessionDirectory sessionDirectory,
    required void Function() notifyListeners,
  }) {
    if (userId <= 0) {
      return Future<UserProfile?>.value(null);
    }

    final cached = sessionDirectory.cachedUser(userId);
    if (cached != null) {
      return Future<UserProfile?>.value(cached);
    }

    final existing = sessionDirectory.trackedFetch(userId);
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        final profile = await authService.getUser(userId);
        sessionDirectory.rememberUser(profile);
        notifyListeners();
        return profile;
      } catch (_) {
        return null;
      } finally {
        sessionDirectory.clearTrackedFetch(userId);
      }
    }();

    sessionDirectory.trackFetch(userId, future);
    return future;
  }

  Future<UserProfile?> findUserByUsername({
    required String username,
    required AuthService authService,
    required SessionDirectory sessionDirectory,
    required void Function() notifyListeners,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    for (final user in sessionDirectory.cachedUsers()) {
      if (user.username == trimmed) {
        return user;
      }
    }

    try {
      final user = await authService.getUserByUsername(trimmed);
      sessionDirectory.rememberUser(user);
      notifyListeners();
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshSessions({
    required Session? session,
    required SessionService sessionService,
    required SessionDirectory sessionDirectory,
    required void Function() notifyListeners,
    bool notify = true,
  }) async {
    if (session == null) {
      sessionDirectory.clearSessionState();
      if (notify) {
        notifyListeners();
      }
      return;
    }

    try {
      final items = await sessionService.list(userId: session.userId);
      sessionDirectory.rememberSessionSummaries(items);
    } catch (_) {
      // Keep local peer list as a fallback if session sync fails.
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> addPeer({
    required int peerId,
    required SessionDirectory sessionDirectory,
    required Future<void> Function() persistPeers,
    required void Function() notifyListeners,
  }) async {
    if (!sessionDirectory.addPeer(peerId)) {
      return;
    }
    await persistPeers();
    notifyListeners();
  }

  Future<void> removePeer({
    required int peerId,
    required SessionDirectory sessionDirectory,
    required Future<void> Function() persistPeers,
    required void Function() notifyListeners,
  }) async {
    if (!sessionDirectory.removePeer(peerId)) {
      return;
    }
    await persistPeers();
    notifyListeners();
  }

  void clearUnread({
    required int peerId,
    required SessionDirectory sessionDirectory,
    required void Function() notifyListeners,
  }) {
    if (!sessionDirectory.clearUnread(peerId)) {
      return;
    }
    notifyListeners();
  }
}

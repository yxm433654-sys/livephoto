import 'package:shared_preferences/shared_preferences.dart';
import 'package:vox_flutter/application/session/session_directory.dart';
import 'package:vox_flutter/models/session.dart';

class SessionScopeStore {
  const SessionScopeStore();

  static const sessionKey = 'session';
  static const peersKey = 'peers';
  static const lastMessageIdKey = 'lastMessageId';

  Future<int> restore({
    required SharedPreferences? preferences,
    required Session? session,
    required SessionDirectory sessionDirectory,
  }) async {
    sessionDirectory.clearSessionState();
    if (preferences == null) {
      return 0;
    }

    final peerRaw = preferences.getStringList(_scopedKey(peersKey, session));
    if (peerRaw != null) {
      sessionDirectory.restorePeers(
        peerRaw.map((value) => int.tryParse(value)).whereType<int>().toList(),
      );
    }
    return preferences.getInt(_scopedKey(lastMessageIdKey, session)) ?? 0;
  }

  Future<void> savePeers({
    required SharedPreferences? preferences,
    required Session? session,
    required SessionDirectory sessionDirectory,
  }) {
    return preferences?.setStringList(
          _scopedKey(peersKey, session),
          sessionDirectory.peers.map((value) => value.toString()).toList(),
        ) ??
        Future<void>.value();
  }

  Future<void> saveLastMessageId({
    required SharedPreferences? preferences,
    required Session? session,
    required int lastMessageId,
  }) {
    return preferences?.setInt(
          _scopedKey(lastMessageIdKey, session),
          lastMessageId,
        ) ??
        Future<void>.value();
  }

  String scopedKey(String base, Session? session) => _scopedKey(base, session);

  String _scopedKey(String base, Session? session) {
    final userId = session?.userId;
    return userId == null ? base : '${base}_$userId';
  }
}

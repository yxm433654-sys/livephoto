import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vox_flutter/application/session/session_scope_store.dart';
import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/services/network/server_config_store.dart';

class SessionLifecycle {
  const SessionLifecycle();

  Future<BootstrapState> loadBootstrapState({
    required SharedPreferences preferences,
    required ServerConfigStore serverConfigStore,
  }) async {
    final endpoints = await serverConfigStore.load(preferences);
    return BootstrapState(
      endpoints: endpoints,
      session: restorePersistedSession(preferences),
    );
  }

  Future<void> syncSignedInState({
    required Session? session,
    required Future<void> Function() restoreScopedState,
    required Future<void> Function({bool notify}) refreshSessions,
    required void Function() startRealtime,
  }) async {
    await restoreScopedState();
    if (session == null) {
      return;
    }
    await refreshSessions(notify: false);
    startRealtime();
  }

  Future<void> clearSignedOutState({
    required SharedPreferences? preferences,
    required Future<void> Function() stopRealtime,
    required void Function() clearSessionDirectory,
    required void Function() clearConnectionNotice,
    required void Function() resetLastMessageId,
  }) async {
    await stopRealtime();
    resetLastMessageId();
    clearConnectionNotice();
    await clearPersistedSession(preferences);
    clearSessionDirectory();
  }

  Future<void> persistSession(
    SharedPreferences? preferences,
    Session session,
  ) {
    return preferences?.setString(
          SessionScopeStore.sessionKey,
          jsonEncode(session.toJson()),
        ) ??
        Future<void>.value();
  }

  Future<void> clearPersistedSession(SharedPreferences? preferences) {
    return preferences?.remove(SessionScopeStore.sessionKey) ??
        Future<void>.value();
  }

  Session? restorePersistedSession(SharedPreferences preferences) {
    final rawSession = preferences.getString(SessionScopeStore.sessionKey);
    return _restoreStoredSession(rawSession);
  }

  Session? _restoreStoredSession(String? rawSession) {
    if (rawSession == null || rawSession.trim().isEmpty) {
      return null;
    }
    return Session.fromJson(jsonDecode(rawSession));
  }
}

class BootstrapState {
  const BootstrapState({
    required this.endpoints,
    required this.session,
  });

  final ServerEndpoints endpoints;
  final Session? session;
}

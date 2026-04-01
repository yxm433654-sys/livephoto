import 'package:shared_preferences/shared_preferences.dart';
import 'package:vox_flutter/application/realtime/realtime_runtime_state.dart';
import 'package:vox_flutter/application/session/session_directory.dart';
import 'package:vox_flutter/application/session/session_scope_store.dart';
import 'package:vox_flutter/models/session.dart';

class SessionPersistence {
  const SessionPersistence();

  Future<void> restoreScopedState({
    required SharedPreferences? preferences,
    required Session? session,
    required SessionDirectory sessionDirectory,
    required SessionScopeStore sessionScopeStore,
    required RealtimeRuntimeState realtimeRuntimeState,
  }) async {
    final restoredLastMessageId = await sessionScopeStore.restore(
      preferences: preferences,
      session: session,
      sessionDirectory: sessionDirectory,
    );
    realtimeRuntimeState.resetLastMessageId();
    realtimeRuntimeState.updateLastMessageId(restoredLastMessageId);
  }

  Future<void> savePeers({
    required SharedPreferences? preferences,
    required Session? session,
    required SessionDirectory sessionDirectory,
    required SessionScopeStore sessionScopeStore,
  }) {
    return sessionScopeStore.savePeers(
      preferences: preferences,
      session: session,
      sessionDirectory: sessionDirectory,
    );
  }

  Future<void> saveLastMessageId({
    required SharedPreferences? preferences,
    required Session? session,
    required SessionScopeStore sessionScopeStore,
    required RealtimeRuntimeState realtimeRuntimeState,
  }) {
    return sessionScopeStore.saveLastMessageId(
      preferences: preferences,
      session: session,
      lastMessageId: realtimeRuntimeState.lastMessageId,
    );
  }
}

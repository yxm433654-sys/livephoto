import 'package:shared_preferences/shared_preferences.dart';
import 'package:vox_flutter/application/session/session_lifecycle.dart';
import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/services/auth/auth_service.dart';
import 'package:vox_flutter/services/network/server_config_store.dart';

class AccountFlow {
  const AccountFlow();

  Future<AccountBootstrap> initialize({
    required SharedPreferences preferences,
    required ServerConfigStore serverConfigStore,
    required Future<void> Function(String apiBaseUrl, String wsBaseUrl)
        rebuildServices,
    required Future<void> Function(Session? session) syncSignedInState,
  }) async {
    final bootstrapState = await const SessionLifecycle().loadBootstrapState(
      preferences: preferences,
      serverConfigStore: serverConfigStore,
    );
    await rebuildServices(
      bootstrapState.endpoints.apiBaseUrl,
      bootstrapState.endpoints.wsBaseUrl,
    );
    await syncSignedInState(bootstrapState.session);
    return AccountBootstrap(
      apiBaseUrl: bootstrapState.endpoints.apiBaseUrl,
      wsBaseUrl: bootstrapState.endpoints.wsBaseUrl,
      session: bootstrapState.session,
    );
  }

  Future<AccountEndpoints?> updateEndpoints({
    required SharedPreferences? preferences,
    required String apiBaseUrl,
    required String? wsBaseUrl,
    required ServerConfigStore serverConfigStore,
    required Session? session,
    required Future<void> Function(String apiBaseUrl, String wsBaseUrl)
        rebuildServices,
    required Future<void> Function(Session? session) syncSignedInState,
  }) async {
    if (preferences == null) {
      return null;
    }

    final endpoints = await serverConfigStore.save(
      preferences,
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsBaseUrl,
    );
    await rebuildServices(endpoints.apiBaseUrl, endpoints.wsBaseUrl);
    await syncSignedInState(session);
    return AccountEndpoints(
      apiBaseUrl: endpoints.apiBaseUrl,
      wsBaseUrl: endpoints.wsBaseUrl,
    );
  }

  Future<Session> login({
    required String username,
    required String password,
    required AuthService authService,
    required Future<void> Function() stopRealtime,
    required Future<void> Function(Session session) persistSession,
    required Future<void> Function(Session? session) syncSignedInState,
  }) async {
    final nextSession = await authService.login(
      username: username,
      password: password,
    );
    await stopRealtime();
    await persistSession(nextSession);
    await syncSignedInState(nextSession);
    return nextSession;
  }

  Future<void> register({
    required String username,
    required String password,
    required String? avatarUrl,
    required AuthService authService,
    required Future<void> Function(String username, String password) login,
  }) async {
    await authService.register(
      username: username,
      password: password,
      avatarUrl: avatarUrl,
    );
    await login(username, password);
  }

  Future<void> logout({
    required Future<void> Function() clearSignedOutState,
  }) {
    return clearSignedOutState();
  }
}

class AccountBootstrap {
  const AccountBootstrap({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.session,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
  final Session? session;
}

class AccountEndpoints {
  const AccountEndpoints({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
}

